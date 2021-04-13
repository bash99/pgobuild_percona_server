#!/bin/bash

yum_install() {
    yum install -y centos-release-scl && \
    yum install -y devtoolset-9-gcc-c++ automake libtool openssl-devel && \
    echo "source /opt/rh/devtoolset-9/enable " > /etc/profile.d/devtoolset-9.sh
    yum install -y git rsync
}

apt_install() {
    apt install build-essential git rsync -y
}

[[ -f /usr/bin/apt ]] && apt_install
[[ -f /usr/bin/yum ]] && yum_install