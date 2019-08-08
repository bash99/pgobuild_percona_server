#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
. $SELF_PATH/common.sh

sh -c "$MYSQLD_WITHOPT" &
sleep 3 && tail $MYSQL_LOG
