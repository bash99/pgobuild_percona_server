#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_BUILD_PATH"}
MYSQL_BUILD_PATH=$1

cd $MYSQL_BUILD_PATH

if [ ! -r VERSION ]; then
  echo "Assert: 'VERSION' file not found!"
  exit 1
fi

if [ "$(grep "MYSQL_VERSION_EXTRA=" VERSION | sed 's|MYSQL_VERSION_EXTRA=||;s|[ \t]||g')" == "" ]; then  # MS has no extra version number
  perl -pi -e "s/^(MYSQL_VERSION_PATCH.*)\$/\$1-pgo/" VERSION 
else
  perl -pi -e "s/^(MYSQL_VERSION_EXTRA.*)\$/\$1-pgo/" VERSION 
fi
