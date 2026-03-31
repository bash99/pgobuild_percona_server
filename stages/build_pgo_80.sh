#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/mysql.sh"

: "${MYSQL_VER:=8.0}"
: "${MYSQL_MINI_VER:=44-35}"
: "${WORK_ROOT:=$REPO_ROOT/work}"
: "${LOG_ROOT:=$WORK_ROOT/logs}"
: "${RESULT_ROOT:=$WORK_ROOT/results}"
: "${ENABLE_LTO:=ON}"
: "${ENABLE_CCACHE:=AUTO}"
: "${LINKER_FLAVOR:=default}"
: "${FORCE_INSOURCE_BUILD:=OFF}"
: "${NORMAL_BUILD_PROFILE:=normal}"
: "${PGO_BUILD_PROFILE:=pgo}"
: "${PGO_GEN_PROFILE:=pgo-gen}"
: "${PGO_USE_PROFILE:=pgoed}"
: "${PGO_PROFILE_DIR:=$WORK_ROOT/pgo/ps-${MYSQL_VER}.${MYSQL_MINI_VER}/profile-data}"
: "${PGO_GEN_PORT:=34081}"
: "${PGO_USE_PORT:=34082}"
: "${TRAIN_MODE:=}"
: "${PGO_TRAIN_MODE:=${TRAIN_MODE:-joint_read}}"
: "${PGO_BENCHMARK_MODE:=${TRAIN_MODE:-readonly}}"
: "${PGO_TRAIN_DB_ENGINES:=innodb}"
: "${PGO_VALIDATE_DB_ENGINES:=$PGO_TRAIN_DB_ENGINES}"
: "${PGO_VERDICT_ENGINE:=innodb}"
: "${STRICT_PGO_VERDICT:=ON}"
: "${SKIP_PGO_GENERATE:=OFF}"
: "${REUSE_NORMAL_DATASET_FOR_PGO:=ON}"
: "${PGO_DATASET_MODE:=clone}"
: "${BENCHMARK_SETTLE_SECONDS:=120}"
: "${POST_PREPARE_SETTLE_SECONDS:=120}"
: "${CLONED_DATASET_WARMUP:=ON}"
: "${ACTIVE_BENCHMARK_MODE:=OFF}"
: "${ACTIVE_BENCHMARK_LOG_ROOT:=$LOG_ROOT/active}"
: "${ACTIVE_BENCHMARK_PRE_SECONDS:=30}"
: "${ACTIVE_BENCHMARK_POST_SECONDS:=30}"
: "${ACTIVE_BENCHMARK_INTERVAL:=1}"
: "${STABILITY_THRESHOLD_PCT:=10}"
: "${FAIL_ON_SUSPICIOUS_BENCH:=OFF}"
: "${NORMAL_BASELINE_LOG:=$WORK_ROOT/logs/sysbench-train-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${NORMAL_BUILD_PROFILE}.log}"

require_cmd date find sed tee awk

case "$MYSQL_VER" in
  8.0|8.4)
    ;;
  *)
    die "build_pgo_80.sh only supports MYSQL_VER=8.0 or 8.4"
    ;;
esac

list_contains_word() {
  local list="$1"
  local word="$2"
  case " $list " in
    *" $word "*) return 0 ;;
    *) return 1 ;;
  esac
}

sysbench_log_for_engine() {
  local log_prefix="$1"
  local db_engine="$2"
  if [[ "$db_engine" == "innodb" ]]; then
    printf '%s.log\n' "$log_prefix"
  else
    printf '%s-%s.log\n' "$log_prefix" "$db_engine"
  fi
}

normal_baseline_log_for_engine() {
  local db_engine="$1"
  if [[ "$db_engine" == "innodb" ]]; then
    printf '%s\n' "$NORMAL_BASELINE_LOG"
  else
    printf '%s/sysbench-train-ps-%s.%s-%s-%s.log\n' "$LOG_ROOT" "$MYSQL_VER" "$MYSQL_MINI_VER" "$NORMAL_BUILD_PROFILE" "$db_engine"
  fi
}

format_improvement_pct() {
  local pgo="$1"
  local base="$2"

  if [[ -z "$pgo" || -z "$base" ]]; then
    printf '%s' 'n/a'
    return 0
  fi

  awk -v pgo="$pgo" -v base="$base" 'BEGIN { if (base <= 0) { printf "n/a"; exit } printf "%.2f%%", ((pgo - base) / base) * 100 }'
}

