#!/usr/bin/env bash

set -euo pipefail

: "${1?Usage: $0 user@host [remote_repo_dir]}"
REMOTE_HOST="$1"
REMOTE_REPO_DIR="${2:-/mnt/localssd/pgobuild_percona_server}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"

cd "$REPO_ROOT"

command -v git >/dev/null 2>&1 || { echo 'git is required' >&2; exit 1; }
command -v rsync >/dev/null 2>&1 || { echo 'rsync is required' >&2; exit 1; }

SYNC_SOURCE_ARCHIVES="${SYNC_SOURCE_ARCHIVES:-matched}"
MYSQL_VER_FILTER="${MYSQL_VER:-}"
MYSQL_MINI_VER_FILTER="${MYSQL_MINI_VER:-}"

TRACKED_LIST="$(mktemp)"
trap 'rm -f "$TRACKED_LIST"' EXIT

git ls-files > "$TRACKED_LIST"

rsync -az --delete \
  --files-from="$TRACKED_LIST" \
  "$REPO_ROOT/" "$REMOTE_HOST:$REMOTE_REPO_DIR/"

copy_selected_source_archives() {
  local copied=0
  local tarball
  local -a patterns=()

  case "$SYNC_SOURCE_ARCHIVES" in
    off|OFF|false|FALSE|0)
      echo "skipped extra source archives (SYNC_SOURCE_ARCHIVES=$SYNC_SOURCE_ARCHIVES)"
      return 0
      ;;
    matched)
      if [[ -z "$MYSQL_VER_FILTER" || -z "$MYSQL_MINI_VER_FILTER" ]]; then
        echo "skipped extra source archives (MYSQL_VER / MYSQL_MINI_VER not set)"
        return 0
      fi

      patterns=(
        "$REPO_ROOT/percona-server-${MYSQL_VER_FILTER}.${MYSQL_MINI_VER_FILTER}.tar.gz"
        "$REPO_ROOT/percona-server-${MYSQL_VER_FILTER}.${MYSQL_MINI_VER_FILTER}.tar.xz"
        "$REPO_ROOT/percona-server-${MYSQL_VER_FILTER}.${MYSQL_MINI_VER_FILTER}.tar.bz2"
        "$REPO_ROOT/Percona-Server-${MYSQL_VER_FILTER}.${MYSQL_MINI_VER_FILTER}.tar.gz"
        "$REPO_ROOT/Percona-Server-${MYSQL_VER_FILTER}.${MYSQL_MINI_VER_FILTER}.tar.xz"
        "$REPO_ROOT/Percona-Server-${MYSQL_VER_FILTER}.${MYSQL_MINI_VER_FILTER}.tar.bz2"
      )
      ;;
    *)
      echo "unsupported SYNC_SOURCE_ARCHIVES=$SYNC_SOURCE_ARCHIVES" >&2
      exit 1
      ;;
  esac

  for tarball in "${patterns[@]}"; do
    [[ -e "$tarball" ]] || continue
    rsync -az "$tarball" "$REMOTE_HOST:$REMOTE_REPO_DIR/"
    copied=1
  done

  if [[ "$copied" -eq 1 ]]; then
    echo "synced selected source archive(s) for ${MYSQL_VER_FILTER}.${MYSQL_MINI_VER_FILTER}"
  else
    echo "no matching source archive found locally for ${MYSQL_VER_FILTER}.${MYSQL_MINI_VER_FILTER}; remote host should download sources itself"
  fi
}

copy_selected_source_archives

echo "synced tracked repository files to $REMOTE_HOST:$REMOTE_REPO_DIR"
echo "excluded unrelated tar.gz / tar.xz / tar.zst archives; only tracked files and optional matched source tarballs are synced"
echo "excluded ignored content such as workdirs, caches, local results and build artifacts"
