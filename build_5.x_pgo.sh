#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Patched by Ben(bash99@gmail.com) for automatic pgo

#patch -p1 < ../cmake-pgo.patch

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
rm -Rf ${CURPATH}_opt
#mkdir -p ${CURPATH}_opt
rm -f /tmp/5.7_opt_build
cp -R ${CURPATH} ${CURPATH}_opt
cd ${CURPATH}_opt

### TEMPORARY HACK TO AVOID COMPILING TB (WHICH IS NOT READY YET)
rm -Rf ./plugin/tokudb-backup-plugin

cmake . -DWITH_ZLIB=system -DBUILD_CONFIG=mysql_release -DFEATURE_SET=community -DWITH_EMBEDDED_SERVER=OFF -DWITH_TOKUDB=0 -DDOWNLOAD_BOOST=0 -DWITH_BOOST=../boost_1_59_0 -DWITH_SSL=system -DWITH_PAM=ON ${ASAN} | tee /tmp/5.7_opt_build
if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi
if [ "${ASAN}" != "" -a $MS -eq 1 ]; then
  ASAN_OPTIONS="detect_leaks=0" make -j12 | tee -a /tmp/5.7_opt_build  # Upstream is affected by http://bugs.mysql.com/bug.php?id=80014 (fixed in PS)
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi
else
  make -j12 | tee -a /tmp/5.7_opt_build
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi
fi

chown -R mysql:mysql .

LD_PRELOAD="/usr/lib64/libjemalloc.so.1" MALLOC_CONF="lg_dirty_mult:-1" sql/mysqld --basedir=/usr/local/mysql --datadir=/usr/local/mysql/data --plugin-dir=/usr/local/mysql/lib/mysql/plugin --user=mysql --log-error=/var/lib/mysql/alert.log --open-files-limit=10000 --pid-file=/usr/local/mysql/data/mysql-0105.pid --socket=/var/lib/mysql/mysql.sock &
#### waiting buffer pool load
sleep 60;


### generate profile
sh ../pspgo-utils/train-sysbench.sh

# /usr/local/src/tpcc-mysql-autoinc-pk/tpcc_start -dtpcc100 -utpcc -ptpcc -w100 -c32 -r300 -l3600

mysqladmin shutdown

### use profile
find . -name "flags.make" | xargs -n 64 perl -pi -e "s/profile-generate/profile-use -fprofile-correction /g"
find . -name "link.txt" | xargs -n 64 perl -pi -e "s/profile-generate/profile-use -fprofile-correction /g"

make -j12

# clean results
rm -rf _CPack_Packages/Linux/TGZ/*
./scripts/make_binary_distribution
cd _CPack_Packages/Linux/TGZ/*linux-x86_64/
mv bin/mysqld ../
strip --strip-debug bin/* lib/*.so lib/*.a lib/mysql/plugin/*.so ./mysql-test/lib/My/SafeProcess/my_safe_process

grep -rinl profile-gen . | xargs -n 64 perl -pi -e "s/--profile-generate //g" 
grep -rinl profile-use . | xargs -n 64 perl -pi -e "s/profile-use -fprofile-correction //g"
mv ../mysqld bin/
cd .. && tar zcf mysql-ps-pgo_linux-x86_64.tar.gz *linux-x86_64/

strip *linux-x86_64/bin/mysqld
mv *linux-x86_64/mysql-test .. && tar cf - *linux-x86_64/ | pxz -3 > mysql-percona-mini_linux-x86_64.tar.xz


exit

