[中文说明 / Chinese README](README.zh-CN.md)

# pgobuild_percona_server

Community-maintained tooling for building, benchmarking, packaging, and validating PGOed Percona Server binaries.

This repository is not an official Percona release channel.

## What It Covers

- prepare build hosts for supported Linux distributions
- download Percona Server source tarballs
- build normal and PGOed binaries
- benchmark with `sysbench`
- package minimized binary tarballs for release use
- keep reproducible evidence for benchmark and packaging results

The main entrypoint is `run.sh`.

## Verified Matrix

| Percona Server | Status | Public references |
| --- | --- | --- |
| `8.4` | active | [8.4.8-8 PGO + Docker](task_archives/8.4.8-8-alma9-pgo-docker-completed.md), [8.4.8-8 RocksDB validation](artifacts/Percona-Server-8.4.8-8-rocksdb/pgo-readonly-8.4.8-8-rdb-both-20260317.md) |
| `8.0` | active | [8.0.45-36 RocksDB validation](artifacts/Percona-Server-8.0.45-36-rocksdb/pgo-readonly-8.0.45-36-rdb-both-20260318.md) |
| `5.7` | maintained legacy target | [5.7.44-54 readonly PGO recovery](task_archives/5.7.44-54-centos7-readonly-pgo-fixed.md) |
| `5.6` | historical / final-note target | kept as a future closing release note for a final `CentOS 7` style build |

More public milestones are listed in [ROADMAP.md](ROADMAP.md).

## Benchmark Highlights

| Target | Scope | Result |
| --- | --- | --- |
| `8.4.8-8` | readonly PGO on `AlmaLinux 9` | `read_only +49.61%`, `point_select +58.53%` |
| `8.0.45-36` | `WITH_ROCKSDB=ON`, dual-engine training | `InnoDB read_only +42.72%`, `RocksDB read_only +62.19%` |
| `5.7.44-54` | readonly PGO recovery on `CentOS 7` compatible host | `read_only +28.29%`, `point_select +28.34%` |

The repository keeps sanitized public evidence only. Full maintainer run logs stay outside the public tree.

## Releases

Prebuilt binaries are intended to be distributed through GitHub Releases:

- releases page: <https://github.com/bash99/pgobuild_percona_server/releases>
- latest release shortcut: <https://github.com/bash99/pgobuild_percona_server/releases/latest>

Release assets are expected to follow this naming convention:

- `Percona-Server-<version>-PGOed.Linux.x86_64.<distro>.mini.tar.zst`
- `SHA256SUMS.txt`
- a matching benchmark summary such as `pgo-readonly-<version>-<date>.md`

This repository no longer documents private download mirrors.

Release upload workflow:

- staging and checksum generation: `bash tools/prepare_release_assets.sh`
- draft release creation and asset upload: `bash tools/publish_github_release.sh`
- detailed procedure: [docs/release_upload_workflow.md](docs/release_upload_workflow.md)

## Quick Start

Clone the repository:

```bash
git clone https://github.com/bash99/pgobuild_percona_server.git
cd pgobuild_percona_server
```

Set the version you want to build:

```bash
export MYSQL_VER=8.4
export MYSQL_MINI_VER=8-8
export WORK_ROOT="$PWD/work"
```

Run the full flow with separate flags:

```bash
bash run.sh -i -d -n -p
```

Notes:

- pass flags separately; the historical combined form like `-idnp` is obsolete
- `-i` installs build dependencies and usually requires `sudo`
- `-d` downloads source tarballs if they are not already present
- `-n` runs normal build, smoke, benchmark, and package steps
- `-p` runs the PGO build, benchmark, and package steps

## Common Environment Variables

| Variable | Meaning |
| --- | --- |
| `MYSQL_VER` | major branch, for example `5.7`, `8.0`, `8.4` |
| `MYSQL_MINI_VER` | upstream Percona release suffix, for example `45-36` or `8-8` |
| `WORK_ROOT` | build, runtime, and benchmark workspace |
| `CPU_OPT_FLAGS` | extra CPU tuning flags passed into the build |
| `WITH_ROCKSDB` | set to `ON` for RocksDB-enabled builds |
| `ENABLE_LTO` | set to `ON` for LTO-enabled builds where supported |
| `SKIP_FULLTEXT_MECAB` | set to `ON` to disable MeCab-dependent fulltext build paths |
| `PGO_TRAIN_MODE` | overrides the training workload mode |
| `PGO_BENCHMARK_MODE` | overrides the validation workload mode |

Default PGO policy:

- `PGO_TRAIN_MODE=joint_read`
- `PGO_BENCHMARK_MODE=readonly`

See [docs/pgo_train_modes.md](docs/pgo_train_modes.md) for why `joint_read` is the default.

## Docker

Release builds are intended to be published on Docker Hub, but the repository keeps a local Docker recipe so the image can always be rebuilt from a release asset.

- image recipe: [docker/percona-server-8.4-pgoed](docker/percona-server-8.4-pgoed/README.md)
- verification log: [docker/percona-server-8.4-pgoed/verification.md](docker/percona-server-8.4-pgoed/verification.md)
- sysbench image-vs-image benchmark harness: [docker/percona-server-8.4-pgoed/bench/README.md](docker/percona-server-8.4-pgoed/bench/README.md)

The current Docker recipe targets `8.4.8-8` and expects a matching PGOed `mini.tar.zst` release asset.

## Docs

- [ROADMAP.md](ROADMAP.md)
- [docs/pgo_validation_checklist.md](docs/pgo_validation_checklist.md)
- [docs/pgo_train_modes.md](docs/pgo_train_modes.md)
- [docs/remote_pgo_workflow.md](docs/remote_pgo_workflow.md)
- [docs/release_upload_workflow.md](docs/release_upload_workflow.md)
- [docs/how_to_refresh_latest_8_0.md](docs/how_to_refresh_latest_8_0.md)
- [task_archives/README.md](task_archives/README.md)

## License

The scripts and documentation in this repository are licensed under [MIT](LICENSE).

Percona Server itself and bundled third-party components remain subject to their own upstream licenses.

## Legacy

The historical project README is preserved as [README_old.md](README_old.md).
