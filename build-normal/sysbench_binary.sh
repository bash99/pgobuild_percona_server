#!/bin/bash
# a help script, only for quicktest, MYSQL_BASE should have a same version MYSQL version of TARBALL, and sysbench is ready
# so we skip init mysql and compile sysbench part


SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_TARBALL MYSQL_BASE_PATH MYSQL_VER"}
: ${2?"Usage: $0 MYSQL_TARBALL MYSQL_BASE_PATH MYSQL_VER"}
: ${3?"Usage: $0 MYSQL_TARBALL MYSQL_BASE_PATH MYSQL_VER"}
MYSQL_TARBALL=$1
MYSQL_BASE=$2
export MYSQL_VER=$3

export MYSQL_USER=`whoami`

case "$MYSQL_TARBALL" in
  *.tar.zst|*.tar.zstd|*.tzst)
    command -v zstd >/dev/null 2>&1 || { echo "zstd is required to extract $MYSQL_TARBALL" >&2; exit 1; }
    zstd -dc "$MYSQL_TARBALL" | tar -xf - -C "$MYSQL_BASE" --strip-components=1
    ;;
  *)
    tar -xf "$MYSQL_TARBALL" -C "$MYSQL_BASE" --strip-components=1
    ;;
esac

bash $SELF_PATH/start_normal.sh $MYSQL_BASE

bash $SELF_PATH/../sysbench/init-sysbench.sh $MYSQL_BASE

bash $SELF_PATH/../sysbench/train-sysbench.sh $MYSQL_BASE | tee /tmp/sb_test_bin_result.txt

bash $SELF_PATH/shutdown_normal.sh $MYSQL_BASE
