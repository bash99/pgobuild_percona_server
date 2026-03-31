#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

if is_container_env; then
  log_warn "container environment detected; skipping limits.conf and sysctl tuning"
  exit 0
fi

if [[ -f /etc/security/limits.conf ]] && ! grep -q 'mysql[[:space:]]\+soft[[:space:]]\+memlock[[:space:]]\+unlimited' /etc/security/limits.conf; then
  perl -0pi -e 's/# End of file\n?//g' /etc/security/limits.conf
  cat >>/etc/security/limits.conf <<'LIMITS_EOF'
*               hard    nofile  102400
*               soft    nofile  102400
mysql           soft    memlock unlimited
mysql           hard    memlock unlimited
root            soft    memlock unlimited
root            hard    memlock unlimited
# End of file
LIMITS_EOF
  log_info "updated /etc/security/limits.conf"
else
  log_info "limits.conf already contains mysql memlock settings or file missing"
fi

sysctl -w fs.file-max=100000
sysctl -w vm.swappiness=10
