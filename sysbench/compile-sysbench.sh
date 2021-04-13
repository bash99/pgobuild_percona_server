#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}

MYSQL_BASE=$1

if [ "$SYSBENCH_BASE" == "" ]; then
  # rm -rf sysbench $MYSQL_BASE/sysbench && \
  SYSBENCH_SRC=sysbench_1.0
  git clone --depth 1 https://github.com/akopytov/sysbench -b 1.0 $SYSBENCH_SRC

  export LDFLAGS="-L$MYSQL_BASE/lib -lstdc++"
  cd $SYSBENCH_SRC && git pull \
  && ./autogen.sh \
  && ./configure --with-mysql=$MYSQL_BASE \
  && make clean \
  && make -j ${nproc} \
  && make install -j ${nproc} prefix=$MYSQL_BASE/sysbench
## tmp config for build static sysbench
#  && perl -pi.bak -e "s/-lperconaserverclient/-lperconaserverclient -lstdc++/" Makefile src/Makefile \
#  && perl -pi.bak -e "s/-l-pthread/-lpthread/g" Makefile src/Makefile \
#  && mv -f $MYSQL_BASE/lib/libmysqlclient.so $MYSQL_BASE/lib/libmysqlclient.soso \
#  && mv -f $MYSQL_BASE/lib/libmysqlclient.soso $MYSQL_BASE/lib/libmysqlclient.so \
#  && mv -f $MYSQL_BASE/lib/libperconaserverclient.soso $MYSQL_BASE/lib/libperconaserverclient.so \
#  && mv -f $MYSQL_BASE/lib/libperconaserverclient.so $MYSQL_BASE/lib/libperconaserverclient.soso \
else
  if [ -d $SYSBENCH_BASE ]; then
    sleep 15
    echo "SYSBENCH exists, don't download and compile"
  else
    echo "SYSBENCH_BASE is setting, but is a dir, something wrong!"
    exit 1
  fi
fi
