curl -L -C - https://sourceforge.net/projects/boost/files/boost/1.59.0/boost_1_59_0.tar.bz2/download -o boost_1_59_0.tar.bz2 \
&& tar jxf boost_1_59_0.tar.bz2 \
&& git clone  --depth 1 https://github.com/percona/percona-server.git -b 5.7 ps-5.7
