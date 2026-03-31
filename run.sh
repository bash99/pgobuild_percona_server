#!/usr/bin/env bash

set -euo pipefail

init_system=''
normal_build=''
pgo_build=''
download_source=''
skip_fulltext_mecab='false'

print_usage() {
  printf "Usage: run.sh [-i] [-d] [-n] [-p] [--skip-fulltext-mecab]\n"
  printf "i init system lib and gcc, require sudo permissions\n"
  printf "d download source\n"
  printf "n normal build\n"
  printf "p pgo build\n"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) init_system='true' ;;
    -n) normal_build='true' ;;
    -p) pgo_build='true' ;;
    -d) download_source='true' ;;
    --skip-fulltext-mecab) skip_fulltext_mecab='true' ;;
    -h|--help) print_usage ;;
    *) print_usage ;;
  esac
  shift
done

[[ -z $init_system && -z $download_source && -z $normal_build && -z $pgo_build ]] && print_usage

SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_PATH/lib/common.sh"

: ${CPU_OPT_FLAGS:="-march=nehalem -mtune=haswell"}
: ${MYSQL_VER:=8.0}
: ${MYSQL_MINI_VER:=45-36}
if [[ "$skip_fulltext_mecab" == 'true' ]]; then
  export SKIP_FULLTEXT_MECAB=ON
else
  export SKIP_FULLTEXT_MECAB=OFF
fi

export MYSQL_VER MYSQL_MINI_VER CPU_OPT_FLAGS SKIP_FULLTEXT_MECAB

export MYSQL_SOURCE_PATH="$SELF_PATH/percona-server-Percona-Server-${MYSQL_VER}.${MYSQL_MINI_VER}"
export WORK_ROOT="${WORK_ROOT:-$SELF_PATH/work}"

if [[ "$init_system" == 'true' ]]; then
  bash "$SELF_PATH/prepare/prepare_system.sh"
fi

if [[ "$download_source" == 'true' ]]; then
  bash "$SELF_PATH/prepare/download-source.sh"
fi

if platform_enable_optional_toolchain >/dev/null; then
  log_info "enabled optional toolchain: ${PLATFORM_OPTIONAL_TOOLCHAIN_PATH:-unknown}"
fi

if [[ "$normal_build" == 'true' ]]; then
  case "$MYSQL_VER" in
    8.0|8.4)
      bash "$SELF_PATH/stages/build_normal_80.sh"
      bash "$SELF_PATH/stages/smoke_normal_80.sh"
      bash "$SELF_PATH/stages/benchmark_normal_80.sh"
      ;;
    5.7)
      bash "$SELF_PATH/stages/build_normal_57.sh"
      bash "$SELF_PATH/stages/smoke_normal.sh"
      bash "$SELF_PATH/stages/benchmark_normal.sh"
      ;;
    *)
      die "unsupported MYSQL_VER for normal build flow: $MYSQL_VER"
      ;;
  esac
fi

if [[ "$pgo_build" == 'true' ]]; then
  case "$MYSQL_VER" in
    8.0|8.4)
      bash "$SELF_PATH/stages/build_pgo_80.sh"
      ;;
    5.7)
      bash "$SELF_PATH/stages/build_pgo_57.sh"
      ;;
    *)
      die "unsupported MYSQL_VER for PGO build flow: $MYSQL_VER"
      ;;
  esac
fi
