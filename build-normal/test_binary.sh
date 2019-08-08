#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_TARBALl MYSQL_BASE_PATH"}
: ${2?"Usage: $0 MYSQL_TARBALL MYSQL_BASE_PATH"}
MYSQL_TARBALL=$1
MYSQL_BASE=$2

if [ -d $MYSQL_BASE ]; then
    echo "MYSQL_BASE_PATH $MYSQL_BASE exists!, don't overwirte"
    exit 1
fi

mkdir -p $MYSQL_BASE && tar -xf $MYSQL_TARBALL -C $MYSQL_BASE --strip-components=1

bash $SELF_PATH/../sysbench/compile-sysbench.sh $MYSQL_BASE
if [ $? -ne 0 ]; then echo "sysbench compile failed! Assert: non-0 exit status detected!"; exit 1; fi

export MYSQL_USER=`whoami`
bash $SELF_PATH/init_normal.sh $MYSQL_BASE

bash $SELF_PATH/start_normal.sh $MYSQL_BASE

bash $SELF_PATH/../sysbench/init-sysbench.sh $MYSQL_BASE

bash $SELF_PATH/../sysbench/train-sysbench.sh $MYSQL_BASE | tee /tmp/sb_test_bin_result.txt

bash $SELF_PATH/shutdown_normal.sh $MYSQL_BASE

