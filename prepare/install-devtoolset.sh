yum install -y centos-release-scl
yum install -y install devtoolset-7-gcc-c++ automake libtool openssl-devel
scl enable devtoolset-7 bash && echo "source /opt/rh/devtoolset-7/enable " > /etc/profile.d/devtoolset-7.sh
