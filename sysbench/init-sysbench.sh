#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

MYSQL_CLI_OPT="$MYSQL_BASE/bin/mysql -uroot --socket=$MYSQL_BASE/data/mysql.sock"
sh -c "$MYSQL_CLI_OPT" <<EOF
drop user sbtest@localhost;
EOF
sh -c "$MYSQL_CLI_OPT" <<EOF
create user sbtest@localhost identified with mysql_native_password by 'sbtest12';
EOF

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
. $SELF_PATH/common_config.sh

sh -c "$MYSQL_CLI_OPT" <<EOF
drop database if exists sbtest_${dbeng};
create database sbtest_${dbeng};
grant all on sbtest_${dbeng}.* to sbtest@localhost;
EOF

CUR_PATH=`pwd`
cd $SYSBENCH_LUA_DIR

echo $SYSBENCH_BIN oltp_insert.lua $SYSBENCH_OPT --threads=1 prepare
$SYSBENCH_BIN oltp_insert.lua $SYSBENCH_OPT --threads=1 prepare

cd $CUR_PATH
