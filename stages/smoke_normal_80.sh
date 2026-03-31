#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/mysql.sh"

: "${MYSQL_VER:=8.0}"
: "${MYSQL_MINI_VER:=44-35}"
: "${BUILD_PROFILE:=normal}"
: "${WORK_ROOT:=$REPO_ROOT/work}"
: "${INSTALL_ROOT:=$WORK_ROOT/install/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}}"
: "${MYSQL_PORT:=34080}"
: "${MYSQL_CLONE_STATE_FILE:=}"
: "${MYSQL_DATA_DIR_OVERRIDE:=}"

case "$MYSQL_VER" in
  8.0|8.4)
    ;;
  *)
    die "smoke_normal_80.sh only supports MYSQL_VER=8.0 or 8.4"
    ;;
esac

require_cmd date dd head mktemp sed awk
require_cmd sha1sum

[[ -x "$INSTALL_ROOT/bin/mysqld" ]] || die "missing mysqld under $INSTALL_ROOT; build/install first"
[[ -x "$INSTALL_ROOT/bin/mysql" ]] || die "missing mysql client under $INSTALL_ROOT; build/install first"
[[ -x "$INSTALL_ROOT/bin/mysqladmin" ]] || die "missing mysqladmin under $INSTALL_ROOT; build/install first"

STAGE_NAME="$(mysql_stage_name "$MYSQL_VER" "$MYSQL_MINI_VER" "$BUILD_PROFILE")"
RUNTIME_ROOT="$(mysql_runtime_root "$WORK_ROOT" "$STAGE_NAME")"
STATE_ROOT="$(mysql_state_root "$WORK_ROOT" "$STAGE_NAME")"

DATA_DIR="$RUNTIME_ROOT/data"
TMP_DIR="$RUNTIME_ROOT/tmp"
ETC_DIR="$RUNTIME_ROOT/etc"
RUN_DIR="$RUNTIME_ROOT/run"
LOG_DIR="$RUNTIME_ROOT/log"
CNF_FILE="$ETC_DIR/my.cnf"
SOCKET_PATH="$RUN_DIR/mysql.sock"
PID_PATH="$RUN_DIR/mysql.pid"
LOG_PATH="$LOG_DIR/mysql.err.log"
BOOTSTRAP_DEFAULTS="$ETC_DIR/bootstrap-client.cnf"
ROOT_DEFAULTS="$ETC_DIR/root-client.cnf"
STATE_FILE="$STATE_ROOT/runtime.env"
ROOT_PASSWORD_FILE="$STATE_ROOT/root.password"
SBTEST_PASSWORD_FILE="$STATE_ROOT/sbtest.password"

