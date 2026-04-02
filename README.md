[中文 README](README.zh-CN.md)

# pgobuild_percona_server

PGO build, benchmark, packaging, and release tooling for Percona Server.

This project exists to build faster Percona Server binaries by training GCC Profile-Guided Optimization with a broadly useful, non-I/O-bound OLTP read workload. The default training path uses sysbench `point_select` and `read_only` style traffic, keeps the benchmark CPU-bound rather than storage-bound, and then rebuilds the server with `-fprofile-use`.

The goal is not to overfit to one narrow synthetic case. The goal is to produce a binary that shows clear gains on general OLTP read workloads and often still improves mixed `read_write` workloads as well.

This repository is community-maintained and is not an official Percona release channel.

## Why PGO Works Here

GCC PGO follows the classic three-stage loop:

1. instrumented build
2. training run on representative OLTP traffic
3. profile-use rebuild

For MySQL / Percona hot paths, that runtime profile can improve inlining, code layout, and branch behavior in the CPU-heavy parts of query execution. This repository automates the full cycle through `run.sh`: environment preparation, source download, normal build, profile-generate build, sysbench training, profile-use rebuild, validation, and mini tarball packaging.

Current default policy:

- `PGO_TRAIN_MODE=joint_read`
- `PGO_BENCHMARK_MODE=readonly`

## Performance Snapshot

Current public releases show repeatable read-heavy gains from about `+28%` to `+62%`, depending on version and engine.

