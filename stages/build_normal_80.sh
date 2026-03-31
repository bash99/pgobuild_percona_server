#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

if platform_enable_optional_toolchain >/dev/null 2>&1; then
  log_info "enabled optional toolchain: ${PLATFORM_OPTIONAL_TOOLCHAIN_PATH:-unknown}"
fi

: "${MYSQL_VER:=8.0}"
: "${MYSQL_MINI_VER:=44-35}"
: "${BUILD_PROFILE:=normal}"
: "${ENABLE_CCACHE:=AUTO}"
: "${ENABLE_LTO:=OFF}"
: "${LTO_JOBS:=auto}"
: "${LINKER_FLAVOR:=default}"
: "${DOWNLOAD_BOOST:=AUTO}"
: "${CPU_OPT_FLAGS:=-march=nehalem -mtune=haswell}"
: "${FORCE_INSOURCE_BUILD:=OFF}"
: "${PGO_MODE:=off}"
: "${PGO_PROFILE_DIR:=}"
: "${PGO_USE_WARNING_POLICY:=relaxed}"
: "${ENABLE_GROUP_REPLICATION:=ON}"
: "${SKIP_FULLTEXT_MECAB:=OFF}"
: "${WITH_ROCKSDB:=OFF}"

case "$MYSQL_VER" in
  8.0|8.4)
    ;;
  *)
    die "build_normal_80.sh only supports MYSQL_VER=8.0 or 8.4"
    ;;
esac

CMAKE_BIN="$(resolve_cmake_command || true)"
[[ -n "$CMAKE_BIN" ]] || die "cmake or cmake3 is required"
require_cmd awk curl make nproc sed tar "$CMAKE_BIN"

SOURCE_DIR="$(detect_source_dir "$REPO_ROOT" "$MYSQL_VER" "$MYSQL_MINI_VER")"
BOOST_METADATA="$(extract_boost_metadata "$SOURCE_DIR")"
BOOST_PACKAGE_NAME="${BOOST_METADATA%%|*}"
BOOST_DOWNLOAD_URL="${BOOST_METADATA#*|}"

WORK_ROOT="${WORK_ROOT:-$REPO_ROOT/work}"
BUILD_ROOT="${BUILD_ROOT:-$WORK_ROOT/build/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-$BUILD_PROFILE}"
INSTALL_ROOT="${INSTALL_ROOT:-$WORK_ROOT/install/ps-${MYSQL_VER}.${MYSQL_MINI_VER}-$BUILD_PROFILE}"
LOG_ROOT="${LOG_ROOT:-$WORK_ROOT/logs}"
LOG_FILE="$LOG_ROOT/build-normal-${MYSQL_VER}.${MYSQL_MINI_VER}-$BUILD_PROFILE.log"
BOOST_ROOT="${BOOST_ROOT:-}"
BOOST_DOWNLOAD_DIR="${BOOST_DOWNLOAD_DIR:-$WORK_ROOT/cache/boost}"
CCACHE_ROOT="${CCACHE_ROOT:-$WORK_ROOT/cache/ccache}"
MECAB_PREFIX="${MECAB_PREFIX:-}"
MECAB_LIBRARY_DIR=""
BUILD_JOBS="${BUILD_JOBS:-$(default_jobs)}"

ensure_dir "$WORK_ROOT"
ensure_dir "$LOG_ROOT"
rm -rf "$BUILD_ROOT" "$INSTALL_ROOT"
ensure_dir "$BUILD_ROOT"
ensure_dir "$INSTALL_ROOT"
ensure_dir "$BOOST_DOWNLOAD_DIR"
ensure_dir "$CCACHE_ROOT"

case "$PGO_MODE" in
  off)
    ;;
  generate|use)
    if [[ -z "$PGO_PROFILE_DIR" ]]; then
      PGO_PROFILE_DIR="$WORK_ROOT/pgo/ps-${MYSQL_VER}.${MYSQL_MINI_VER}/profile-data"
    fi
    ensure_dir "$PGO_PROFILE_DIR"
    ;;
  *)
    die "unsupported PGO_MODE: $PGO_MODE"
    ;;
esac

BOOST_TARBALL="$BOOST_DOWNLOAD_DIR/${BOOST_PACKAGE_NAME}.tar.bz2"
BOOST_EXTRACTED_DIR="$BOOST_DOWNLOAD_DIR/${BOOST_PACKAGE_NAME}"
if [[ -f "$BOOST_TARBALL" && ! -d "$BOOST_EXTRACTED_DIR" ]]; then
  if ! tar -tjf "$BOOST_TARBALL" >/dev/null 2>&1; then
    log_warn "removing corrupt boost tarball: $BOOST_TARBALL"
    rm -f "$BOOST_TARBALL"
  fi
fi

