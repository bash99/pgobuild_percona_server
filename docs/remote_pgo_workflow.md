# Remote PGO Workflow

## Goal

Make it safe and repeatable to:

- clone this repo onto a fresh remote build host such as `AlmaLinux 8` or `AlmaLinux 9`
- run the full normal + PGO flow under `/mnt/localssd`
- bring back only the useful outputs

## What to sync to remote

Sync only two categories:

1. tracked repository files
2. source tarballs required for build bootstrap

Do **not** sync these large or host-specific paths:

- `work/`, `work-*/`
- `local/`
- unpacked source trees such as `percona-server-Percona-Server-*`
- generated packages such as `Percona-Server-*.mini.tar.zst`
- temporary benchmark/runtime artifacts

Recommended helper:

- push code + source archives: `tools/remote_sync_to_host.sh`

This helper uses `git ls-files`, which naturally follows the repository's ignore strategy by syncing only tracked project files, then separately sends Percona/Boost source tarballs if present in repo root.

## What to run on remote

Typical remote sequence:

1. `run.sh -i`
2. `run.sh -d` if source tarballs are not already present
3. `run.sh -n`
4. `run.sh -p`

Current default PGO policy:

- `profile-generate`: `joint_read`
- `profile-use` validation: `readonly`

If you need to compare all four training modes again, use `tools/run_pgo_train_matrix.sh`.

Recommended environment:

- `WORK_ROOT=/mnt/localssd/pgobuild_percona_server/work-remote-alma8`
- use `/mnt/localssd` for build tree, runtime, sysbench dataset and result logs

## Pre-benchmark config guard (non I/O bound OLTP)

本项目的 PGO 验证目标是 **非 I/O bound 的 OLTP 负载**（尤其 `point_select`/`read_only`）。

因此在开始跑 sysbench 之前，必须先确认 runtime 配置已经处于“benchmark 调优形态”，否则 baseline/PGO 结论会被 I/O 等待主导而失真。

最低要求（MySQL/Percona 8.x）：

- 记录并核对关键变量：
  - `SHOW VARIABLES LIKE 'innodb_buffer_pool_size'`（绝不能意外回落到上游默认 `128MB`）
  - `SHOW VARIABLES LIKE 'performance_schema'`
  - `SHOW VARIABLES LIKE 'innodb_flush_method'`
- 对 `point_select`/`read_only` 启用 `mpstat/iostat/pidstat` 采样，确认 `iowait` 不会长期偏高（经验阈值：`> 10%` 基本可判 I/O bound）

历史踩坑提示（已在 `8.4.7-7` / `AlmaLinux 9.7` 复现并修复）：

- 重构后 `8.x` runtime 配置漏了旧 benchmark 调优，导致 `innodb_buffer_pool_size` 退回 `128MB`，把 `point_select` 跑成 I/O bound；
- 这种情况下先不要讨论 PGO，先修配置再重跑 baseline。

配置依据说明：

- 8.x 的 benchmark runtime `my.cnf` 由 `lib/mysql.sh:mysql_emit_config()` 生成；
- 历史上同类调优来自旧模板 `build-normal/init_conf.sh`；
- refactor/migration 时必须显式迁移这些“影响负载形态”的参数。

详细检查项见：

- `docs/pgo_validation_checklist.md`

## Startup quiesce rule

Before sysbench benchmark starts, the runtime should satisfy:

1. InnoDB buffer pool load completed
2. InnoDB pending writes reached zero
3. zero pending writes observed in 2 consecutive polls

This is now implemented in `lib/mysql.sh` via `mysql_wait_for_startup_quiesce()` and used by both normal and PGO benchmark flows.

Why it matters:

- waiting only for `mysqld ready for connections` is insufficient
- waiting only for `buffer pool load completed` is insufficient
- startup flush/transient can still distort `point_select`

## Standard train mode

`joint_read` is now the standard `profile-generate` mode because it covers both `point_select` and `read_only`, avoids `read_write` noise, and produced the best overall balance in the `8.4.7-7` AlmaLinux 9 matrix.

Reference:

- `docs/pgo_train_modes.md`

## What to collect back

Only collect:

- benchmark/result markdown files
- sysbench and startup wait logs
- final mini packages

Recommended helper:

- collect remote outputs: `tools/remote_collect_results.sh`

This intentionally avoids copying back:

- remote runtime datadirs
- build trees
- source trees
- intermediate caches

## Package naming

To avoid overwrite/confusion across distros, package filenames include distro tag and use zstd compression:

- `Percona-Server-<version>-Normal.Linux.x86_64.<distro>.mini.tar.zst`
- `Percona-Server-<version>-PGOed.Linux.x86_64.<distro>.mini.tar.zst`

Compression: `zstd -T0 -19`.

The distro tag defaults from `/etc/os-release` as `<id><major-version>` (for example `almalinux8`, `ubuntu22`) and can be overridden with `DISTRO_TAG=...` when needed.

## Recommended remote-host assumptions

- enough space on fast SSD/NVMe partition
- enough free space for duplicate runtime datadir during PGO validation
- root or equivalent privileges for dependency install
- stable network for source/bootstrap download

Practical minimums from this round:

- use `/mnt/localssd`
- monitor free space continuously when duplicating normal datadir into PGO runtime
- keep remote collection narrow to results/packages only

## AlmaLinux 9 / Percona 8.4 notes

- enable `CRB` before installing `mecab-devel` and `mecab-ipadic` on AlmaLinux 9
- install `rpcgen` for `Percona Server 8.4` builds
- keep `LINKER_FLAVOR=default` for PGO on `gcc-toolset-12` hosts to avoid `ld.gold` failures
- if remote source download is slow, rsync only the target unpacked source tree; do not copy unrelated local tar archives

## Lessons from AlmaLinux 8 round

1. shipping the whole workspace wastes time and SSD space
2. tracked files + source tarballs are sufficient
3. result pull-back should be narrow and explicit
4. benchmark start must wait for startup quiesce, not just mysqld readiness
5. package names must carry distro tag to avoid cross-host overwrite
