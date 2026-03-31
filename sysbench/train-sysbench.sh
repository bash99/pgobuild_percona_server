#!/bin/bash

set -euo pipefail

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

. "$SELF_PATH/common_config.sh"

CUR_PATH=`pwd`
cd "$SYSBENCH_LUA_DIR"

TRAIN_MODE=${TRAIN_MODE:-full}
RUN_PHASE=${RUN_PHASE:-unspecified}
ACTIVE_BENCHMARK_MODE=${ACTIVE_BENCHMARK_MODE:-OFF}
ACTIVE_BENCHMARK_LOG_ROOT=${ACTIVE_BENCHMARK_LOG_ROOT:-}
ACTIVE_BENCHMARK_PRE_SECONDS=${ACTIVE_BENCHMARK_PRE_SECONDS:-30}
ACTIVE_BENCHMARK_POST_SECONDS=${ACTIVE_BENCHMARK_POST_SECONDS:-30}
ACTIVE_BENCHMARK_INTERVAL=${ACTIVE_BENCHMARK_INTERVAL:-1}
STABILITY_THRESHOLD_PCT=${STABILITY_THRESHOLD_PCT:-10}
FAIL_ON_SUSPICIOUS_BENCH=${FAIL_ON_SUSPICIOUS_BENCH:-OFF}
READ_ONLY_ONLY_TIME=${READ_ONLY_ONLY_TIME:-$max_oltp_time}
POINT_SELECT_ONLY_TIME=${POINT_SELECT_ONLY_TIME:-$standalone_point_select_time}

