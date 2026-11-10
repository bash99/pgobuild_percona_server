# Percona Server 8.0 PGOed Docker Image

This directory contains a community-maintained Docker image recipe built from a PGOed `mini.tar.zst` produced by this repository. It follows the same layout as [docker/percona-server-8.4-pgoed](../percona-server-8.4-pgoed).

Current default assumptions:

- target server: `Percona Server 8.0.46-37` (RocksDB-enabled PGOed build)
- input binary: `Percona-Server-8.0.46-37-PGOed.Linux.x86_64.almalinux8.mini.tar.zst`
- base image: `redhat/ubi8-minimal` (matches the AlmaLinux 8 build platform: glibc 2.28, OpenSSL 1.1)
- telemetry disabled by default
- `jemalloc` preloaded when available

## Prerequisites

1. Download the matching release asset from GitHub Releases (`8.0.46-37`) into the repo tree, or pass an alternate relative path with `--build-arg PS_TARBALL=...`.
2. Build from the repository root so `COPY ${PS_TARBALL}` works.

Default expected path:

- `artifacts/Percona-Server-8.0.46-37-rocksdb/Percona-Server-8.0.46-37-PGOed.Linux.x86_64.almalinux8.mini.tar.zst`

## Build

```bash
docker build -f docker/percona-server-8.0-pgoed/Dockerfile \
  -t ps-8.0.46-37-pgoed \
  -t ps-8.0-pgoed .
```

To use a different tarball path:

```bash
docker build -f docker/percona-server-8.0-pgoed/Dockerfile \
  -t ps-8.0.46-37-pgoed \
  --build-arg PS_TARBALL=artifacts/Percona-Server-8.0.46-37-rocksdb/Percona-Server-8.0.46-37-PGOed.Linux.x86_64.almalinux8.mini.tar.zst \
  .
```

## Run

```bash
docker run --name ps8004637 --rm \
  -e MYSQL_ROOT_PASSWORD=root \
  -p 3306:3306 \
  ps-8.0.46-37-pgoed
```

Basic connectivity check:

```bash
docker exec -it ps8004637 mysql -uroot -proot -e "SELECT VERSION();"
```

Expected version:

- `8.0.46-37`

Enable MyRocks explicitly if needed:

```bash
docker exec -it ps8004637 mysql -uroot -proot \
  -e "INSTALL PLUGIN ROCKSDB SONAME 'ha_rocksdb.so'; SELECT PLUGIN_NAME, PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS WHERE PLUGIN_NAME='ROCKSDB';"
```

## Layout

- config: `/etc/my.cnf` and `/etc/my.cnf.d/*.cnf`
- datadir: `/var/lib/mysql`
- init hooks: `/docker-entrypoint-initdb.d/*.(sh|sql|sql.gz)`

## Notes

- `MYSQL_ONETIME_PASSWORD=1` expires the password of every root account created during initialization, including `root@localhost` and the account selected by `MYSQL_ROOT_HOST`.
- The X Plugin is built into `mysqld` and enabled by default, even though there is no separate `mysqlx.so`. The image exposes classic protocol port `3306` and X Protocol port `33060`, matching the upstream `percona/percona-server:8.0` image. Add `-p 33060:33060` to publish X Protocol on the host, or pass `--mysqlx=0` to disable it.
- The binary was built on AlmaLinux 8; `redhat/ubi8-minimal` provides the compatible runtime (`openssl-libs` 1.1.x).
- `libatomic`, `libtirpc`, and `pam` are installed so optional plugins (`component_uuid_vx_udf.so`, `group_replication.so`, `auth_pam*.so`) can load.
- `jemalloc` and `mecab` are currently installed from direct RPM URLs; if you want stricter supply-chain control, replace those URLs with a mirrored repository under your control.
- `ha_rocksdb.so` is shipped in the image, but the plugin is not auto-installed on first boot.

## Related Docs

- sysbench benchmark harness: [docker/percona-server-8.4-pgoed/bench/README.md](../percona-server-8.4-pgoed/bench/README.md) (image names are overridable via `OFFICIAL_IMAGE`/`PGOED_IMAGE`)
- upstream 8.4 image recipe: [docker/percona-server-8.4-pgoed](../percona-server-8.4-pgoed)
