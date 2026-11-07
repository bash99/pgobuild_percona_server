FROM redhat/ubi8-minimal

LABEL org.opencontainers.image.title="Percona Server 5.7 (PGOed community build)" \
      org.opencontainers.image.description="Community-maintained Docker image built from the repository's PGOed Percona Server binary tarball." \
      org.opencontainers.image.source="https://github.com/bash99/pgobuild_percona_server" \
      org.opencontainers.image.vendor="Community build" \
      org.opencontainers.image.licenses="MIT"

# Default to the PGOed mini package published in this repo.
# Build with repo root as context:
#   docker build -f docker/percona-server-5.7-pgoed/Dockerfile .
ARG PS_TARBALL="artifacts/Percona-Server-5.7.44-57-centos7/Percona-Server-5.7.44-57-PGOed.Linux.x86_64.centos7.mini.tar.zst"
ARG PS_BASEDIR="/usr/local/percona-server"

ENV PS_BASEDIR="${PS_BASEDIR}"
ENV PATH="${PS_BASEDIR}/bin:${PATH}"

# It is intentionally used another UID, to have backward compatibility with
# the previous Percona image versions published on Docker Hub.
# ubi8-minimal does not ship shadow-utils, unlike ubi9-minimal.
RUN set -eux; \
    microdnf -y install shadow-utils; \
    groupadd -g 1001 mysql; \
    useradd -u 1001 -r -g 1001 -s /sbin/nologin -m -c "Default Application User" mysql

RUN set -eux; \
    microdnf -y install \
        ca-certificates \
        cpio \
        findutils \
        gawk \
        grep \
        gzip \
        hostname \
        libaio \
        ncurses-libs \
        numactl-libs \
        openssl-libs \
        pam \
        procps-ng \
        sed \
        tar \
        which \
        zstd \
        tzdata; \
    microdnf -y reinstall tzdata; \
    \
    microdnf -y install compat-openssl10; \
    \
    curl -fsSL -o /tmp/jemalloc.rpm https://rpmfind.net/linux/epel/8/Everything/x86_64/Packages/j/jemalloc-5.2.1-3.el8.x86_64.rpm; \
    rpm -Uvh /tmp/jemalloc.rpm; \
    \
    # The CentOS 7 build ships an interactive `mysql` client linked against the
    # EL7-era ncurses5/readline6 sonames. Extract just those libraries from the
    # CentOS 7 vault RPMs instead of installing (and clobbering) the EL8
    # ncurses/readline packages.
    curl -fsSL -o /tmp/ncurses5-libs.rpm https://vault.centos.org/7.9.2009/os/x86_64/Packages/ncurses-libs-5.9-14.20130511.el7_4.x86_64.rpm; \
    curl -fsSL -o /tmp/readline6.rpm https://vault.centos.org/7.9.2009/os/x86_64/Packages/readline-6.2-11.el7.x86_64.rpm; \
    cd /tmp; \
    rpm2cpio ncurses5-libs.rpm | cpio -idm --quiet; \
    rpm2cpio readline6.rpm | cpio -idm --quiet; \
    # EL7 packages predate the usr merge: readline ships under /lib64 while
    # ncurses-libs ships under /usr/lib64, so copy by name.
    find . -name "libncurses.so.5*" -o -name "libtinfo.so.5*" -o -name "libreadline.so.6*" | xargs -I{} cp -a {} /usr/lib64/; \
    cd /; \
    microdnf clean all; \
    rm -rf /tmp/jemalloc.rpm /tmp/ncurses5-libs.rpm /tmp/readline6.rpm /tmp/usr /tmp/lib64; \
    rm -rf /var/cache/dnf /var/cache/yum

COPY ${PS_TARBALL} /tmp/percona-server-mini.tar.zst
RUN set -eux; \
    mkdir -p "${PS_BASEDIR}"; \
    zstd -dc /tmp/percona-server-mini.tar.zst | tar -xf - -C "${PS_BASEDIR}" --strip-components=1; \
    rm -f /tmp/percona-server-mini.tar.zst; \
    "${PS_BASEDIR}/bin/mysqld" --version; \
    "${PS_BASEDIR}/bin/mysql" --version

COPY docker/percona-server-5.7-pgoed/my.cnf /etc/my.cnf
COPY docker/percona-server-5.7-pgoed/docker.cnf /etc/my.cnf.d/docker.cnf
COPY docker/percona-server-5.7-pgoed/docker-entrypoint.sh /docker-entrypoint.sh

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
