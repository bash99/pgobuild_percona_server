#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
SELF_PATH=`cd $SELF_PATH; pwd`

: ${MYSQL_VER:=8.0}
: ${MYSQL_MINI_VER:=15-6}
export MYSQL_VER MYSQL_MINI_VER

CUR_PATH=`pwd`

export MYSQL_SOURCE_PATH=$CUR_PATH/ps-${MYSQL_VER}
export MYSQL_BASE=$CUR_PATH/local/ps${MYSQL_VER}

bash $SELF_PATH/prepare/doall.sh
if [ $? -ne 0 ]; then echo "prepare requirement and mysql source failed! Assert: non-0 exit status detected!"; exit 1; fi

. /etc/profile

bash $SELF_PATH/build-normal/doall.sh
if [ $? -ne 0 ]; then echo "build normal failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/build-opt/doall.sh $MYSQL_BASE $MYSQL_SOURCE_PATH $MYSQL_VER
