#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH MYSQL_BUILD_PATH MYSQL_VER"}
: ${2?"Usage: $0 MYSQL_BASE_PATH MYSQL_BUILD_PATH MYSQL_VER"}
: ${3?"Usage: $0 MYSQL_BASE_PATH MYSQL_BUILD_PATH MYSQL_VER"}
MYSQL_BASE=$1
MYSQL_BUILD_PATH=$2
MYSQL_VER=$3

NPROC=$(nproc)
MJ=$(($NPROC*3/2))
: ${optflags:="-march=nehalem -mtune=haswell"}

cd $MYSQL_BUILD_PATH

rm -f /tmp/${MYSQL_VER}_build

case $MYSQL_VER in
	5.7)
	        cmake . -DBUILD_CONFIG=mysql_release -DCMAKE_BUILD_TYPE=RelWithDebInfo -DFEATURE_SET=community \
	           -DWITH_NUMA=ON -DWITH_SYSTEMD=1 -DWITH_EMBEDDED_SERVER=OFF -DWITH_ZLIB=system \
	           -DWITH_INNODB_MEMCACHED=1 -DWITH_SCALABILITY_METRICS=ON -DDOWNLOAD_BOOST=0 -DWITH_BOOST=../boost_1_59_0 \
	           -DWITH_SSL=system -DWITH_MECAB=/opt/rh/rh-mysql57/root/usr/ -DENABLE_DOWNLOADS=1 -DWITH_PAM=ON ${ASAN} \
	           -DWITH_TOKUDB=1 -DWITH_ROCKSDB=1 -DCMAKE_INSTALL_PREFIX=$MYSQL_BASE | tee /tmp/${MYSQL_VER}_build
                ;;
	5.6)
	        cmake . -DBUILD_CONFIG=mysql_release -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_DTRACE=OFF -DWITH_EMBEDDED_SERVER=OFF \
	           -DCMAKE_C_FLAGS="${optflags}" -DCMAKE_CXX_FLAGS="${optflags}" \
	           -DWITH_INNODB_MEMCACHED=ON -DWITH_SSL=system -DWITH_PAM=ON -DFEATURE_SET=community \
	           -DWITH_ROCKSDB=0 -DWITH_SCALABILITY_METRICS=ON -DCMAKE_INSTALL_PREFIX=$MYSQL_BASE | tee /tmp/${MYSQL_VER}_build
                ;;
        *)
		echo "unsupport percona server version! don't know how to cmake"
		exit 1
		;;
esac

if [ $? -ne 0 ]; then echo "cmake config failed! Assert: non-0 exit status detected!"; exit 1; fi

make VERBOSE=1 -j$MJ | tee -a /tmp/${MYSQL_VER}_build
if [ $? -ne 0 ]; then echo "make failed! Assert: non-0 exit status detected!"; exit 1; fi
