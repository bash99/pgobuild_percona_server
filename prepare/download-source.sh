#!/bin/bash

## mysql VERSION 5.6 44-86.0  5.7 26-29 8.0 15-6
#https://www.percona.com/downloads/Percona-Server-8.0/Percona-Server-8.0.15-6/source/tarball/percona-server-8.0.15-6.tar.gz
MAJOR_VER=${MYSQL_VER:-5.7}
MINI_VER=${MYSQLMINI_VER:-26-29}
MYSQL_SOURCE_PATH=ps-${MAJOR_VER}
MYSQL_SOURCE_TARBALL=percona-server-${MAJOR_VER}.${MINI_VER}.tar.gz
if [ ! -d $MYSQL_SOURCE_PATH ]; then
    curl -L -C - https://www.percona.com/downloads/Percona-Server-${MAJOR_VER}/Percona-Server-${MAJOR_VER}.${MINI_VER}/source/tarball/percona-server-${MAJOR_VER}.${MINI_VER}.tar.gz \
        -o $MYSQL_SOURCE_TARBALL && \
        mkdir -p $MYSQL_SOURCE_PATH && tar -xf $MYSQL_SOURCE_TARBALL \
        -C $MYSQL_SOURCE_PATH --strip-components=1
fi
#
# && git clone  --depth 1 https://github.com/percona/percona-server.git -b 5.7 ps-5.7 \
# && cd ps-5.7 && git submodule init && git submodule update

export BOOST_VER=1_69_0
# export BOOST_VER=1_59_0
export BOOST_DOT_VER=`echo $BOOST_VER | sed -e "s/\_/./g"`
if [ ! -d boost_${BOOST_VER} ]; then
  curl -L -C - https://sourceforge.net/projects/boost/files/boost/${BOOST_DOT_VER}/boost_${BOOST_VER}.tar.bz2/download -o boost_${BOOST_VER}.tar.bz2 \
    && tar jxf boost_${BOOST_VER}.tar.bz2
fi