SOCKET_PATH_LIMIT="${SOCKET_PATH_LIMIT:-107}"
if (( ${#SOCKET_PATH} > SOCKET_PATH_LIMIT )); then
  short_id="$(printf '%s' "$STAGE_NAME" | sha1sum | awk '{print substr($1,1,8)}')"
  SHORT_RUN_DIR="$WORK_ROOT/run/$short_id"
  log_warn "socket path is too long (${#SOCKET_PATH} > ${SOCKET_PATH_LIMIT}); using shorter run dir: $SHORT_RUN_DIR"
  rm -rf "$SHORT_RUN_DIR"
  ensure_dir "$SHORT_RUN_DIR"
  SOCKET_PATH="$SHORT_RUN_DIR/mysql.sock"
  PID_PATH="$SHORT_RUN_DIR/mysql.pid"
fi

read_state_var() {
  local state_file="$1"
  local key="$2"
  awk -F= -v search_key="$key" '$1 == search_key { sub(/^[^=]*=/, "", $0); print $0; exit }' "$state_file"
}

shutdown_existing_stage() {
  local state_file="$1"
  local existing_defaults existing_pid_file existing_pid
  local lingering_pid

  [[ -f "$state_file" ]] || return 0

  existing_defaults="$(read_state_var "$state_file" MYSQL_ROOT_DEFAULTS_FILE)"
  existing_pid_file="$(read_state_var "$state_file" MYSQL_PID_FILE)"
  if [[ -n "$existing_defaults" && -f "$existing_defaults" ]]; then
    log_info "shutting down existing mysqld for ${BUILD_PROFILE}"
    "$INSTALL_ROOT/bin/mysqladmin" --defaults-file="$existing_defaults" shutdown >/dev/null 2>&1 || true
  fi

  if [[ -n "$existing_pid_file" && -f "$existing_pid_file" ]]; then
    existing_pid="$(cat "$existing_pid_file" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      kill "$existing_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -9 "$existing_pid" >/dev/null 2>&1 || true
    fi
  fi

  while read -r lingering_pid; do
    [[ -n "$lingering_pid" ]] || continue
    if kill -0 "$lingering_pid" 2>/dev/null; then
      log_info "killing lingering mysqld pid $lingering_pid for ${BUILD_PROFILE}"
      kill "$lingering_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -9 "$lingering_pid" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -f "$INSTALL_ROOT/bin/mysqld" || true)
}

EXISTING_STATE_FILE="$STATE_FILE"
shutdown_existing_stage "$EXISTING_STATE_FILE"
sleep 2

ensure_dir "$WORK_ROOT"
rm -rf "$RUNTIME_ROOT"
if [[ -n "$MYSQL_DATA_DIR_OVERRIDE" ]]; then
  DATA_DIR="$MYSQL_DATA_DIR_OVERRIDE"
  [[ -d "$DATA_DIR" ]] || die "MYSQL_DATA_DIR_OVERRIDE is set but datadir does not exist: $DATA_DIR"
else
  ensure_dir "$DATA_DIR"
fi
ensure_dir "$TMP_DIR"
ensure_dir "$ETC_DIR"
ensure_dir "$RUN_DIR"
ensure_dir "$LOG_DIR"
ensure_dir "$STATE_ROOT"

PLUGIN_DIR="$(mysql_find_plugin_dir "$INSTALL_ROOT")"
SERVER_ID="$(date +%s | tail -c 5)"
CLONED_DATASET=0

mysql_emit_config \
  "$MYSQL_VER" \
  "$INSTALL_ROOT" \
  "$DATA_DIR" \
  "$TMP_DIR" \
  "$SOCKET_PATH" \
  "$LOG_PATH" \
  "$PID_PATH" \
  "$MYSQL_PORT" \
  "$SERVER_ID" \
  "$PLUGIN_DIR" > "$CNF_FILE"

if [[ -n "$MYSQL_CLONE_STATE_FILE" ]]; then
  [[ -f "$MYSQL_CLONE_STATE_FILE" ]] || die "clone state file not found: $MYSQL_CLONE_STATE_FILE"

  SOURCE_DATA_DIR="$(read_state_var "$MYSQL_CLONE_STATE_FILE" MYSQL_DATA_DIR)"
  SOURCE_ROOT_PASSWORD_FILE="$(read_state_var "$MYSQL_CLONE_STATE_FILE" MYSQL_ROOT_PASSWORD_FILE)"
  SOURCE_SBTEST_PASSWORD_FILE="$(read_state_var "$MYSQL_CLONE_STATE_FILE" MYSQL_SBTEST_PASSWORD_FILE)"

  [[ -d "$SOURCE_DATA_DIR" ]] || die "clone source datadir not found: $SOURCE_DATA_DIR"
  [[ -f "$SOURCE_ROOT_PASSWORD_FILE" ]] || die "clone source root password file not found: $SOURCE_ROOT_PASSWORD_FILE"
  [[ -f "$SOURCE_SBTEST_PASSWORD_FILE" ]] || die "clone source sbtest password file not found: $SOURCE_SBTEST_PASSWORD_FILE"

  ROOT_PASSWORD="$(<"$SOURCE_ROOT_PASSWORD_FILE")"
  SBTEST_PASSWORD="$(<"$SOURCE_SBTEST_PASSWORD_FILE")"

  if [[ -z "$MYSQL_DATA_DIR_OVERRIDE" ]]; then
    log_info "cloning datadir from $SOURCE_DATA_DIR to $DATA_DIR"
    cp -a "$SOURCE_DATA_DIR"/. "$DATA_DIR"/
  else
    log_info "reusing existing datadir via MYSQL_DATA_DIR_OVERRIDE=$MYSQL_DATA_DIR_OVERRIDE (clone source=$SOURCE_DATA_DIR)"
  fi
  mysql_write_client_defaults "$ROOT_DEFAULTS" root "$ROOT_PASSWORD" "$SOCKET_PATH"
  WAIT_DEFAULTS="$ROOT_DEFAULTS"
  CLONED_DATASET=1
else
  ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(mysql_generate_password root)}"
  SBTEST_PASSWORD="${MYSQL_SBTEST_PASSWORD:-sbtest12}"

  mysql_write_client_defaults "$BOOTSTRAP_DEFAULTS" root '' "$SOCKET_PATH"

  log_info "initializing datadir: $DATA_DIR"
  "$INSTALL_ROOT/bin/mysqld" \
    --defaults-file="$CNF_FILE" \
    --initialize-insecure \
    --user="$(whoami)"

  WAIT_DEFAULTS="$BOOTSTRAP_DEFAULTS"
fi

declare -a start_cmd
start_cmd=("$INSTALL_ROOT/bin/mysqld" "--defaults-file=$CNF_FILE" "--user=$(whoami)")
if command -v numactl >/dev/null 2>&1 && ! is_container_env; then
  start_cmd=(numactl --interleave=all "${start_cmd[@]}")
fi

jemalloc_lib="$(find_jemalloc_lib || true)"
if [[ -n "$jemalloc_lib" ]]; then
  log_info "starting mysqld with jemalloc: $jemalloc_lib"
  LD_PRELOAD="$jemalloc_lib" "${start_cmd[@]}" > /dev/null 2>&1 &
else
  log_info "starting mysqld without jemalloc override"
  "${start_cmd[@]}" > /dev/null 2>&1 &
fi
MYSQLD_PID=$!

mysql_wait_until_ready \
  "$INSTALL_ROOT/bin/mysqladmin" \
  "$WAIT_DEFAULTS" \
  "$SOCKET_PATH" \
  "$MYSQLD_PID" \
  120 \
  "$LOG_PATH"

if (( CLONED_DATASET == 0 )); then
  log_info "provisioning local accounts for smoke and future sysbench"
  cat <<SQL | "$INSTALL_ROOT/bin/mysql" --defaults-file="$BOOTSTRAP_DEFAULTS"
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASSWORD}';
$(mysql_create_local_user_sql "$MYSQL_VER" sbtest "$SBTEST_PASSWORD" if-not-exists)
GRANT ALL PRIVILEGES ON *.* TO 'sbtest'@'localhost';
FLUSH PRIVILEGES;
SQL

  mysql_write_client_defaults "$ROOT_DEFAULTS" root "$ROOT_PASSWORD" "$SOCKET_PATH"
fi

printf '%s\n' "$ROOT_PASSWORD" > "$ROOT_PASSWORD_FILE"
printf '%s\n' "$SBTEST_PASSWORD" > "$SBTEST_PASSWORD_FILE"
chmod 600 "$ROOT_PASSWORD_FILE" "$SBTEST_PASSWORD_FILE"

cat > "$STATE_FILE" <<STATE
MYSQL_VER=${MYSQL_VER}
MYSQL_MINI_VER=${MYSQL_MINI_VER}
BUILD_PROFILE=${BUILD_PROFILE}
INSTALL_ROOT=${INSTALL_ROOT}
RUNTIME_ROOT=${RUNTIME_ROOT}
MYSQL_DATA_DIR=${DATA_DIR}
MYSQL_SOCKET=${SOCKET_PATH}
MYSQL_PID_FILE=${PID_PATH}
MYSQL_LOG=${LOG_PATH}
MYSQL_PORT=${MYSQL_PORT}
MYSQL_ROOT_DEFAULTS_FILE=${ROOT_DEFAULTS}
MYSQL_ROOT_PASSWORD_FILE=${ROOT_PASSWORD_FILE}
MYSQL_SBTEST_PASSWORD_FILE=${SBTEST_PASSWORD_FILE}
STATE
chmod 600 "$STATE_FILE"

log_info "running socket smoke query"
"$INSTALL_ROOT/bin/mysql" --defaults-file="$ROOT_DEFAULTS" -e 'SELECT VERSION() AS version, @@socket AS socket_path'

log_info "running sbtest auth smoke query"
"$INSTALL_ROOT/bin/mysql" \
  --protocol=socket \
  --socket="$SOCKET_PATH" \
  --user=sbtest \
  --password="$SBTEST_PASSWORD" \
  -e 'SELECT CURRENT_USER() AS current_user_name'

log_info "smoke succeeded; runtime state saved to $STATE_FILE"