NORMAL_INSTALL_ROOT="$WORK_ROOT/install/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${NORMAL_BUILD_PROFILE}"
NORMAL_STATE_FILE="$WORK_ROOT/state/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${NORMAL_BUILD_PROFILE}/runtime.env"
SHARED_SYSBENCH_ROOT="$WORK_ROOT/sysbench-runtime/ps-${MYSQL_VER}.${MYSQL_MINI_VER}"
PGO_GEN_LOG_PREFIX="$LOG_ROOT/sysbench-train-${PGO_GEN_PROFILE}-$(date +%Y%m%d)"
PGO_USE_LOG_PREFIX="$LOG_ROOT/sysbench-train-${PGO_USE_PROFILE}-$(date +%Y%m%d)"
PGO_GEN_LOG="${PGO_GEN_LOG_PREFIX}.log"
PGO_USE_LOG="${PGO_USE_LOG_PREFIX}.log"
: "${RESULT_FILE:=$RESULT_ROOT/pgo-readonly-${MYSQL_VER}.${MYSQL_MINI_VER}-$(date +%Y%m%d).md}"
PGO_BUILD_ROOT="$WORK_ROOT/build/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${PGO_BUILD_PROFILE}"
BUILD_ROOT_USE="$PGO_BUILD_ROOT"

[[ -x "$NORMAL_INSTALL_ROOT/bin/mysqld" ]] || die "missing normal install root: $NORMAL_INSTALL_ROOT"
[[ -f "$NORMAL_STATE_FILE" ]] || die "missing normal runtime state: $NORMAL_STATE_FILE"

ensure_dir "$LOG_ROOT"
ensure_dir "$RESULT_ROOT"
ensure_dir "$SHARED_SYSBENCH_ROOT"
if [[ "$SKIP_PGO_GENERATE" != "ON" ]]; then
  rm -rf "$PGO_PROFILE_DIR"
fi
ensure_dir "$PGO_PROFILE_DIR"

if ! list_contains_word "$PGO_VALIDATE_DB_ENGINES" "$PGO_VERDICT_ENGINE"; then
  die "PGO_VERDICT_ENGINE=$PGO_VERDICT_ENGINE is not included in PGO_VALIDATE_DB_ENGINES=$PGO_VALIDATE_DB_ENGINES"
fi

for db_engine in $PGO_TRAIN_DB_ENGINES $PGO_VALIDATE_DB_ENGINES; do
  baseline_log="$(normal_baseline_log_for_engine "$db_engine")"
  [[ -f "$baseline_log" ]] || die "missing normal baseline log for db_engine=${db_engine}: $baseline_log"
done

ensure_sysbench_root() {
  if [[ -x "$SHARED_SYSBENCH_ROOT/bin/sysbench" && -d "$SHARED_SYSBENCH_ROOT/share/sysbench" ]]; then
    return 0
  fi

  log_info "preparing reusable sysbench root: $SHARED_SYSBENCH_ROOT"
  rm -rf "$SHARED_SYSBENCH_ROOT"
  env SYSBENCH_BASE="$SHARED_SYSBENCH_ROOT" bash "$REPO_ROOT/sysbench/compile-sysbench.sh" "$NORMAL_INSTALL_ROOT" \
    > "$LOG_ROOT/sysbench-compile-pgo-shared-${MYSQL_VER}.${MYSQL_MINI_VER}.log" 2>&1

  [[ -x "$SHARED_SYSBENCH_ROOT/bin/sysbench" ]] || die "shared sysbench binary missing: $SHARED_SYSBENCH_ROOT/bin/sysbench"
  [[ -d "$SHARED_SYSBENCH_ROOT/share/sysbench" ]] || die "shared sysbench lua dir missing: $SHARED_SYSBENCH_ROOT/share/sysbench"
}

read_state_var() {
  local state_file="$1"
  local key="$2"
  awk -F= -v search_key="$key" '$1 == search_key { sub(/^[^=]*=/, "", $0); print $0; exit }' "$state_file"
}

shutdown_stage_if_running() {
  local state_file="$1"
  if [[ -f "$state_file" ]]; then
    set -a
    . "$state_file"
    set +a
    if [[ -S "${MYSQL_SOCKET:-}" ]]; then
      log_info "shutting down lingering mysqld for ${BUILD_PROFILE:-unknown}"
      mysql_shutdown_with_defaults "$INSTALL_ROOT/bin/mysqladmin" "$MYSQL_ROOT_DEFAULTS_FILE" || true
    fi
  fi
}

