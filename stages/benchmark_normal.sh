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
: "${LOG_ROOT:=$WORK_ROOT/logs}"
: "${INSTALL_ROOT:=$WORK_ROOT/install/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}}"
: "${BUILD_ROOT:=$WORK_ROOT/build/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}}"

require_cmd bash tee

STAGE_NAME="$(mysql_stage_name "$MYSQL_VER" "$MYSQL_MINI_VER" "$BUILD_PROFILE")"
STATE_FILE="$WORK_ROOT/state/$STAGE_NAME/runtime.env"
SYSBENCH_COMPILE_LOG="$LOG_ROOT/sysbench-compile-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}.log"
SYSBENCH_INIT_LOG="$LOG_ROOT/sysbench-init-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}.log"
SYSBENCH_TRAIN_LOG="$LOG_ROOT/sysbench-train-ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}.log"
PACKAGE_SUFFIX="$BUILD_PROFILE"

ensure_dir "$LOG_ROOT"
[[ -f "$STATE_FILE" ]] || die "missing runtime state file: $STATE_FILE"
[[ -x "$INSTALL_ROOT/bin/mysqld" ]] || die "missing mysqld under $INSTALL_ROOT"
[[ -d "$BUILD_ROOT" ]] || die "missing build root: $BUILD_ROOT"

set -a
. "$STATE_FILE"
set +a

if ! "$INSTALL_ROOT/bin/mysqladmin" --defaults-file="$MYSQL_ROOT_DEFAULTS_FILE" ping >/dev/null 2>&1; then
  log_warn "runtime for ${BUILD_PROFILE} is not responding; recreating it via smoke_normal.sh"
  env \
    MYSQL_VER="$MYSQL_VER" \
    MYSQL_MINI_VER="$MYSQL_MINI_VER" \
    BUILD_PROFILE="$BUILD_PROFILE" \
    WORK_ROOT="$WORK_ROOT" \
    INSTALL_ROOT="$INSTALL_ROOT" \
    bash "$REPO_ROOT/stages/smoke_normal.sh"

  set -a
  . "$STATE_FILE"
  set +a
fi

log_info "waiting for MySQL startup quiesce for ${BUILD_PROFILE}"
mysql_wait_for_startup_quiesce "$INSTALL_ROOT" "$MYSQL_ROOT_DEFAULTS_FILE" "$MYSQL_LOG" 240

log_info "compiling sysbench for ${BUILD_PROFILE}"
(
  cd "$REPO_ROOT"
  env SYSBENCH_BASE="$INSTALL_ROOT/sysbench" bash "$REPO_ROOT/sysbench/compile-sysbench.sh" "$INSTALL_ROOT"
) | tee "$SYSBENCH_COMPILE_LOG"

log_info "initializing sysbench dataset for ${BUILD_PROFILE}"
env \
  MYSQL_ROOT_DEFAULTS_FILE="$MYSQL_ROOT_DEFAULTS_FILE" \
  MYSQL_SOCKET="$MYSQL_SOCKET" \
  SYSBENCH_BASE="$INSTALL_ROOT/sysbench" \
  bash "$REPO_ROOT/sysbench/init-sysbench.sh" "$INSTALL_ROOT" | tee "$SYSBENCH_INIT_LOG"

log_info "running sysbench baseline for ${BUILD_PROFILE}"
env \
  MYSQL_ROOT_DEFAULTS_FILE="$MYSQL_ROOT_DEFAULTS_FILE" \
  MYSQL_SOCKET="$MYSQL_SOCKET" \
  SYSBENCH_BASE="$INSTALL_ROOT/sysbench" \
  bash "$REPO_ROOT/sysbench/train-sysbench.sh" "$INSTALL_ROOT" | tee "$SYSBENCH_TRAIN_LOG"

log_info "shutting down mysql for ${BUILD_PROFILE}"
mysql_shutdown_with_defaults "$INSTALL_ROOT/bin/mysqladmin" "$MYSQL_ROOT_DEFAULTS_FILE"

log_info "packaging build for ${BUILD_PROFILE}"
(
  cd "$REPO_ROOT"
  bash "$REPO_ROOT/build-opt/make_package.sh" "$BUILD_ROOT" "$PACKAGE_SUFFIX"
)

log_info "normal benchmark flow complete for ${BUILD_PROFILE}"
