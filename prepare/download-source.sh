export BOOST_VER=1_69_0
# export BOOST_VER=1_59_0
export BOOST_DOT_VER=`echo $BOOST_VER | sed -e "s/\_/./g"`
curl -L -C - https://sourceforge.net/projects/boost/files/boost/${BOOST_DOT_VER}/boost_${BOOST_VER}.tar.bz2/download -o boost_${BOOST_VER}.tar.bz2 \
&& tar jxf boost_${BOOST_VER}.tar.bz2
#
# export MAJOR_VER="5.7"
# export MINI_VER="26-29"
#curl -L -C - -O https://www.percona.com/downloads/Percona-Server-$MAJOR_VER/Percona-Server-${MAJOR_VER}.${VER}/source/tarball/percona-server-${MAJOR_VER}.${VER}.tar.gz
#https://www.percona.com/downloads/Percona-Server-8.0/Percona-Server-8.0.15-6/source/tarball/percona-server-8.0.15-6.tar.gz
#
# && git clone  --depth 1 https://github.com/percona/percona-server.git -b 5.7 ps-5.7 \
# && cd ps-5.7 && git submodule init && git submodule update