extract_case_transactions_per_sec() {
  local log_file="$1"
  local case_name="$2"

  awk '
    $0 ~ /=== SYSBENCH_CASE_BEGIN/ && $0 ~ ("case=" target_case " ") { in_case=1; next }
    $0 ~ /=== SYSBENCH_CASE_END/ && in_case { in_case=0 }
    in_case && /transactions:/ {
      value=$3
      gsub(/[()]/, "", value)
      print value
      exit
    }
  ' target_case="$case_name" "$log_file"
}

escape_gcda_prefix() {
  printf '%s\n' "$1" | tr '/' '#'
}

collect_gcda_stats() {
  find "$PGO_PROFILE_DIR" -type f -name '*.gcda' -printf '%s\n' | \
    awk '{sum+=$1; count+=1; if ($1 > 0) nz+=1} END {printf "%d %d %d\n", count, nz, sum}'
}

verify_profile_generation() {
  local build_root="$1"
  local escaped_prefix

  escaped_prefix="$(escape_gcda_prefix "$build_root")"
  read -r GCDA_COUNT GCDA_NONZERO_COUNT GCDA_TOTAL_BYTES <<<"$(collect_gcda_stats)"
  (( GCDA_COUNT > 0 )) || die "no gcda files found under $PGO_PROFILE_DIR"
  (( GCDA_NONZERO_COUNT > 0 )) || die "all gcda files are zero-sized under $PGO_PROFILE_DIR"

  GCDA_MATCHING_BUILD_COUNT="$(find "$PGO_PROFILE_DIR" -type f -name '*.gcda' | awk -v prefix="$escaped_prefix" 'index($0, prefix) { count += 1 } END { print count + 0 }')"
  (( GCDA_MATCHING_BUILD_COUNT > 0 )) || die "profile data under $PGO_PROFILE_DIR does not match build root $build_root"

  log_info "profile generation complete: gcda_count=$GCDA_COUNT nonzero=$GCDA_NONZERO_COUNT total_bytes=$GCDA_TOTAL_BYTES matched_build_root=$GCDA_MATCHING_BUILD_COUNT"
}

verify_profile_use() {
  local build_root="$1"
  local build_profile="$2"
  local build_log="$LOG_ROOT/build-normal-${MYSQL_VER}.${MYSQL_MINI_VER}-${build_profile}.log"
  local cache_file="$build_root/CMakeCache.txt"

  [[ -f "$build_log" ]] || die "missing build log: $build_log"
  [[ -f "$cache_file" ]] || die "missing CMake cache: $cache_file"

  grep -F "FPROFILE_USE:BOOL=ON" "$cache_file" >/dev/null || die "FPROFILE_USE is not enabled in $cache_file"
  grep -F "FPROFILE_DIR:UNINITIALIZED=$PGO_PROFILE_DIR" "$cache_file" >/dev/null || die "FPROFILE_DIR is not $PGO_PROFILE_DIR in $cache_file"
  grep -F -- "-fprofile-use=$PGO_PROFILE_DIR" "$build_log" >/dev/null || die "build log does not contain -fprofile-use=$PGO_PROFILE_DIR"

  PGO_USE_MISSING_PROFILE_COUNT="$(grep -c 'missing-profile' "$build_log" || true)"
  log_info "profile-use compile confirmed: fprofile-use=$PGO_PROFILE_DIR, missing-profile warnings=$PGO_USE_MISSING_PROFILE_COUNT"
}

