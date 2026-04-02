#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/mysql.sh"

: "${MYSQL_VER:=5.7}"
: "${MYSQL_MINI_VER:=44-54}"
: "${WORK_ROOT:=$REPO_ROOT/work}"
: "${LOG_ROOT:=$WORK_ROOT/logs}"
: "${RESULT_ROOT:=$WORK_ROOT/results}"
: "${NORMAL_BUILD_PROFILE:=normal}"
: "${PGO_BUILD_PROFILE:=pgobuild}"
: "${PGO_GEN_PROFILE:=pgo-gen}"
: "${PGO_USE_PROFILE:=pgoed}"
: "${PGO_PROFILE_DIR:=$WORK_ROOT/pgo/ps-${MYSQL_VER}.${MYSQL_MINI_VER}/profile-data}"
: "${TRAIN_MODE:=}"
: "${PGO_TRAIN_MODE:=${TRAIN_MODE:-joint_read}}"
: "${PGO_BENCHMARK_MODE:=${TRAIN_MODE:-readonly}}"
: "${REUSE_NORMAL_DATASET_FOR_PGO:=ON}"
: "${PGO_GEN_PORT:=34081}"
: "${PGO_USE_PORT:=34082}"
: "${CPU_OPT_FLAGS:=-march=nehalem -mtune=haswell}"
: "${SKIP_FULLTEXT_MECAB:=OFF}"

case "$MYSQL_VER" in
  5.6|5.7)
    ;;
  *)
    die "build_pgo_57.sh only supports MYSQL_VER=5.6 or 5.7"
    ;;
esac

require_cmd awk bash find sed tee

SOURCE_DIR="$(detect_source_dir "$REPO_ROOT" "$MYSQL_VER" "$MYSQL_MINI_VER")"
NORMAL_INSTALL_ROOT="$WORK_ROOT/install/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${NORMAL_BUILD_PROFILE}"
NORMAL_BUILD_ROOT="$WORK_ROOT/build/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${NORMAL_BUILD_PROFILE}"
NORMAL_STATE_FILE="$WORK_ROOT/state/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${NORMAL_BUILD_PROFILE}/runtime.env"
NORMAL_TRAIN_LOG="$LOG_ROOT/sysbench-train-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${NORMAL_BUILD_PROFILE}.log"
PGO_BUILD_ROOT="${SOURCE_DIR}_${PGO_BUILD_PROFILE}"
PGO_GEN_BUILD_LOG="$LOG_ROOT/build-normal-${MYSQL_VER}.${MYSQL_MINI_VER}-${PGO_GEN_PROFILE}.log"
PGO_USE_BUILD_LOG="$LOG_ROOT/build-normal-${MYSQL_VER}.${MYSQL_MINI_VER}-${PGO_USE_PROFILE}.log"
PGO_GEN_TRAIN_LOG="$LOG_ROOT/sysbench-train-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${PGO_GEN_PROFILE}.log"
PGO_USE_TRAIN_LOG="$LOG_ROOT/sysbench-train-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${PGO_USE_PROFILE}.log"
RESULT_FILE="$RESULT_ROOT/pgo-${PGO_BENCHMARK_MODE}-${MYSQL_VER}.${MYSQL_MINI_VER}-$(date +%Y%m%d).md"
COMPILE_TIME_DIR="$LOG_ROOT/compile-times"

ensure_dir "$LOG_ROOT"
ensure_dir "$RESULT_ROOT"
ensure_dir "$COMPILE_TIME_DIR"
rm -rf "$PGO_PROFILE_DIR"
ensure_dir "$PGO_PROFILE_DIR"

[[ -x "$NORMAL_INSTALL_ROOT/bin/mysqld" ]] || die "missing normal install root: $NORMAL_INSTALL_ROOT"
[[ -d "$NORMAL_BUILD_ROOT" ]] || die "missing normal build root: $NORMAL_BUILD_ROOT"
[[ -f "$NORMAL_STATE_FILE" ]] || die "missing normal runtime state: $NORMAL_STATE_FILE"
[[ -f "$NORMAL_TRAIN_LOG" ]] || die "missing normal train log: $NORMAL_TRAIN_LOG"

