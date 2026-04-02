#!/usr/bin/env bash

set -euo pipefail

CMDPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$CMDPATH/../lib/common.sh"
. "$CMDPATH/../lib/platform.sh"
. "$CMDPATH/../lib/mysql.sh"

: "${SKIP_FULLTEXT_MECAB:=OFF}"

run_with_privilege() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "need root privileges or sudo to run: $*" >&2
    exit 1
  fi
}

run_with_privilege "$CMDPATH/install-devtoolset.sh"
run_with_privilege "$CMDPATH/install-misc.sh"
run_with_privilege "$CMDPATH/init_syslimit.sh"


MECAB_PREFIX="$(find_mecab_prefix || true)"
if ! mysql_supports_mecab "${MYSQL_VER:-8.0}"; then
  echo "info: MYSQL_VER=${MYSQL_VER:-8.0} does not require MeCab fulltext support"
elif [[ -n "$MECAB_PREFIX" ]]; then
  echo "mecab detected at: $MECAB_PREFIX"
else
  if [[ "$SKIP_FULLTEXT_MECAB" == "ON" ]]; then
    echo "warning: mecab headers not found after prepare; continuing because SKIP_FULLTEXT_MECAB=ON" >&2
  else
    echo "error: mecab headers not found after prepare; install mecab dependencies or pass --skip-fulltext-mecab" >&2
    exit 1
  fi
fi