if [[ -z "$MECAB_PREFIX" ]]; then
  if MECAB_PREFIX="$(find_mecab_prefix || true)"; then
    log_info "using mecab from $MECAB_PREFIX"
  else
    if [[ "$SKIP_FULLTEXT_MECAB" == "ON" ]]; then
      log_warn "mecab not found; WITH_MECAB disabled because SKIP_FULLTEXT_MECAB=ON"
    else
      die "mecab headers not found; install fulltext mecab dependencies or pass --skip-fulltext-mecab"
    fi
  fi
fi

if [[ -n "$MECAB_PREFIX" ]]; then
  MECAB_LIBRARY_DIR="$(find_mecab_library_dir "$MECAB_PREFIX" || true)"
  [[ -n "$MECAB_LIBRARY_DIR" ]] || die "failed to locate libmecab under $MECAB_PREFIX"
fi

if [[ -z "$BOOST_ROOT" ]]; then
  BOOST_ROOT="$(find_boost_root \
    "$BOOST_PACKAGE_NAME" \
    "$SOURCE_DIR/extra/boost" \
    "$SOURCE_DIR/include" \
    "$SOURCE_DIR" \
    "$REPO_ROOT" \
    "$REPO_ROOT/deps" \
    "$WORK_ROOT/cache" || true)"
fi

if [[ -n "$BOOST_ROOT" ]]; then
  DOWNLOAD_BOOST_VALUE=0
elif [[ "$DOWNLOAD_BOOST" == "AUTO" || "$DOWNLOAD_BOOST" == "ON" ]]; then
  download_boost_tarball "$BOOST_DOWNLOAD_DIR" "$BOOST_PACKAGE_NAME" "$BOOST_DOWNLOAD_URL" >/dev/null
  BOOST_ROOT="$BOOST_DOWNLOAD_DIR"
  DOWNLOAD_BOOST_VALUE=0
else
  die "$BOOST_PACKAGE_NAME not found locally; set BOOST_ROOT or allow DOWNLOAD_BOOST=ON"
fi

if [[ "$ENABLE_LTO" == "ON" ]]; then
  WITH_LTO_VALUE="ON"
  LTO_C_FLAGS="-flto=${LTO_JOBS}"
  LTO_CXX_FLAGS="-flto=${LTO_JOBS}"
  LTO_LINK_FLAGS="-flto=${LTO_JOBS}"
else
  WITH_LTO_VALUE="OFF"
  LTO_C_FLAGS=""
  LTO_CXX_FLAGS=""
  LTO_LINK_FLAGS=""
fi

CCACHE_MODE="disabled"
if [[ "$ENABLE_CCACHE" == "ON" || "$ENABLE_CCACHE" == "AUTO" ]]; then
  if has_cmd ccache; then
    CCACHE_MODE="enabled"
  elif [[ "$ENABLE_CCACHE" == "ON" ]]; then
    die "ENABLE_CCACHE=ON but ccache is not installed"
  fi
fi

LINKER_MODE="default"
LINKER_FLAGS=""
case "$LINKER_FLAVOR" in
  AUTO)
    if has_cmd ld.gold; then
      LINKER_MODE="gold"
      LINKER_FLAGS="-fuse-ld=gold"
    fi
    ;;
  gold)
    has_cmd ld.gold || die "LINKER_FLAVOR=gold but ld.gold is not installed"
    LINKER_MODE="gold"
    LINKER_FLAGS="-fuse-ld=gold"
    ;;
  default|bfd|off|OFF)
    LINKER_MODE="default"
    ;;
  *)
    die "unsupported LINKER_FLAVOR: $LINKER_FLAVOR"
    ;;
esac

CMAKE_C_FLAGS_VALUE="$CPU_OPT_FLAGS"
CMAKE_CXX_FLAGS_VALUE="$CPU_OPT_FLAGS"
CMAKE_EXE_LINKER_FLAGS_VALUE=""
CMAKE_SHARED_LINKER_FLAGS_VALUE=""

if [[ -n "$LTO_C_FLAGS" ]]; then
  CMAKE_C_FLAGS_VALUE+=" $LTO_C_FLAGS"
  CMAKE_CXX_FLAGS_VALUE+=" $LTO_CXX_FLAGS"
  CMAKE_EXE_LINKER_FLAGS_VALUE+=" $LTO_LINK_FLAGS"
  CMAKE_SHARED_LINKER_FLAGS_VALUE+=" $LTO_LINK_FLAGS"
fi

if [[ -n "$LINKER_FLAGS" ]]; then
  CMAKE_C_FLAGS_VALUE+=" $LINKER_FLAGS"
  CMAKE_CXX_FLAGS_VALUE+=" $LINKER_FLAGS"
  CMAKE_EXE_LINKER_FLAGS_VALUE+=" $LINKER_FLAGS"
  CMAKE_SHARED_LINKER_FLAGS_VALUE+=" $LINKER_FLAGS"
