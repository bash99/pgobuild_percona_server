yum install centos-release-scl
yum install install devtoolset-4-gcc-c++
scl enable devtoolset-4 bash && echo "source /opt/rh/devtoolset-4/enable " > /etc/profile.d/devtoolset-4.sh
