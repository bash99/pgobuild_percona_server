#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"

OFFICIAL_IMAGE="${OFFICIAL_IMAGE:-percona/percona-server:8.4.8-8.1}"
PGOED_IMAGE="${PGOED_IMAGE:-ps-8.4.8-8-pgoed:latest}"
SYSBENCH_IMAGE="${SYSBENCH_IMAGE:-perconalab/sysbench:latest}"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
SB_DB="${SB_DB:-sbtest}"
SB_USER="${SB_USER:-sbtest}"
SB_PASSWORD="${SB_PASSWORD:-sbtest}"

SB_TABLES="${SB_TABLES:-16}"
SB_TABLE_SIZE="${SB_TABLE_SIZE:-500000}"
SB_THREADS_LIST="${SB_THREADS_LIST:-1 4 8 16}"
SB_TIME="${SB_TIME:-60}"
SB_WARMUP_TIME="${SB_WARMUP_TIME:-30}"
SB_REPORT_INTERVAL="${SB_REPORT_INTERVAL:-10}"
SB_PERCENTILE="${SB_PERCENTILE:-95}"

SB_HOST="${SB_HOST:-127.0.0.1}"
SB_PORT="${SB_PORT:-3306}"
SB_MYSQL_SSL="${SB_MYSQL_SSL:-required}"

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RUN_ROOT="${RUN_ROOT:-${script_dir}/runs}"
RUN_DIR="${RUN_ROOT}/${RUN_ID}"

RUN_VARIANTS="${RUN_VARIANTS:-official pgoed}"

bench_cnf_host_path="${bench_cnf_host_path:-${script_dir}/zz-benchmark.cnf}"
bench_cnf_container_path="/etc/my.cnf.d/zz-benchmark.cnf"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

wait_mysql() {
  local container="$1"
  local deadline now
  deadline=$(( $(date +%s) + 120 ))
  while true; do
    if docker exec "$container" mysqladmin -uroot -p"${MYSQL_ROOT_PASSWORD}" --protocol=tcp ping >/dev/null 2>&1; then
      return 0
    fi
    now="$(date +%s)"
    if (( now >= deadline )); then
      docker logs --tail 200 "$container" >&2 || true
      echo "mysqld not ready within 120s: $container" >&2
      return 1
    fi
    sleep 1
  done
}

sysbench_cmd_base() {
  cat <<EOF
sysbench
--db-driver=mysql
--mysql-host=${SB_HOST}
--mysql-port=${SB_PORT}
--mysql-user=${SB_USER}
--mysql-password=${SB_PASSWORD}
--mysql-db=${SB_DB}
--mysql-ssl=${SB_MYSQL_SSL}
--mysql-storage-engine=innodb
--tables=${SB_TABLES}
--table-size=${SB_TABLE_SIZE}
--report-interval=${SB_REPORT_INTERVAL}
--percentile=${SB_PERCENTILE}
EOF
}

run_sysbench() {
  local lua="$1"
  local action="$2"
  local threads="${3:-}"
  local seconds="${4:-}"
  local out_log="$5"

  local -a args
  mapfile -t args < <(sysbench_cmd_base)

  if [[ -n "${threads:-}" ]]; then
    args+=( "--threads=${threads}" )
  fi
  if [[ -n "${seconds:-}" ]]; then
    args+=( "--time=${seconds}" )
  fi

  # shellcheck disable=SC2206
  docker run --rm --network host "${SYSBENCH_IMAGE}" \
    "${args[@]}" "/usr/share/sysbench/${lua}" "${action}" | tee "${out_log}"
}

start_sampling() {
  local mysqld_pid="$1"
  local sample_dir="$2"

  mkdir -p "$sample_dir"

  vmstat 1 >"${sample_dir}/vmstat.log" 2>&1 &
  echo $! >"${sample_dir}/vmstat.pid"

  if command -v iostat >/dev/null 2>&1; then
    iostat -dx 1 >"${sample_dir}/iostat.log" 2>&1 &
    echo $! >"${sample_dir}/iostat.pid"
  fi

  if command -v pidstat >/dev/null 2>&1; then
    pidstat -h -p "${mysqld_pid}" -rud 1 >"${sample_dir}/pidstat.log" 2>&1 &
    echo $! >"${sample_dir}/pidstat.pid"
  fi
}

