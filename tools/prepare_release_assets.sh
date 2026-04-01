#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

: "${RELEASE_STAGE_ROOT:=$REPO_ROOT/local/release-assets}"

usage() {
  cat <<'EOF'
Usage:
  bash tools/prepare_release_assets.sh [artifact_dir_or_tarball ...]

Behavior:
  - finds one PGO tarball per input directory
  - converts legacy tarball names to the public README naming convention
  - copies assets into local/release-assets/<version>/upload/
  - generates SHA256SUMS.txt
  - generates release-notes.md and release.env metadata

Examples:
  bash tools/prepare_release_assets.sh \
    artifacts/Percona-Server-8.4.8-8-rocksdb \
    artifacts/Percona-Server-8.0.45-36-rocksdb \
    artifacts/centos7-percona57-pgo-5.7.44-54

  bash tools/prepare_release_assets.sh
EOF
}

select_pgo_tarball() {
  local dir="$1"

  find "$dir" -maxdepth 1 -type f \
    \( -name 'Percona-Server-*-PGOed.Linux.*.mini.tar.zst' -o -name 'mini_percona-server-*-pgoed*.tar.zst' \) \
    | sort | head -n 1
}

select_result_md() {
  local dir="$1"

  find "$dir" -maxdepth 1 -type f -name 'pgo-readonly-*.md' | sort | tail -n 1
}

canonical_tarball_name() {
  local base="$1"

  if [[ "$base" =~ ^Percona-Server-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)-PGOed\.Linux\.([^.]+)\.([^.]+)\.mini\.tar\.zst$ ]]; then
    printf '%s\n' "$base"
    return 0
  fi

  if [[ "$base" =~ ^mini_percona-server-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)-pgoed_([^.]+)\.tar\.zst$ ]]; then
    printf 'Percona-Server-%s-PGOed.Linux.x86_64.%s.mini.tar.zst\n' \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  die "unsupported PGO tarball naming: $base"
}

release_tag_from_tarball() {
  local base="$1"

  if [[ "$base" =~ ^Percona-Server-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)-PGOed\.Linux\. ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$base" =~ ^mini_percona-server-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)-pgoed_ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  die "failed to derive release tag from tarball: $base"
}

extract_metric_from_result() {
  local result_md="$1"
  local case_name="$2"

  awk -F'|' -v case_name="$case_name" '
    $0 ~ ("\\| " case_name " \\|") {
      value=$5
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$result_md"
}

extract_readonly_delta() {
  local result_md="$1"
  local value=""

  value="$(sed -n 's/^- readonly improvement vs normal: //p' "$result_md" | head -n 1)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  extract_metric_from_result "$result_md" "read_only"
}

generate_release_notes() {
  local tag="$1"
  local canonical_tarball="$2"
  local result_md="$3"
  local readonly_delta=""
  local point_select_delta=""
  local result_base=""

  if [[ -n "$result_md" && -f "$result_md" ]]; then
    readonly_delta="$(extract_readonly_delta "$result_md" || true)"
    point_select_delta="$(extract_metric_from_result "$result_md" "point_select" || true)"
    result_base="$(basename "$result_md")"
  fi

  cat <<EOF
# Percona Server ${tag} PGOed Community Build

This release contains a validated PGOed binary tarball produced by this repository.

Assets:

- \`${canonical_tarball}\`
- \`SHA256SUMS.txt\`
EOF

  if [[ -n "$result_base" ]]; then
    cat <<EOF
- \`${result_base}\`
EOF
  fi

  cat <<EOF

Validation snapshot:

EOF

  if [[ -n "$readonly_delta" ]]; then
    printf -- '- `read_only` improvement: `%s`\n' "$readonly_delta"
  fi

  if [[ -n "$point_select_delta" ]]; then
    printf -- '- `point_select` improvement: `%s`\n' "$point_select_delta"
  fi

  cat <<EOF

Notes:

- This is a community-maintained build, not an official Percona release channel.
- See the bundled benchmark summary for workload details and validation context.
EOF
}

stage_one() {
  local input="$1"
  local source_dir=""
  local tarball=""
  local canonical_name=""
  local tag=""
  local stage_dir=""
  local upload_dir=""
  local result_md=""

  if [[ -d "$input" ]]; then
    source_dir="$input"
    tarball="$(select_pgo_tarball "$source_dir")"
  elif [[ -f "$input" ]]; then
    tarball="$input"
    source_dir="$(cd "$(dirname "$tarball")" && pwd)"
  else
    die "input does not exist: $input"
  fi

  [[ -n "$tarball" ]] || die "no PGO tarball found for input: $input"

  canonical_name="$(canonical_tarball_name "$(basename "$tarball")")"
  tag="$(release_tag_from_tarball "$(basename "$tarball")")"
  result_md="$(select_result_md "$source_dir")"

  stage_dir="$RELEASE_STAGE_ROOT/$tag"
  upload_dir="$stage_dir/upload"

  rm -rf "$stage_dir"
  ensure_dir "$upload_dir"

  cp -f "$tarball" "$upload_dir/$canonical_name"

  if [[ -n "$result_md" ]]; then
    cp -f "$result_md" "$upload_dir/$(basename "$result_md")"
  fi

  (
    cd "$upload_dir"
    sha256sum ./* > SHA256SUMS.txt
  )

  generate_release_notes "$tag" "$canonical_name" "$result_md" > "$stage_dir/release-notes.md"

  cat > "$stage_dir/release.env" <<EOF
RELEASE_TAG=$tag
RELEASE_TITLE=Percona Server $tag PGOed community build
UPLOAD_DIR=$upload_dir
CANONICAL_TARBALL=$canonical_name
RESULT_MD=$(basename "${result_md:-}")
SOURCE_DIR=$source_dir
EOF

  log_info "staged release assets for $tag at $stage_dir"
  log_info "upload assets:"
  find "$upload_dir" -maxdepth 1 -type f | sort
}

main() {
  local -a inputs=()
  local dir

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  ensure_dir "$RELEASE_STAGE_ROOT"
  require_cmd awk find sha256sum sort

  if (( $# > 0 )); then
    inputs=("$@")
  else
    while IFS= read -r dir; do
      [[ -n "$(select_pgo_tarball "$dir")" ]] || continue
      inputs+=("$dir")
    done < <(find "$REPO_ROOT/artifacts" -mindepth 1 -maxdepth 1 -type d | sort)
  fi

  (( ${#inputs[@]} > 0 )) || die "no artifact directories or tarballs provided"

  for dir in "${inputs[@]}"; do
    stage_one "$dir"
  done
}

main "$@"
