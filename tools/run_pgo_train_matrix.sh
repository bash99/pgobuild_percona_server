#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

: "${MYSQL_VER:=8.4}"
: "${MYSQL_MINI_VER:=7-7}"
: "${WORK_ROOT:=$REPO_ROOT/work}"
: "${MATRIX_ROOT:=$WORK_ROOT/profile-matrix-${MYSQL_VER}.${MYSQL_MINI_VER}-$(date +%Y%m%d-%H%M%S)}"
: "${MATRIX_MAX_RETRIES:=3}"
: "${BENCHMARK_SETTLE_SECONDS:=120}"
: "${POST_PREPARE_SETTLE_SECONDS:=120}"
: "${ACTIVE_BENCHMARK_MODE:=ON}"
: "${ACTIVE_BENCHMARK_PRE_SECONDS:=30}"
: "${ACTIVE_BENCHMARK_POST_SECONDS:=30}"
: "${ACTIVE_BENCHMARK_INTERVAL:=1}"
: "${STABILITY_THRESHOLD_PCT:=10}"
: "${FAIL_ON_SUSPICIOUS_BENCH:=ON}"
: "${CLONED_DATASET_WARMUP:=ON}"
: "${MATRIX_SUMMARY_ONLY:=OFF}"

case "$MYSQL_VER" in
  8.0|8.4)
    ;;
  *)
    die "run_pgo_train_matrix.sh only supports MYSQL_VER=8.0 or 8.4"
    ;;
esac

require_cmd awk date grep sed

ensure_dir "$MATRIX_ROOT"
ensure_dir "$MATRIX_ROOT/logs"
ensure_dir "$MATRIX_ROOT/results"
ensure_dir "$MATRIX_ROOT/active"
ensure_dir "$MATRIX_ROOT/packages"

BASELINE_LOG_ROOT="$MATRIX_ROOT/logs/normal"
BASELINE_ACTIVE_ROOT="$MATRIX_ROOT/active/normal"
BASELINE_RESULT_ROOT="$MATRIX_ROOT/results/normal"
BASELINE_LOG_FILE="$BASELINE_LOG_ROOT/sysbench-train-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-normal.log"
SUMMARY_FILE="$MATRIX_ROOT/matrix-summary.md"
RUN_NOTE_FILE="$MATRIX_ROOT/run-info.txt"
MATRIX_BASENAME="$(basename "$MATRIX_ROOT")"

cat > "$RUN_NOTE_FILE" <<EOF
date=$(date -Iseconds)
repo_root=$REPO_ROOT
mysql_ver=$MYSQL_VER
mysql_mini_ver=$MYSQL_MINI_VER
work_root=$WORK_ROOT
matrix_root=$MATRIX_ROOT
benchmark_settle_seconds=$BENCHMARK_SETTLE_SECONDS
post_prepare_settle_seconds=$POST_PREPARE_SETTLE_SECONDS
active_benchmark_mode=$ACTIVE_BENCHMARK_MODE
active_benchmark_pre_seconds=$ACTIVE_BENCHMARK_PRE_SECONDS
active_benchmark_post_seconds=$ACTIVE_BENCHMARK_POST_SECONDS
active_benchmark_interval=$ACTIVE_BENCHMARK_INTERVAL
stability_threshold_pct=$STABILITY_THRESHOLD_PCT
fail_on_suspicious_bench=$FAIL_ON_SUSPICIOUS_BENCH
cloned_dataset_warmup=$CLONED_DATASET_WARMUP
EOF