run_sysbench_phase() {
  local build_profile="$1"
  local mysql_port="$2"
  local log_prefix="$3"
  local sysbench_mode="$4"
  local db_engines="$5"
  local state_file="$WORK_ROOT/state/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${build_profile}/runtime.env"
  local clone_state_file=""
  local mysql_data_dir_override=""
  local install_root="$WORK_ROOT/install/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${build_profile}"
  local db_engine warmup_log log_file run_phase

  shutdown_stage_if_running "$state_file"

  log_info "building ${build_profile} with PGO mode ${PGO_MODE}"
  env \
    MYSQL_VER="$MYSQL_VER" \
    MYSQL_MINI_VER="$MYSQL_MINI_VER" \
    BUILD_PROFILE="$build_profile" \
    ENABLE_LTO="$ENABLE_LTO" \
    ENABLE_CCACHE="$ENABLE_CCACHE" \
    LINKER_FLAVOR="$LINKER_FLAVOR" \
    FORCE_INSOURCE_BUILD="$FORCE_INSOURCE_BUILD" \
    BUILD_ROOT="$PGO_BUILD_ROOT" \
    INSTALL_ROOT="$install_root" \
    PGO_MODE="$PGO_MODE" \
    PGO_PROFILE_DIR="$PGO_PROFILE_DIR" \
    bash "$REPO_ROOT/stages/build_normal_80.sh"

  if [[ "$REUSE_NORMAL_DATASET_FOR_PGO" == "ON" ]]; then
    clone_state_file="$NORMAL_STATE_FILE"
  fi

  case "$PGO_DATASET_MODE" in
    clone)
      ;;
    shared_normal_datadir)
      [[ -n "$clone_state_file" ]] || die "PGO_DATASET_MODE=shared_normal_datadir requires REUSE_NORMAL_DATASET_FOR_PGO=ON"
      mysql_data_dir_override="$(read_state_var "$clone_state_file" MYSQL_DATA_DIR)"
      [[ -n "$mysql_data_dir_override" ]] || die "failed to read MYSQL_DATA_DIR from $clone_state_file"
      [[ -d "$mysql_data_dir_override" ]] || die "shared normal datadir does not exist: $mysql_data_dir_override"
      ;;
    *)
      die "unsupported PGO_DATASET_MODE: $PGO_DATASET_MODE"
      ;;
  esac

  log_info "starting ${build_profile} runtime"
  env \
    MYSQL_VER="$MYSQL_VER" \
    MYSQL_MINI_VER="$MYSQL_MINI_VER" \
    BUILD_PROFILE="$build_profile" \
    INSTALL_ROOT="$install_root" \
    MYSQL_PORT="$mysql_port" \
    MYSQL_CLONE_STATE_FILE="$clone_state_file" \
    MYSQL_DATA_DIR_OVERRIDE="$mysql_data_dir_override" \
    bash "$REPO_ROOT/stages/smoke_normal_80.sh"

  [[ -f "$state_file" ]] || die "missing runtime state file: $state_file"
  set -a
  . "$state_file"
  set +a

  if [[ -n "$clone_state_file" ]]; then
    log_info "reusing existing sysbench dataset from $clone_state_file"
    mysql_wait_for_startup_quiesce "$install_root" "$MYSQL_ROOT_DEFAULTS_FILE" "$MYSQL_LOG" 240
    if (( BENCHMARK_SETTLE_SECONDS > 0 )); then
      log_info "sleeping ${BENCHMARK_SETTLE_SECONDS}s after startup quiesce for ${build_profile}"
      sleep "$BENCHMARK_SETTLE_SECONDS"
    fi
    if [[ "$CLONED_DATASET_WARMUP" == "ON" ]]; then
      for db_engine in $db_engines; do
        warmup_log="$LOG_ROOT/sysbench-warmup-${build_profile}-${db_engine}-$(date +%Y%m%d).log"
        log_info "warming cloned sysbench dataset for ${build_profile} db_engine=${db_engine}"
        env \
          MYSQL_ROOT_DEFAULTS_FILE="$MYSQL_ROOT_DEFAULTS_FILE" \
          MYSQL_SOCKET="$MYSQL_SOCKET" \
          SYSBENCH_BASE="$SHARED_SYSBENCH_ROOT" \
          dbeng="$db_engine" \
          bash "$REPO_ROOT/sysbench/warmup-sysbench.sh" "$install_root" \
          2>&1 | tee "$warmup_log"
      done
    fi
  else
    for db_engine in $db_engines; do
      log_info "preparing sysbench dataset for ${build_profile} db_engine=${db_engine}"
      env \
        MYSQL_ROOT_DEFAULTS_FILE="$MYSQL_ROOT_DEFAULTS_FILE" \
        MYSQL_SOCKET="$MYSQL_SOCKET" \
        SYSBENCH_BASE="$SHARED_SYSBENCH_ROOT" \
        dbeng="$db_engine" \
        bash "$REPO_ROOT/sysbench/init-sysbench.sh" "$install_root"

      if (( POST_PREPARE_SETTLE_SECONDS > 0 )); then
        log_info "sleeping ${POST_PREPARE_SETTLE_SECONDS}s after dataset prepare for ${build_profile} db_engine=${db_engine}"
        sleep "$POST_PREPARE_SETTLE_SECONDS"
      fi
    done
  fi

  for db_engine in $db_engines; do
    log_file="$(sysbench_log_for_engine "$log_prefix" "$db_engine")"
    : > "$log_file"

    run_phase="$build_profile"
    if [[ "$db_engine" != "innodb" ]]; then
      run_phase="${build_profile}-${db_engine}"
    fi

    log_info "training/benchmarking ${build_profile} db_engine=${db_engine} TRAIN_MODE=$sysbench_mode"
    env \
      MYSQL_ROOT_DEFAULTS_FILE="$MYSQL_ROOT_DEFAULTS_FILE" \
      MYSQL_SOCKET="$MYSQL_SOCKET" \
      SYSBENCH_BASE="$SHARED_SYSBENCH_ROOT" \
      dbeng="$db_engine" \
      TRAIN_MODE="$sysbench_mode" \
      RUN_PHASE="$run_phase" \
      ACTIVE_BENCHMARK_MODE="$ACTIVE_BENCHMARK_MODE" \
      ACTIVE_BENCHMARK_LOG_ROOT="$ACTIVE_BENCHMARK_LOG_ROOT" \
      ACTIVE_BENCHMARK_PRE_SECONDS="$ACTIVE_BENCHMARK_PRE_SECONDS" \
      ACTIVE_BENCHMARK_POST_SECONDS="$ACTIVE_BENCHMARK_POST_SECONDS" \
      ACTIVE_BENCHMARK_INTERVAL="$ACTIVE_BENCHMARK_INTERVAL" \
      STABILITY_THRESHOLD_PCT="$STABILITY_THRESHOLD_PCT" \
      FAIL_ON_SUSPICIOUS_BENCH="$FAIL_ON_SUSPICIOUS_BENCH" \
      bash "$REPO_ROOT/sysbench/train-sysbench.sh" "$install_root" 2>&1 | tee "$log_file"

    [[ -s "$log_file" ]] || die "sysbench log is empty: $log_file"
  done

  log_info "stopping ${build_profile} runtime"
  "$install_root/bin/mysqladmin" --defaults-file="$MYSQL_ROOT_DEFAULTS_FILE" shutdown
}

