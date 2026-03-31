#!/usr/bin/env bash

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MIRROR_BASE="${ALMALINUX_MIRROR_BASE:-https://repo.almalinux.org/almalinux}"

run_with_privilege() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "need root privileges or sudo to run: $*"
  fi
}

os_id="$(detect_os_id)"
if [[ "$os_id" != "almalinux" ]]; then
  log_info "configure_almalinux_mirror.sh: detected os_id=${os_id}; skipping"
  exit 0
fi

update_repo_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  # Switch from mirrorlist to a fixed baseurl (keeps $releasever/$basearch variables intact).
  run_with_privilege sed -i -E \
    -e 's/^mirrorlist=/#mirrorlist=/g' \
    -e 's|^# baseurl=https://repo\.almalinux\.org/almalinux/\$releasever/|baseurl='"$MIRROR_BASE"'/$releasever/|g' \
    "$file"
}

for repo in baseos appstream extras crb; do
  update_repo_file "/etc/yum.repos.d/almalinux-${repo}.repo"
done

run_with_privilege bash -lc 'if [[ -f /etc/dnf/dnf.conf ]]; then
  grep -q \"^max_parallel_downloads=\" /etc/dnf/dnf.conf || echo \"max_parallel_downloads=10\" >> /etc/dnf/dnf.conf
  grep -q \"^fastestmirror=\" /etc/dnf/dnf.conf || echo \"fastestmirror=True\" >> /etc/dnf/dnf.conf
  grep -q \"^deltarpm=\" /etc/dnf/dnf.conf || echo \"deltarpm=False\" >> /etc/dnf/dnf.conf
fi'

log_info "AlmaLinux mirror configured: baseurl=${MIRROR_BASE}"
