#!/usr/bin/env bash

set -euo pipefail

: "${1?Usage: $0 user@host [remote_work_root] [local_output_dir]}"
REMOTE_HOST="$1"
REMOTE_WORK_ROOT="${2:-/mnt/localssd/pgobuild_percona_server/work-remote-alma8}"
LOCAL_OUTPUT_DIR="${3:-$(pwd)/local/remote-results}"

mkdir -p "$LOCAL_OUTPUT_DIR/logs" "$LOCAL_OUTPUT_DIR/results" "$LOCAL_OUTPUT_DIR/packages" "$LOCAL_OUTPUT_DIR/build"

rsync -az \
  "$REMOTE_HOST:$REMOTE_WORK_ROOT/results/" "$LOCAL_OUTPUT_DIR/results/"

rsync -az \
  --include='*/' \
  --include='sysbench-*.log' \
  --include='build-normal-*.log' \
  --include='remote-run-*.log' \
  --include='pgoed-*.log' \
  --include='*quiesce*.log' \
  --include='*buffer-pool*.log' \
  --exclude='*' \
  "$REMOTE_HOST:$REMOTE_WORK_ROOT/logs/" "$LOCAL_OUTPUT_DIR/logs/"

rsync -az \
  --include='*/' \
  --include='CMakeCache.txt' \
  --exclude='*' \
  "$REMOTE_HOST:$REMOTE_WORK_ROOT/build/" "$LOCAL_OUTPUT_DIR/build/"

rsync -az \
  --include='Percona-Server-*.mini.tar.zst' \
  --include='mini_*.tar.xz' \
  --exclude='*' \
  "$REMOTE_HOST:/mnt/localssd/pgobuild_percona_server/" "$LOCAL_OUTPUT_DIR/packages/"

echo "collected results into $LOCAL_OUTPUT_DIR"
echo "included: benchmark/result logs and mini packages only"
