# Percona Server 8.0 PGOed Image Verification

Local build and container smoke test of the image recipe in this directory.

- date: `2026-11-07`
- build input: `artifacts/Percona-Server-8.0.46-37-rocksdb/Percona-Server-8.0.46-37-PGOed.Linux.x86_64.almalinux8.mini.tar.zst`
  - sha256 matches the published `SHA256SUMS.txt` (`933655002186d9f5d475e927eddb65ba7f7e898da14f1781def27af2667bf93e`)
- base image: `redhat/ubi8-minimal`
- image id: `sha256:d90aa0e0b96bf06ccfc9d529eecdc62b851e9514b701ccf7efaecdff7f72176f` (tags `ps-8.0.46-37-pgoed` / `ps-8.0-pgoed`, size `519MB`)

## Checks performed

- `docker build` from repo root succeeds; `mysqld --version` inside the build reports `8.0.46-37`
- first-boot initialization with `MYSQL_ROOT_PASSWORD` / `MYSQL_DATABASE` / `MYSQL_USER` / `MYSQL_PASSWORD` completes
- `SELECT VERSION()` over TCP reports `8.0.46-37`
- the provisioned non-root user can connect over TCP and write to the created database
- `INSTALL PLUGIN ROCKSDB SONAME 'ha_rocksdb.so'` succeeds; a RocksDB table can be written and read again after restart
- the built-in X Plugin is enabled on `33060`, the image declares that port, and an actual `mysqlsh --mysqlx` client successfully executes a query
- container restart keeps the dataset and the user-created table
- `LD_PRELOAD` resolves `libjemalloc.so.2` in the running server
- root and application passwords containing apostrophes, backslashes, and embedded newlines work through `_FILE`, with both the default server SQL mode and `NO_BACKSLASH_ESCAPES`
- `.sql`, `.sql.gz`, and `.sh` init hooks, timezone conversion, `mysqldump --no-tablespaces`, and graceful stop/start pass
- generated provisioning SQL does not change the server SQL mode used by init hooks or subsequent client sessions
- `MYSQL_ONETIME_PASSWORD=1` expires both local and configured remote root accounts with the default host, `MYSQL_ROOT_HOST=localhost`, and `MYSQL_ROOT_HOST=192.0.2.%`; a query through `--connect-expired-password` is rejected with error 1820 until the password is rotated

## Known limitations

- the X Plugin is built into `mysqld`; no separate `mysqlx.so` is needed. Disable it explicitly with `--mysqlx=0` if it is not required
- telemetry disabled via the same `PERCONA_TELEMETRY_DISABLE=1` / `--percona_telemetry_disable=1` mechanism as the 8.4 image
