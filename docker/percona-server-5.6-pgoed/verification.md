# Percona Server 5.6 PGOed Image Verification

Local build and container smoke test of the image recipe in this directory.

- date: `2026-11-07`
- build input: `artifacts/Percona-Server-5.6.51-93.0-centos7/Percona-Server-5.6.51-93.0-pgo-PGOed.Linux.x86_64.centos7.mini.tar.zst`
  - downloaded from the `5.6.51-93.0` GitHub release
- base image: `redhat/ubi8-minimal` + `compat-openssl10` (provides the EL7-era `libssl.so.10` / `libcrypto.so.10`) + `perl` (for `scripts/mysql_install_db`)
- image id: `sha256:4ffe6c833a65b780b0c23479a7eea1998b4c5185c2983634e3af50aaf413e48d` (tags `ps-5.6.51-93.0-pgoed` / `ps-5.6-pgoed`, size `395MB`)

## Checks performed

- `docker build` from repo root succeeds; build-time `mysqld --version` / `mysql --version` both run
- first-boot bootstrap uses `scripts/mysql_install_db` (5.6 has no `--initialize`), followed by the standard entrypoint provisioning
- `SELECT VERSION()` over TCP reports `5.6.51-93.0-pgo`
- the provisioned non-root user can connect over TCP and write to the created database
- cleanup verified: no anonymous users and no `test` database remain; only `root` plus the provisioned user exist
- `plugin_dir` and `lc-messages-dir` are pinned to the tarball layout (`lib/mysql/plugin`, `share`)
- container restart keeps the dataset and the user-created table
- `LD_PRELOAD` resolves `libjemalloc.so.2` in the running server
- root and application passwords containing apostrophes, backslashes, and embedded newlines work through `_FILE`, with both the default server SQL mode and `NO_BACKSLASH_ESCAPES`
- `.sql`, `.sql.gz`, and `.sh` init hooks, timezone conversion, `mysqldump`, and graceful stop/start pass
- `--innodb-data-file-path=ibdata1:24M:autoextend` is honored by bootstrap; `--defaults-file` selecting a 32MB system tablespace also initializes successfully
- the legacy bootstrap uses its required SQL mode without changing the SQL mode requested for the running server
- `MYSQL_ONETIME_PASSWORD=1` expires all created root accounts with the default host, `MYSQL_ROOT_HOST=localhost`, and `MYSQL_ROOT_HOST=192.0.2.%`; local root cannot issue queries before rotating its password
- the bounded fallback password generator returns 64 hexadecimal characters under `pipefail` when `pwmake` is unavailable

## Known limitations

- the interactive `mysql` client needs the EL7-era `libncurses.so.5` / `libtinfo.so.5` / `libreadline.so.6`; these are copied into `/usr/lib64` from CentOS 7 vault RPMs during build
- no X Plugin and no MyRocks in this build (only `3306` exposed)
- MySQL 5.6 does not auto-generate TLS certificates; mount certificate files if TLS is required