ensure_sysbench_root

if [[ "$SKIP_PGO_GENERATE" != "ON" ]]; then
  PGO_MODE=generate
  run_sysbench_phase "$PGO_GEN_PROFILE" "$PGO_GEN_PORT" "$PGO_GEN_LOG_PREFIX" "$PGO_TRAIN_MODE" "$PGO_TRAIN_DB_ENGINES"
else
  log_warn "SKIP_PGO_GENERATE=ON: skipping profile-generate build + sysbench training; reusing existing data in $PGO_PROFILE_DIR"
fi

verify_profile_generation "$PGO_BUILD_ROOT"

PGO_MODE=use
run_sysbench_phase "$PGO_USE_PROFILE" "$PGO_USE_PORT" "$PGO_USE_LOG_PREFIX" "$PGO_BENCHMARK_MODE" "$PGO_VALIDATE_DB_ENGINES"
verify_profile_use "$PGO_BUILD_ROOT" "$PGO_USE_PROFILE"

log_info "packaging pgoed build"
bash "$REPO_ROOT/build-opt/make_package.sh" "$BUILD_ROOT_USE" "pgoed"

VERDICT_BASE_LOG="$(normal_baseline_log_for_engine "$PGO_VERDICT_ENGINE")"
VERDICT_PGO_LOG="$(sysbench_log_for_engine "$PGO_USE_LOG_PREFIX" "$PGO_VERDICT_ENGINE")"
VERDICT_NORMAL_POINT_TPS="$(extract_case_transactions_per_sec "$VERDICT_BASE_LOG" point_select)"
VERDICT_NORMAL_READONLY_TPS="$(extract_case_transactions_per_sec "$VERDICT_BASE_LOG" read_only)"
VERDICT_PGO_POINT_TPS="$(extract_case_transactions_per_sec "$VERDICT_PGO_LOG" point_select)"
VERDICT_PGO_READONLY_TPS="$(extract_case_transactions_per_sec "$VERDICT_PGO_LOG" read_only)"

[[ -n "$VERDICT_NORMAL_READONLY_TPS" ]] || die "failed to parse normal readonly TPS from $VERDICT_BASE_LOG"
[[ -n "$VERDICT_PGO_READONLY_TPS" ]] || die "failed to parse PGO readonly TPS from $VERDICT_PGO_LOG"

