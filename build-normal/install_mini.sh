#!/bin/bash

: ${1?"Usage: $0 MYSQL_BUILD_PATH INSTALL_PREFIX"}
MYSQL_BUILD_PATH=$1
if [ "$2" != "" ]; then
    INSTALL_PREFIX=$2
    PREIFX_OPT="-DCMAKE_INSTALL_PREFIX=$2 "
fi

cd $MYSQL_BUILD_PATH

## deal with some absolute cmake install paths
perl -pi -e "s{/usr/local/mysql/usr}{$INSTALL_PREFIX}g" scripts/*.cmake

## install without mysql-test(too large and no use for server package)
cat cmake_install.cmake | perl -e "while(<>) {print unless /mysql-test/;}" > cmake.tmp
cp -f cmake_install.cmake cmake_install.cmake.bak
mv -f cmake.tmp cmake_install.cmake
make preinstall -j `nproc`

## call camke directly as prefix don't work for cmake at install stage 
/usr/bin/cmake -DCMAKE_INSTALL_DO_STRIP=1 ${PREIFX_OPT} -P cmake_install.cmake
#echo make install/strip/fast -j `nproc`