stop_sampling() {
  local sample_dir="$1"
  local pid_file pid
  for pid_file in vmstat.pid iostat.pid pidstat.pid; do
    if [[ -f "${sample_dir}/${pid_file}" ]]; then
      pid="$(cat "${sample_dir}/${pid_file}")"
      kill "${pid}" >/dev/null 2>&1 || true
      rm -f "${sample_dir:?}/${pid_file}"
    fi
  done
  sleep 1
}

record_host_env() {
  mkdir -p "$RUN_DIR"
  {
    echo "date: $(date -Is)"
    echo "cwd: ${repo_root}"
    echo
    echo "## uname -a"
    uname -a
    echo
    echo "## lscpu"
    lscpu
    echo
    echo "## free -h"
    free -h
    echo
    echo "## cpu governors"
    if compgen -G "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor" >/dev/null; then
      for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        printf '%s: %s\n' "$g" "$(cat "$g" 2>/dev/null || true)"
      done
    else
      echo "no cpufreq scaling_governor info"
    fi
    echo
    echo "## lsblk"
    lsblk -o NAME,TYPE,SIZE,ROTA,MODEL,MOUNTPOINTS
    echo
    echo "## docker version"
    docker version
  } >"${RUN_DIR}/env.md"

  docker run --rm "${SYSBENCH_IMAGE}" sysbench --version >"${RUN_DIR}/sysbench-version.txt"

  cat >"${RUN_DIR}/params.env" <<EOF
RUN_ID=${RUN_ID}
OFFICIAL_IMAGE=${OFFICIAL_IMAGE}
PGOED_IMAGE=${PGOED_IMAGE}
SYSBENCH_IMAGE=${SYSBENCH_IMAGE}
SB_TABLES=${SB_TABLES}
SB_TABLE_SIZE=${SB_TABLE_SIZE}
SB_THREADS_LIST=${SB_THREADS_LIST}
SB_TIME=${SB_TIME}
SB_WARMUP_TIME=${SB_WARMUP_TIME}
SB_REPORT_INTERVAL=${SB_REPORT_INTERVAL}
SB_PERCENTILE=${SB_PERCENTILE}
SB_HOST=${SB_HOST}
SB_PORT=${SB_PORT}
SB_MYSQL_SSL=${SB_MYSQL_SSL}
EOF
}

record_mysql_snapshot() {
  local container="$1"
  local out_dir="$2"
  mkdir -p "$out_dir"

  docker exec "$container" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --protocol=tcp -e \
    "SELECT VERSION() AS version, @@version_comment AS version_comment, @@version_compile_os AS compile_os, @@version_compile_machine AS compile_machine\\G" \
    >"${out_dir}/server-version.txt"

  docker exec "$container" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --protocol=tcp -e \
    "SHOW VARIABLES WHERE Variable_name IN ( \
      'innodb_buffer_pool_size', \
      'innodb_flush_log_at_trx_commit', \
      'innodb_flush_method', \
      'innodb_redo_log_capacity', \
      'sync_binlog', \
      'performance_schema', \
      'skip_name_resolve' \
    );" \
    >"${out_dir}/server-variables.txt"

  docker exec "$container" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --protocol=tcp -Nse \
    "SELECT ROUND(SUM(data_length+index_length)/1024/1024, 1) FROM information_schema.tables WHERE table_schema='${SB_DB}';" \
    >"${out_dir}/dataset-size-mb.txt" || true

  docker logs --tail 200 "$container" >"${out_dir}/docker-logs.tail.txt" 2>&1 || true
}

