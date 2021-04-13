#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
. $SELF_PATH/common.sh

sudo sync
#sudo sysctl -q -w vm.drop_caches=3
#sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"

JEMALLOC="/usr/lib64/libjemalloc.so.1"
## lg_dirty_mult:-1 is deal with bug of jemalloc 3.3, showld disable for jemalloc 3.9
JEMALLOC_CONF='lg_dirty_mult:-1'
[[ -f /usr/lib/x86_64-linux-gnu/libjemalloc.so ]] && JEMALLOC=/usr/lib/x86_64-linux-gnu/libjemalloc.so && JEMALLOC_CONF=""
export LD_PRELOAD=$JEMALLOC MALLOC_CONF=$JEMALLOC_CONF

sh -c "numactl --interleave=all $MYSQLD_WITHOPT" &
# [[ ! -f $MYSQL_LOG ]] && sleep 1
# ( tail -f -n0 $MYSQL_LOG & ) | grep -q "ready for connections"
( tail -F -n0 $MYSQL_LOG & ) | grep -q "ready for connections"
tail $MYSQL_LOG
