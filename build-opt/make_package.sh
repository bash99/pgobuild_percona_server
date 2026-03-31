#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
SELF_PATH=`cd $SELF_PATH; pwd`

: ${1?"Usage: $0 MYSQL_BUILD_PATH PGOED"}
MYSQL_BUILD_PATH=$1
PGOED=$2

detect_distro_tag() {
  if [[ -n "${DISTRO_TAG:-}" ]]; then
    printf '%s\n' "$DISTRO_TAG"
    return 0
  fi
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    printf '%s%s\n' "${ID:-linux}" "${VERSION_ID:+${VERSION_ID%%.*}}"
    return 0
  fi
  printf '%s\n' 'linux'
}

detect_pkg_version() {
  local pkgname="$1"
  local version
  version="$(printf '%s\n' "$pkgname" | sed -r 's/^percona-server-//; s/-[Ll]inux-.*$//')"
  [[ -n "$version" ]] || return 1
  printf '%s\n' "$version"
}

detect_flavor_token() {
  local suffix="$1"
  case "$suffix" in
    pgoed|pgo|pgo-*|*pgo*)
      printf '%s\n' 'PGOed'
      ;;
    normal|baseline)
      printf '%s\n' 'Normal'
      ;;
    *)
      printf '%s\n' "$suffix"
      ;;
  esac
}

for cmd in zstd tar xargs grep perl sed uname; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "required command not found: $cmd" >&2; exit 1; }
done

CUR_PATH=`pwd`

cd $MYSQL_BUILD_PATH

# clean results
rm -rf _CPack_Packages/Linux/TGZ/* _CPack_Packages/Linux/usr
mkdir -p _CPack_Packages/Linux/TGZ

PKGNAME=`grep CPACK_PACKAGE_FILE_NAME CPackConfig.cmake | cut -d '"' -f 2`
PREFIX_DIR=$MYSQL_BUILD_PATH/_CPack_Packages/Linux/TGZ/$PKGNAME

bash $SELF_PATH/../build-normal/install_mini.sh ${MYSQL_BUILD_PATH} $PREFIX_DIR

cd $PREFIX_DIR

## comment out line below for test and static libary
rm -rf lib/*.a lib/mysql/plugin/*test* lib/mysql/plugin/qa_auth_* lib/mysql/plugin/*example* mysql-test
grep -rinl profile-gen . | xargs -n 64 perl -pi -e "s///g"
grep -rinl profile-use . | xargs -n 64 perl -pi -e "s///g"
cd .. 

DISTRO_TAG="$(detect_distro_tag)"
PKG_VERSION="$(detect_pkg_version "$PKGNAME")" || { echo "failed to parse version from $PKGNAME" >&2; exit 1; }
FLAVOR_TOKEN="$(detect_flavor_token "$PGOED")"
ARCH="$(uname -m)"

OUTPUT_FILE="Percona-Server-${PKG_VERSION}-${FLAVOR_TOKEN}.Linux.${ARCH}.${DISTRO_TAG}.mini.tar.zst"
tar cf - "$PKGNAME" | zstd -T0 -19 > "$CUR_PATH/$OUTPUT_FILE"
echo "created package: $CUR_PATH/$OUTPUT_FILE"