if mysql_supports_mecab "$MYSQL_VER" && [[ "$SKIP_FULLTEXT_MECAB" != "ON" ]]; then
  export MECAB_INC="${MECAB_INC:-$(find_mecab_prefix || true)}"
  [[ -n "${MECAB_INC:-}" ]] || die "mecab headers not found; install fulltext mecab dependencies or pass --skip-fulltext-mecab"
fi

extract_case_tps() {
  local log_file="$1"
  local case_name="$2"
  local legacy_index=""
  local value=""

  value="$(awk -v target="$case_name" '
    $0 ~ "=== SYSBENCH_CASE_BEGIN" && $0 ~ ("case=" target " ") { in_case=1; next }
    in_case && /transactions:/ {
      metric=$3
      gsub(/[()]/, "", metric)
      print metric
      exit
    }
    $0 ~ "=== SYSBENCH_CASE_END" && in_case { in_case=0 }
  ' "$log_file")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  case "$case_name" in
    point_select) legacy_index=1 ;;
    read_only) legacy_index=2 ;;
    read_write) legacy_index=3 ;;
    *) legacy_index="" ;;
  esac

  [[ -n "$legacy_index" ]] || return 0

  awk '/transactions:/ { metric=$3; gsub(/[()]/, "", metric); values[++count]=metric } END { if (count >= idx) print values[idx] }' idx="$legacy_index" "$log_file"
}

verify_profile_generation() {
  local count nonzero total_bytes matching_build_count escaped_prefix
  read -r count nonzero total_bytes <<<"$(find "$PGO_PROFILE_DIR" -type f -name '*.gcda' -printf '%s\n' | awk '{sum+=$1; count+=1; if ($1 > 0) nz+=1} END {printf "%d %d %d\n", count, nz, sum}')"
  (( count > 0 )) || die "no gcda files found under $PGO_PROFILE_DIR"
  (( nonzero > 0 )) || die "all gcda files are zero-sized under $PGO_PROFILE_DIR"
  escaped_prefix="${PGO_BUILD_ROOT////#}"
  matching_build_count="$(find "$PGO_PROFILE_DIR" -type f -name '*.gcda' | awk -v prefix="$escaped_prefix" 'index($0, prefix) { count += 1 } END { print count + 0 }')"
  (( matching_build_count > 0 )) || die "profile data under $PGO_PROFILE_DIR does not match build root $PGO_BUILD_ROOT"
  log_info "profile generation complete: gcda_count=$count nonzero=$nonzero total_bytes=$total_bytes matching_build_count=$matching_build_count"
}

verify_profile_use() {
  local cache_file="$PGO_BUILD_ROOT/CMakeCache.txt"
  [[ -f "$cache_file" ]] || die "missing CMake cache: $cache_file"
  grep -F -- "-fprofile-use" "$PGO_USE_BUILD_LOG" >/dev/null || die "build log does not contain -fprofile-use"
  grep -F -- "$PGO_PROFILE_DIR" "$PGO_USE_BUILD_LOG" >/dev/null || die "build log does not reference $PGO_PROFILE_DIR"
  log_info "profile-use compile confirmed in $PGO_USE_BUILD_LOG"
}

run_smoke_with_optional_clone() {
  local build_profile="$1"
  local install_root="$2"
  local mysql_port="$3"
  local clone_state_file=""

  if [[ "$REUSE_NORMAL_DATASET_FOR_PGO" == "ON" ]]; then
    clone_state_file="$NORMAL_STATE_FILE"
  fi

  env \
    MYSQL_VER="$MYSQL_VER" \
    MYSQL_MINI_VER="$MYSQL_MINI_VER" \
    BUILD_PROFILE="$build_profile" \
    WORK_ROOT="$WORK_ROOT" \
    INSTALL_ROOT="$install_root" \
    MYSQL_PORT="$mysql_port" \
    MYSQL_CLONE_STATE_FILE="$clone_state_file" \
    bash "$REPO_ROOT/stages/smoke_normal.sh"
}

