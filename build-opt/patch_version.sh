#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

: ${1?"Usage: $0 MYSQL_BUILD_PATH"}
MYSQL_BUILD_PATH=$1

cd $MYSQL_BUILD_PATH

VERSION_FILE=''
if [ -r VERSION ]; then
  VERSION_FILE=VERSION
elif [ -r MYSQL_VERSION ]; then
  VERSION_FILE=MYSQL_VERSION
else
  echo "Assert: version metadata file not found!"
  exit 1
fi

if [ "$(grep "MYSQL_VERSION_EXTRA=" "$VERSION_FILE" | sed 's|MYSQL_VERSION_EXTRA=||;s|[ \t]||g')" == "" ]; then  # MS has no extra version number
  perl -pi -e "s/^(MYSQL_VERSION_PATCH.*)\$/\$1-pgo/" "$VERSION_FILE"
else
  perl -pi -e "s/^(MYSQL_VERSION_EXTRA.*)\$/\$1-pgo/" "$VERSION_FILE"
fi
