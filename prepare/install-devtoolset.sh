#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

pkg_manager="$(detect_pkg_manager)"
os_family="$(detect_os_family)"
os_version_id="$(detect_os_version_id)"

install_debian_toolchain() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y build-essential gcc g++ make git rsync ca-certificates curl gnupg
}

install_rhel_toolchain() {
  local installer
  local curl_pkg
  installer="$1"

  curl_pkg="curl"
  if rpm -q curl-minimal >/dev/null 2>&1; then
    curl_pkg="curl-minimal"
  fi

  "$installer" install -y gcc gcc-c++ make git rsync ca-certificates "$curl_pkg" gnupg2

  if [[ "$os_version_id" == 8* || "$os_version_id" == 9* ]]; then
    "$installer" install -y \
      gcc-toolset-12-gcc \
      gcc-toolset-12-gcc-c++ \
      gcc-toolset-12-binutils \
      gcc-toolset-12-libatomic-devel \
      gcc-toolset-12-annobin-annocheck \
      gcc-toolset-12-annobin-plugin-gcc
  fi
}

case "$pkg_manager" in
  apt)
    install_debian_toolchain
    ;;
  dnf|yum)
    if [[ "$os_family" != 'rhel' ]]; then
      die "unexpected package manager family: $pkg_manager on $os_family"
    fi
    install_rhel_toolchain "$pkg_manager"
    ;;
  *)
    die "unsupported package manager: $pkg_manager"
    ;;
esac

if platform_enable_optional_toolchain >/dev/null; then
  log_info "optional toolchain available: ${PLATFORM_OPTIONAL_TOOLCHAIN_PATH:-unknown}"
else
  log_info "using system compiler toolchain"
fi
