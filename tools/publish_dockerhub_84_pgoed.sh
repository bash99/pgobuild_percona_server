#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/lib/common.sh"

: "${DOCKER_REPO:=bash99/percona-server-8.4-pgoed}"
: "${DOCKERFILE_PATH:=docker/percona-server-8.4-pgoed/Dockerfile}"
: "${PS_TARBALL:=artifacts/Percona-Server-8.4.8-8-rocksdb/Percona-Server-8.4.8-8-PGOed.Linux.x86_64.almalinux9.mini.tar.zst}"
: "${PUSH_LATEST:=OFF}"
: "${PUSH_MAJOR:=ON}"
: "${DOCKER_BUILD_CONTEXT:=.}"

usage() {
  cat <<'EOF'
Usage:
  bash tools/publish_dockerhub_84_pgoed.sh [options]

Options:
  --tarball <path>      Relative tarball path passed to Dockerfile via PS_TARBALL
  --repo <name>         Docker Hub repo, default: bash99/percona-server-8.4-pgoed
  --version <x.y.z-n>   Override inferred Percona Server version
  --push-latest         Also push :latest
  --no-push-major       Skip the major tag (default pushes :8.4)
  --build-only          Build and tag locally, but do not push
  -h, --help            Show help

Examples:
  bash tools/publish_dockerhub_84_pgoed.sh

  bash tools/publish_dockerhub_84_pgoed.sh \
    --tarball artifacts/Percona-Server-8.4.9-9-rocksdb/Percona-Server-8.4.9-9-PGOed.Linux.x86_64.almalinux9.mini.tar.zst \
    --push-latest
EOF
}

infer_version_from_tarball() {
  local tarball="$1"
  local base
  base="$(basename "$tarball")"

  if [[ "$base" =~ ^Percona-Server-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)-PGOed\.Linux\. ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  die "failed to infer version from tarball name: $base"
}

infer_major_tag() {
  local version="$1"

  if [[ "$version" =~ ^([0-9]+\.[0-9]+)\.[0-9]+-[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  die "failed to infer major tag from version: $version"
}

ensure_tarball_in_context() {
  local tarball="$1"
  [[ -f "$REPO_ROOT/$tarball" ]] || die "tarball not found in repo context: $tarball"
}

main() {
  local version=""
  local build_only="false"
  local major_tag=""
  local version_image=""
  local major_image=""
  local latest_image=""
  local -a tags=()

  while (( $# > 0 )); do
    case "$1" in
      --tarball)
        shift
        [[ $# -gt 0 ]] || die "--tarball requires a value"
        PS_TARBALL="$1"
        ;;
      --repo)
        shift
        [[ $# -gt 0 ]] || die "--repo requires a value"
        DOCKER_REPO="$1"
        ;;
      --version)
        shift
        [[ $# -gt 0 ]] || die "--version requires a value"
        version="$1"
        ;;
      --push-latest)
        PUSH_LATEST="ON"
        ;;
      --no-push-major)
        PUSH_MAJOR="OFF"
        ;;
      --build-only)
        build_only="true"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  require_cmd docker
  ensure_tarball_in_context "$PS_TARBALL"

  if [[ -z "$version" ]]; then
    version="$(infer_version_from_tarball "$PS_TARBALL")"
  fi

  major_tag="$(infer_major_tag "$version")"
  version_image="$DOCKER_REPO:$version"
  major_image="$DOCKER_REPO:$major_tag"
  latest_image="$DOCKER_REPO:latest"

  tags=("$version_image")
  if [[ "$PUSH_MAJOR" == "ON" ]]; then
    tags+=("$major_image")
  fi
  if [[ "$PUSH_LATEST" == "ON" ]]; then
    tags+=("$latest_image")
  fi

  log_info "building Docker image from tarball: $PS_TARBALL"
  log_info "target repo: $DOCKER_REPO"
  log_info "tags: ${tags[*]}"

  docker build \
    -f "$REPO_ROOT/$DOCKERFILE_PATH" \
    --build-arg "PS_TARBALL=$PS_TARBALL" \
    -t "$version_image" \
    "$REPO_ROOT/$DOCKER_BUILD_CONTEXT"

  if [[ "$PUSH_MAJOR" == "ON" ]]; then
    docker tag "$version_image" "$major_image"
  fi

  if [[ "$PUSH_LATEST" == "ON" ]]; then
    docker tag "$version_image" "$latest_image"
  fi

  if [[ "$build_only" == "true" ]]; then
    log_info "build-only mode; skipping docker push"
    exit 0
  fi

  for image in "${tags[@]}"; do
    log_info "pushing $image"
    docker push "$image"
  done
}

main "$@"
