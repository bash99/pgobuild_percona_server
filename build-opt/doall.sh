#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
SELF_PATH=`cd $SELF_PATH; pwd`

: ${1?"Usage: $0 MYSQL_BASE_PATH MYSQL_SOURCE_PATH MYSQL_VER"}
: ${2?"Usage: $0 MYSQL_BASE_PATH MYSQL_SOURCE_PATH MYSQL_VER"}
: ${3?"Usage: $0 MYSQL_BASE_PATH MYSQL_SOURCE_PATH MYSQL_VER"}
MYSQL_BASE=$1
MYSQL_SOURCE_PATH=$2
MYSQL_VER=$3


bash $SELF_PATH/build_pgo.sh $MYSQL_BASE $MYSQL_SOURCE_PATH $MYSQL_VER
if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/make_package.sh ${MYSQL_SOURCE_PATH}_pgobuild "pgoed"

rm -rf ${MYSQL_SOURCE_PATH}_pgobuild
