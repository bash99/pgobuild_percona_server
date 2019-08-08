#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
. $SELF_PATH/common.sh

#echo $MYSQLADMIN_PATH -u root --socket=$MYSQL_SOCK_PATH shutdown
$MYSQLADMIN_PATH -u root --socket=$MYSQL_SOCK_PATH shutdown