| Version | Environment | Public result | Links |
| --- | --- | --- | --- |
| `8.4.8-8` | `AlmaLinux 9` | `read_only +49.61%`, `point_select +58.53%` | [release](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.4.8-8), [result](https://github.com/bash99/pgobuild_percona_server/releases/download/8.4.8-8/pgo-readonly-8.4.8-8-rdb-both-20260317.md) |
| `8.0.45-36` | `AlmaLinux 8`, `WITH_ROCKSDB=ON` | `InnoDB read_only +42.72%`, `RocksDB read_only +62.19%` | [release](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.0.45-36), [result](https://github.com/bash99/pgobuild_percona_server/releases/download/8.0.45-36/pgo-readonly-8.0.45-36-rdb-both-20260318.md) |
| `5.7.44-54` | `CentOS 7` | `read_only +28.29%`, `point_select +28.34%` | [release](https://github.com/bash99/pgobuild_percona_server/releases/tag/5.7.44-54), [result](https://github.com/bash99/pgobuild_percona_server/releases/download/5.7.44-54/pgo-readonly-5.7.44-54-20260309.md) |
| `5.6.51-93.0` | `CentOS 7` | `read_only +32.90%`, `point_select +45.34%` | [release](https://github.com/bash99/pgobuild_percona_server/releases/tag/5.6.51-93.0), [result](https://github.com/bash99/pgobuild_percona_server/releases/download/5.6.51-93.0/pgo-readonly-5.6.51-93.0-20260402.md) |

Mixed workload improvement also appears repeatedly:

- historical project results included about `+22.97%` on an `8.0` `read_write` validation
- current Docker head-to-head testing against the upstream image showed `read_write +6.56% ~ +18.58%`

## Quick Test By Yourself

If you only want to verify the result quickly, Docker is usually the fastest path.

Docker Hub:

- <https://hub.docker.com/r/bash99/percona-server-8.4-pgoed>

Current published image tags:

- `bash99/percona-server-8.4-pgoed:8.4.8-8`
- `bash99/percona-server-8.4-pgoed:8.4`

Matching GitHub release:

- [Percona Server 8.4.8-8 release](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.4.8-8)

Basic smoke test:

```bash
docker pull bash99/percona-server-8.4-pgoed:8.4.8-8

docker run --name ps8488 --rm \
  -e MYSQL_ROOT_PASSWORD=root \
  -p 13306:3306 -p 13360:33060 \
  -d bash99/percona-server-8.4-pgoed:8.4.8-8

docker exec -it ps8488 mysql -uroot -proot -e "SELECT VERSION();"
```

Expected version:

- `8.4.8-8`

Enable and verify MyRocks if needed:

```bash
docker exec -it ps8488 mysql -uroot -proot \
  -e "INSTALL PLUGIN ROCKSDB SONAME 'ha_rocksdb.so'; SHOW PLUGINS LIKE 'ROCKSDB';"
```

Detailed image verification:

- [docker/percona-server-8.4-pgoed/verification.md](docker/percona-server-8.4-pgoed/verification.md)

## Quick Docker Performance Check

To compare the published PGOed image with the upstream Percona image on the same host:

```bash
git clone https://github.com/bash99/pgobuild_percona_server.git
cd pgobuild_percona_server

PGOED_IMAGE=bash99/percona-server-8.4-pgoed:8.4.8-8 \
OFFICIAL_IMAGE=percona/percona-server:8.4.8-8.1 \
bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh
```

Current local same-version summary from the `2026-04-02` harness run:

- `point_select`: about `+34.56% ~ +43.98%`
- `read_only`: about `+31.08% ~ +37.50%`
- `read_write`: about `+6.56% ~ +18.58%`

Current published PGO binaries are produced by generating profiles and rebuilding on a NUMA-enabled `8-core` VM. Because of that, local Docker A/B checks on a `4-core` non-NUMA development machine may show gains slightly below the dedicated validation reports.

Related docs:

- [docker/percona-server-8.4-pgoed/bench/README.md](docker/percona-server-8.4-pgoed/bench/README.md)
- [current 8.4.8 same-version report](docker/percona-server-8.4-pgoed/bench/report-sysbench-vs-official-8.4.8-8.1.md)

## GitHub Releases

GitHub Releases is the primary public download channel for binary tarballs:

- releases page: <https://github.com/bash99/pgobuild_percona_server/releases>
- latest shortcut: <https://github.com/bash99/pgobuild_percona_server/releases/latest>

Release assets follow this naming convention:

- `Percona-Server-<version>[-pgo]-PGOed.Linux.x86_64.<distro>.mini.tar.zst`
- `SHA256SUMS.txt`
- a matching benchmark summary such as `pgo-readonly-<version>-<date>.md`

Current published binaries:

| Version | Platform | Tarball | Benchmark summary |
| --- | --- | --- | --- |
| [`8.4.8-8`](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.4.8-8) | `AlmaLinux 9` | [download](https://github.com/bash99/pgobuild_percona_server/releases/download/8.4.8-8/Percona-Server-8.4.8-8-PGOed.Linux.x86_64.almalinux9.mini.tar.zst) | [summary](https://github.com/bash99/pgobuild_percona_server/releases/download/8.4.8-8/pgo-readonly-8.4.8-8-rdb-both-20260317.md) |
| [`8.0.45-36`](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.0.45-36) | `AlmaLinux 8` | [download](https://github.com/bash99/pgobuild_percona_server/releases/download/8.0.45-36/Percona-Server-8.0.45-36-PGOed.Linux.x86_64.almalinux8.mini.tar.zst) | [summary](https://github.com/bash99/pgobuild_percona_server/releases/download/8.0.45-36/pgo-readonly-8.0.45-36-rdb-both-20260318.md) |
| [`5.7.44-54`](https://github.com/bash99/pgobuild_percona_server/releases/tag/5.7.44-54) | `CentOS 7` | [download](https://github.com/bash99/pgobuild_percona_server/releases/download/5.7.44-54/Percona-Server-5.7.44-54-PGOed.Linux.x86_64.centos7.mini.tar.zst) | [summary](https://github.com/bash99/pgobuild_percona_server/releases/download/5.7.44-54/pgo-readonly-5.7.44-54-20260309.md) |
| [`5.6.51-93.0`](https://github.com/bash99/pgobuild_percona_server/releases/tag/5.6.51-93.0) | `CentOS 7` | [download](https://github.com/bash99/pgobuild_percona_server/releases/download/5.6.51-93.0/Percona-Server-5.6.51-93.0-pgo-PGOed.Linux.x86_64.centos7.mini.tar.zst) | [summary](https://github.com/bash99/pgobuild_percona_server/releases/download/5.6.51-93.0/pgo-readonly-5.6.51-93.0-20260402.md) |

## Stability

The stability story is straightforward:

- historical signal: an earlier `5.7.19` PGO binary from this project lineage reportedly ran on about `100+` production servers for roughly `1.5 years` without crash reports
- current release discipline: a build is only considered publishable after smoke testing, runtime identity checks, profile generation checks, profile-use checks, and benchmark consistency checks all pass
- operational expectation: these are community builds, so they should still be benchmarked and staged in your own environment before production rollout

Useful references:

- [docs/pgo_validation_checklist.md](docs/pgo_validation_checklist.md)
- [docs/pgo_train_modes.md](docs/pgo_train_modes.md)

## Build From Source

Clone the repository:

```bash
git clone https://github.com/bash99/pgobuild_percona_server.git
cd pgobuild_percona_server
```

Set the target version:

```bash
export MYSQL_VER=8.4
export MYSQL_MINI_VER=8-8
export WORK_ROOT="$PWD/work"
```

Run the full flow:

```bash
bash run.sh -i -d -n -p
```

Notes:

- pass flags separately
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

## Support Matrix

| Percona Server | Status | Notes |
| --- | --- | --- |
| `8.4` | active | current primary release target and Docker target |
| `8.0` | active | current primary release target |
| `5.7` | maintained legacy target | still validated for `CentOS 7` style workflows |
| `5.6` | historical / closed | final `CentOS 7` compatible public build published as `5.6.51-93.0` |

## AI-Assisted Maintenance

This refactor was executed with `Codex` against the repository workspace.

For future changes, validation, and deployment work, start with [AGENTS.md](AGENTS.md) and use suitable AI agent tools that can operate directly on the repository. `AGENTS.md` captures the project purpose, execution graph, and public/private content boundaries that future agent-driven work should follow.

## Docs

- [AGENTS.md](AGENTS.md)
- [ROADMAP.md](ROADMAP.md)
- [docs/pgo_validation_checklist.md](docs/pgo_validation_checklist.md)
- [docs/pgo_train_modes.md](docs/pgo_train_modes.md)
- [docs/pgo_crossdb_non_io_bound_oltp_design.md](docs/pgo_crossdb_non_io_bound_oltp_design.md)
- [docker/percona-server-8.4-pgoed/README.md](docker/percona-server-8.4-pgoed/README.md)
- [docs/release_upload_workflow.md](docs/release_upload_workflow.md)

## License

The scripts and documentation in this repository are licensed under [MIT](LICENSE).

Percona Server, MySQL, and bundled third-party components remain subject to their own upstream licenses and copyright notices.

MySQL copyright belongs to Oracle and/or its affiliates. Percona Server carries separate upstream copyright and license notices from Percona and other contributors.

## Legacy

The historical project README is preserved as [README_old.md](README_old.md).
