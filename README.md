# pgobuild_percona_server
some help scripts to build a PGO version percona_server 5.7

## usage
sorry, it's far from complete.

you need a worked percona compiling and build directory, a optimized mysql config, some cpu(>=4 core) to some real performance test so pgo can work.
### check out this as pspgo-utils
git clone https://github.com/bash99/pgobuild_percona_server.git pspgo-utils

### prepare build evenrionment
#### install gcc/g++
use aleast gcc 4.9, 5.2 or higher is fine, use devtoolset-4-gcc-c++ in centos 7(may be 6)  
see install-devtoolset-4-gcc.sh
#### install jemalloc pxz numactl-devel rh-mysql57-mecab-devel
make sure ```/usr/lib64/libjemalloc.so.1``` exists or create a link for it
#### install boost
boost_1_59_0 (https://sourceforge.net/projects/boost/files/boost/1.59.0/boost_1_59_0.tar.bz2/download)
in you build dir, you'll clone PS source in same dir.  
At the end, your build dir will like
```
boost_1_59_0
ps-5.7
pspgo-utils
```

### prepare a normal percona build
flow the guide 
https://www.percona.com/doc/percona-server/5.7/installation.html#source-from-git
complete two steps
#### Installing Percona Server from the Git Source Tree
#### Compiling Percona Server from Source
I'll assume you install percona in default /usr/local/mysql dir, and mysql.sock path is /var/lib/mysql/mysql.sock

### tune your mysql
flow the guide 
http://www.speedemy.com/17-key-mysql-config-file-settings-mysql-5-7-proof/  
setting ```innodb_buffer_pool_dump_pct = 100```, so you can repeat sysbench without too much warm-up time

### install sysbench 0.5 (from package or source)

### generate stand sysbench load
db: sbtest
user: sbtest
pass: sbtest12
16 table, 2M rows per table.
see init-sysbench.sh
and run some sysbenchtest train-sysbench.sh to make sure everything is ok

### do pgo build
#### patch pgo, cd your PS build dir
```
cd 5.7
patch -p1 < PATHTO_THIS/cmake-pgo.patch
```
you can see the march is setting to Westmere ( Nehalem-based Xeon with AES instruction ), feel free to setting this to
lowest cpu generation you had/like.

#### run build scripts
build_5.x_pgo.sh

found your pgo build in 
```
5.7_opt/_CPack_Packages/Linux/TGZ/
```
or your can replace mysqld directly and play some benchmark(sysbench, big select/sort/group ...)

