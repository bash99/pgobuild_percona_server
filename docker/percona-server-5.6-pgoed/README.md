# Percona Server 5.6 PGOed Docker Image

This directory contains a community-maintained Docker image recipe built from a PGOed `mini.tar.zst` produced by this repository. It follows the same layout as [docker/percona-server-8.4-pgoed](../percona-server-8.4-pgoed).

Current default assumptions:

- target server: `Percona Server 5.6.51-93.0` PGOed build (historical final CentOS 7 compatible release)
- input binary: `Percona-Server-5.6.51-93.0-pgo-PGOed.Linux.x86_64.centos7.mini.tar.zst`
- base image: `redhat/ubi8-minimal` (EL8 glibc runs the CentOS 7 build; `compat-openssl10` provides the required `libssl.so.10` / `libcrypto.so.10`)
- `jemalloc` preloaded when available

## Prerequisites

1. Download the matching release asset from GitHub Releases (`5.6.51-93.0`) into the repo tree, or pass an alternate relative path with `--build-arg PS_TARBALL=...`.
2. Build from the repository root so `COPY ${PS_TARBALL}` works.

Default expected path:

- `artifacts/Percona-Server-5.6.51-93.0-centos7/Percona-Server-5.6.51-93.0-pgo-PGOed.Linux.x86_64.centos7.mini.tar.zst`

## Build

```bash
docker build -f docker/percona-server-5.6-pgoed/Dockerfile \
  -t ps-5.6.51-93.0-pgoed \
  -t ps-5.6-pgoed .
```

## Run

```bash
docker run --name ps565193 --rm \
  -e MYSQL_ROOT_PASSWORD=root \
  -p 3306:3306 \
  ps-5.6.51-93.0-pgoed
```

Basic connectivity check:

```bash
docker exec -it ps565193 mysql -uroot -proot -e "SELECT VERSION();"
```

Expected version:

- `5.6.51-93.0-pgo`

## Layout

- config: `/etc/my.cnf` and `/etc/my.cnf.d/*.cnf`
- datadir: `/var/lib/mysql`
- init hooks: `/docker-entrypoint-initdb.d/*.(sh|sql|sql.gz)`

## Notes

- `MYSQL_ONETIME_PASSWORD=1` expires the password of every root account created during initialization, including `root@localhost` and the account selected by `MYSQL_ROOT_HOST`.
- MySQL 5.6 has no `mysqld --initialize`; the entrypoint bootstraps the data directory with `scripts/mysql_install_db` from the tarball, then prunes anonymous users / remote roots / the `test` database and sets the root password with `SET PASSWORD ... = PASSWORD(...)` (5.6 syntax).
- The binary was built on CentOS 7 (glibc 2.17, OpenSSL 1.0.2 sonames). `redhat/ubi8-minimal` runs it via `compat-openssl10`.
- The CentOS 7 `mysql` client is linked against EL7-era `libncurses.so.5` / `libtinfo.so.5` / `libreadline.so.6`. Those three libraries are extracted from CentOS 7 vault RPMs into `/usr/lib64` (without replacing the EL8 ncurses/readline packages).
- No X Plugin and no MyRocks in this build; only `EXPOSE 3306`.
- Percona Server 5.6 has no telemetry component, so no telemetry flag is passed to mysqld.
- MySQL 5.6 does not auto-generate SSL certificates; mount certificate files if you need TLS.
- `auth_pam.so` / `auth_pam_compat.so` can load because `pam` is installed. HandlerSocket (`handlersocket.so`) is shipped as well.

## Related Docs

- upstream 8.4 image recipe: [docker/percona-server-8.4-pgoed](../percona-server-8.4-pgoed)
- release validation summary: [artifacts/Percona-Server-5.6.51-93.0-centos7/pgo-readonly-5.6.51-93.0-20260402.md](../../artifacts/Percona-Server-5.6.51-93.0-centos7/pgo-readonly-5.6.51-93.0-20260402.md)
