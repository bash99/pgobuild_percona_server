#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

pkg_manager="$(detect_pkg_manager)"
os_family="$(detect_os_family)"

install_debian_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    autoconf automake libtool pkg-config \
    bzip2 cmake libjemalloc-dev mecab libmecab-dev mecab-ipadic libnuma-dev libaio-dev libncurses-dev \
    libreadline-dev libcurl4-openssl-dev libpam0g-dev bison tmux bc patch \
    libssl-dev libre2-dev libtirpc-dev libedit-dev zip zstd libdata-dmp-perl sysstat \
    numactl libkrb5-dev libldap-dev zlib1g-dev libsasl2-dev libsasl2-modules-gssapi-mit
}

install_rhel_packages() {
  local installer
  local -a mecab_packages
  installer="$1"

  if [[ "$installer" == "dnf" ]]; then
    if ! dnf -q config-manager --help >/dev/null 2>&1; then
      log_info "dnf config-manager unavailable; installing dnf-plugins-core to manage repos"
      dnf install -y dnf-plugins-core || true
    fi
    dnf config-manager --set-enabled crb >/dev/null 2>&1 || true
    dnf config-manager --set-enabled powertools >/dev/null 2>&1 || true
  fi

  "$installer" install -y \
    autoconf automake libtool pkgconfig \
    bzip2 cmake numactl numactl-devel libaio-devel ncurses-devel \
    readline-devel libcurl-devel pam-devel bison tmux bc patch \
    openssl-devel libtirpc-devel rpcgen zip zstd perl-Data-Dumper sysstat \
    krb5-devel openldap-devel zlib-devel cyrus-sasl-devel cyrus-sasl-scram

  mapfile -t mecab_packages < <(rhel_mecab_packages)
  if printf '%s\n' "${mecab_packages[@]}" | grep -qx 'centos-release-scl-rh'; then
    "$installer" install -y centos-release-scl-rh || true
  fi

  log_info "installing mecab packages: ${mecab_packages[*]}"
  if ! "$installer" install -y "${mecab_packages[@]}"; then
    log_warn "mecab packages are unavailable via current repositories; prepare/build will fail unless --skip-fulltext-mecab is used"
  fi
}

case "$pkg_manager" in
  apt)
    install_debian_packages
    ;;
  dnf|yum)
    if [[ "$os_family" != 'rhel' ]]; then
      die "unexpected package manager family: $pkg_manager on $os_family"
    fi
    install_rhel_packages "$pkg_manager"
    ;;
  *)
    die "unsupported package manager: $pkg_manager"
    ;;
esac
