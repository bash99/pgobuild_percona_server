#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
. $SELF_PATH/common.sh

rm -rf ${MYSQL_DATA_PATH}
mkdir -p ${MYSQL_DATA_PATH}
mkdir -p $MYSQL_BASE/etc

bash $SELF_PATH/init_conf.sh ${MYSQL_DATA_PATH} $MYSQL_VER> $MYSQL_CNF_PATH

if [ -f "$MYSQL_BASE/scripts/mysql_install_db" ]; then ## old mysql 5.6
  rm -f ~/.mysql_secret
  $MYSQL_BASE/scripts/mysql_install_db --user=$MYSQL_USER --basedir=$MYSQL_BASE --datadir=${MYSQL_DATA_PATH} --random-passwords
else
  sh -c "$MYSQLD_WITHOPT --initialize"
fi

bash $SELF_PATH/start_normal.sh $MYSQL_BASE
if [ -f "$MYSQL_BASE/scripts/mysql_install_db" ]; then ## old mysql 5.6 init tablespace on first start
  sleep 50
fi

sleep 10 && bash $SELF_PATH/init_setpass.sh $MYSQL_BASE

bash $SELF_PATH/shutdown_normal.sh $MYSQL_BASE