fi

if [[ "$PGO_MODE" == "use" && "$PGO_USE_WARNING_POLICY" == "relaxed" ]]; then
  # GCC may report coverage-mismatch for valid-but-shifted inline/profile mappings in 8.0.
  # Keep the warning visible in logs, but do not fail the whole profile-use build on it.
  CMAKE_C_FLAGS_VALUE+=" -Wno-error=coverage-mismatch -Wno-error=missing-profile"
  CMAKE_CXX_FLAGS_VALUE+=" -Wno-error=coverage-mismatch -Wno-error=missing-profile"
fi

declare -a cmake_args
cmake_args=(
  "$SOURCE_DIR"
  -DBUILD_CONFIG=mysql_release
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
  -DCMAKE_INSTALL_PREFIX="$INSTALL_ROOT"
  -DFEATURE_SET=community
  -DMYSQL_MAINTAINER_MODE=OFF
  -DFORCE_INSOURCE_BUILD="$FORCE_INSOURCE_BUILD"
  -DWITH_SSL=system
  -DWITH_ZLIB=bundled
  -DWITH_ZSTD=bundled
  -DWITH_LZ4=bundled
  -DWITH_LIBEVENT=bundled
  -DWITH_PROTOBUF=bundled
  -DWITH_RAPIDJSON=bundled
  -DWITH_ICU=bundled
  -DWITH_EDITLINE=bundled
  -DWITH_SYSTEM_LIBS=ON
  -DWITH_PAM=ON
  -DWITH_NUMA=ON
  -DWITH_LDAP=system
  -DWITH_NDB=OFF
  -DWITH_GROUP_REPLICATION="$ENABLE_GROUP_REPLICATION"
  -DWITH_ROUTER=OFF
  -DWITH_UNIT_TESTS=OFF
  -DWITH_INNODB_MEMCACHED=ON
  -DWITH_ROCKSDB="$WITH_ROCKSDB"
  -DWITH_PACKAGE_FLAGS=OFF
  -DWITH_COREDUMPER=OFF
  -DWITH_COMPONENT_KEYRING_KMIP=OFF
  -DWITH_FIDO=bundled
  -DWITH_PERCONA_TELEMETRY=ON
  -DWITH_BOOST="$BOOST_ROOT"
  -DDOWNLOAD_BOOST="$DOWNLOAD_BOOST_VALUE"
  -DWITH_LTO="$WITH_LTO_VALUE"
  -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS_VALUE"
  -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS_VALUE"
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_EXE_LINKER_FLAGS_VALUE"
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_SHARED_LINKER_FLAGS_VALUE"
)

if [[ "$CCACHE_MODE" == "enabled" ]]; then
  export CCACHE_DIR="${CCACHE_DIR:-$CCACHE_ROOT/store}"
  export CCACHE_TEMPDIR="${CCACHE_TEMPDIR:-$CCACHE_ROOT/tmp}"
  export CCACHE_BASEDIR="${CCACHE_BASEDIR:-$REPO_ROOT}"
  ensure_dir "$CCACHE_DIR"
  ensure_dir "$CCACHE_TEMPDIR"
  cmake_args+=(
    -DCMAKE_C_COMPILER_LAUNCHER=ccache
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
  )
fi

if [[ -n "$MECAB_PREFIX" ]]; then
  cmake_args+=(
    -DWITH_MECAB="$MECAB_PREFIX"
    -DCMAKE_BUILD_RPATH="$MECAB_LIBRARY_DIR"
    -DCMAKE_INSTALL_RPATH="$MECAB_LIBRARY_DIR"
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
  )
fi

if [[ "$PGO_MODE" == "generate" ]]; then
  cmake_args+=(
    -DFPROFILE_GENERATE=ON
    -DFPROFILE_USE=OFF
    -DFPROFILE_DIR="$PGO_PROFILE_DIR"
  )
elif [[ "$PGO_MODE" == "use" ]]; then
  cmake_args+=(
    -DFPROFILE_GENERATE=OFF
    -DFPROFILE_USE=ON
    -DFPROFILE_DIR="$PGO_PROFILE_DIR"
  )
fi

if [[ "$ENABLE_LTO" == "ON" ]]; then
  log_warn "LTO is enabled; on 4C/16G hosts this may still be slow"
fi

log_info "source: $SOURCE_DIR"
log_info "build: $BUILD_ROOT"
log_info "install: $INSTALL_ROOT"
log_info "jobs: $BUILD_JOBS"
log_info "ccache: $CCACHE_MODE"
if [[ "$CCACHE_MODE" == "enabled" ]]; then
  log_info "ccache dir: $CCACHE_DIR"
  log_info "ccache tempdir: $CCACHE_TEMPDIR"
