#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

. $SELF_PATH/common_config.sh

CUR_PATH=`pwd`
cd $SYSBENCH_LUA_DIR

$SYSBENCH_BIN oltp_point_select.lua $SYSBENCH_OPT --time=${max_point_select_time} run
$SYSBENCH_BIN oltp_read_only.lua $SYSBENCH_OPT --time=${max_oltp_time} run
$SYSBENCH_BIN oltp_read_write.lua $SYSBENCH_OPT --time=${max_oltp_time} run

cd $CUR_PATH
