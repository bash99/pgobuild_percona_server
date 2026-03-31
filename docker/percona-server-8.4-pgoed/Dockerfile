FROM redhat/ubi9-minimal

LABEL org.opencontainers.image.title="Percona Server (PGOed community build)" \
      org.opencontainers.image.description="Community-maintained Docker image built from the repository's PGOed Percona Server binary tarball." \
      org.opencontainers.image.source="https://github.com/bash99/pgobuild_percona_server" \
      org.opencontainers.image.vendor="Community build" \
      org.opencontainers.image.licenses="MIT"

# Default to the locally produced RocksDB-enabled mini package in this repo.
# Build with repo root as context:
#   docker build -f docker/percona-server-8.4-pgoed/Dockerfile .
ARG PS_TARBALL="artifacts/Percona-Server-8.4.8-8-rocksdb/Percona-Server-8.4.8-8-PGOed.Linux.x86_64.almalinux9.mini.tar.zst"
ARG PS_BASEDIR="/usr/local/percona-server"

ENV PS_BASEDIR="${PS_BASEDIR}"
ENV PATH="${PS_BASEDIR}/bin:${PATH}"
ENV PERCONA_TELEMETRY_DISABLE=1

# It is intentionally used another UID, to have backward compatibility with
# the previous Percona image versions published on Docker Hub.
RUN set -eux; \
    groupadd -g 1001 mysql; \
    useradd -u 1001 -r -g 1001 -s /sbin/nologin -m -c "Default Application User" mysql

RUN set -eux; \
    microdnf -y install \
        ca-certificates \
        findutils \
        gawk \
        grep \
        gzip \
        hostname \
        libaio \
        ncurses-libs \
        numactl-libs \
        openssl-libs \
        procps-ng \
        sed \
        tar \
        which \
        zstd \
        tzdata; \
    microdnf -y reinstall tzdata; \
    \
    curl -fsSL -o /tmp/jemalloc.rpm https://rpmfind.net/linux/epel/9/Everything/x86_64/Packages/j/jemalloc-5.2.1-2.el9.x86_64.rpm; \
    curl -fsSL -o /tmp/mecab.rpm https://rpmfind.net/linux/almalinux/9.7/AppStream/x86_64/os/Packages/mecab-0.996-3.module_el9.6.0+152+8cbce00c.4.x86_64.rpm; \
    rpm -Uvh /tmp/jemalloc.rpm /tmp/mecab.rpm; \
    microdnf clean all; \
    rm -f /tmp/jemalloc.rpm /tmp/mecab.rpm; \
    rm -rf /var/cache/dnf /var/cache/yum

COPY ${PS_TARBALL} /tmp/percona-server-mini.tar.zst
RUN set -eux; \
    mkdir -p "${PS_BASEDIR}"; \
    zstd -dc /tmp/percona-server-mini.tar.zst | tar -xf - -C "${PS_BASEDIR}" --strip-components=1; \
    rm -f /tmp/percona-server-mini.tar.zst; \
    "${PS_BASEDIR}/bin/mysqld" --version

COPY docker/percona-server-8.4-pgoed/my.cnf /etc/my.cnf
COPY docker/percona-server-8.4-pgoed/docker.cnf /etc/my.cnf.d/docker.cnf
COPY docker/percona-server-8.4-pgoed/docker-entrypoint.sh /docker-entrypoint.sh

RUN set -eux; \
    chmod 0755 /docker-entrypoint.sh; \
    /usr/bin/install -m 0775 -o mysql -g root -d /var/lib/mysql /var/run/mysqld /docker-entrypoint-initdb.d /var/log/mysql; \
    /usr/bin/install -m 0664 -o mysql -g root /dev/null /etc/sysconfig/mysql; \
    echo "THP_SETTING=never" >> /etc/sysconfig/mysql; \
    chown -R mysql:root /etc/my.cnf /etc/my.cnf.d; \
    chmod -R ug+rwX /etc/my.cnf /etc/my.cnf.d; \
    chown mysql:mysql /docker-entrypoint.sh

VOLUME ["/var/lib/mysql", "/var/log/mysql"]

ENTRYPOINT ["/docker-entrypoint.sh"]

USER mysql
EXPOSE 3306 33060
CMD ["mysqld"]
