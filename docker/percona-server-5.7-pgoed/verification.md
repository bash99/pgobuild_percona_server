# Percona Server 5.7 PGOed Image Verification

Local build and container smoke test of the image recipe in this directory.

- date: `2026-11-07`
- build input: `artifacts/Percona-Server-5.7.44-57-centos7/Percona-Server-5.7.44-57-PGOed.Linux.x86_64.centos7.mini.tar.zst`
  - sha256 matches the committed `SHA256SUMS.txt` (`713936a22dc048a38116d05c73a6517854f63b0ba9ad52a3317b993d3b343ed0`)
- base image: `redhat/ubi8-minimal` + `compat-openssl10` (provides the EL7-era `libssl.so.10` / `libcrypto.so.10`)
- image id: `sha256:e87e7f68d443534edf26aa2db8fd9c9cd3ed5c5735906f2d2ae4a8b902a98f85` (tags `ps-5.7.44-57-pgoed` / `ps-5.7-pgoed`, size `313MB`)

## Checks performed

- `docker build` from repo root succeeds; build-time `mysqld --version` / `mysql --version` both run
- first-boot initialization with `MYSQL_ROOT_PASSWORD` / `MYSQL_DATABASE` / `MYSQL_USER` / `MYSQL_PASSWORD` completes
- `SELECT VERSION()` over TCP reports `5.7.44-57-pgo`
- the provisioned non-root user can connect over TCP and write to the created database
- `plugin_dir` and `lc-messages-dir` are pinned to the tarball layout; SQL errors include their English diagnostic text and startup no longer reports a missing `errmsg.sys`
- `mysql.session` survives provisioning; after `INSTALL PLUGIN mysqlx SONAME 'mysqlx.so'`, an actual `mysqlsh --mysqlx` client successfully executes a query on port `33060`
- container restart keeps the dataset and the user-created table
- `LD_PRELOAD` resolves `libjemalloc.so.2` in the running server
- root and application passwords containing apostrophes, backslashes, and embedded newlines work through `_FILE`, with both the default server SQL mode and `NO_BACKSLASH_ESCAPES`
- `.sql`, `.sql.gz`, and `.sh` init hooks, timezone conversion, `mysqldump`, and graceful stop/start pass
- generated provisioning SQL does not change the server SQL mode used by init hooks or subsequent client sessions
- `MYSQL_ONETIME_PASSWORD=1` expires both local and configured remote root accounts with the default host, `MYSQL_ROOT_HOST=localhost`, and `MYSQL_ROOT_HOST=192.0.2.%`; a query through `--connect-expired-password` is rejected with error 1820 until the password is rotated

## Known limitations

- the interactive `mysql` client needs the EL7-era `libncurses.so.5` / `libtinfo.so.5` / `libreadline.so.6`; these are copied into `/usr/lib64` from CentOS 7 vault RPMs during build
- `libpluginmecab.so` is shipped but requires the SCL soname `libmecab.so.rh-mysql57-2`, which is not available from EL8 repos; the MeCab fulltext parser is therefore not loadable out of the box
