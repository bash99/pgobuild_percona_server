# Percona Server Profile-Guided Optimization utils

This project contains some help scripts to build a PGO version of [Percona Server for MySQL®](https://www.percona.com/software/mysql-database/percona-server) (5.6, 5.7, 8.0).

| Percona Server for MySQL® is a free, fully compatible, enhanced and open source drop-in replacement for any MySQL database.

## Introduce

Profile-Guided Optimization is a optimization technique of compilers, which use application runtime data to
making compilation decisions like inlining functions or unroll loops.

Which contains three stages

1. instrumented compilation: compiling program with instrument code.
2. profiled execution: run program in real/simulated workloads and generating profile data.
3. optimization compile: re-compiling program with those data.

MariaDB has some PR that mentioned they used PGO on their enterprise cluster version.

So I try this on percona server, use sysbench oltp as the workload and get good results.

## Benchmark

It got about 20~40% improvement on oltp benchmarks (read_only or read_write).

| TPS | 5.6	| 5.6_PGO	| improvement	| 5.7	| 5.7_PGO	| improvement	|8.0	| 8.0_PGO	| improvement |
| ----------| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |
| point_select| 70106.22	|92630.52	|32.13%	|70180.87	|100511.44	|43.22%	|61668.86	|94908.89	|53.90% |
| read_only |1969.35	|2537.66	|28.86%	|2404.53	|3229.28	|34.30%	|2846.61	|3709.64	|30.32% |
| read_write |1387.48    |1780.91	|28.36%	|1596.53	|2246.4	|40.71%	|1417.5	|1743.1	|22.97% |

Hardware: 8 Core 16G VM and 100G SSD, use a 4.8G memory pool and 7.7G dataset (2M table size, 16 tables), with 16 oltp threads.

Although the profiling workload is not a tpcc like workload, it also get 7.4% improvement on transaction with [TPCC-Like Workload for Sysbench 1.0](https://github.com/Percona-Lab/tpcc-mysql) .

| Benchmark | 8.0 | 8.0_PGO | improvement |
| ----------| ----- | ----- | ----- |
| Transactions | 922.20 | 990.43 | 7.40% |
| Latency avg (ms) | 21.68 | 20.19 | 6.87% |
| Latency 95p (ms) |63.32 | 57.87 | 8.61% |

It's also got some improvement on rocksdb oltp result even trained with innodb as db engine, about 14~24% on a test (copy some settings from network).

There also a seperate script named test_binary.sh can be used to test against [offical binary download from percona](https://www.percona.com/downloads/Percona-Server-LATEST/)

## Quick Start

### requirement

At least 4C/8G vm with 70G storage is need for build PGOed Percona Server 8.0, for 5.6 maybe 25G is enough, SSD is recommend for fast compiling and stable oltp-write result.

CentOS7 should be used (as percona official docker image use it).

Make sure your VM has internet connection or has http_proxy/https_proxy setted.

### check out

```bash
mkdir mysql-build
cd mysql-build
git clone https://github.com/bash99/pgobuild_percona_server.git pspgo-utils
```

### set build version

edit pspgo-utils/doall.sh, set version you want build. You can found right version number from [Percona Server Download](https://www.percona.com/downloads/Percona-Server-LATEST/), you can also try [5.6](https://www.percona.com/downloads/Percona-Server-5.6/LATEST/), [5.7](https://www.percona.com/downloads/Percona-Server-5.7/LATEST/).

```doall.sh
...
export MYSQL_VER=8.0
export MYSQL_MINI_VER=16-7
...
```

### do it in one step

```bash
bash pspgo-utils/doall.sh
```

Waiting it complete, you can have a dinner while it running build.

you 'll found a benchmark result file like 8.0_pgo_result.txt in current dir, and two minified package(remove mysql-test and striped debug-symbols) like mini_percona-server-8.0.15-6-pgo-linux-x86_64.tar.xz and mini_percona-server-8.0.15-6-linux-x86_64.tar.xz

please check 8.0_pgo_result.txt content to make sure PGO is worked. a success build should show good improvement in it like below

```txt
/tmp/8.0_normal_result.txt:    transactions:                        3084179 (61668.86 per sec.)
/tmp/8.0_normal_result.txt:    transactions:                        455523 (2846.61 per sec.)
/tmp/8.0_normal_result.txt:    transactions:                        226846 (1417.50 per sec.)
/tmp/8.0_pgoed_result.txt:    transactions:                        4746353 (94908.89 per sec.)
/tmp/8.0_pgoed_result.txt:    transactions:                        593600 (3709.64 per sec.)
/tmp/8.0_pgoed_result.txt:    transactions:                        278987 (1743.10 per sec.)
```

### use the package

The PGOed package like mini_percona-server-8.0.15-6-pgo-linux-x86_64.tar.xz can be used as a binary tarball to install mysql-server, the same as [official instruction](https://www.percona.com/doc/percona-server/8.0/installation.html#installing-percona-server-from-a-binary-tarball).

### 


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

