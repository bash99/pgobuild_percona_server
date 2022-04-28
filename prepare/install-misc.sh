#!/bin/bash

yum_install() {
GNUPGHOME=~/gnupg && mkdir -p ~/gnupg && chmod 600 ~/gnupg \
&& gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A 99DB70FAE1D7CE227FB6488205B555B38483C65D 352c64e5 \
&& gpg --export --armor 352c64e5 > ${GNUPGHOME}/RPM-GPG-KEY-EPEL \
&& yum install epel-release -y \
&& gpg --export --armor 430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A > ${GNUPGHOME}/RPM-GPG-KEY-Percona \
&& rpm --import ${GNUPGHOME}/RPM-GPG-KEY-* \
&& yum -y install -y jemalloc pxz numactl numactl-devel rh-mysql57-mecab-devel bzip2 cmake3 libaio-devel \
      ncurses-devel readline-devel libcurl-devel pam-devel bison-devel bison tmux bc patch \
      openssl-devel re2-devel libtirpc-devel libedit-devel  zip zstd perl-Data-Dumper \
      krb5-devel cyrus-sasl-devel cyrus-sasl-scram openldap-devel zlib-devel \
&& alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 \
--slave /usr/local/bin/ctest ctest /usr/bin/ctest3 \
--slave /usr/local/bin/cpack cpack /usr/bin/cpack3 \
--slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3 \
--family cmake
}

apt_install() {
    apt install libjemalloc-dev bzip2 cmake libmecab-dev libnuma-dev libaio-dev libncurses-dev \
      libreadline-dev libcurl4-openssl-dev libpam0g-dev libbison-dev bison tmux bc patch \
      libssl-dev libre2-dev libtirpc-dev libedit-dev zip zstd libdata-dmp-perl pkg-config \
      numactl automake autoconf libtool libkrb5-dev libldap-dev \
      zlib1g-dev libsasl2-dev libsasl2-modules-gssapi-mit -y
}

if [ -f /usr/bin/apt ]; then
	apt_install
elif [ -f /usr/bin/yum ]; then
      	yum_install
fi