ensure_dir() {
  mkdir -p "$1"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

find_mysqld_pid() {
  pgrep -nf "$MYSQL_BASE/bin/mysqld" || true
}

start_background_sampler() {
  local log_file="$1"
  shift
  "$@" >"$log_file" 2>&1 &
  printf '%s\n' "$!"
}

stop_background_samplers() {
  local sampler_pid
  for sampler_pid in "$@"; do
    [[ -n "$sampler_pid" ]] || continue
    kill "$sampler_pid" >/dev/null 2>&1 || true
  done

  for sampler_pid in "$@"; do
    [[ -n "$sampler_pid" ]] || continue
    wait "$sampler_pid" >/dev/null 2>&1 || true
  done
}

evaluate_case_stability() {
  local case_name="$1"
  local log_file="$2"
  local phase="$3"

  if [[ "$case_name" == "read_write" ]]; then
    echo "=== SYSBENCH_CASE_STABILITY phase=${phase} case=${case_name} status=SKIPPED reason=read_write_exempt ==="
    return 0
  fi

  awk '
    /^\[/ {
      for (i = 1; i <= NF; ++i) {
        if ($i == "tps:") {
          value = $(i + 1)
          gsub(/[^0-9.]/, "", value)
          samples[++count] = value + 0
          break
        }
      }
    }
    END {
      if (count <= 1) {
        printf "=== SYSBENCH_CASE_STABILITY phase=%s case=%s status=SKIPPED reason=insufficient_samples total_samples=%d ===\n", phase, case_name, count
        exit 0
      }

      for (i = 2; i <= count; ++i) {
        sample = samples[i]
        sum += sample
        if (stable_count == 0 || sample < min) min = sample
        if (stable_count == 0 || sample > max) max = sample
        stable_count += 1
      }

      mean = sum / stable_count
      high_dev = ((max - mean) / mean) * 100
      low_dev = ((mean - min) / mean) * 100
      max_dev = high_dev > low_dev ? high_dev : low_dev
      status = max_dev > threshold ? "SUSPICIOUS" : "STABLE"

      printf "=== SYSBENCH_CASE_STABILITY phase=%s case=%s status=%s samples=%d mean_tps=%.2f min_tps=%.2f max_tps=%.2f max_deviation_pct=%.2f threshold_pct=%.2f ===\n", \
        phase, case_name, status, stable_count, mean, min, max, max_dev, threshold

      exit (status == "SUSPICIOUS") ? 86 : 0
    }
  ' phase="$phase" case_name="$case_name" threshold="$STABILITY_THRESHOLD_PCT" "$log_file"
}

run_case_with_sampling() {
  local case_name="$1"
  local lua_script="$2"
  local time_limit="$3"
  local temp_log="$4"
  local case_stamp case_dir prefix mysqld_pid sysbench_pid
  local -a sampler_pids=()

  if [[ "$ACTIVE_BENCHMARK_MODE" != "ON" ]]; then
    "$SYSBENCH_BIN" "$lua_script" $SYSBENCH_OPT --time=${time_limit} run >"$temp_log" 2>&1
    return 0
  fi

  ensure_dir "$ACTIVE_BENCHMARK_LOG_ROOT"
  case_dir="$ACTIVE_BENCHMARK_LOG_ROOT/$RUN_PHASE"
  ensure_dir "$case_dir"
  case_stamp="$(date +%Y%m%dT%H%M%S)"
  prefix="$case_dir/${case_name}-${case_stamp}"
  mysqld_pid="$(find_mysqld_pid)"

  echo "=== SYSBENCH_CASE_SAMPLING phase=${RUN_PHASE} case=${case_name} prefix=${prefix} pre_seconds=${ACTIVE_BENCHMARK_PRE_SECONDS} post_seconds=${ACTIVE_BENCHMARK_POST_SECONDS} interval_seconds=${ACTIVE_BENCHMARK_INTERVAL} mysqld_pid=${mysqld_pid:-unknown} ==="

  if has_cmd mpstat; then
    sampler_pids+=("$(start_background_sampler "${prefix}.mpstat.log" env LC_ALL=C S_TIME_FORMAT=ISO mpstat -P ALL "$ACTIVE_BENCHMARK_INTERVAL")")
  fi
  if has_cmd iostat; then
    sampler_pids+=("$(start_background_sampler "${prefix}.iostat.log" env LC_ALL=C S_TIME_FORMAT=ISO iostat -xtm -y -t "$ACTIVE_BENCHMARK_INTERVAL")")
  fi
  if has_cmd pidstat && [[ -n "$mysqld_pid" ]]; then
    sampler_pids+=("$(start_background_sampler "${prefix}.pidstat-pre.log" env LC_ALL=C S_TIME_FORMAT=ISO pidstat -durh -p "$mysqld_pid" "$ACTIVE_BENCHMARK_INTERVAL")")
  fi

  sleep "$ACTIVE_BENCHMARK_PRE_SECONDS"

  "$SYSBENCH_BIN" "$lua_script" $SYSBENCH_OPT --time=${time_limit} run >"$temp_log" 2>&1 &
  sysbench_pid=$!

  if has_cmd pidstat; then
    sampler_pids+=("$(start_background_sampler "${prefix}.pidstat.log" env LC_ALL=C S_TIME_FORMAT=ISO pidstat -durh -p "${mysqld_pid:-0},${sysbench_pid}" "$ACTIVE_BENCHMARK_INTERVAL")")
  fi

  wait "$sysbench_pid"
  sleep "$ACTIVE_BENCHMARK_POST_SECONDS"
  stop_background_samplers "${sampler_pids[@]}"
}

run_case() {
  local case_name="$1"
  local lua_script="$2"
  local time_limit="$3"
  local temp_log

  temp_log="$(mktemp)"
  trap 'rm -f "$temp_log"' RETURN

  echo "=== SYSBENCH_CASE_BEGIN phase=${RUN_PHASE} case=${case_name} ==="
  run_case_with_sampling "$case_name" "$lua_script" "$time_limit" "$temp_log"
  cat "$temp_log"

  if evaluate_case_stability "$case_name" "$temp_log" "$RUN_PHASE"; then
    :
  else
    local status=$?
    if [[ "$status" -eq 86 && "$FAIL_ON_SUSPICIOUS_BENCH" == "ON" ]]; then
      echo "=== SYSBENCH_CASE_END phase=${RUN_PHASE} case=${case_name} status=FAILED_SUSPICIOUS ==="
      return "$status"
    fi
  fi

  echo "=== SYSBENCH_CASE_END phase=${RUN_PHASE} case=${case_name} ==="
  rm -f "$temp_log"
  trap - RETURN
}

case "$TRAIN_MODE" in
  point_select|point_select_only)
    run_case point_select oltp_point_select.lua ${POINT_SELECT_ONLY_TIME}
    ;;
  read_only|read_only_only)
    run_case read_only oltp_read_only.lua ${READ_ONLY_ONLY_TIME}
    ;;
  readonly|joint_read)
    run_case point_select oltp_point_select.lua ${max_point_select_time}
    run_case read_only oltp_read_only.lua ${max_oltp_time}
    ;;
  full)
    run_case point_select oltp_point_select.lua ${max_point_select_time}
    run_case read_only oltp_read_only.lua ${max_oltp_time}
    run_case read_write oltp_read_write.lua ${max_oltp_time}
    ;;
  *)
    echo "unsupported TRAIN_MODE: $TRAIN_MODE" >&2
    exit 1
    ;;
esac

cd "$CUR_PATH"
