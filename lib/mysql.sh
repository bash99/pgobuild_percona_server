#!/usr/bin/env bash

set -euo pipefail

MYSQL_STAGE_TIMEOUT_DEFAULT=120

mysql_stage_name() {
  local version="$1"
  local mini_ver="$2"
  local profile="$3"
  printf 'ps-%s.%s-%s\n' "$version" "$mini_ver" "$profile"
}

mysql_supports_mecab() {
  case "$1" in
    5.7|8.0|8.4)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mysql_supports_initialize_insecure() {
  case "$1" in
    5.6)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

mysql_runtime_root() {
  local work_root="$1"
  local stage_name="$2"
  printf '%s/runtime/%s\n' "$work_root" "$stage_name"
}

mysql_state_root() {
  local work_root="$1"
  local stage_name="$2"
  printf '%s/state/%s\n' "$work_root" "$stage_name"
}

mysql_generate_password() {
  local prefix="${1:-tmp}"
  local token
  set +o pipefail
  token="$(dd if=/dev/urandom bs=32 count=1 status=none | base64 | tr -dc 'A-Za-z0-9' | head -c 16)"
  set -o pipefail
  printf '%s_%s\n' "$prefix" "$token"
}

mysql_write_client_defaults() {
  local file="$1"
  local user="$2"
  local password="$3"
  local socket="$4"
  cat > "$file" <<EOF
[client]
user=${user}
socket=${socket}
protocol=socket
EOF
  if [[ -n "$password" ]]; then
    printf 'password=%s\n' "$password" >> "$file"
  fi
  chmod 600 "$file"
}

mysql_find_plugin_dir() {
  local install_root="$1"
  local candidate
  for candidate in \
    "$install_root/lib/plugin" \
    "$install_root/lib/mysql/plugin" \
    "$install_root/lib64/mysql/plugin"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  die "could not locate MySQL plugin directory under $install_root"
}

mysql_sbtest_auth_clause() {
  local mysql_ver="$1"
  local password="$2"

  case "$mysql_ver" in
    8.0)
      printf "IDENTIFIED WITH mysql_native_password BY '%s'" "$password"
      ;;
    *)
      printf "IDENTIFIED BY '%s'" "$password"
      ;;
  esac
}

mysql_create_local_user_sql() {
  local mysql_ver="$1"
  local username="$2"
  local password="$3"
  local create_mode="${4:-create}"
  local auth_clause

  auth_clause="$(mysql_sbtest_auth_clause "$mysql_ver" "$password")"

  case "$create_mode" in
    create)
      printf "CREATE USER '%s'@'localhost' %s;\n" "$username" "$auth_clause"
      ;;
    if-not-exists)
      printf "CREATE USER IF NOT EXISTS '%s'@'localhost' %s;\n" "$username" "$auth_clause"
      ;;
    *)
      die "unsupported create_mode for mysql_create_local_user_sql: $create_mode"
      ;;
  esac
}

mysql_provision_local_accounts_sql() {
  local mysql_ver="$1"
  local root_password="$2"
  local sbtest_password="$3"

  case "$mysql_ver" in
    5.6)
      cat <<EOF
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${root_password}');
GRANT ALL PRIVILEGES ON *.* TO 'sbtest'@'localhost' IDENTIFIED BY '${sbtest_password}';
FLUSH PRIVILEGES;
EOF
      ;;
    *)
      cat <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password}';
$(mysql_create_local_user_sql "$mysql_ver" sbtest "$sbtest_password" if-not-exists)
GRANT ALL PRIVILEGES ON *.* TO 'sbtest'@'localhost';
FLUSH PRIVILEGES;
EOF
      ;;
  esac
}

mysql_prepare_sysbench_user_sql() {
  local mysql_ver="$1"
  local sbtest_password="$2"

  case "$mysql_ver" in
    5.6)
      cat <<EOF
GRANT ALL PRIVILEGES ON *.* TO 'sbtest'@'localhost' IDENTIFIED BY '${sbtest_password}';
FLUSH PRIVILEGES;
EOF
      ;;
    *)
      cat <<EOF
$(mysql_create_local_user_sql "$mysql_ver" sbtest "$sbtest_password" if-not-exists)
ALTER USER 'sbtest'@'localhost' $(mysql_sbtest_auth_clause "$mysql_ver" "$sbtest_password");
FLUSH PRIVILEGES;
EOF
      ;;
  esac
}

mysql_detect_total_memory_mb() {
  awk '/MemTotal/ { printf "%d\n", ($2 + 1023) / 1024; exit }' /proc/meminfo
}

mysql_default_buffer_pool_mb() {
  local total_mb pct cap granularity pool_mb

  total_mb="${MYSQL_TOTAL_MEMORY_MB_OVERRIDE:-$(mysql_detect_total_memory_mb)}"
  pct="${MYSQL_BUFFER_POOL_PCT:-75}"
  cap="${MYSQL_BUFFER_POOL_CAP_MB:-4800}"
  granularity="${MYSQL_BUFFER_POOL_GRANULARITY_MB:-64}"

  pool_mb=$(( total_mb * pct / 100 ))
  pool_mb=$(( pool_mb / granularity * granularity ))

  if (( pool_mb < granularity )); then
    pool_mb="$granularity"
  fi
  if (( pool_mb > cap )); then
    pool_mb="$cap"
  fi

  printf '%s\n' "$pool_mb"
}

