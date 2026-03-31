# Percona Server 8.4 PGOed Docker Image

This directory contains a community-maintained Docker image recipe built from a PGOed `mini.tar.zst` produced by this repository.

Current default assumptions:

- target server: `Percona Server 8.4.8-8`
- input binary: RocksDB-enabled PGOed mini tarball
- base image: `redhat/ubi9-minimal`
- telemetry disabled by default
- `jemalloc` preloaded when available

## Prerequisites

1. Download the matching release asset from GitHub Releases.
2. Place it in the repository tree, or pass an alternate relative path with `--build-arg PS_TARBALL=...`.
3. Build from the repository root so `COPY ${PS_TARBALL}` works.

Default expected path:

- `artifacts/Percona-Server-8.4.8-8-rocksdb/Percona-Server-8.4.8-8-PGOed.Linux.x86_64.almalinux9.mini.tar.zst`

## Build

```bash
docker build -f docker/percona-server-8.4-pgoed/Dockerfile \
  -t ps-8.4.8-8-pgoed \
  -t ps-8.4-pgoed .
```

To use a different tarball path:

```bash
docker build -f docker/percona-server-8.4-pgoed/Dockerfile \
  -t ps-8.4.8-8-pgoed \
  --build-arg PS_TARBALL=artifacts/Percona-Server-8.4.8-8-rocksdb/Percona-Server-8.4.8-8-PGOed.Linux.x86_64.almalinux9.mini.tar.zst \
  .
```

## Run

```bash
docker run --name ps8488 --rm \
  -e MYSQL_ROOT_PASSWORD=root \
  -p 3306:3306 -p 33060:33060 \
  ps-8.4.8-8-pgoed
```

Basic connectivity check:

```bash
docker exec -it ps8488 mysql -uroot -proot -e "SELECT VERSION();"
```

Enable MyRocks explicitly if needed:

```bash
docker exec -it ps8488 mysql -uroot -proot \
  -e "INSTALL PLUGIN ROCKSDB SONAME 'ha_rocksdb.so'; SHOW PLUGINS LIKE 'ROCKSDB';"
```

## Layout

- config: `/etc/my.cnf` and `/etc/my.cnf.d/*.cnf`
- datadir: `/var/lib/mysql`
- init hooks: `/docker-entrypoint-initdb.d/*.(sh|sql|sql.gz)`

## Notes

- `tzdata` is reinstalled because `ubi9-minimal` may lack the expected zoneinfo payload by default.
- `jemalloc` and `mecab` are currently installed from direct RPM URLs; if you want stricter supply-chain control, replace those URLs with a mirrored repository under your control.
- `ha_rocksdb.so` is shipped in the image, but the plugin is not auto-installed on first boot.

## Related Docs

- verification log: `docker/percona-server-8.4-pgoed/verification.md`
- sysbench benchmark harness: `docker/percona-server-8.4-pgoed/bench/README.md`
- head-to-head report: `docker/percona-server-8.4-pgoed/bench/report-sysbench-vs-official-8.4.7-7.1.md`
