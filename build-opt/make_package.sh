#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_BUILD_PATH PGOED"}
MYSQL_BUILD_PATH=$1
PGOED=$2

CUR_PATH=`pwd`

cd $MYSQL_BUILD_PATH

# clean results
rm -rf _CPack_Packages/Linux/TGZ/* _CPack_Packages/Linux/usr
mkdir -p _CPack_Packages/Linux/TGZ

PKGNAME=`grep CPACK_PACKAGE_FILE_NAME CPackConfig.cmake | cut -d '"' -f 2`
PREFIX_DIR=$MYSQL_BUILD_PATH/_CPack_Packages/Linux/TGZ/$PKGNAME

bash $SELF_PATH/../build-normal/install_mini.sh ${MYSQL_BUILD_PATH} $PREFIX_DIR

cd $PREFIX_DIR

rm -rf lib/*.a lib/mysql/plugin/*test* lib/mysql/plugin/qa_auth_* lib/mysql/plugin/*example* mysql-test
grep -rinl profile-gen . | xargs -n 64 perl -pi -e "s///g"
grep -rinl profile-use . | xargs -n 64 perl -pi -e "s///g"
cd .. 
tar cf - $PKGNAME | pxz -4 > $CUR_PATH/mini_$PKGNAME-${PGOED}.tar.xz
## zstd is good, we'll use it once default tar on centos 7 can automatic decompress it
#tar cf - $PKGNAME | zstd -T0 -6 > $CUR_PATH/mini_$PKGNAME.tar.zst
