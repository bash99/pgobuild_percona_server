#!/bin/bash

set -euo pipefail

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

. "$SELF_PATH/common_config.sh"

WARMUP_CASE=${WARMUP_CASE:-point_select}
WARMUP_TIME=${WARMUP_TIME:-$warmup_time}

CUR_PATH=`pwd`
cd "$SYSBENCH_LUA_DIR"

echo "=== SYSBENCH_PREWARM_BEGIN case=${WARMUP_CASE} time=${WARMUP_TIME} ==="
case "$WARMUP_CASE" in
  point_select)
    "$SYSBENCH_BIN" oltp_point_select.lua $SYSBENCH_OPT --time=${WARMUP_TIME} run
    ;;
  read_only)
    "$SYSBENCH_BIN" oltp_read_only.lua $SYSBENCH_OPT --time=${WARMUP_TIME} run
    ;;
  *)
    echo "unsupported WARMUP_CASE: $WARMUP_CASE" >&2
    exit 1
    ;;
esac
echo "=== SYSBENCH_PREWARM_END case=${WARMUP_CASE} time=${WARMUP_TIME} ==="

cd "$CUR_PATH"
