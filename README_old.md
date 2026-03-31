# Percona Server Profile-Guided Optimization utils

> Historical README retained for reference. Download links, license notes, and workflow details in this file may be outdated; use `README.md` for current public guidance.

This project contains some help scripts to build a PGO version of [Percona Server for MySQL®](https://www.percona.com/software/mysql-database/percona-server) (5.6, 5.7, 8.0, 8.4).

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

## Docs Guide

- 快速验证与异常排查：`docs/pgo_validation_checklist.md`
- PGO 训练模式与默认策略：`docs/pgo_train_modes.md`
- 跨数据库（非 IO bound OLTP）PGO 抽象设计：`docs/pgo_crossdb_non_io_bound_oltp_design.md`
- 远程 PGO 执行流程：`docs/remote_pgo_workflow.md`
- 最新 `8.0` 小版本刷新方法：`docs/how_to_refresh_latest_8_0.md`

## Core Conclusion

- 详细验证与排查清单见 `docs/pgo_validation_checklist.md`。
- 目前已验证 `Percona Server 8.4 / 8.0 / 5.7 / 更早的 5.6` 在 `sysbench oltp readonly` 负载上，`PGO` 的常见有效提升区间大致在 `15% ~ 45%`。
- 已确认重构后的 `8.x` stage 可在远程 `AlmaLinux 9.7` 上完成 `Percona Server 8.4.7-7` 的 `normal + MeCab fulltext + PGO joint_read(train) + readonly(validate) + mini package` 全链路。
- 从 `2026-03-11` 起，常规 `profile-generate` 默认模式改为 `joint_read`，验证仍保持 `readonly`；原因与四模式矩阵见 `docs/pgo_train_modes.md`。
- 如果提升显著低于 `10%`，或显著高于 `100%`，通常都应视为异常信号；优先排查训练流程、profile 消费、结果解析、二进制混用、数据集一致性与环境稳定性，而不是直接接受结果。
- 后续做 PGO 验证时，先保证“结果可信”，再讨论“结果好不好看”。

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

If you can not build by your self or want to try it fast, the original historical text referenced private mirrors for prebuilt binaries. Those private mirror URLs have been removed from the public repository. Use GitHub Releases from the current project README instead.
and official binary [5.6.44](https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.44-86.0/binary/tarball/Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz)

run bellow scripts to test results (assume you have sudo permisson and at least 15G disk)

```bash
mkdir mysql-build
cd mysql-build
# historical private mirror URL removed
wget -c https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.44-86.0/binary/tarball/Percona-Server-5.6.44-rel86.0-Linux.x86_64.ssl101.tar.gz
export SYSBENCH_BASE=`pwd`/sysbench_bin
mkdir -p $SYSBENCH_BASE
# historical private mirror URL removed
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

you 'll found a benchmark result file like 8.0_pgo_result.txt in current dir, and two minified packages (with mysql-test and debug-symbols stripped) like:

- `Percona-Server-8.0.15-6-Normal.Linux.x86_64.<distro>.mini.tar.zst`
- `Percona-Server-8.0.15-6-PGOed.Linux.x86_64.<distro>.mini.tar.zst`

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

The PGOed package like `Percona-Server-8.0.19-10-PGOed.Linux.x86_64.almalinux8.mini.tar.zst` can be used as a binary tarball to install mysql-server, the same as [official instruction](https://www.percona.com/doc/percona-server/8.0/installation.html#installing-percona-server-from-a-binary-tarball).
Note it's packaged without big mysql-test directory, if you need it or want make some test, change build-normal/install_mini.sh and build-opt/make_package.sh

### Packaging convention

All generated mini packages follow this naming + compression convention:

- name: `Percona-Server-<version>-<Normal|PGOed>.Linux.<arch>.<distro>.mini.tar.zst`
  - example: `Percona-Server-8.0.45-36-PGOed.Linux.x86_64.almalinux8.mini.tar.zst`
  - `<distro>` defaults from `/etc/os-release` as `<id><major-version>` (for example `almalinux8`, `ubuntu22`)
- compression: `zstd -T0 -19`
- recommended local archive dir: `artifacts/Percona-Server-<version>/`
  - keep the `mini.tar.zst`, a `pgo-readonly-*.md`, and `install_<distro>.md` (dependency notes)

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

Current default policy:

- `PGO profile-generate`: `joint_read`
- `PGO validation benchmark`: `readonly`

If you need legacy behavior, you can still override with:

- `TRAIN_MODE=readonly` to keep old single-mode behavior
- or explicitly split with `PGO_TRAIN_MODE=...` and `PGO_BENCHMARK_MODE=...`

### Sysbench scripts

Scripts for Sysbench is in [sysbench/](sysbench/).

It contains scripts which download sysbench branch 1.0 from github and compile against current installed mysql, and do sysbench init and benchmark.

You can also use a pre-build sysbench binary which static linked againest libmysql.a to avoid this. (see scripts above)
set SYSBENCH_BASE to pre-build sysbench dir.

### Fulltext / MeCab support

The legacy scripts built `WITH_MECAB` when `mecab` headers were available, which is required for the MeCab fulltext parser path.

In the current stage-based flow:

- build-time MeCab detection is handled in `stages/build_normal_80.sh`
- Debian/Ubuntu install path installs `mecab`, `libmecab-dev`, and `mecab-ipadic`
- RHEL `7` keeps using Software Collections packages for the matching server major:
  - `Percona Server 5.7`: `centos-release-scl-rh`, `rh-mysql57-mecab`, `rh-mysql57-mecab-devel`
  - `Percona Server 8.0`: `centos-release-scl-rh`, `rh-mysql80-mecab`, `rh-mysql80-mecab-devel`
- RHEL / Alma / Rocky `8` and `9` use AppStream's generic MeCab packages instead of `rh-mysql80` / `rh-mysql84` packages:
  - `mecab`
  - `mecab-devel`
  - `mecab-ipadic`
- if MeCab packages are unavailable, `prepare` / build now fail by default
- use `--skip-fulltext-mecab` only when you explicitly want to build without MeCab fulltext parser support
- `MECAB_PREFIX` can still be provided explicitly if MeCab is installed in a non-standard prefix
- when MeCab lives outside the system default loader path, the `8.0` stage build now writes the detected MeCab library directory into build/install `RPATH`, so `libpluginmecab.so` can resolve `libmecab.so` without setting `LD_LIBRARY_PATH`

If MeCab-based fulltext support is required on a build host, ensure the required repositories are enabled and verify that `mecab.h` is present before starting the build.

### CentOS / AlmaLinux 8/9 install note

For `CentOS Stream 8`, `AlmaLinux 8`, and similar `RHEL 8` hosts, install dependencies from `BaseOS` + `AppStream` and make sure the MeCab development files are present:

Minimal packages for `MeCab fulltext + mini package compression`:

```bash
dnf install -y mecab mecab-devel mecab-ipadic zstd
```

```bash
dnf install -y \
  gcc gcc-c++ make git rsync curl ca-certificates gnupg2 \
  gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils \
  autoconf automake libtool pkgconfig bzip2 cmake numactl numactl-devel \
  libaio-devel ncurses-devel readline-devel libcurl-devel pam-devel \
  openssl-devel libtirpc-devel krb5-devel openldap-devel zlib-devel \
  cyrus-sasl-devel cyrus-sasl-scram bison tmux bc patch zip zstd \
  perl-Data-Dumper mecab mecab-devel mecab-ipadic
```

AlmaLinux 9 additional notes:

- enable `CRB` before installing `mecab-devel` and `mecab-ipadic`
- install `rpcgen` for `8.4` build requirements
- keep `LINKER_FLAVOR=default` for `PGO` on `gcc-toolset-12` hosts to avoid `ld.gold` linker failures

Validation points:

- `dnf provides '*/mecab.h'` should resolve to `mecab-devel`
- `rpm -ql mecab-devel | grep '/mecab.h$'` should show `/usr/include/mecab.h`
- `rpm -ql mecab | grep '/libmecab.so'` should show the shared library under `/usr/lib64`

### Remote AlmaLinux / SSH workflow

For remote build hosts such as `AlmaLinux 8` or `AlmaLinux 9`, use the dedicated helpers and workflow notes:

- if upstream source download is too slow on the remote host, rsync only the required unpacked source tree for the target version; still avoid sending unrelated local archives

- push tracked repo files + source tarballs only: `tools/remote_sync_to_host.sh`
- collect back results + packages only: `tools/remote_collect_results.sh`
- detailed workflow notes: `docs/remote_pgo_workflow.md`

This avoids copying `work/`, unpacked source trees, caches and other large host-local artifacts over SSH.

### New 8.0 startup and connection flow

For `MYSQL_VER=8.0` and `MYSQL_MINI_VER=44-35`, `run.sh -n` now uses the new stage flow under `stages/`:

1. build and install into `work/install/ps-8.0.44-35-normal`
2. initialize a fresh datadir under `work/runtime/ps-8.0.44-35-normal`
3. start `mysqld` and wait until `mysqladmin ping` succeeds
4. provision local `root` and `sbtest` accounts for smoke and future sysbench use
5. persist runtime metadata under `work/state/ps-8.0.44-35-normal`

Important runtime files:

- runtime state: `work/state/ps-8.0.44-35-normal/runtime.env`
- root client defaults: `work/runtime/ps-8.0.44-35-normal/etc/root-client.cnf`
- root password file: `work/state/ps-8.0.44-35-normal/root.password`
- sbtest password file: `work/state/ps-8.0.44-35-normal/sbtest.password`
- socket: `work/runtime/ps-8.0.44-35-normal/run/mysql.sock`
- error log: `work/runtime/ps-8.0.44-35-normal/log/mysql.err.log`

Typical local connection checks:

```bash
source work/state/ps-8.0.44-35-normal/runtime.env

work/install/ps-8.0.44-35-normal/bin/mysql \
  --defaults-extra-file="$MYSQL_ROOT_DEFAULTS_FILE" \
  -e 'SELECT VERSION(), @@socket'

work/install/ps-8.0.44-35-normal/bin/mysql \
  --protocol=socket \
  --socket="$MYSQL_SOCKET" \
  --user=sbtest \
  --password="$(cat "$MYSQL_SBTEST_PASSWORD_FILE")" \
  -e 'SELECT CURRENT_USER()'
```

This flow intentionally avoids writing `~/.my.cnf`. All one-shot build credentials and connection state stay under `work/runtime/` and `work/state/`.

Shutdown example:

```bash
source work/state/ps-8.0.44-35-normal/runtime.env

work/install/ps-8.0.44-35-normal/bin/mysqladmin \
  --defaults-extra-file="$MYSQL_ROOT_DEFAULTS_FILE" \
  shutdown
```

After shutdown, you can confirm the server is down by checking that `$MYSQL_SOCKET` and `$MYSQL_PID_FILE` are no longer active, or by running `ps` against the recorded pid.

### Binary for more Test
The original historical text referenced additional private mirror downloads here. Those private mirror URLs have been removed from the public repository.

## CopyRight

This historical README originally stated that the project used GPL-style licensing. The current repository license is now defined by the root `LICENSE` file instead.

MySQL and Percona Server is on their own License like Copyright (c) 2000, 2020, Oracle and/or its affiliates.
