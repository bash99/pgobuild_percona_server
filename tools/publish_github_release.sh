#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

: "${RELEASE_STAGE_ROOT:=$REPO_ROOT/local/release-assets}"

usage() {
  cat <<'EOF'
Usage:
  bash tools/publish_github_release.sh [options] <stage_dir ...>

Options:
  --repo <owner/repo>   Override repository slug
  --create-tag          Create and push the release tag if it does not exist remotely
  --publish             Publish immediately instead of keeping the release as draft
  --all                 Publish every staged release under local/release-assets/
  -h, --help            Show help

Examples:
  bash tools/publish_github_release.sh --create-tag local/release-assets/8.4.8-8
  bash tools/publish_github_release.sh --all
EOF
}

infer_repo_slug() {
  local remote_url slug

  remote_url="$(git config --get remote.origin.url)"
  [[ -n "$remote_url" ]] || die "failed to read remote.origin.url"

  case "$remote_url" in
    git@github.com:*)
      slug="${remote_url#git@github.com:}"
      ;;
    https://github.com/*)
      slug="${remote_url#https://github.com/}"
      ;;
    http://github.com/*)
      slug="${remote_url#http://github.com/}"
      ;;
    *)
      die "unsupported GitHub remote URL: $remote_url"
      ;;
  esac

  printf '%s\n' "${slug%.git}"
}

ensure_branch_pushed() {
  local ahead
  ahead="$(git rev-list --left-right --count origin/HEAD...HEAD | awk '{print $2}')"
  if (( ahead > 0 )); then
    die "HEAD is ahead of origin by $ahead commit(s); push the branch first with: git push origin HEAD"
  fi
}

ensure_clean_worktree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    die "working tree is not clean; commit or stash changes before creating release tags"
  fi
}

remote_tag_exists() {
  local tag="$1"
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1
}

create_and_push_tag() {
  local tag="$1"

  ensure_clean_worktree
  ensure_branch_pushed

  if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    git tag -a "$tag" -m "Release $tag"
  fi

  git push origin "refs/tags/$tag"
}

upload_or_create_release() {
  local stage_dir="$1"
  local repo_slug="$2"
  local create_tag="$3"
  local publish_now="$4"
  local tag=""
  local title=""
  local upload_dir=""
  local notes_file=""
  local -a assets=()

  [[ -f "$stage_dir/release.env" ]] || die "missing release.env in $stage_dir"
  # shellcheck disable=SC1090
  . "$stage_dir/release.env"

  tag="${RELEASE_TAG:-$(basename "$stage_dir")}"
  title="${RELEASE_TITLE:-Percona Server $tag PGOed community build}"
  upload_dir="${UPLOAD_DIR:-$stage_dir/upload}"
  notes_file="$stage_dir/release-notes.md"

  [[ -d "$upload_dir" ]] || die "missing upload directory: $upload_dir"
  [[ -f "$notes_file" ]] || die "missing release notes: $notes_file"

  mapfile -t assets < <(find "$upload_dir" -maxdepth 1 -type f | sort)
  (( ${#assets[@]} > 0 )) || die "no assets found in $upload_dir"

  if ! remote_tag_exists "$tag"; then
    if [[ "$create_tag" == "true" ]]; then
      create_and_push_tag "$tag"
    else
      die "remote tag $tag does not exist; rerun with --create-tag after pushing the branch"
    fi
  fi

  if gh release view "$tag" --repo "$repo_slug" >/dev/null 2>&1; then
    log_info "release $tag already exists; updating assets and notes"
    gh release upload "$tag" "${assets[@]}" --clobber --repo "$repo_slug"
    if [[ "$publish_now" == "true" ]]; then
      gh release edit "$tag" --repo "$repo_slug" --title "$title" --notes-file "$notes_file" --draft=false
    else
      gh release edit "$tag" --repo "$repo_slug" --title "$title" --notes-file "$notes_file" --draft
    fi
  else
    log_info "creating new release $tag for $repo_slug"
    if [[ "$publish_now" == "true" ]]; then
      gh release create "$tag" "${assets[@]}" \
        --repo "$repo_slug" \
        --title "$title" \
        --notes-file "$notes_file" \
        --verify-tag
    else
      gh release create "$tag" "${assets[@]}" \
        --repo "$repo_slug" \
        --title "$title" \
        --notes-file "$notes_file" \
        --verify-tag \
        --draft
    fi
  fi
}

main() {
  local repo_slug=""
  local create_tag="false"
  local publish_now="false"
  local use_all="false"
  local -a stage_dirs=()

  while (( $# > 0 )); do
    case "$1" in
      --repo)
        shift
        [[ $# -gt 0 ]] || die "--repo requires a value"
        repo_slug="$1"
        ;;
      --create-tag)
        create_tag="true"
        ;;
      --publish)
        publish_now="true"
        ;;
      --all)
        use_all="true"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        stage_dirs+=("$1")
        ;;
    esac
    shift
  done

  require_cmd gh git find sort
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

  if [[ -z "$repo_slug" ]]; then
    repo_slug="$(infer_repo_slug)"
  fi

  if [[ "$use_all" == "true" ]]; then
    while IFS= read -r stage_dir; do
      stage_dirs+=("$stage_dir")
    done < <(find "$RELEASE_STAGE_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
  fi

  (( ${#stage_dirs[@]} > 0 )) || die "no stage directories provided"

  for stage_dir in "${stage_dirs[@]}"; do
    upload_or_create_release "$stage_dir" "$repo_slug" "$create_tag" "$publish_now"
  done
}

main "$@"
