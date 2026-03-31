#!/usr/bin/env bash

set -euo pipefail

platform_read_os_release() {
  local key="$1"
  if [[ -r /etc/os-release ]]; then
    awk -F= -v wanted="$key" '$1 == wanted {
      value=$2
      gsub(/^"|"$/, "", value)
      print value
      exit
    }' /etc/os-release
  fi
}

detect_os_id() {
  local os_id
  os_id="$(platform_read_os_release ID || true)"
  if [[ -n "$os_id" ]]; then
    printf '%s\n' "$os_id"
  else
    printf 'unknown\n'
  fi
}

detect_os_version_id() {
  local version_id
  version_id="$(platform_read_os_release VERSION_ID || true)"
  printf '%s\n' "$version_id"
}

detect_os_family() {
  local os_id id_like
  os_id="$(detect_os_id)"
  id_like="$(platform_read_os_release ID_LIKE || true)"

  case " $os_id $id_like " in
    *" debian "*|*" ubuntu "*)
      printf 'debian\n'
      ;;
    *" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" fedora "*)
      printf 'rhel\n'
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt\n'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf\n'
  elif command -v yum >/dev/null 2>&1; then
    printf 'yum\n'
  else
    printf 'unknown\n'
  fi
}

is_container_env() {
  [[ -f /.dockerenv || -f /run/.containerenv ]] && return 0
  grep -qaE '(docker|containerd|kubepods|podman|lxc)' /proc/1/cgroup 2>/dev/null
}

resolve_cmake_command() {
  local candidate
  for candidate in cmake cmake3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

find_mecab_prefix() {
  local prefix
  for prefix in $(mecab_candidate_prefixes); do
    if [[ -f "$prefix/include/mecab.h" ]]; then
      printf '%s\n' "$prefix"
      return 0
    fi
  done

  return 1
}

mecab_candidate_prefixes() {
  local os_family os_version mysql_ver
  os_family="$(detect_os_family)"
  os_version="$(detect_os_version_id)"
  mysql_ver="${MYSQL_VER:-}"

  if [[ "$os_family" == "rhel" && "$os_version" == 7* ]]; then
    case "$mysql_ver" in
      5.7)
        printf '%s\n' /opt/rh/rh-mysql57/root/usr /opt/rh/rh-mysql80/root/usr /usr /usr/local
        return 0
        ;;
      8.0|8.4)
        printf '%s\n' /opt/rh/rh-mysql80/root/usr /opt/rh/rh-mysql84/root/usr /usr /usr/local
        return 0
        ;;
    esac
  fi

  printf '%s\n' /usr /usr/local /opt/rh/rh-mysql84/root/usr /opt/rh/rh-mysql80/root/usr /opt/rh/rh-mysql57/root/usr
}

find_mecab_library_dir() {
  local prefix="$1"
  local candidate
  for candidate in \
    "$prefix/lib64" \
    "$prefix/lib"; do
    if [[ -f "$candidate/libmecab.so" || -f "$candidate/libmecab.so.2" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

rhel_mecab_packages() {
  local os_version mysql_ver
  os_version="$(detect_os_version_id)"
  mysql_ver="${MYSQL_VER:-}"

  if [[ "$os_version" == 7* ]]; then
    case "$mysql_ver" in
      5.7)
        printf '%s\n' centos-release-scl-rh rh-mysql57-mecab rh-mysql57-mecab-devel
        return 0
        ;;
      8.0|8.4)
        printf '%s\n' centos-release-scl-rh rh-mysql80-mecab rh-mysql80-mecab-devel
        return 0
        ;;
    esac
  fi

  printf '%s\n' mecab mecab-devel mecab-ipadic
}

find_jemalloc_lib() {
  local path
  for path in \
    /usr/lib/x86_64-linux-gnu/libjemalloc.so \
    /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    /usr/lib64/libjemalloc.so \
    /usr/lib64/libjemalloc.so.1 \
    /usr/lib64/libjemalloc.so.2 \
    /lib64/libjemalloc.so.2; do
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  return 1
}

platform_enable_optional_toolchain() {
  local candidate
  PLATFORM_OPTIONAL_TOOLCHAIN_PATH=''
  for candidate in \
    /opt/rh/gcc-toolset-13/enable \
    /opt/rh/gcc-toolset-12/enable \
    /opt/rh/gcc-toolset-11/enable \
    /opt/rh/gcc-toolset-10/enable \
    /opt/rh/devtoolset-10/enable \
    /opt/rh/devtoolset-9/enable \
    /opt/rh/devtoolset-8/enable \
    /opt/rh/devtoolset-7/enable; do
    if [[ -f "$candidate" ]]; then
      . "$candidate"
      PLATFORM_OPTIONAL_TOOLCHAIN_PATH="$candidate"
      export PLATFORM_OPTIONAL_TOOLCHAIN_PATH
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}