extract_case_tps() {
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

extract_stability_status() {
  local log_file="$1"
  local case_name="$2"
  grep "=== SYSBENCH_CASE_STABILITY " "$log_file" | grep "case=${case_name} " | tail -n 1 | sed -n 's/.*status=\([^ ]*\).*/\1/p'
}

read_attempt_meta() {
  local meta_file="$1"
  local key="$2"

  sed -n "s/^${key}=//p" "$meta_file" | head -n 1
}

latest_attempt_for_mode() {
  local mode="$1"
  local mode_root="$MATRIX_ROOT/results/$mode"
  local latest_file="$mode_root/latest-attempt.txt"
  local attempt=""

  if [[ -f "$latest_file" ]]; then
    attempt="$(grep -E '^[0-9]+$' "$latest_file" | tail -n 1 || true)"
  fi

  if [[ -z "$attempt" && -d "$mode_root" ]]; then
    attempt="$(
      find "$mode_root" -maxdepth 1 -mindepth 1 -type d -name 'attempt-*' -printf '%f\n' \
        | sed 's/^attempt-//' | sort -n | tail -n 1
    )"
  fi

  [[ -n "$attempt" ]] || return 1
  printf '%s\n' "$attempt" > "$latest_file"
  printf '%s\n' "$attempt"
}

