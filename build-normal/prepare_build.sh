#!/bin/bash

: ${1?"Usage: $0 MYSQL_SOURCE_PATH MYSQL_VER BUILD_PATH_SUFFIX"}
: ${2?"Usage: $0 MYSQL_SOURCE_PATH MYSQL_VER BUILD_PATH_SUFFIX"}
: ${3?"Usage: $0 MYSQL_SOURCE_PATH MYSQL_VER BUILD_PATH_SUFFIX"}
MYSQL_SOURCE_PATH=$1
MYSQL_VER=$2
BUILD_PATH_SUFFIX=$3

cd $MYSQL_SOURCE_PATH

CURPATH=$(echo $PWD | sed 's|.*/||')
### do git checkout and path
### git reset --hard && git checkout $MYSQL_VER && git reset --hard && git submodule init && git submodule update
cd ..
rm -Rf ${CURPATH}_${BUILD_PATH_SUFFIX}
rm -f /tmp/${MYSQL_VER}_build
cp -al ${CURPATH} ${CURPATH}_${BUILD_PATH_SUFFIX}
