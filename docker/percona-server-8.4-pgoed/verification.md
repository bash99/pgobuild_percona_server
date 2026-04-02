# Verification

## Verification (2026-03-18)

### Build

```bash
docker build -f docker/percona-server-8.4-pgoed/Dockerfile -t ps-8.4.8-8-pgoed -t ps-8.4-pgoed .
```

### Run (basic root password + port mapping)

```bash
docker run --name ps8488 -e MYSQL_ROOT_PASSWORD=root -p 13306:3306 -p 13360:33060 -d ps-8.4.8-8-pgoed
```

Host-side TCP connectivity (using the `mysql` client extracted from the mini package):

```bash
mkdir -p .tmp
tmpdir=$(mktemp -d .tmp/ps8488-rdb-XXXXXX)
zstd -dc artifacts/Percona-Server-8.4.8-8-rocksdb/Percona-Server-8.4.8-8-PGOed.Linux.x86_64.almalinux9.mini.tar.zst | tar -xf - -C "$tmpdir"
"$tmpdir"/percona-server-8.4.8-8-linux-x86_64/bin/mysql -h 127.0.0.1 -P 13306 -uroot -proot \
  -e "SELECT VERSION() AS version, @@port AS port, @@socket AS socket;"
```

Expected output:

```text
version  port  socket
8.4.8-8  3306  /var/lib/mysql/mysql.sock
```

Port `33060` is reachable:

```bash
nc -zv 127.0.0.1 13360
```

Expected output includes:

```text
Connection to 127.0.0.1 13360 port [tcp/*] succeeded!
```

Telemetry is disabled:

```bash
"$tmpdir"/percona-server-8.4.8-8-linux-x86_64/bin/mysql -h 127.0.0.1 -P 13306 -uroot -proot \
  -e "SHOW VARIABLES LIKE 'percona_telemetry_disable';"
```

Expected output:

```text
Variable_name             Value
percona_telemetry_disable ON
```

jemalloc preload is active:

```bash
docker exec ps8488 sh -c 'grep -m1 -E "libjemalloc" /proc/1/maps'
```

Expected output includes:

```text
/usr/lib64/libjemalloc.so.2
```

RocksDB plugin can be enabled and used:

```bash
"$tmpdir"/percona-server-8.4.8-8-linux-x86_64/bin/mysql -h 127.0.0.1 -P 13306 -uroot -proot <<'SQL'
INSTALL PLUGIN ROCKSDB SONAME 'ha_rocksdb.so';
SHOW PLUGINS LIKE 'ROCKSDB';
CREATE DATABASE IF NOT EXISTS rdbtest;
USE rdbtest;
CREATE TABLE t1 (id INT PRIMARY KEY) ENGINE=ROCKSDB;
SHOW TABLE STATUS LIKE 't1'\G
SQL
```

Expected output includes:

```text
Name: t1
Engine: ROCKSDB
```

Cleanup:

```bash
docker rm -f ps8488
```

### Run (create database + user)

```bash
docker run --name ps8488test \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=appdb \
  -e MYSQL_USER=appuser \
  -e MYSQL_PASSWORD=apppass \
  -p 13307:3306 \
  -d ps-8.4.8-8-pgoed
```

```bash
"$tmpdir"/percona-server-8.4.8-8-linux-x86_64/bin/mysql -h 127.0.0.1 -P 13307 -uappuser -papppass \
  -e "SELECT CURRENT_USER(); SHOW DATABASES LIKE 'appdb';"
```

Expected output:

```text
CURRENT_USER()
appuser@%
Database (appdb)
appdb
```

Cleanup:

```bash
docker rm -f ps8488test
```

### Notes

- `get_mempolicy: Operation not permitted` / NUMA policy warnings are expected in unprivileged containers.
- `mysql_tzinfo_to_sql` may warn and skip non-zoneinfo files (e.g. `zone.tab`, `tzdata.zi`); this does not block startup.
