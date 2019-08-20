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

Although the profiling workload is not a tpcc like workload, it also get 7.4% improvement on transaction with [TPCC-Like Workload for Sysbench 1.0](https://github.com/Percona-Lab/tpcc-mysql) . (scale = 10 , tables = 10, so a 10G dataset)

| Benchmark | 8.0 | 8.0_PGO | improvement |
| ----------| ----- | ----- | ----- |
| Transactions | 922.20 | 990.43 | 7.40% |
| Latency avg (ms) | 21.68 | 20.19 | 6.87% |
| Latency 95p (ms) |63.32 | 57.87 | 8.61% |

It's also got some improvement on rocksdb oltp result even trained with innodb as db engine, about 14~24% on a test (copy some settings from network).

There also a seperate script named test_binary.sh can be used to test against offical binary download from percona, for example [5.6.44](https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.44-86.0/binary/tarball/Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz). You'll found the PGOed version show same improvement vs offical binary.

### quick test by your self

If you can not build by your self or want to try it fast, you can download binary built by me, [5.6.44-86.0](https://dl.ximen.bid/mini_percona-server-5.6.44-86.0-pgo-linux-x86_64.tar.xz), [5.7.26-29](https://dl.ximen.bid/mini_percona-server-5.7.26-29-pgo-linux-x86_64.tar.xz).
and official binary [5.6.44](https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.44-86.0/binary/tarball/Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz)

run bellow scripts to test results (assume you put pspgo-utils and binaries in same directory)

```bash
wget https://dl.ximen.bid/mini_percona-server-5.6.44-86.0-pgo-linux-x86_64.tar.xz
wget https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.44-86.0/binary/tarball/Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz
bash pspgo-utils/build-normal/test_binary.sh mini_percona-server-5.6.44-86.0-pgo-linux-x86_64.tar.xz "`pwd`/local/ps-5.6"
grep transactions /tmp/sb_test_bin_result.txt > pgo_result.txt
rm -rf "`pwd`/local/ps-5.6"
bash pspgo-utils/build-normal/test_binary.sh Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz `pwd`/local/ps-5.6
grep transactions /tmp/sb_test_bin_result.txt > normal_result.txt
cat pgo_result.txt normal_result.txt
```

### Stability

Binary build use 5.7.19 is running in production on about 100- servers for one and half years, no crash reported.

System avg loads decrease about 14% in first week.

## Quick Start

### requirement

At least 4C/8G vm with 70G storage is need for build PGOed Percona Server 8.0, for 5.6 maybe 25G is enough, SSD is recommend for fast compiling and stable oltp-write result.

CentOS7 should be used (as percona official docker image use it).

Make sure your VM has internet connection or has http_proxy/https_proxy setted.

Use a account with sudo permission to build.

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

### other build flags

edit build-opt/build_pgo.sh and build-normal/compile.sh, find all optflags line, change "-march=nehalem -mtune=haswell" to your hardware requirement, the default is ok for most server hardware after 2011.

## Usage in Detail

### Prepare

Scripts for set-up build enverionment is in [prepare/](prepare/).

install-devtoolset.sh is install devtoolset-7-gcc-c++ so we can use gcc 7

install-misc.sh is install devel libaries and cmake

scripts above is hard-coded to CentOS 7, if you want use this script on debian, you need custom it for your needs.

download-source.sh is downloading mysql and required boost libary source.

### Build Normal Binary

Scripts for normal build and some simple control is in [build-normal/](build-normal/).

init_conf.sh will generate a sample config for benchmark, which use tips from [17 KEY MYSQL CONFIG FILE SETTINGS (MYSQL 5.7 PROOF)](http://www.speedemy.com/17-key-mysql-config-file-settings-mysql-5-7-proof/), other key config for more real workload simulating is

```my.cnf
log_bin
character_set_server=utf8mb4
```

compile.sh is do actual compile.

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

## CopyRight

[GPL v2|V3](https://en.wikipedia.org/wiki/GNU_General_Public_License)
