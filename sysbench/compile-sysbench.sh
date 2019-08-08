#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}

MYSQL_BASE=$1

if [ "$SYSBENCH_BASE" == "" ]; then
  # rm -rf sysbench $MYSQL_BASE/sysbench && \
  git clone --depth 1 https://github.com/akopytov/sysbench -b 1.0 sysbench

  export LDFLAGS="-L$MYSQL_BASE/lib"
  cd sysbench && git pull \
  && ./autogen.sh \
  && ./configure --with-mysql=$MYSQL_BASE \
  && make clean -j ${nproc} && make install -j ${nproc} prefix=$MYSQL_BASE/sysbench
else
  if [ -d $SYSBENCH_BASE ]; then
    echo "SYSBENCH exists, don't download and compile"
  else
    echo "SYSBENCH_BASE is setting, but is a dir, something wrong!"
    exit 1
  fi
fi
