#!/bin/bash

init_system=''
normal_build=''
pgo_build=''
download_source=''

print_usage() {
  printf "Usage: -i -n -p -d \n"
  printf "i init system lib and gcc, require sudo permissions\n"
  printf "d download source\n"
  printf "n normal build\n"
  printf "p pgo build\n"
  exit 1
}

while getopts 'inpd' flag; do
  case "${flag}" in
    i) init_system='true' ;;
    n) normal_build='true' ;;
    p) pgo_build='true' ;;
    d) download_source='true' ;;
    *) print_usage ;;
  esac
done

[[ -z $init_system && -z $download_source && -z $normal_build && -z $pgo_build ]] && print_usage

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
SELF_PATH=`cd $SELF_PATH; pwd`

: ${CPU_OPT_FLAGS:="-march=nehalem -mtune=haswell"}
: ${MYSQL_VER:=5.6}
: ${MYSQL_MINI_VER:=48-80.0}
export MYSQL_VER MYSQL_MINI_VER CPU_OPT_FLAGS

CUR_PATH=`pwd`

export MYSQL_SOURCE_PATH=$CUR_PATH/ps-${MYSQL_VER}
export MYSQL_BASE=$CUR_PATH/local/ps-${MYSQL_VER}

if [[ "$init_system" == "true" ]]; then
  bash $SELF_PATH/prepare/prepare_system.sh
  if [ $? -ne 0 ]; then echo "prepare requirement and mysql source failed! Assert: non-0 exit status detected!"; exit 1; fi
fi

if [[ "$download_source" == 'true' ]]; then
  bash $SELF_PATH/prepare/download-source.sh
  if [ $? -ne 0 ]; then echo "prepare requirement and mysql source failed! Assert: non-0 exit status detected!"; exit 1; fi
fi

[[ -f /opt/rh/devtoolset-7/enable ]] && . /opt/rh/devtoolset-7/enable
[[ -f /opt/rh/devtoolset-8/enable ]] && . /opt/rh/devtoolset-8/enable
[[ -f /opt/rh/devtoolset-9/enable ]] && . /opt/rh/devtoolset-9/enable

if [[ "$normal_build" == 'true' ]]; then
  bash $SELF_PATH/build-normal/doall.sh
  if [ $? -ne 0 ]; then echo "build normal failed! Assert: non-0 exit status detected!"; exit 1; fi
fi

if [[ "$pgo_build" == 'true' ]]; then
  bash $SELF_PATH/build-opt/doall.sh $MYSQL_BASE $MYSQL_SOURCE_PATH $MYSQL_VER
fi
 
