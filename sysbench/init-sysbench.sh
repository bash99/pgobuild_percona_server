#!/bin/bash

set -euo pipefail

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1
SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_PATH/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/mysql.sh"

require_cmd awk df

if [[ -n "${MYSQL_ROOT_DEFAULTS_FILE:-}" ]]; then
  MYSQL_CLI=("$MYSQL_BASE/bin/mysql" "--defaults-file=$MYSQL_ROOT_DEFAULTS_FILE")
else
  MYSQL_CLI=("$MYSQL_BASE/bin/mysql" "-uroot" "--socket=$MYSQL_BASE/data/mysql.sock")
fi

"${MYSQL_CLI[@]}" <<EOF
$(mysql_prepare_sysbench_user_sql "${MYSQL_VER:-8.0}" sbtest12)
EOF

. "$SELF_PATH/common_config.sh"

MIN_DISK_FREE_PCT="${MIN_DISK_FREE_PCT:-15}"

mysql_scalar() {
  "${MYSQL_CLI[@]}" -Nse "$1"
}

check_disk_free_pct_or_die() {
  local path="$1"
  local free_pct
  free_pct="$(df -P "$path" | awk 'NR==2 { gsub(/%/, "", $5); used=$5+0; printf "%d\n", 100-used }')"
  [[ -n "${free_pct:-}" ]] || die "failed to determine disk free pct for: $path"
  if (( free_pct < MIN_DISK_FREE_PCT )); then
    die "disk free pct ${free_pct}% is below threshold ${MIN_DISK_FREE_PCT}% for filesystem hosting ${path}"
  fi
  log_info "disk free pct ok: ${free_pct}% (threshold ${MIN_DISK_FREE_PCT}%) for ${path}"
}

ensure_rocksdb_plugin_active() {
  local status
  status="$(mysql_scalar "SELECT PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS WHERE PLUGIN_NAME='ROCKSDB'")"
  if [[ "$status" == "ACTIVE" ]]; then
    log_info "rocksdb plugin already ACTIVE"
    return 0
  fi

  if [[ -n "$status" ]]; then
    die "rocksdb plugin exists but is not ACTIVE (status=$status); manual intervention required"
  fi

  log_info "installing rocksdb plugin"
  "${MYSQL_CLI[@]}" -e "INSTALL PLUGIN ROCKSDB SONAME 'ha_rocksdb.so';"
  status="$(mysql_scalar "SELECT PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS WHERE PLUGIN_NAME='ROCKSDB'")"
  [[ "$status" == "ACTIVE" ]] || die "rocksdb plugin not ACTIVE after installation (status=${status:-missing})"
  log_info "rocksdb plugin installed and ACTIVE"
}

datadir="$(mysql_scalar "SELECT @@datadir")"
[[ -n "$datadir" ]] || die "failed to read @@datadir"
check_disk_free_pct_or_die "$datadir"

if [[ "${dbeng}" == "rocksdb" ]]; then
  ensure_rocksdb_plugin_active
fi

"${MYSQL_CLI[@]}" <<EOF
drop database if exists sbtest_${dbeng};
create database sbtest_${dbeng};
grant all on sbtest_${dbeng}.* to sbtest@localhost;
EOF

CUR_PATH=`pwd`
cd $SYSBENCH_LUA_DIR

echo $SYSBENCH_BIN oltp_insert.lua $SYSBENCH_OPT --threads=1 prepare
$SYSBENCH_BIN oltp_insert.lua $SYSBENCH_OPT --threads=1 prepare
## warm up after init
$SYSBENCH_BIN oltp_point_select.lua $SYSBENCH_OPT --time=${warmup_time} run

cd $CUR_PATH

check_disk_free_pct_or_die "$datadir"
