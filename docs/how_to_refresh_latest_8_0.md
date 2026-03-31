# How To Refresh The Latest 8.0 Version

This repository now treats the `stages/` flow as the only active path for `8.0`.
The old entry script is kept only for reference in `run_legacy.sh`.

## 1. Set the target version

Example:

```bash
export MYSQL_VER=8.0
export MYSQL_MINI_VER=45-36
```

## 2. Download the source package

```bash
bash run.sh -d
```

Expected retained source artifact:

- `percona-server-${MYSQL_VER}.${MYSQL_MINI_VER}.tar.gz`

## 3. Run the normal flow

```bash
bash run.sh -n
```

This performs:

1. `stages/build_normal_80.sh`
2. `stages/smoke_normal_80.sh`
3. `stages/benchmark_normal_80.sh`

Expected outputs:

- normal benchmark log under `work/logs/`
- normal mini package
  - `Percona-Server-${MYSQL_VER}.${MYSQL_MINI_VER}-Normal.Linux.x86_64.<distro>.mini.tar.zst`

## 4. Run the PGO flow

```bash
bash run.sh -p
```

This performs:

1. `profile-generate` build
2. readonly training with `point_select + read_only`
3. `profile-use` rebuild
4. readonly validation against the normal baseline
5. pgo mini package generation

Expected outputs:

- `work/results/pgo-readonly-${MYSQL_VER}.${MYSQL_MINI_VER}-$(date +%Y%m%d).md`
- `Percona-Server-${MYSQL_VER}.${MYSQL_MINI_VER}-PGOed.Linux.x86_64.<distro>.mini.tar.zst`

## 5. Archive and cleanup

After validation succeeds:

1. summarize the public-safe results in `task_archives/` or `docs/`
2. update the public-facing roadmap/status docs as needed
3. record detailed maintainer notes in the private maintainer repo rather than the public tree
4. remove transient `work/` build/install/runtime data if disk space is needed
5. archive the deliverables under `artifacts/Percona-Server-${MYSQL_VER}.${MYSQL_MINI_VER}/`:
   - `Percona-Server-${MYSQL_VER}.${MYSQL_MINI_VER}-PGOed.Linux.x86_64.<distro>.mini.tar.zst`
   - `pgo-readonly-${MYSQL_VER}.${MYSQL_MINI_VER}-$(date +%Y%m%d).md`
   - `install_<distro>.md` (dependency notes)
6. retain only:
   - latest source tarball
   - the `artifacts/` archive directories
   - archive/procedure documents
