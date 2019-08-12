#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
. $SELF_PATH/common.sh

sudo sync
#sudo sysctl -q -w vm.drop_caches=3
#sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"

## lg_dirty_mult:-1 is deal with bug of jemalloc 3.3
export LD_PRELOAD='/usr/lib64/libjemalloc.so.1' MALLOC_CONF='lg_dirty_mult:-1'

sh -c "numactl --interleave=all $MYSQLD_WITHOPT" &
( tail -f -n0 $MYSQL_LOG & ) | grep -q "ready for connections"
tail $MYSQL_LOG
