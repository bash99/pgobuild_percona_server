#!/usr/bin/env bash

set -euo pipefail

COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$COMMON_LIB_DIR/platform.sh"

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
  done
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_dir() {
  mkdir -p "$1"
}

resolve_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/.." && pwd
}

detect_source_dir() {
  local repo_root version mini_ver exact_dir legacy_dir
  repo_root="$1"
  version="$2"
  mini_ver="${3:-}"

  if [[ -n "${MYSQL_SOURCE_PATH:-}" && -d "${MYSQL_SOURCE_PATH}" ]]; then
    printf '%s\n' "$(cd "${MYSQL_SOURCE_PATH}" && pwd)"
    return 0
  fi

  exact_dir="$repo_root/percona-server-Percona-Server-${version}.${mini_ver}"
  legacy_dir="$repo_root/ps-${version}"

  if [[ -n "$mini_ver" && -d "$exact_dir" ]]; then
    printf '%s\n' "$exact_dir"
    return 0
  fi

  if [[ -d "$legacy_dir" ]]; then
    printf '%s\n' "$legacy_dir"
    return 0
  fi

  die "could not locate source tree for MySQL ${version}.${mini_ver:-x}"
}

default_jobs() {
  local cpu_count mem_gib max_jobs
  cpu_count="$(nproc)"
  mem_gib="$(awk '/MemTotal/ {printf "%d", ($2 + 1048575) / 1048576}' /proc/meminfo)"

  if [[ "${ENABLE_LTO:-ON}" == "ON" ]]; then
    max_jobs=$(( mem_gib / 4 ))
  else
    max_jobs=$(( mem_gib / 2 ))
  fi

  if (( max_jobs < 1 )); then
    max_jobs=1
  fi

  if (( max_jobs > cpu_count )); then
    max_jobs="$cpu_count"
  fi

  printf '%s\n' "$max_jobs"
}

extract_boost_metadata() {
  local source_dir="$1"
  local boost_cmake package url
  boost_cmake="$source_dir/cmake/boost.cmake"
  [[ -f "$boost_cmake" ]] || die "missing boost metadata file: $boost_cmake"

  package="$(sed -n 's/^[[:space:]]*SET(BOOST_PACKAGE_NAME "\([^"]*\)").*/\1/p' "$boost_cmake" | head -n 1)"
  url="$(sed -n 's/^[[:space:]]*"\(https:\/\/[^\"]*\)".*/\1/p' "$boost_cmake" | head -n 1)"

  [[ -n "$package" ]] || die "failed to parse BOOST_PACKAGE_NAME from $boost_cmake"

  if [[ -z "$url" ]]; then
    url="https://archives.boost.io/release/$(boost_dotted_version_from_package "$package")/source/${package}.tar.bz2"
  fi

  url="${url//\$\{BOOST_TARBALL\}/${package}.tar.bz2}"

  printf '%s|%s\n' "$package" "$url"
}

boost_dotted_version_from_package() {
  local package="$1"
  printf '%s\n' "${package#boost_}" | tr '_' '.'
}

find_boost_root() {
  local package_name="$1"
  shift
  local candidate
  for candidate in "$@"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate/boost/version.hpp" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [[ -f "$candidate/$package_name/boost/version.hpp" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

curl_resume() {
  local url="$1"
  local output="$2"
  local retries="${3:-20}"
  local attempt=1
  local connect_timeout="${CURL_CONNECT_TIMEOUT:-20}"
  local max_time="${CURL_MAX_TIME:-1800}"
  local min_speed_limit="${CURL_MIN_SPEED_LIMIT:-1024}"
  local min_speed_time="${CURL_MIN_SPEED_TIME:-30}"

  while (( attempt <= retries )); do
    if curl \
      -f -L -C - \
      --connect-timeout "$connect_timeout" \
      --max-time "$max_time" \
      --speed-limit "$min_speed_limit" \
      --speed-time "$min_speed_time" \
      -o "$output" "$url"; then
      return 0
    fi
    log_warn "download failed for $url (attempt $attempt/$retries); retrying"
    attempt=$(( attempt + 1 ))
    sleep 2
  done

  return 1
}

download_boost_tarball() {
  local output_dir="$1"
  local package_name="$2"
  local upstream_url="$3"
  local tarball="$output_dir/${package_name}.tar.bz2"
  local dotted_version jfrog_url url
  local -a mirrors=()

  dotted_version="$(boost_dotted_version_from_package "$package_name")"
  jfrog_url="https://boostorg.jfrog.io/artifactory/main/release/${dotted_version}/source/${package_name}.tar.bz2"
  mirrors=(
    "https://mirrors.aliyun.com/blfs/conglomeration/boost/${package_name}.tar.bz2"
    "https://mirrors.tuna.tsinghua.edu.cn/boost/${package_name}.tar.bz2"
    "$upstream_url"
    "$jfrog_url"
  )

  ensure_dir "$output_dir"

  if [[ -f "$tarball" ]] && tar -tjf "$tarball" >/dev/null 2>&1; then
    printf '%s\n' "$tarball"
    return 0
  fi

  rm -f "$tarball"
  for url in "${mirrors[@]}"; do
    log_info "downloading $package_name from $url"
    if curl_resume "$url" "$tarball" 30 && tar -tjf "$tarball" >/dev/null 2>&1; then
      printf '%s\n' "$tarball"
      return 0
    fi
    log_warn "boost download or validation failed for $url"
    rm -f "$tarball"
  done

  return 1
}
