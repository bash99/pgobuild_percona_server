#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Patched by Ben(bash99@gmail.com) for automatic pgo

NPROC=$(nproc)
MJ=$(($NPROC*3/2))
INSPATH=$(echo $PWD)
cd ps-5.7

if [ ! -r VERSION ]; then
  echo "Assert: 'VERSION' file not found!"
fi

ASAN=
if [ "${1}" != "" ]; then
  echo "Building with ASAN enabled"
  ASAN="-DWITH_ASAN=ON"
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
rm -Rf ${CURPATH}_normal
#mkdir -p ${CURPATH}_normal
rm -f /tmp/5.7_normal_build
cp -al ${CURPATH} ${CURPATH}_normal
cd ${CURPATH}_normal

### TEMPORARY HACK TO AVOID COMPILING TB (WHICH IS NOT READY YET)
rm -Rf ./plugin/tokudb-backup-plugin

cmake . -DWITH_ZLIB=system -DBUILD_CONFIG=mysql_release -DFEATURE_SET=community -DWITH_NUMA=ON -DWITH_SYSTEMD=1 -DWITH_EMBEDDED_SERVER=OFF -DWITH_TOKUDB=0 -DWITH_ROCKSDB=0 -DDOWNLOAD_BOOST=0 -DWITH_BOOST=../boost_1_59_0 -DWITH_SSL=bundled -DWITH_MECAB=/opt/rh/rh-mysql57/root/usr/ -DENABLE_DOWNLOADS=1 -DWITH_PAM=ON ${ASAN} -DCMAKE_INSTALL_PREFIX=${INSPATH}/local/mysql | tee /tmp/5.7_normal_build
if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi
if [ "${ASAN}" != "" -a $MS -eq 1 ]; then
  ASAN_OPTIONS="detect_leaks=0" make -j$MJ | tee -a /tmp/5.7_normal_build  # Upstream is affected by http://bugs.mysql.com/bug.php?id=80014 (fixed in PS)
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi
else
  make -j$MJ | tee -a /tmp/5.7_normal_build
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi
fi

#make DESTDIR=${INSPATH} install
make install

# ugly fix, not sure cmake or make PREFIX problem
ln -s ${INSPATH}/local/mysql/lib/* ${INSPATH}/local/mysql/lib/mysql/
