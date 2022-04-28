#!/bin/bash

yum_install() {
    yum install -y centos-release-scl && \
    yum install -y devtoolset-9-gcc-c++ devtoolset-10-gcc-c++ automake libtool openssl-devel && \
#    echo "source /opt/rh/devtoolset-9/enable " > /etc/profile.d/devtoolset-9.sh
    yum install -y git rsync
}

apt_install() {
    apt install build-essential git rsync -y
}

if [ -f /usr/bin/apt ]; then
	apt_install
elif [ -f /usr/bin/yum ]; then
      	yum_install
fi
