#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
SELF_PATH=`cd $SELF_PATH; pwd`

export MYSQL_USER=`whoami`
CUR_PATH=`pwd`
: ${MYSQL_BASE:=${CUR_PATH}/local/mysql}

BUILD_EXT="build"
MYSQL_BUILD_PATH=${MYSQL_SOURCE_PATH}_${BUILD_EXT}
bash $SELF_PATH/prepare_build.sh $MYSQL_SOURCE_PATH $MYSQL_VER ${BUILD_EXT}

bash $SELF_PATH/compile.sh $MYSQL_BASE ${MYSQL_BUILD_PATH} $MYSQL_VER
if [ $? -ne 0 ]; then echo "compile failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/install_mini.sh ${MYSQL_BUILD_PATH} $MYSQL_BASE
if [ $? -ne 0 ]; then echo "install failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/init_normal.sh $MYSQL_BASE
if [ $? -ne 0 ]; then echo "install failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/start_normal.sh $MYSQL_BASE

bash $SELF_PATH/../sysbench/compile-sysbench.sh $MYSQL_BASE
bash $SELF_PATH/../sysbench/init-sysbench.sh $MYSQL_BASE

bash $SELF_PATH/../sysbench/train-sysbench.sh $MYSQL_BASE | tee /tmp/${MYSQL_VER}_normal_result.txt

bash $SELF_PATH/shutdown_normal.sh $MYSQL_BASE

if [ $? -ne 0 ]; then echo "all failed! Assert: non-0 exit status detected!"; exit 1; fi
bash $SELF_PATH/../build-opt/make_package.sh ${MYSQL_BUILD_PATH} "normal"

if [ $? -ne 0 ]; then echo "package failed! Assert: non-0 exit status detected!"; exit 1; fi
rm -rf ${MYSQL_BUILD_PATH}
