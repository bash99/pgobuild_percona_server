#!/bin/bash

GNUPGHOME=~/gnupg && mkdir -p ~/gnupg && chmod 600 ~/gnupg \
&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 352c64e5 \
&& gpg --export --armor 352c64e5 > ${GNUPGHOME}/RPM-GPG-KEY-EPEL \
&& yum install epel-release -y \
&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A \
&& gpg --export --armor 430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A > ${GNUPGHOME}/RPM-GPG-KEY-Percona \
&& rpm --import ${GNUPGHOME}/RPM-GPG-KEY-* \
&& yum -y install -y jemalloc pxz numactl numactl-devel rh-mysql57-mecab-devel bzip2 cmake3 libaio-devel \
      ncurses-devel readline-devel libcurl-devel pam-devel bison-devel bison tmux bc patch \
      openssl-devel re2-devel libtirpc-devel \
&& alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 \
--slave /usr/local/bin/ctest ctest /usr/bin/ctest3 \
--slave /usr/local/bin/cpack cpack /usr/bin/cpack3 \
--slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3 \
--family cmake