fi
log_info "linker: $LINKER_MODE"
log_info "lto: $ENABLE_LTO"
log_info "lto jobs: $LTO_JOBS"
log_info "pgo mode: $PGO_MODE"
log_info "rocksdb: $WITH_ROCKSDB"
if [[ "$PGO_MODE" != "off" ]]; then
  log_info "pgo profile dir: $PGO_PROFILE_DIR"
fi
if [[ "$PGO_MODE" == "use" ]]; then
  log_info "pgo use warning policy: $PGO_USE_WARNING_POLICY"
fi
log_info "force in-source build: $FORCE_INSOURCE_BUILD"
log_info "boost package: $BOOST_PACKAGE_NAME"
log_info "boost root: $BOOST_ROOT"
log_info "download boost: $DOWNLOAD_BOOST_VALUE"
log_info "log: $LOG_FILE"
if [[ -n "$MECAB_PREFIX" ]]; then
  log_info "mecab prefix: $MECAB_PREFIX"
  log_info "mecab library dir: $MECAB_LIBRARY_DIR"
fi

{
  printf 'timestamp=%s\n' "$(date -Iseconds)"
  printf 'source=%s\n' "$SOURCE_DIR"
  printf 'build=%s\n' "$BUILD_ROOT"
  printf 'install=%s\n' "$INSTALL_ROOT"
  printf 'jobs=%s\n' "$BUILD_JOBS"
  printf 'enable_ccache=%s\n' "$ENABLE_CCACHE"
  printf 'ccache_mode=%s\n' "$CCACHE_MODE"
  printf 'ccache_root=%s\n' "$CCACHE_ROOT"
  printf 'ccache_dir=%s\n' "${CCACHE_DIR:-}"
  printf 'ccache_tempdir=%s\n' "${CCACHE_TEMPDIR:-}"
  printf 'enable_lto=%s\n' "$ENABLE_LTO"
  printf 'lto_jobs=%s\n' "$LTO_JOBS"
  printf 'pgo_mode=%s\n' "$PGO_MODE"
  printf 'pgo_profile_dir=%s\n' "$PGO_PROFILE_DIR"
  printf 'pgo_use_warning_policy=%s\n' "$PGO_USE_WARNING_POLICY"
  printf 'with_rocksdb=%s\n' "$WITH_ROCKSDB"
  printf 'linker_flavor=%s\n' "$LINKER_FLAVOR"
  printf 'linker_mode=%s\n' "$LINKER_MODE"
  printf 'force_insource_build=%s\n' "$FORCE_INSOURCE_BUILD"
  printf 'boost_package=%s\n' "$BOOST_PACKAGE_NAME"
  printf 'boost_url=%s\n' "$BOOST_DOWNLOAD_URL"
  printf 'boost_root=%s\n' "$BOOST_ROOT"
  printf 'mecab_prefix=%s\n' "$MECAB_PREFIX"
  printf 'mecab_library_dir=%s\n' "$MECAB_LIBRARY_DIR"
  printf 'download_boost=%s\n' "$DOWNLOAD_BOOST_VALUE"
  printf 'cpu_opt_flags=%s\n' "$CPU_OPT_FLAGS"
  printf 'cmake_c_flags=%s\n' "$CMAKE_C_FLAGS_VALUE"
  printf 'cmake_cxx_flags=%s\n' "$CMAKE_CXX_FLAGS_VALUE"
  printf 'cmake_exe_linker_flags=%s\n' "$CMAKE_EXE_LINKER_FLAGS_VALUE"
  printf 'cmake_shared_linker_flags=%s\n' "$CMAKE_SHARED_LINKER_FLAGS_VALUE"
  printf 'hostname=%s\n' "$(hostname)"
} > "$LOG_FILE"

"$CMAKE_BIN" -S "$SOURCE_DIR" -B "$BUILD_ROOT" "${cmake_args[@]:1}" 2>&1 | tee -a "$LOG_FILE"
"$CMAKE_BIN" --build "$BUILD_ROOT" --parallel "$BUILD_JOBS" 2>&1 | tee -a "$LOG_FILE"
"$CMAKE_BIN" --install "$BUILD_ROOT" 2>&1 | tee -a "$LOG_FILE"

[[ -x "$INSTALL_ROOT/bin/mysqld" ]] || die "missing installed binary: $INSTALL_ROOT/bin/mysqld"
[[ -x "$INSTALL_ROOT/bin/mysql" ]] || die "missing installed client: $INSTALL_ROOT/bin/mysql"
[[ -d "$INSTALL_ROOT/lib/plugin" ]] || die "missing plugin directory: $INSTALL_ROOT/lib/plugin"

log_info "build completed successfully"
"$INSTALL_ROOT/bin/mysqld" --version | tee -a "$LOG_FILE"
"$INSTALL_ROOT/bin/mysql" --version | tee -a "$LOG_FILE"