VERDICT_STATUS=FAIL
if awk -v pgo="$VERDICT_PGO_READONLY_TPS" -v base="$VERDICT_NORMAL_READONLY_TPS" 'BEGIN { exit !(pgo > base) }'; then
  VERDICT_STATUS=PASS
fi

cat > "$RESULT_FILE" <<EOF2
# PGO Readonly Validation

- date: $(date -Iseconds)
- mysql_version: ${MYSQL_VER}.${MYSQL_MINI_VER}
- pgo_train_mode: ${PGO_TRAIN_MODE}
- pgo_benchmark_mode: ${PGO_BENCHMARK_MODE}
- pgo_train_db_engines: ${PGO_TRAIN_DB_ENGINES}
- pgo_validate_db_engines: ${PGO_VALIDATE_DB_ENGINES}
- pgo_verdict_engine: ${PGO_VERDICT_ENGINE}
- strict_pgo_verdict: ${STRICT_PGO_VERDICT}
- reuse_normal_dataset_for_pgo: ${REUSE_NORMAL_DATASET_FOR_PGO}
- pgo_dataset_mode: ${PGO_DATASET_MODE}
- shared_sysbench_root: ${SHARED_SYSBENCH_ROOT}
- pgo_build_root: ${PGO_BUILD_ROOT}
- pgo_profile_dir: ${PGO_PROFILE_DIR}
- gcda_count: ${GCDA_COUNT}
- gcda_nonzero_count: ${GCDA_NONZERO_COUNT}
- gcda_total_bytes: ${GCDA_TOTAL_BYTES}
- gcda_matching_build_root_count: ${GCDA_MATCHING_BUILD_COUNT}
- pgo_use_missing_profile_count: ${PGO_USE_MISSING_PROFILE_COUNT}
EOF2

{
  echo
  echo "## Logs"
  echo
  for db_engine in $PGO_VALIDATE_DB_ENGINES; do
    echo "- normal_log[${db_engine}]: $(normal_baseline_log_for_engine "$db_engine")"
  done
  for db_engine in $PGO_TRAIN_DB_ENGINES; do
    echo "- pgo_gen_log[${db_engine}]: $(sysbench_log_for_engine "$PGO_GEN_LOG_PREFIX" "$db_engine")"
  done
  for db_engine in $PGO_VALIDATE_DB_ENGINES; do
    echo "- pgo_use_log[${db_engine}]: $(sysbench_log_for_engine "$PGO_USE_LOG_PREFIX" "$db_engine")"
  done
} >> "$RESULT_FILE"

{
  echo
  echo "## TPS Summary"
} >> "$RESULT_FILE"

for db_engine in $PGO_VALIDATE_DB_ENGINES; do
  base_log="$(normal_baseline_log_for_engine "$db_engine")"
  pgo_log="$(sysbench_log_for_engine "$PGO_USE_LOG_PREFIX" "$db_engine")"
  base_point="$(extract_case_transactions_per_sec "$base_log" point_select)"
  base_readonly="$(extract_case_transactions_per_sec "$base_log" read_only)"
  pgo_point="$(extract_case_transactions_per_sec "$pgo_log" point_select)"
  pgo_readonly="$(extract_case_transactions_per_sec "$pgo_log" read_only)"

  base_point="${base_point:-n/a}"
  base_readonly="${base_readonly:-n/a}"
  pgo_point="${pgo_point:-n/a}"
  pgo_readonly="${pgo_readonly:-n/a}"

  cat >> "$RESULT_FILE" <<EOF2

### db_engine=${db_engine}

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | ${base_point} | ${pgo_point} | $(format_improvement_pct "$pgo_point" "$base_point") |
| read_only | ${base_readonly} | ${pgo_readonly} | $(format_improvement_pct "$pgo_readonly" "$base_readonly") |
EOF2
done

cat >> "$RESULT_FILE" <<EOF2

## Verdict

- verdict_engine: ${PGO_VERDICT_ENGINE}
- readonly_vs_normal: ${VERDICT_STATUS}
- readonly improvement vs normal: $(format_improvement_pct "$VERDICT_PGO_READONLY_TPS" "$VERDICT_NORMAL_READONLY_TPS")
EOF2

log_info "pgo validation complete: $RESULT_FILE"

if [[ "$VERDICT_STATUS" != "PASS" && "$STRICT_PGO_VERDICT" == "ON" ]]; then
  die "PGO readonly TPS did not beat normal baseline for db_engine=${PGO_VERDICT_ENGINE}; see $RESULT_FILE"
fi
