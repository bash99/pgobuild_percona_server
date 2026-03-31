#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

: "${MYSQL_VER:=5.7}"
: "${MYSQL_MINI_VER:=44-54}"
: "${BUILD_PROFILE:=normal}"
: "${WORK_ROOT:=$REPO_ROOT/work}"
: "${LOG_ROOT:=$WORK_ROOT/logs}"
: "${INSTALL_ROOT:=$WORK_ROOT/install/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}}"
: "${CPU_OPT_FLAGS:=-march=nehalem -mtune=haswell}"
: "${SKIP_FULLTEXT_MECAB:=OFF}"

[[ "$MYSQL_VER" == "5.7" ]] || die "build_normal_57.sh only supports MYSQL_VER=5.7"

require_cmd bash awk make nproc sed tar

SOURCE_DIR="$(detect_source_dir "$REPO_ROOT" "$MYSQL_VER" "$MYSQL_MINI_VER")"
BUILD_ROOT="${SOURCE_DIR}_${BUILD_PROFILE}"
WORK_BUILD_ROOT="$WORK_ROOT/build/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}"
BUILD_LOG="$LOG_ROOT/build-normal-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}.log"
COMPILE_TIME_FILE="$LOG_ROOT/compile-time-${MYSQL_VER}.${MYSQL_MINI_VER}-${BUILD_PROFILE}.txt"

ensure_dir "$WORK_ROOT"
ensure_dir "$LOG_ROOT"
ensure_dir "$WORK_ROOT/build"
ensure_dir "$(dirname "$INSTALL_ROOT")"
rm -rf "$INSTALL_ROOT"
rm -rf "$WORK_BUILD_ROOT"

if [[ "$SKIP_FULLTEXT_MECAB" != "ON" ]]; then
  export MECAB_INC="${MECAB_INC:-$(find_mecab_prefix || true)}"
  [[ -n "${MECAB_INC:-}" ]] || die "mecab headers not found; install fulltext mecab dependencies or pass --skip-fulltext-mecab"
fi

log_info "building Percona Server ${MYSQL_VER}.${MYSQL_MINI_VER} into $INSTALL_ROOT"
log_info "source: $SOURCE_DIR"
[[ -n "${MECAB_INC:-}" ]] && log_info "mecab: $MECAB_INC"

(
  cd "$REPO_ROOT"
  export MYSQL_BASE="$INSTALL_ROOT"
  export MYSQL_SOURCE_PATH="$SOURCE_DIR"
  bash "$REPO_ROOT/build-normal/prepare_build.sh" "$SOURCE_DIR" "$MYSQL_VER" "$BUILD_PROFILE"
  bash "$REPO_ROOT/build-normal/compile.sh" "$INSTALL_ROOT" "$BUILD_ROOT" "$MYSQL_VER"
  bash "$REPO_ROOT/build-normal/install_mini.sh" "$BUILD_ROOT" "$INSTALL_ROOT"
) 2>&1 | tee "$BUILD_LOG"

[[ -x "$INSTALL_ROOT/bin/mysqld" ]] || die "mysqld not found under $INSTALL_ROOT after build"
[[ -d "$BUILD_ROOT" ]] || die "build root missing after build: $BUILD_ROOT"
ln -s "$BUILD_ROOT" "$WORK_BUILD_ROOT"

if [[ -f "/tmp/${MYSQL_VER}_build" ]]; then
  cp "/tmp/${MYSQL_VER}_build" "$COMPILE_TIME_FILE"
fi

log_info "5.7 normal build complete"
