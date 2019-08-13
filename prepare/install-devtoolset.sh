#!/bin/bash

yum install -y centos-release-scl && \
yum install -y devtoolset-7-gcc-c++ automake libtool openssl-devel && \
echo "source /opt/rh/devtoolset-7/enable " > /etc/profile.d/devtoolset-7.sh