run_train_only() {
  local build_profile="$1"
  local install_root="$2"
  local output_log="$3"
  local sysbench_mode="$4"
  local state_file="$WORK_ROOT/state/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${build_profile}/runtime.env"

  set -a
  . "$state_file"
  set +a

  log_info "waiting for MySQL startup quiesce for ${build_profile}"
  mysql_wait_for_startup_quiesce "$install_root" "$MYSQL_ROOT_DEFAULTS_FILE" "$MYSQL_LOG" 240

  if [[ ! -x "$install_root/sysbench/bin/sysbench" ]]; then
    (
      cd "$REPO_ROOT"
      env SYSBENCH_BASE="$install_root/sysbench" bash "$REPO_ROOT/sysbench/compile-sysbench.sh" "$install_root"
    ) | tee "$LOG_ROOT/sysbench-compile-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${build_profile}.log"
  fi

  {
    echo "=== TRAIN_PHASE_BEGIN profile=${build_profile} ==="
    echo "=== MYSQL_VERSION_BEGIN profile=${build_profile} ==="
    "$install_root/bin/mysql" --defaults-file="$MYSQL_ROOT_DEFAULTS_FILE" -Nse 'SELECT VERSION()'
    echo "=== MYSQL_VERSION_END profile=${build_profile} ==="
    env \
      MYSQL_ROOT_DEFAULTS_FILE="$MYSQL_ROOT_DEFAULTS_FILE" \
      MYSQL_SOCKET="$MYSQL_SOCKET" \
      SYSBENCH_BASE="$install_root/sysbench" \
      TRAIN_MODE="$sysbench_mode" \
      RUN_PHASE="$build_profile" \
      table_size="${table_size:-}" \
      table_count="${table_count:-}" \
      oltp_threads="${oltp_threads:-}" \
      warmup_time="${warmup_time:-}" \
      max_point_select_time="${max_point_select_time:-}" \
      max_oltp_time="${max_oltp_time:-}" \
      dbeng="${dbeng:-}" \
      bash "$REPO_ROOT/sysbench/train-sysbench.sh" "$install_root"
    echo "=== TRAIN_PHASE_END profile=${build_profile} ==="
  } | tee "$output_log"

  mysql_shutdown_with_defaults "$install_root/bin/mysqladmin" "$MYSQL_ROOT_DEFAULTS_FILE"
}

log_info "building profile-generate binary"
(
  cd "$REPO_ROOT"
  bash "$REPO_ROOT/build-normal/prepare_build.sh" "$SOURCE_DIR" "$MYSQL_VER" "$PGO_BUILD_PROFILE"
  bash "$REPO_ROOT/build-opt/patch_version.sh" "$PGO_BUILD_ROOT"
  export MYSQL_BASE="$NORMAL_INSTALL_ROOT"
  export optflags=" $CPU_OPT_FLAGS -fprofile-generate -fprofile-dir=$PGO_PROFILE_DIR"
  bash "$REPO_ROOT/build-normal/compile.sh" "$NORMAL_INSTALL_ROOT" "$PGO_BUILD_ROOT" "$MYSQL_VER"
  bash "$REPO_ROOT/build-normal/install_mini.sh" "$PGO_BUILD_ROOT" "$NORMAL_INSTALL_ROOT"
) 2>&1 | tee "$PGO_GEN_BUILD_LOG"
[[ -f "/tmp/${MYSQL_VER}_build" ]] && cp "/tmp/${MYSQL_VER}_build" "$COMPILE_TIME_DIR/${MYSQL_VER}.${MYSQL_MINI_VER}-${PGO_GEN_PROFILE}.txt"

run_smoke_with_optional_clone "$PGO_GEN_PROFILE" "$NORMAL_INSTALL_ROOT" "$PGO_GEN_PORT"
run_train_only "$PGO_GEN_PROFILE" "$NORMAL_INSTALL_ROOT" "$PGO_GEN_TRAIN_LOG" "$PGO_TRAIN_MODE"
verify_profile_generation

