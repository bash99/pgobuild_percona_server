#!/bin/bash

## mysql VERSION 5.6 44-86.0  5.7 26-29 8.0 15-6 remote url is like
## https://www.percona.com/downloads/Percona-Server-8.0/Percona-Server-8.0.15-6/source/tarball/percona-server-8.0.15-6.tar.gz
## vanilla mysql, only 8.0
## https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.23.tar.gz
MAJOR_VER=${MYSQL_VER:-5.7}
MINI_VER=${MYSQL_MINI_VER:-30-33}
MYSQL_SOURCE_PATH=${MYSQL_SOURCE_PATH:-ps-${MAJOR_VER}}
MYSQL_SOURCE_TARBALL=percona-server-${MAJOR_VER}.${MINI_VER}.tar.gz
MYSQL_SOURCE_TARBALL_URL=${MYSQL_SOURCE_TARBALL_URL:-https://downloads.percona.com/downloads/Percona-Server-${MAJOR_VER}/Percona-Server-${MAJOR_VER}.${MINI_VER}/source/tarball/percona-server-${MAJOR_VER}.${MINI_VER}.tar.gz}
MYSQL_SOURCE_FALLBACK_URL=${MYSQL_SOURCE_FALLBACK_URL:-https://github.com/percona/percona-server/archive/refs/tags/Percona-Server-${MAJOR_VER}.${MINI_VER}.tar.gz}

safe_curl_download() {
	local url=$1
	local file=$2
	local retries=${3:-5}
	local attempt=1
	if [[ -f $file ]]; then
		local local_size=$(ls -l $file | cut -d ' ' -f 5)
		local remote_size=$(https_proxy="" curl -Is "$url" | grep -i Content-Length | sed -e "s/\r//" | awk '{print $2}')

		[[ -n "$remote_size" && "$remote_size" == "$local_size" ]] && echo "no need to download" && return 0
	fi

	while (( attempt <= retries )); do
		curl -fL -C - "$url" -o "$file" && return 0
		local ec=$?
		if [[ $ec -eq 22 ]]; then
			break
		fi
		attempt=$((attempt + 1))
		sleep 2
	done
	return 1
}

if [[ -d "$MYSQL_SOURCE_PATH" && ! -f "$MYSQL_SOURCE_PATH/CMakeLists.txt" ]]; then
    rm -rf "$MYSQL_SOURCE_PATH"
fi

if [ ! -d "$MYSQL_SOURCE_PATH" ]; then
    MYSQL_URL="$MYSQL_SOURCE_TARBALL_URL"
    [[ -z ${ORIGIN_MYSQL:-} ]] || MYSQL_URL=https://dev.mysql.com/get/Downloads/MySQL-${MAJOR_VER}/mysql-${MAJOR_VER}.${MINI_VER}.tar.gz
    [[ -z ${ORIGIN_MYSQL:-} ]] || MYSQL_SOURCE_TARBALL=mysql-${MAJOR_VER}.${MINI_VER}.tar.gz
    echo "ORIGIN_MYSQL=${ORIGIN_MYSQL:-}" use mysql url: $MYSQL_URL
    if ! safe_curl_download "$MYSQL_URL" "$MYSQL_SOURCE_TARBALL"; then
        if [[ -n "$MYSQL_SOURCE_FALLBACK_URL" ]]; then
            echo "primary source download failed, fallback to: $MYSQL_SOURCE_FALLBACK_URL"
            MYSQL_SOURCE_TARBALL="$(basename "$MYSQL_SOURCE_FALLBACK_URL")"
            safe_curl_download "$MYSQL_SOURCE_FALLBACK_URL" "$MYSQL_SOURCE_TARBALL"
        else
            exit 1
        fi
    fi
    mkdir -p "$MYSQL_SOURCE_PATH" && tar -xf "$MYSQL_SOURCE_TARBALL" \
        -C "$MYSQL_SOURCE_PATH" --strip-components=1
fi
if [ $? -ne 0 ]; then echo "download mysql source failed! Assert: non-0 exit status detected!"; exit 1; fi

#
# && git clone  --depth 1 https://github.com/percona/percona-server.git -b 5.7 ps-5.7 \
# && cd ps-5.7 && git submodule init && git submodule update

verlte() { 
    printf '%s\n%s' "$1" "$2" | sort -C -V
}

case $MYSQL_VER in
        5.7)
		BOOST_VER=1_59_0
		;;
        *)
		;;
esac

if [ "$BOOST_VER" != "" ]; then
  BOOST_DOT_VER=`echo $BOOST_VER | sed -e "s/\_/./g"`
  if [ ! -d boost_${BOOST_VER} ]; then
    curl $curl_retry_opt -L -C - https://sourceforge.net/projects/boost/files/boost/${BOOST_DOT_VER}/boost_${BOOST_VER}.tar.bz2/download -o boost_${BOOST_VER}.tar.bz2 \
      && tar jxf boost_${BOOST_VER}.tar.bz2
    if [ $? -ne 0 ]; then echo "cmake config failed! Assert: non-0 exit status detected!"; exit 1; fi
  fi
fi
