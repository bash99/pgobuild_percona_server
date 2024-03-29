#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH MYSQL_BUILD_PATH MYSQL_VER"}
: ${2?"Usage: $0 MYSQL_BASE_PATH MYSQL_BUILD_PATH MYSQL_VER"}
: ${3?"Usage: $0 MYSQL_BASE_PATH MYSQL_BUILD_PATH MYSQL_VER"}
MYSQL_BASE=$1
MYSQL_BUILD_PATH=$2
MYSQL_VER=$3

NPROC=$(nproc)
MJ=$(($NPROC*3/2))
optflags="$optflags $CPU_OPT_FLAGS"

[[ -f /opt/rh/rh-mysql57/root/usr/include/mecab.h ]] && MECAB_INC=/opt/rh/rh-mysql57/root/usr
[[ -f /opt/rh/rh-mysql80/root/usr/include/mecab.h ]] && MECAB_INC=/opt/rh/rh-mysql80/root/usr
[[ -f /usr/include/mecab.h ]] && MECAB_INC=/usr

CMAKE=cmake
[[ -f /usr/bin/ccmake3 ]] && CMAKE=cmake3

cd $MYSQL_BUILD_PATH

rm -f /tmp/${MYSQL_VER}_build

verlte() {
    printf '%s\n%s' "$1" "$2" | sort -C -V
}

date > /tmp/${MYSQL_VER}_build
case $MYSQL_VER in
	5.7)
	        $CMAKE . -DBUILD_CONFIG=mysql_release -DCMAKE_BUILD_TYPE=RelWithDebInfo -DFEATURE_SET=community \
                   -DCMAKE_C_FLAGS="${optflags}" -DCMAKE_CXX_FLAGS="${optflags}" \
	           -DWITH_NUMA=ON -DWITH_SYSTEMD=1 -DWITH_EMBEDDED_SERVER=OFF -DWITH_ZLIB=system \
	           -DWITH_INNODB_MEMCACHED=1 -DWITH_SCALABILITY_METRICS=ON -DDOWNLOAD_BOOST=0 -DWITH_BOOST=../boost_1_59_0 \
	           -DWITH_SSL=system -DWITH_MECAB=$MECAB_INC -DENABLE_DOWNLOADS=1 -DWITH_PAM=ON ${ASAN} \
	           -DWITH_TOKUDB=1 -DWITH_ROCKSDB=1 2>&1 | tee -a /tmp/${MYSQL_VER}_build
                ;;
	5.6)
	        $CMAKE . -DBUILD_CONFIG=mysql_release -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_DTRACE=OFF -DWITH_EMBEDDED_SERVER=OFF \
	           -DCMAKE_C_FLAGS="${optflags}" -DCMAKE_CXX_FLAGS="${optflags}" -DWITH_SSL=system -DENABLE_DOWNLOADS=1 \
	           -DWITH_INNODB_MEMCACHED=ON -DWITH_SSL=system -DWITH_PAM=ON -DFEATURE_SET=community \
	           -DWITH_ROCKSDB=0 -DWITH_SCALABILITY_METRICS=ON 2>&1 | tee -a /tmp/${MYSQL_VER}_build
                ;;
	8.0)
                ## 8.0's flto require much memory, so MJ = total_memory_inGB / 4
                MEM_K=$(free|grep Mem|awk '{print$2}')
		MEM_G=$(echo "($MEM_K+768*1024)/1024/1024"|bc)
		MJ=$(echo "$MEM_G/4"|bc)
		LTOMJ=$(echo "$MJ/2"|bc)

                [[ -z $ORIGIN_MYSQL ]] && OTHER_ENG="" || OTHER_ENG="-DWITH_ROCKSDB=1 -DWITH_TOKUDB=OFF"

                $CMAKE . -DBUILD_CONFIG=mysql_release -DCMAKE_BUILD_TYPE=RelWithDebInfo -DFEATURE_SET=community \
                   -DWITH_NUMA=ON -DWITH_SYSTEMD=1 -DWITH_READLINE=system -DWITH_SSL=system \
		   -DCMAKE_CXX_LINK_FLAGS="-flto=${LTOMJ}" -DCMAKE_SHARED_LINKER_FLAGS="-flto=${LTOMJ}"  \
                   -DCMAKE_C_FLAGS="${optflags} -flto=${LTOMJ}" -DCMAKE_CXX_FLAGS="${optflags} -flto=${LTOMJ}" \
                   -DMYSQL_MAINTAINER_MODE=OFF -DFORCE_INSOURCE_BUILD=1 -DWITH_LZ4=bundled -DWITH_ZLIB=bundled \
                   -DWITH_PROTOBUF=bundled -DWITH_RAPIDJSON=bundled -DWITH_ICU=bundled -DWITH_LIBEVENT=bundled \
                   -DWITH_INNODB_MEMCACHED=1 -DWITH_BOOST=../boost_cur -DDOWNLOAD_BOOST=ON -DWITH_SYSTEM_LIBS=ON \
                   -DWITH_MECAB=$MECAB_INC -DENABLE_DOWNLOADS=1 -DWITH_PAM=1 -DWITH_ZSTD=bundled ${ASAN} \
                   ${OTHER_ENG} ${PGO_OPT} \
		   -DWITH_KEYRING_VAULT=1 2>&1 | tee -a /tmp/${MYSQL_VER}_build
                ## still some bug when direct make install, systemd require write to /usr/local/mysql, 
                ## which ignore INSTALL_PREFIX, need run command below to workaroud
                $CMAKE build -DCMAKE_INSTALL_PREFIX=$MYSQL_BASE .
                ;;
        *)
		echo "unsupport percona server version! don't know how to cmake"
		exit 1
		;;
esac
if [ $? -ne 0 ]; then echo "cmake config failed! Assert: non-0 exit status detected!"; exit 1; fi

make VERBOSE=1 -j$MJ 2>&1 | tee -a /tmp/${MYSQL_VER}_build
if [ $? -ne 0 ]; then echo "make failed! Assert: non-0 exit status detected!"; exit 1; fi

date >> /tmp/${MYSQL_VER}_build