log_info "building profile-use binary"
(
  cd "$PGO_BUILD_ROOT"
  export MYSQL_BASE="$NORMAL_INSTALL_ROOT"
  export optflags=" $CPU_OPT_FLAGS -fprofile-use -fprofile-dir=$PGO_PROFILE_DIR -fprofile-correction -Wno-missing-profile"
  bash "$REPO_ROOT/build-normal/compile.sh" "$NORMAL_INSTALL_ROOT" "$PGO_BUILD_ROOT" "$MYSQL_VER"
  bash "$REPO_ROOT/build-normal/install_mini.sh" "$PGO_BUILD_ROOT" "$NORMAL_INSTALL_ROOT"
) 2>&1 | tee "$PGO_USE_BUILD_LOG"
[[ -f "/tmp/${MYSQL_VER}_build" ]] && cp "/tmp/${MYSQL_VER}_build" "$COMPILE_TIME_DIR/${MYSQL_VER}.${MYSQL_MINI_VER}-${PGO_USE_PROFILE}.txt"
verify_profile_use

run_smoke_with_optional_clone "$PGO_USE_PROFILE" "$NORMAL_INSTALL_ROOT" "$PGO_USE_PORT"
run_train_only "$PGO_USE_PROFILE" "$NORMAL_INSTALL_ROOT" "$PGO_USE_TRAIN_LOG" "$PGO_BENCHMARK_MODE"

NORMAL_POINT_SELECT_TPS="$(extract_case_tps "$NORMAL_TRAIN_LOG" point_select)"
NORMAL_READ_ONLY_TPS="$(extract_case_tps "$NORMAL_TRAIN_LOG" read_only)"
PGO_POINT_SELECT_TPS="$(extract_case_tps "$PGO_USE_TRAIN_LOG" point_select)"
PGO_READ_ONLY_TPS="$(extract_case_tps "$PGO_USE_TRAIN_LOG" read_only)"

[[ -n "$NORMAL_READ_ONLY_TPS" ]] || die "failed to parse normal read_only TPS from $NORMAL_TRAIN_LOG"
[[ -n "$PGO_READ_ONLY_TPS" ]] || die "failed to parse pgo read_only TPS from $PGO_USE_TRAIN_LOG"

READONLY_DELTA_PCT="$(awk -v n="$NORMAL_READ_ONLY_TPS" -v p="$PGO_READ_ONLY_TPS" 'BEGIN { if (n == 0) { print "inf" } else { printf "%.2f", ((p - n) / n) * 100 } }')"
POINT_DELTA_PCT="$(awk -v n="$NORMAL_POINT_SELECT_TPS" -v p="$PGO_POINT_SELECT_TPS" 'BEGIN { if (n == 0) { print "inf" } else { printf "%.2f", ((p - n) / n) * 100 } }')"

log_info "packaging PGO build"
(
  cd "$REPO_ROOT"
  bash "$REPO_ROOT/build-opt/make_package.sh" "$PGO_BUILD_ROOT" "$PGO_USE_PROFILE"
)

cat > "$RESULT_FILE" <<RESULT
# Percona Server ${MYSQL_VER}.${MYSQL_MINI_VER} PGO Validation

- pgo_train_mode: ${PGO_TRAIN_MODE}
- pgo_benchmark_mode: ${PGO_BENCHMARK_MODE}
- host work root: ${WORK_ROOT}
- source dir: ${SOURCE_DIR}
- pgo build root: ${PGO_BUILD_ROOT}
- normal install root: ${NORMAL_INSTALL_ROOT}
- pgo profile dir: ${PGO_PROFILE_DIR}
- mecab prefix: ${MECAB_INC:-disabled}
- normal point_select TPS: ${NORMAL_POINT_SELECT_TPS}
- normal read_only TPS: ${NORMAL_READ_ONLY_TPS}
- pgo point_select TPS: ${PGO_POINT_SELECT_TPS}
- pgo read_only TPS: ${PGO_READ_ONLY_TPS}
- point_select delta: ${POINT_DELTA_PCT}%
- read_only delta: ${READONLY_DELTA_PCT}%
- normal baseline log: ${NORMAL_TRAIN_LOG}
- pgo-gen training log: ${PGO_GEN_TRAIN_LOG}
- pgo validation log: ${PGO_USE_TRAIN_LOG}
- pgo build log: ${PGO_USE_BUILD_LOG}
RESULT

awk -v delta="$READONLY_DELTA_PCT" 'BEGIN { exit !(delta+0 > 0) }' || die "PGO read_only delta is not positive: ${READONLY_DELTA_PCT}%"

log_info "5.x PGO flow complete; result summary: $RESULT_FILE"
