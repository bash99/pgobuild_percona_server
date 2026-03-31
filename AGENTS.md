# AGENTS.md

## Project Purpose

This repository automates building Percona Server (5.7/8.0/8.4, with historical 5.6 support) with and without PGO (Profile-Guided Optimization), benchmarking via Sysbench, and packaging minimized tarballs. The intended top-level workflow is:

1. Prepare build host dependencies
2. Download Percona/MySQL source
3. Build and benchmark a normal binary
4. Build instrumented binary, collect profile, rebuild with profile-use
5. Benchmark PGO binary and package outputs

The canonical orchestrator is `run.sh`.

## Repository Structure

- `run.sh`
  - Main entrypoint with flags:
    - `-i`: prepare system packages/toolchain
    - `-d`: download source
    - `-n`: normal build + benchmark + package
    - `-p`: PGO build + benchmark + package
  - Exports defaults: `MYSQL_VER`, `MYSQL_MINI_VER`, `CPU_OPT_FLAGS`, `MYSQL_SOURCE_PATH`, `MYSQL_BASE`.
  - Sources devtoolset enable scripts if present.

- `README.md`
  - Public English overview and release guidance.
- `README.zh-CN.md`
  - Public Chinese overview.
- `README_old.md`
  - Historical README kept for reference only.
- `ROADMAP.md`
  - Public-facing support matrix and next milestones.

- `prepare/`
  - `prepare_system.sh`: runs install scripts and system limits setup.
  - `install-devtoolset.sh`: compiler/tool setup via `yum` or `apt`.
  - `install-misc.sh`: build dependencies (`cmake`, libraries, tooling).
  - `init_syslimit.sh`: modifies `/etc/security/limits.conf` and kernel params.
  - `download-source.sh`: fetches source tarballs and optional Boost.
  - `update-source.sh`: legacy git update helper.
  - `doall.sh`: old partial wrapper.

- `build-normal/`
  - `doall.sh`: full non-PGO pipeline.
  - `prepare_build.sh`: creates build tree (`cp -al`) from source tree.
  - `compile.sh`: version-specific CMake+make build logic.
  - `install_mini.sh`: installs selected CMake components with strip.
  - `init_normal.sh`: initializes data directory and credentials.
  - `init_conf.sh`: generates benchmark-oriented MySQL config.
  - `start_normal.sh` / `shutdown_normal.sh`: lifecycle control.
  - `init_setpass.sh`: rotates root password and writes `~/.my.cnf`.
  - `test_binary.sh` / `sysbench_binary.sh`: benchmark binary tarballs directly.
  - `common.sh`: shared runtime paths and command templates.
  - `mysql-cli.sh`, `enable_rocksdb.sh`: convenience utilities.

- `build-opt/`
  - `doall.sh`: PGO wrapper.
  - `build_pgo.sh`: two-phase PGO build/training/use workflow.
  - `patch_version.sh`: appends `-pgo` into server VERSION metadata.
  - `make_package.sh`: packages minified tarball and removes profile strings.

- `sysbench/`
  - `compile-sysbench.sh`: downloads/builds sysbench 1.0 against built MySQL.
  - `init-sysbench.sh`: creates test user/database and prepares dataset.
  - `train-sysbench.sh`: runs point-select/read-only/read-write workloads.
  - `common_config.sh`: central benchmark parameters.

- `old_doall.sh`
  - Deprecated/buggy legacy orchestrator; keep only for history reference.

## How Scripts Relate (Execution Graph)

### End-to-end non-PGO

```
run.sh -n
-> build-normal/doall.sh
   -> build-normal/prepare_build.sh
   -> build-normal/compile.sh
   -> build-normal/install_mini.sh
   -> build-normal/init_normal.sh
   -> build-normal/start_normal.sh
   -> sysbench/compile-sysbench.sh
   -> sysbench/init-sysbench.sh
   -> sysbench/train-sysbench.sh
   -> build-normal/shutdown_normal.sh
   -> build-opt/make_package.sh (normal package)
```

### End-to-end PGO

```
run.sh -p
-> build-opt/doall.sh
   -> build-opt/build_pgo.sh
      -> build-normal/prepare_build.sh
      -> build-opt/patch_version.sh
      -> build-normal/compile.sh (profile-generate)
      -> build-normal/install_mini.sh
      -> build-normal/start_normal.sh
      -> sysbench/train-sysbench.sh (collect profile)
      -> build-normal/shutdown_normal.sh
      -> build-normal/prepare_build.sh (8.0 path reset)
      -> build-normal/compile.sh (profile-use)
      -> build-normal/install_mini.sh
      -> build-normal/start_normal.sh
      -> sysbench/train-sysbench.sh (validation)
      -> build-normal/shutdown_normal.sh
   -> build-opt/make_package.sh (pgoed package)
```

### Setup and source

```
run.sh -i -> prepare/prepare_system.sh -> install scripts + limits script
run.sh -d -> prepare/download-source.sh
```

## Internal Planning

Public repository content should stay user-facing.

Internal planning materials such as:

- current task tracking
- main milestone tracking
- detailed task archives
- raw remote host notes

should live in the maintainer private repo or a local ignored `internal/` directory, not in the public tree.
