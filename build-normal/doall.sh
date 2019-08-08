#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

export MYSQL_USER=`whoami`
: ${MYSQL_BASE:=`pwd`/local/mysql}

bash $SELF_PATH/prepare_build.sh $MYSQL_SOURCE_PATH $MYSQL_VER "build"
MYSQL_BUILD_PATH=${MYSQL_SOURCE_PATH}_build

bash $SELF_PATH/compile.sh $MYSQL_BASE ${MYSQL_BUILD_PATH} $MYSQL_VER
if [ $? -ne 0 ]; then echo "compile failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/install_mini.sh ${MYSQL_BUILD_PATH} $MYSQL_BASE
if [ $? -ne 0 ]; then echo "install failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/init_normal.sh $MYSQL_BASE

bash $SELF_PATH/start_normal.sh $MYSQL_BASE

bash $SELF_PATH/../sysbench/compile-sysbench.sh $MYSQL_BASE
bash $SELF_PATH/../sysbench/init-sysbench.sh $MYSQL_BASE

bash $SELF_PATH/../sysbench/train-sysbench.sh $MYSQL_BASE | tee /tmp/${MYSQL_VER}_normal_result.txt

bash $SELF_PATH/shutdown_normal.sh $MYSQL_BASE

