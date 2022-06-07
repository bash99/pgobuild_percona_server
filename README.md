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

It got about 20-40% improvement on oltp benchmarks (read_only or read_write).
update: more improvement on 8.0 with link time optimization (gcc -flto), another 5-20%

| TPS | 5.6	| 5.6_PGO	| improvement	| 5.7	| 5.7_PGO	| improvement	|8.0	| 8.0_PGO	| improvement |
| ----------| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |
| point_select| 70106.22	|92630.52	|32.13%	|70180.87	|100511.44	|43.22%	|61668.86	|94908.89	|53.90% |
| read_only |1969.35	|2537.66	|28.86%	|2404.53	|3229.28	|34.30%	|2846.61	|3709.64	|30.32% |
| read_write |1387.48    |1780.91	|28.36%	|1596.53	|2246.4	|40.71%	|1417.5	|1743.1	|22.97% |

Hardware: 8 Core 16G VM and 100G SSD, use a 4.8G memory pool and 7.7G dataset (2M table size, 16 tables), with 16 oltp threads.

Although the profiling workload is not a tpcc like workload, it also get 7.4% improvement on transaction with [TPCC-Like Workload for Sysbench 1.0](https://github.com/Percona-Lab/tpcc-mysql) . (scale = 10 , tables = 10, so a 10G dataset)

| Benchmark | 8.0 | 8.0_PGO | improvement |
| ----------| ----- | ----- | ----- |
| Transactions | 922.20 | 990.43 | 7.40% |
| Latency avg (ms) | 21.68 | 20.19 | 6.87% |
| Latency 95p (ms) |63.32 | 57.87 | 8.61% |

It's also got some improvement on rocksdb oltp result even trained with innodb as db engine, about 14~24% on a test (copy some settings from network).

There also a seperate script named test_binary.sh can be used to test against offical binary download from percona, for example [5.6.44](https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.44-86.0/binary/tarball/Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz). You'll found the PGOed version show same improvement vs offical binary.

### quick test by your self

If you can not build by your self or want to try it fast, you can download binary built by me, [5.6.44-86.0](https://dl.ximen.bid/pgoed_percona-server/mini_percona-server-5.6.48-86.0-pgo-linux-x86_64.tar.xz), [5.7.37-40](https://dl.ximen.bid/mysqlpgo/mini_percona-server-5.7.37-40-linux-x86_64-pgoed_centos7.tar.xz). (centos7 binary)
and official binary [5.6.44](https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.44-86.0/binary/tarball/Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz)

run bellow scripts to test results (assume you have sudo permisson and at least 15G disk)

```bash
mkdir mysql-build
cd mysql-build
wget -c https://dl.ximen.bid/pgoed_percona-server/mini_percona-server-5.6.44-86.0-pgo-linux-x86_64.tar.xz
wget -c https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.44-86.0/binary/tarball/Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz
export SYSBENCH_BASE=`pwd`/sysbench_bin
mkdir -p $SYSBENCH_BASE
curl -L -q https://dl.ximen.bid/pgoed_percona-server/sysbench-1.17.static.tar.xz | tar -Jxf - -C $SYSBENCH_BASE --strip-components=1
git clone https://github.com/bash99/pgobuild_percona_server.git pspgo-utils
## make sure you has required rpm installed
sudo pspgo-utils/prepare/install-misc.sh
sudo pspgo-utils/prepare/init_syslimit.sh
export MYSQL_VER=5.6
export MYSQL_BASE="`pwd`/local/ps-$MYSQL_VER"
rm -rf "$MYSQL_BASE"
bash `pwd`/pspgo-utils/build-normal/test_binary.sh mini_percona-server-5.6.44-86.0-pgo-linux-x86_64.tar.xz "$MYSQL_BASE" $MYSQL_VER
grep transactions /tmp/sb_test_bin_result.txt > pgo_result.txt
rm -rf "$MYSQL_BASE"
bash pspgo-utils/build-normal/test_binary.sh Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz "$MYSQL_BASE" $MYSQL_VER
grep transactions /tmp/sb_test_bin_result.txt > normal_result.txt
grep trans pgo_result.txt normal_result.txt
```

result from a aws c3large box (2c 3.75G 512M swap 16Gssd*2 as raid0)

```txt
pgo_result.txt:    transactions:                        1330627 (26608.29 per sec.)
pgo_result.txt:    transactions:                        114073 (712.86 per sec.)
pgo_result.txt:    transactions:                        80200  (501.13 per sec.)
normal_result.txt:    transactions:                        905104 (18099.37 per sec.)
normal_result.txt:    transactions:                        84038  (525.16 per sec.)
normal_result.txt:    transactions:                        61317  (383.12 per sec.)
```

### Stability

Binary build use 5.7.19 is running in production on about 100- servers for one and half years, no crash reported.

System avg load decreased about 14% in first week.

## Quick Start

### requirement

At least 4C/16G vm with 100G storage is need for build PGOed Percona Server 8.0 (with 30G for /tmp is required for compile with -flto flags), for 5.6 maybe 2c/4G 25G is enough (without LTO), SSD is recommend for fast compiling and stable oltp-write result.

CentOS7 should be used (as percona official docker image use it). 
Updated: I've also fix script for debian 10/centos7, it should be worked.

Make sure your VM has internet connection or has http_proxy/https_proxy setted.

Use a account with sudo permission to build.

### check out

```bash
mkdir mysql-build
cd mysql-build
git clone https://github.com/bash99/pgobuild_percona_server.git pspgo-utils
```

### set build version

export env to set version you want build. You can found right version number from [Percona Server Download](https://www.percona.com/downloads/Percona-Server-LATEST/), you can also try [5.6](https://www.percona.com/downloads/Percona-Server-5.6/LATEST/), [5.7](https://www.percona.com/downloads/Percona-Server-5.7/LATEST/).

```sh
export MYSQL_VER=8.0
export MYSQL_MINI_VER=19-10
```

### do it in one step

```bash
bash pspgo-utils/run.sh -idnp
```

Waiting it complete, you can have a dinner while it running build; it took 4 hour in a 8c 16G VM for 8.0 with flto, need 1 hour for 5.6.

you 'll found a benchmark result file like 8.0_pgo_result.txt in current dir, and two minified package(with mysql-test and debug-symbols striped) like mini_percona-server-8.0.15-6-pgo-linux-x86_64.tar.xz and mini_percona-server-8.0.15-6-linux-x86_64.tar.xz

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

The PGOed package like mini_percona-server-8.0.19-10-pgo-linux-x86_64.tar.xz can be used as a binary tarball to install mysql-server, the same as [official instruction](https://www.percona.com/doc/percona-server/8.0/installation.html#installing-percona-server-from-a-binary-tarball).
Note it's packaged without big mysql-test directory, if you need it or want make some test, change build-normal/install_mini.sh and build-opt/make_package.sh

### other build flags
export CPU_OPT_FLAGS="you hardware requirement", the default is "-march=nehalem -mtune=haswell", which is ok for most intel server hardware after 2011, also try on AMD zen1 cpu on aws m5a.large, which still show good benchmark result. But this nehalem flags is not test with AMD cpu on production.

## Usage in Detail

### Prepare

Scripts for set-up build enverionment is in [prepare/](prepare/).

```bash pspgo-utils/run.sh -i``` do things below: 
* install-devtoolset.sh is install devtoolset-9-gcc-c++ so we can use gcc 9
* install-misc.sh is install devel libaries and cmake3
* init_syslimit.sh set file and memorylock limits for mysql/current user
* scripts above is hard-coded to CentOS 7, if you want use this script on debian, you need custom it for your needs. Maybe I'll release a debian 10/centos 7 version with ansible playbook.

```bash pspgo-utils/run.sh -d``` do things below: 
* download-source.sh is downloading mysql [ and required boost libary source ].

### Build Normal Binary

Scripts for normal build and some simple control is in [build-normal/](build-normal/).

```bash pspgo-utils/run.sh -n``` do things below: 
* init_conf.sh will generate a sample config for benchmark, which use tips from [17 KEY MYSQL CONFIG FILE SETTINGS (MYSQL 5.7 PROOF)](http://www.speedemy.com/17-key-mysql-config-file-settings-mysql-5-7-proof/)
* other key config for more real workload simulating is
    ```my.cnf
    log_bin
    character_set_server=utf8mb4
    ```
* compile.sh is do actual compile.

You can check [doall.sh](build-normal/doall.sh) for all steps

### Build PGO Binary

Scripts for PGO build is in [build-opt/](build-opt/).

build_pgo.sh is the real part of this utils, which use scripts from build-normal to

1. instrumented compilation
2. profiled execution
3. optimization compile

make_package.sh is utils to make binary package, and remove PGO related flags from mysql libary.

### Sysbench scripts

Scripts for Sysbench is in [sysbench/](sysbench/).

It contains scripts which download sysbench branch 1.0 from github and compile against current installed mysql, and do sysbench init and benchmark.

You can also use a pre-build sysbench binary which static linked againest libmysql.a to avoid this. (see scripts above)
set SYSBENCH_BASE to pre-build sysbench dir.

### Binary for more Test
there are [more mini binarys](https://dl.ximen.bid/mysqlpgo/) build for centos7 or debian 10.

## CopyRight

This utils is under [GPL v2|V3](https://en.wikipedia.org/wiki/GNU_General_Public_License)

MySQL and Percona Server is on their own License like Copyright (c) 2000, 2020, Oracle and/or its affiliates.
