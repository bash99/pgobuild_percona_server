#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_BASE_PATH MYSQL_SOURCE_PATH MYSQL_VER"}
: ${2?"Usage: $0 MYSQL_BASE_PATH MYSQL_SOURCE_PATH MYSQL_VER"}
: ${3?"Usage: $0 MYSQL_BASE_PATH MYSQL_SOURCE_PATH MYSQL_VER"}
MYSQL_BASE=$1
MYSQL_SOURCE_PATH=$2
MYSQL_VER=$3

bash $SELF_PATH/../build-normal/prepare_build.sh $MYSQL_SOURCE_PATH $MYSQL_VER "pgobuild"
MYSQL_BUILD_PATH=${MYSQL_SOURCE_PATH}_pgobuild

bash $SELF_PATH/patch_version.sh $MYSQL_BUILD_PATH

export optflags=" $CPU_OPT_FLAGS "  PGO_OPT=" -DFPROFILE_GENERATE=ON"
bash $SELF_PATH/../build-normal/compile.sh $MYSQL_BASE ${MYSQL_BUILD_PATH} $MYSQL_VER
if [ $? -ne 0 ]; then echo "compile failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/../build-normal/install_mini.sh ${MYSQL_BUILD_PATH} $MYSQL_BASE
if [ $? -ne 0 ]; then echo "install failed! Assert: non-0 exit status detected!"; exit 1; fi

## in normal situation, you should run pgo after normal build, so mysql and sysbench db is already inited
##bash $SELF_PATH/../build-normal/init_normal.sh $MYSQL_BASE
##if [ $? -ne 0 ]; then echo "install failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/../build-normal/start_normal.sh $MYSQL_BASE
#### waiting buffer pool load
sleep 60

### generate profile
##bash $SELF_PATH/../sysbench/compile-sysbench.sh $MYSQL_BASE
## in normal situation, you should run pgo after normal build, so mysql and sysbench db is already inited
##bash $SELF_PATH/../sysbench/init-sysbench.sh $MYSQL_BASE
## mysql 8.0/gcc 9 will generate profile-data in seperate dir
rm -rf profile-data
bash $SELF_PATH/../sysbench/train-sysbench.sh $MYSQL_BASE | tee /tmp/${MYSQL_VER}_genprofile.txt

bash $SELF_PATH/../build-normal/shutdown_normal.sh $MYSQL_BASE

#find ${MYSQL_BUILD_PATH} -name "*.gcda" | tail

#exit 1
### we need reprepared build path for 8.0
bash $SELF_PATH/../build-normal/prepare_build.sh $MYSQL_SOURCE_PATH $MYSQL_VER "pgobuild"

### use profile, some tokudb branch is not used, so we need -Wnoerror=missing-profile
export optflags=" $CPU_OPT_FLAGS -Wno-missing-profile"   PGO_OPT=" -DFPROFILE_USE=ON"
bash $SELF_PATH/../build-normal/compile.sh $MYSQL_BASE ${MYSQL_BUILD_PATH} $MYSQL_VER
if [ $? -ne 0 ]; then echo "compile failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/../build-normal/install_mini.sh ${MYSQL_BUILD_PATH} $MYSQL_BASE
if [ $? -ne 0 ]; then echo "install failed! Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/../build-normal/start_normal.sh $MYSQL_BASE
#### waiting buffer pool load
sleep 60

### test pgoed result
bash $SELF_PATH/../sysbench/train-sysbench.sh $MYSQL_BASE | tee /tmp/${MYSQL_VER}_pgoed_result.txt

bash $SELF_PATH/../build-normal/shutdown_normal.sh $MYSQL_BASE

grep transaction /tmp/${MYSQL_VER}*_result.txt | tee ${MYSQL_VER}_pgo_result.txt