resolve_matrix_path() {
  local raw_path="$1"
  local marker suffix candidate

  [[ -n "$raw_path" ]] || return 0

  if [[ -e "$raw_path" ]]; then
    printf '%s\n' "$raw_path"
    return 0
  fi

  marker="/${MATRIX_BASENAME}/"
  if [[ "$raw_path" == *"$marker"* ]]; then
    suffix="${raw_path#*${marker}}"
    candidate="$MATRIX_ROOT/$suffix"
    if [[ -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  printf '%s\n' "$raw_path"
}

ensure_normal_runtime() {
  local install_root="$WORK_ROOT/install/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-normal"
  local state_file="$WORK_ROOT/state/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-normal/runtime.env"

  if [[ ! -x "$install_root/bin/mysqld" ]]; then
    env MYSQL_VER="$MYSQL_VER" MYSQL_MINI_VER="$MYSQL_MINI_VER" WORK_ROOT="$WORK_ROOT" \
      bash "$REPO_ROOT/stages/build_normal_80.sh"
  fi

  if [[ ! -f "$state_file" ]]; then
    env MYSQL_VER="$MYSQL_VER" MYSQL_MINI_VER="$MYSQL_MINI_VER" WORK_ROOT="$WORK_ROOT" \
      bash "$REPO_ROOT/stages/smoke_normal_80.sh"
  fi
}

run_normal_baseline() {
  ensure_normal_runtime
  ensure_dir "$BASELINE_LOG_ROOT"
  ensure_dir "$BASELINE_RESULT_ROOT"
  ensure_dir "$BASELINE_ACTIVE_ROOT"

  env \
    MYSQL_VER="$MYSQL_VER" \
    MYSQL_MINI_VER="$MYSQL_MINI_VER" \
    WORK_ROOT="$WORK_ROOT" \
    LOG_ROOT="$BASELINE_LOG_ROOT" \
    BENCHMARK_MODE="readonly" \
    BENCHMARK_SETTLE_SECONDS="$BENCHMARK_SETTLE_SECONDS" \
    POST_PREPARE_SETTLE_SECONDS="$POST_PREPARE_SETTLE_SECONDS" \
    ACTIVE_BENCHMARK_MODE="$ACTIVE_BENCHMARK_MODE" \
    ACTIVE_BENCHMARK_LOG_ROOT="$BASELINE_ACTIVE_ROOT" \
    ACTIVE_BENCHMARK_PRE_SECONDS="$ACTIVE_BENCHMARK_PRE_SECONDS" \
    ACTIVE_BENCHMARK_POST_SECONDS="$ACTIVE_BENCHMARK_POST_SECONDS" \
    ACTIVE_BENCHMARK_INTERVAL="$ACTIVE_BENCHMARK_INTERVAL" \
    STABILITY_THRESHOLD_PCT="$STABILITY_THRESHOLD_PCT" \
    FAIL_ON_SUSPICIOUS_BENCH="$FAIL_ON_SUSPICIOUS_BENCH" \
    bash "$REPO_ROOT/stages/benchmark_normal_80.sh"
}

run_normal_baseline_with_retry() {
  local attempt
  for attempt in $(seq 1 "$MATRIX_MAX_RETRIES"); do
    if run_normal_baseline; then
      printf '%s\n' "$attempt" > "$BASELINE_RESULT_ROOT/latest-attempt.txt"
      return 0
    fi
    log_warn "normal baseline attempt=$attempt failed; retrying"
  done
  return 1
}

run_mode_once() {
  local mode="$1"
  local attempt="$2"
  local log_root="$MATRIX_ROOT/logs/$mode/attempt-$attempt"
  local result_root="$MATRIX_ROOT/results/$mode/attempt-$attempt"
  local active_root="$MATRIX_ROOT/active/$mode/attempt-$attempt"
  local package_copy="$MATRIX_ROOT/packages/Percona-Server-${MYSQL_VER}.${MYSQL_MINI_VER}-PGOed.${mode}.attempt-${attempt}.mini.tar.zst"

  ensure_dir "$log_root"
  ensure_dir "$result_root"
  ensure_dir "$active_root"

  env \
    MYSQL_VER="$MYSQL_VER" \
    MYSQL_MINI_VER="$MYSQL_MINI_VER" \
    WORK_ROOT="$WORK_ROOT" \
    LOG_ROOT="$log_root" \
    RESULT_ROOT="$result_root" \
    NORMAL_BASELINE_LOG="$BASELINE_LOG_FILE" \
    PGO_TRAIN_MODE="$mode" \
    PGO_BENCHMARK_MODE="readonly" \
    BENCHMARK_SETTLE_SECONDS="$BENCHMARK_SETTLE_SECONDS" \
    POST_PREPARE_SETTLE_SECONDS="$POST_PREPARE_SETTLE_SECONDS" \
    ACTIVE_BENCHMARK_MODE="$ACTIVE_BENCHMARK_MODE" \
    ACTIVE_BENCHMARK_LOG_ROOT="$active_root" \
    ACTIVE_BENCHMARK_PRE_SECONDS="$ACTIVE_BENCHMARK_PRE_SECONDS" \
    ACTIVE_BENCHMARK_POST_SECONDS="$ACTIVE_BENCHMARK_POST_SECONDS" \
    ACTIVE_BENCHMARK_INTERVAL="$ACTIVE_BENCHMARK_INTERVAL" \
    STABILITY_THRESHOLD_PCT="$STABILITY_THRESHOLD_PCT" \
    FAIL_ON_SUSPICIOUS_BENCH="$FAIL_ON_SUSPICIOUS_BENCH" \
    CLONED_DATASET_WARMUP="$CLONED_DATASET_WARMUP" \
    bash "$REPO_ROOT/stages/build_pgo_80.sh"

  cp -f "$REPO_ROOT/Percona-Server-${MYSQL_VER}.${MYSQL_MINI_VER}-PGOed.Linux.x86_64.almalinux9.mini.tar.zst" "$package_copy"

  cat > "$result_root/attempt.env" <<EOF
mode=$mode
attempt=$attempt
log_root=$log_root
result_root=$result_root
active_root=$active_root
package_copy=$package_copy
pgo_gen_log=$(find "$log_root" -maxdepth 1 -type f -name 'sysbench-train-pgo-gen-*.log' | sort | tail -n 1)
pgo_use_log=$(find "$log_root" -maxdepth 1 -type f -name 'sysbench-train-pgoed-*.log' | sort | tail -n 1)
result_file=$(find "$result_root" -maxdepth 1 -type f -name 'pgo-readonly-*.md' | sort | tail -n 1)
EOF
}

run_mode_with_retry() {
  local mode="$1"
  local attempt
  for attempt in $(seq 1 "$MATRIX_MAX_RETRIES"); do
    if run_mode_once "$mode" "$attempt" >&2; then
      printf '%s\n' "$attempt"
      return 0
    fi
    log_warn "mode=$mode attempt=$attempt failed; retrying"
  done
  return 1
}

render_summary() {
  local baseline_log="$BASELINE_LOG_FILE"
  local normal_point normal_read
  local mode attempt result_root result_file train_log gen_log package_copy meta_file
  local gen_point gen_read pgo_point pgo_read point_status read_status point_delta read_delta

  normal_point="$(extract_case_tps "$baseline_log" point_select)"
  normal_read="$(extract_case_tps "$baseline_log" read_only)"

  cat > "$SUMMARY_FILE" <<EOF
# PGO Train Mode Matrix

- date: $(date -Iseconds)
- mysql_version: ${MYSQL_VER}.${MYSQL_MINI_VER}
- work_root: ${WORK_ROOT}
- matrix_root: ${MATRIX_ROOT}
- baseline_log: ${baseline_log}

## Normal Baseline

| workload | tps |
| --- | ---: |
| point_select | ${normal_point} |
| read_only | ${normal_read} |

## Train Modes

| train_mode | gen_point_select | gen_read_only | pgo_point_select | pgo_read_only | point_select_delta | read_only_delta | point_stability | read_stability |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
EOF

  for mode in point_select_only read_only_only joint_read full; do
    attempt="$(latest_attempt_for_mode "$mode")" || die "unable to determine latest attempt for mode=$mode"
    result_root="$MATRIX_ROOT/results/$mode/attempt-$attempt"
    meta_file="$result_root/attempt.env"
    gen_log="$(resolve_matrix_path "$(read_attempt_meta "$meta_file" pgo_gen_log)")"
    train_log="$(resolve_matrix_path "$(read_attempt_meta "$meta_file" pgo_use_log)")"
    result_file="$(resolve_matrix_path "$(read_attempt_meta "$meta_file" result_file)")"
    package_copy="$(resolve_matrix_path "$(read_attempt_meta "$meta_file" package_copy)")"

    gen_point="$(extract_case_tps "$gen_log" point_select || true)"
    gen_read="$(extract_case_tps "$gen_log" read_only || true)"
    pgo_point="$(extract_case_tps "$train_log" point_select || true)"
    pgo_read="$(extract_case_tps "$train_log" read_only || true)"
    point_status="$(extract_stability_status "$train_log" point_select || true)"
    read_status="$(extract_stability_status "$train_log" read_only || true)"
    point_delta="$(awk -v base="$normal_point" -v val="$pgo_point" 'BEGIN { if (base == "" || val == "") { print "n/a"; exit } printf "%.2f%%", ((val - base) / base) * 100 }')"
    read_delta="$(awk -v base="$normal_read" -v val="$pgo_read" 'BEGIN { if (base == "" || val == "") { print "n/a"; exit } printf "%.2f%%", ((val - base) / base) * 100 }')"

    printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
      "$mode" "${gen_point:-n/a}" "${gen_read:-n/a}" "${pgo_point:-n/a}" "${pgo_read:-n/a}" \
      "$point_delta" "$read_delta" "${point_status:-n/a}" "${read_status:-n/a}" >> "$SUMMARY_FILE"
    printf '\n- %s attempt: %s\n- result_file: %s\n- gen_log: %s\n- pgo_log: %s\n- package: %s\n' \
      "$mode" "$attempt" "$result_file" "$gen_log" "$train_log" "$package_copy" >> "$SUMMARY_FILE"
  done
}

if [[ "$MATRIX_SUMMARY_ONLY" == "ON" ]]; then
  render_summary
  echo "matrix summary refreshed: $SUMMARY_FILE"
  exit 0
fi

run_normal_baseline_with_retry || die "normal baseline failed after retries"

for mode in point_select_only read_only_only joint_read full; do
  attempt="$(run_mode_with_retry "$mode")" || die "mode=$mode failed after retries"
  ensure_dir "$MATRIX_ROOT/results/$mode"
  printf '%s\n' "$attempt" > "$MATRIX_ROOT/results/$mode/latest-attempt.txt"
done

render_summary
echo "matrix completed: $SUMMARY_FILE"
