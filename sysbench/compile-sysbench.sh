#!/usr/bin/env bash

set -euo pipefail

: ${1?"Usage: $0 MYSQL_BASE_PATH"}

MYSQL_BASE=$1
SYSBENCH_INSTALL_PREFIX="${SYSBENCH_BASE:-$MYSQL_BASE/sysbench}"
SYSBENCH_SRC=sysbench_1.0

if [[ -x "$SYSBENCH_INSTALL_PREFIX/bin/sysbench" ]]; then
  echo "SYSBENCH exists, don't download and compile"
  exit 0
fi

if [[ ! -f "$SYSBENCH_SRC/autogen.sh" || ! -f "$SYSBENCH_SRC/configure.ac" ]]; then
  rm -rf "$SYSBENCH_SRC"
  git clone --depth 1 https://github.com/akopytov/sysbench -b 1.0 "$SYSBENCH_SRC"
fi

mkdir -p "$SYSBENCH_INSTALL_PREFIX"

export LDFLAGS="-L$MYSQL_BASE/lib -lstdc++"
cd "$SYSBENCH_SRC" \
&& ACLOCAL=aclocal AUTOMAKE=automake LIBTOOLIZE=libtoolize AUTOCONF=autoconf AUTOHEADER=autoheader ./autogen.sh \
&& ./configure --with-mysql=$MYSQL_BASE \
&& make clean \
&& make -j "$(nproc)" \
&& make install -j "$(nproc)" prefix="$SYSBENCH_INSTALL_PREFIX"
## tmp config for build static sysbench
#  && perl -pi.bak -e "s/-lperconaserverclient/-lperconaserverclient -lstdc++/" Makefile src/Makefile \
#  && perl -pi.bak -e "s/-l-pthread/-lpthread/g" Makefile src/Makefile \
#  && mv -f $MYSQL_BASE/lib/libmysqlclient.so $MYSQL_BASE/lib/libmysqlclient.soso \
#  && mv -f $MYSQL_BASE/lib/libmysqlclient.soso $MYSQL_BASE/lib/libmysqlclient.so \
#  && mv -f $MYSQL_BASE/lib/libperconaserverclient.soso $MYSQL_BASE/lib/libperconaserverclient.so \
#  && mv -f $MYSQL_BASE/lib/libperconaserverclient.so $MYSQL_BASE/lib/libperconaserverclient.soso \