ensure_sb_user() {
  local container="$1"
  docker exec "$container" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --protocol=tcp -e \
    "CREATE DATABASE IF NOT EXISTS \`${SB_DB}\`;
     CREATE USER IF NOT EXISTS '${SB_USER}'@'%' IDENTIFIED BY '${SB_PASSWORD}';
     GRANT ALL PRIVILEGES ON \`${SB_DB}\`.* TO '${SB_USER}'@'%';
     FLUSH PRIVILEGES;" >/dev/null
}

run_image_suite() {
  local image="$1"
  local label="$2"
  local container="psbench-${label}-${RUN_ID}"
  local volume="psbench-${label}-${RUN_ID}-datadir"

  local out_dir="${RUN_DIR}/${label}"
  local sb_dir="${out_dir}/sysbench"
  local sample_root="${out_dir}/samples"

  mkdir -p "$sb_dir" "$sample_root"

  log "prepare: ${label} image=${image}"
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
  docker volume create "$volume" >/dev/null

  docker image inspect "$image" >"${out_dir}/image-inspect.json" 2>&1 || true

  docker run -d --name "$container" --network host \
    -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
    -e MYSQL_DATABASE="${SB_DB}" \
    -e MYSQL_USER="${SB_USER}" \
    -e MYSQL_PASSWORD="${SB_PASSWORD}" \
    -v "${volume}:/var/lib/mysql" \
    -v "${bench_cnf_host_path}:${bench_cnf_container_path}:ro" \
    "${image}" >/dev/null

  wait_mysql "$container"
  ensure_sb_user "$container"

  record_mysql_snapshot "$container" "$out_dir"

  log "sysbench prepare: ${label}"
  run_sysbench "oltp_read_write.lua" "prepare" "8" "" "${sb_dir}/prepare.log"

  # refresh dataset-size after prepare
  record_mysql_snapshot "$container" "$out_dir"

  log "warmup: ${label}"
  run_sysbench "oltp_read_only.lua" "run" "16" "${SB_WARMUP_TIME}" "${sb_dir}/warmup-read_only-t16.log" >/dev/null

  local mysqld_pid
  mysqld_pid="$(docker inspect -f '{{.State.Pid}}' "$container")"
  printf '%s\n' "$mysqld_pid" >"${out_dir}/mysqld-host-pid.txt"

  local threads lua workload log_file sample_dir

  for workload in point_select read_only; do
    lua="oltp_${workload}.lua"
    for threads in ${SB_THREADS_LIST}; do
      log "run: ${label} workload=${workload} threads=${threads}"
      log_file="${sb_dir}/${workload}_t${threads}.log"
      sample_dir="${sample_root}/${workload}_t${threads}"
      start_sampling "$mysqld_pid" "$sample_dir"
      run_sysbench "${lua}" "run" "${threads}" "${SB_TIME}" "${log_file}" >/dev/null
      stop_sampling "$sample_dir"
    done
  done

  workload="read_write"
  lua="oltp_${workload}.lua"
  for threads in ${SB_THREADS_LIST}; do
    log "run: ${label} workload=${workload} threads=${threads}"
    log_file="${sb_dir}/${workload}_t${threads}.log"
    sample_dir="${sample_root}/${workload}_t${threads}"
    start_sampling "$mysqld_pid" "$sample_dir"
    run_sysbench "${lua}" "run" "${threads}" "${SB_TIME}" "${log_file}" >/dev/null
    stop_sampling "$sample_dir"
  done

  log "cleanup: ${label}"
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
}

main() {
  require_cmd docker
  require_cmd vmstat

  mkdir -p "$RUN_DIR"

  record_host_env

  log "pull/ensure images"
  docker pull "${OFFICIAL_IMAGE}" >/dev/null
  docker image inspect "${PGOED_IMAGE}" >/dev/null 2>&1 || {
    echo "missing PGOed image locally: ${PGOED_IMAGE}" >&2
    exit 1
  }
  docker image inspect "${SYSBENCH_IMAGE}" >/dev/null 2>&1 || docker pull "${SYSBENCH_IMAGE}" >/dev/null

  for variant in ${RUN_VARIANTS}; do
    case "${variant}" in
      official)
        run_image_suite "${OFFICIAL_IMAGE}" "official"
        ;;
      pgoed)
        run_image_suite "${PGOED_IMAGE}" "pgoed"
        ;;
      *)
        echo "unsupported RUN_VARIANTS item: ${variant} (expected: official|pgoed)" >&2
        exit 1
        ;;
    esac
  done

  log "parse summary"
  python3 "${script_dir}/parse_sysbench.py" --run-dir "${RUN_DIR}" \
    --out-json "${RUN_DIR}/summary.json" \
    --out-md "${RUN_DIR}/summary.md"

  log "done: ${RUN_DIR}"
}

main "$@"
