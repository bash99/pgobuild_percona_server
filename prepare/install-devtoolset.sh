#!/bin/bash

yum install -y centos-release-scl && \
yum install -y devtoolset-9-gcc-c++ automake libtool openssl-devel && \
echo "source /opt/rh/devtoolset-9/enable " > /etc/profile.d/devtoolset-9.sh
