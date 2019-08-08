curl -L -C - https://sourceforge.net/projects/boost/files/boost/1.59.0/boost_1_59_0.tar.bz2/download -o boost_1_59_0.tar.bz2 \
&& tar jxf boost_1_59_0.tar.bz2 \
&& git clone  --depth 1 https://github.com/percona/percona-server.git -b 5.7 ps-5.7 \
&& cd ps-5.7 && git submodule init && git submodule update
#
# export VER="26-29"
#curl -L -C - https://www.percona.com/downloads/Percona-Server-5.7/Percona-Server-5.7.${VER}/source/tarball/percona-server-5.7.${VER}.tar.gz -o percona-server-5.7.${VER}.tar.gz
