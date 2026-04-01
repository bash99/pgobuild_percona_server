# Release Upload Workflow

This repository now treats GitHub Releases as the primary binary download channel.

The intended public asset set for each version is:

- `Percona-Server-<version>-PGOed.Linux.x86_64.<distro>.mini.tar.zst`
- `SHA256SUMS.txt`
- a matching benchmark summary such as `pgo-readonly-<version>-<date>.md`

## One-Time Setup

1. Push the release-preparation commit to GitHub.
2. Install GitHub CLI (`gh`).
3. Authenticate:

```bash
gh auth login
```

Official references:

- GitHub Releases overview: <https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases>
- `gh release create`: <https://cli.github.com/manual/gh_release_create>
- `gh release upload`: <https://cli.github.com/manual/gh_release_upload>
- `gh release edit`: <https://cli.github.com/manual/gh_release_edit>

## Step 1: Stage Release Assets

The staging script normalizes naming, copies the public-safe result markdown, and generates `SHA256SUMS.txt`.

For the current three release candidates:

```bash
bash tools/prepare_release_assets.sh \
  artifacts/Percona-Server-8.4.8-8-rocksdb \
  artifacts/Percona-Server-8.0.45-36-rocksdb \
  artifacts/centos7-percona57-pgo-5.7.44-54
```

Staged output:

- `local/release-assets/8.4.8-8/`
- `local/release-assets/8.0.45-36/`
- `local/release-assets/5.7.44-54/`

Each stage directory contains:

- `upload/`
- `release-notes.md`
- `release.env`

Example uploaded filenames:

- `Percona-Server-8.4.8-8-PGOed.Linux.x86_64.almalinux9.mini.tar.zst`
- `Percona-Server-8.0.45-36-PGOed.Linux.x86_64.almalinux8.mini.tar.zst`
- `Percona-Server-5.7.44-54-PGOed.Linux.x86_64.centos7.mini.tar.zst`

That last one is produced automatically from the legacy local filename:

- `mini_percona-server-5.7.44-54-pgoed_centos7.tar.zst`

## Step 2: Push The Branch

Before creating release tags, push the branch that contains the public release documentation and workflow:

```bash
git push origin HEAD
```

## Step 3: Create Draft Releases And Upload Assets

The publish script expects a clean, pushed branch when `--create-tag` is used.

Create draft releases for all staged versions:

```bash
bash tools/publish_github_release.sh --all --create-tag
```

Or do them one by one:

```bash
bash tools/publish_github_release.sh --create-tag local/release-assets/8.4.8-8
bash tools/publish_github_release.sh --create-tag local/release-assets/8.0.45-36
bash tools/publish_github_release.sh --create-tag local/release-assets/5.7.44-54
```

By default the script creates or updates a draft release.

To publish immediately instead of keeping drafts:

```bash
bash tools/publish_github_release.sh --all --create-tag --publish
```

## Recommended Human Check Before Publishing

For each draft release, verify:

- title and tag are correct
- tarball filename follows the public naming convention
- `SHA256SUMS.txt` is present
- the benchmark summary markdown matches the tarball version
- release notes look sane

## Semi-Automated Future Flow

After a new build passes validation, the intended routine becomes:

```bash
git push origin HEAD
bash tools/prepare_release_assets.sh artifacts/<version-dir>
bash tools/publish_github_release.sh --create-tag local/release-assets/<version>
```

This is intentionally "semi-automated":

- the script handles naming, checksums, notes, tag creation, and upload
- you still review the draft release before publishing

That matches GitHub CLI's draft-friendly workflow well.
