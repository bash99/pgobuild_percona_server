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
#cat cmake_install.cmake | perl -e "while(<>) {print unless /mysql-test/;}" > cmake.tmp
#cp -f cmake_install.cmake cmake_install.cmake.bak
#mv -f cmake.tmp cmake_install.cmake

make preinstall -j `nproc`
if [ $? -ne 0 ]; then echo "cmake config failed! Assert: non-0 exit status detected!"; exit 1; fi

## call camke directly as prefix don't work for cmake at install stage 
#cmake -DCMAKE_INSTALL_DO_STRIP=1 ${PREIFX_OPT} -P cmake_install.cmake
#echo make install/strip/fast -j `nproc`

## use below method to skip install Test/TestReadme component, which is too many small files.
## Also can futher split binary for docker image
for comp in Server DebugBinaries Developement Development Documentation Info Router IniFiles ManPages Readme Server_Scripts Client DataFiles SharedLibraries SupportFiles tokubackup_headers tokubackup_libs_shared tokuv_misc tokukv_tools Unspecified
do
    cmake -DCMAKE_INSTALL_COMPONENT=$comp -DCMAKE_INSTALL_DO_STRIP=1 ${PREIFX_OPT}  -P cmake_install.cmake
    if [ $? -ne 0 ]; then echo "cmake config failed! Assert: non-0 exit status detected!"; exit 1; fi
done