mysql_benchmark_buffer_pool_mb() {
  if [[ -n "${MYSQL_BUFFER_POOL_MB:-}" ]]; then
    printf '%s\n' "$MYSQL_BUFFER_POOL_MB"
    return 0
  fi

  mysql_default_buffer_pool_mb
}

mysql_emit_config() {
  local mysql_ver="$1"
  local install_root="$2"
  local data_dir="$3"
  local tmp_dir="$4"
  local socket_path="$5"
  local log_path="$6"
  local pid_path="$7"
  local port="$8"
  local server_id="$9"
  local plugin_dir="${10}"
  local buffer_pool_mb

  buffer_pool_mb="$(mysql_benchmark_buffer_pool_mb)"

  cat <<EOF
[client]
socket=${socket_path}

[mysqld]
basedir=${install_root}
datadir=${data_dir}
tmpdir=${tmp_dir}
socket=${socket_path}
log-error=${log_path}
pid-file=${pid_path}
plugin-dir=${plugin_dir}
port=${port}
bind-address=127.0.0.1
server_id=${server_id}
skip_name_resolve=ON
explicit_defaults_for_timestamp=ON
sql_mode=STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO
innodb_buffer_pool_size=${buffer_pool_mb}M
innodb_flush_log_at_trx_commit=2
innodb_flush_method=O_DIRECT
loose_innodb_buffer_pool_dump_at_shutdown=ON
loose_innodb_buffer_pool_load_at_startup=ON
loose_innodb_buffer_pool_dump_pct=100
table_open_cache_instances=16
performance_schema=OFF
EOF

  if [[ "$mysql_ver" == "8.0" ]]; then
    cat <<EOF
default_authentication_plugin=mysql_native_password
EOF
  fi
}

mysql_wait_until_ready() {
  local mysqladmin_bin="$1"
  local defaults_file="$2"
  local socket_path="$3"
  local pid="$4"
  local timeout_secs="${5:-$MYSQL_STAGE_TIMEOUT_DEFAULT}"
  local log_path="${6:-}"
  local deadline

  deadline=$(( $(date +%s) + timeout_secs ))
  while (( $(date +%s) < deadline )); do
    if [[ -S "$socket_path" ]] && "$mysqladmin_bin" --defaults-file="$defaults_file" ping >/dev/null 2>&1; then
      return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null && [[ ! -S "$socket_path" ]]; then
      sleep 1
      continue
    fi
    sleep 1
  done

  [[ -n "$log_path" && -f "$log_path" ]] && tail -n 80 "$log_path" >&2 || true
  die "mysqld did not become ready within ${timeout_secs}s"
}

mysql_shutdown_with_defaults() {
  local mysqladmin_bin="$1"
  local defaults_file="$2"
  "$mysqladmin_bin" --defaults-file="$defaults_file" shutdown >/dev/null
}

mysql_wait_for_startup_quiesce() {
  local install_root="$1"
  local defaults_file="$2"
  local log_file="$3"
  local timeout_secs="${4:-240}"
  local enabled status deadline log_hit pending_line stable_count

  enabled="$($install_root/bin/mysql --defaults-file="$defaults_file" -Nse "SHOW VARIABLES LIKE 'innodb_buffer_pool_load_at_startup'" 2>/dev/null | awk '{print $2}')"
  [[ "${enabled:-}" == "ON" ]] || return 0

  deadline=$(( $(date +%s) + timeout_secs ))
  stable_count=0
  while (( $(date +%s) < deadline )); do
    status="$($install_root/bin/mysql --defaults-file="$defaults_file" -Nse "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_load_status'" 2>/dev/null | awk '{$1=""; sub(/^ /, ""); print}')"
    pending_line="$($install_root/bin/mysql --defaults-file="$defaults_file" -e "SHOW ENGINE INNODB STATUS\G" 2>/dev/null | grep -m1 'Pending writes:' || true)"
    log_hit=""
    if [[ -n "${log_file:-}" && -f "$log_file" ]]; then
      log_hit="$(grep -F 'Buffer pool(s) load completed' "$log_file" | tail -n 1 || true)"
    fi

    if [[ "${status:-}" == *"Cannot open"* && "${status:-}" == *"ib_buffer_pool"* ]]; then
      log_info "buffer pool file is absent; skipping load wait"
      return 0
    fi

    if [[ ( -n "${status:-}" && "$status" == *"load completed"* ) || -n "$log_hit" ]]; then
      if [[ "$pending_line" == *"Pending writes: LRU 0, flush list 0, single page 0"* ]]; then
        stable_count=$((stable_count + 1))
        log_info "startup quiesce poll ${stable_count}/2: ${status:-log-confirmed}; ${pending_line}"
        if (( stable_count >= 2 )); then
          [[ -n "${status:-}" ]] && log_info "startup quiesced by status: $status"
          [[ -n "$log_hit" ]] && log_info "startup quiesced by log: $log_hit"
          return 0
        fi
      else
        stable_count=0
        log_info "buffer pool loaded but startup not quiesced yet: ${pending_line:-Pending writes unavailable}"
      fi
    else
      stable_count=0
      if [[ -n "${status:-}" ]]; then
        log_info "waiting for buffer pool load: $status"
      else
        log_info "waiting for buffer pool load: status unavailable, checking log ${log_file}"
      fi
    fi
    sleep 5
  done

  [[ -n "${log_file:-}" && -f "$log_file" ]] && tail -n 80 "$log_file" >&2 || true
  die "startup did not quiesce within ${timeout_secs}s"
}
