#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Patched by Ben(bash99@gmail.com) for automatic pgo

INSPATH=/usr

cd ps-5.7

if [ ! -r VERSION ]; then
  echo "Assert: 'VERSION' file not found!"
fi

DATE=$(date +'%d%m%y')
PREFIX=
MS=0

if [ "$(grep "MYSQL_VERSION_EXTRA=" VERSION | sed 's|MYSQL_VERSION_EXTRA=||;s|[ \t]||g')" == "" ]; then  # MS has no extra version number
  MS=1
  PREFIX="MS${DATE}"
else
  PREFIX="PS${DATE}"
fi

CURPATH=$(echo $PWD | sed 's|.*/||')

cd ..
rm -Rf ${CURPATH}_opt
#mkdir -p ${CURPATH}_opt
rm -f /tmp/5.7_opt_build
cp -al ${CURPATH} ${CURPATH}_opt
cd ${CURPATH}_opt

patch -p1 < ../pspgo-utils/build-opt/cmake-pgo.patch

### TEMPORARY HACK TO AVOID COMPILING TB (WHICH IS NOT READY YET)
rm -Rf ./plugin/tokudb-backup-plugin

cmake . -DWITH_ZLIB=system -DBUILD_CONFIG=mysql_release -DFEATURE_SET=community -DWITH_NUMA=ON -DWITH_SYSTEMD=1 -DWITH_EMBEDDED_SERVER=OFF -DWITH_TOKUDB=0 -DWITH_ROCKSDB=0 -DDOWNLOAD_BOOST=0 -DWITH_BOOST=../boost_1_59_0 -DWITH_SSL=bundled -DWITH_MECAB=/opt/rh/rh-mysql57/root/usr/ -DENABLE_DOWNLOADS=1 -DWITH_PAM=ON | tee /tmp/5.7_opt_build
if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi
  
make -j12 | tee -a /tmp/5.7_opt_build
if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi

#chown -R mysql:mysql .

cd ..
export MYSQL_USER=`whoami`
export MYSQL_BASE=`pwd`/local/mysql

LD_PRELOAD="/usr/lib64/libjemalloc.so.1" MALLOC_CONF="lg_dirty_mult:-1" ${CURPATH}_opt/sql/mysqld --defaults-file=$MYSQL_BASE/etc/my.automem.cnf --basedir=$MYSQL_BASE --datadir=$MYSQL_BASE/data --plugin-dir=$MYSQL_BASE/lib/mysql/plugin --user=$MYSQL_USER &
#### waiting buffer pool load
sleep 60

### generate profile
sh ../pspgo-utils/build-opt/train-sysbench.sh | tee /tmp/train_onprofile.txt

$MYSQL_BASE/bin/mysqladmin -u root --socket=$MYSQL_BASE/data/mysql.sock shutdown

### use profile
find . -name "flags.make" | xargs -n 64 perl -pi -e "s/profile-generate/profile-use -fprofile-correction /g"
find . -name "link.txt" | xargs -n 64 perl -pi -e "s/profile-generate/profile-use -fprofile-correction /g"

make -j12

LD_PRELOAD="/usr/lib64/libjemalloc.so.1" MALLOC_CONF="lg_dirty_mult:-1" ${CURPATH}_opt/sql/mysqld --defaults-file=$MYSQL_BASE/etc/my.automem.cnf --basedir=$MYSQL_BASE --datadir=$MYSQL_BASE/data --plugin-dir=$MYSQL_BASE/lib/mysql/plugin --user=$MYSQL_USER &
#### waiting buffer pool load
sleep 60

### generate result
sh ../pspgo-utils/build-opt/train-sysbench.sh | tee /tmp/train_result.txt

$MYSQL_BASE/bin/mysqladmin -u root --socket=$MYSQL_BASE/data/mysql.sock shutdown

