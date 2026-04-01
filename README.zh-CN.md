[English README](README.md)

# pgobuild_percona_server

这是一个面向 `Percona Server` 的 PGO 构建、压测、打包与发布仓库。

这个项目的核心目的，是用一种足够通用、且明确保持为非 I/O bound 的 OLTP 读负载来训练 GCC Profile-Guided Optimization，然后编译出在这类负载上明显更快的 `Percona Server` 二进制。默认训练路径使用 sysbench 的 `point_select` 与 `read_only` 读路径，并尽量保证压测是 CPU-bound，而不是被磁盘吞吐主导。

目标不是为了某一个过窄的 synthetic case 做过拟合，而是希望得到一个对通用 OLTP 读负载有显著提升、并且在不少混合 `read_write` 场景里也依然受益的版本。

这个仓库由社区维护，不是 Percona 官方发布渠道。

## 为什么这里的 PGO 有意义

GCC PGO 的基本流程就是三步：

1. 先做 instrumented build
2. 用有代表性的 OLTP 负载跑训练，生成 profile
3. 再做 `profile-use` 重编译

对于 MySQL / Percona 这样的 OLTP 引擎，这份运行时 profile 能帮助编译器更好地优化热点路径上的 inline、代码布局和分支行为。本仓库通过 `run.sh` 把整条链路串起来：准备环境、下载源码、normal build、profile-generate build、sysbench 训练、profile-use rebuild、结果验证，以及 mini tarball 打包。

当前默认策略：

- `PGO_TRAIN_MODE=joint_read`
- `PGO_BENCHMARK_MODE=readonly`

## 性能结果概览

目前公开 release 的证据表明，在读密集 OLTP 负载上，这套方法已经多次得到大约 `+28%` 到 `+62%` 的提升，具体取决于版本和引擎。

| 版本 | 环境 | 公开结果 | 链接 |
| --- | --- | --- | --- |
| `8.4.8-8` | `AlmaLinux 9` | `read_only +49.61%`，`point_select +58.53%` | [release](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.4.8-8)，[result](https://github.com/bash99/pgobuild_percona_server/releases/download/8.4.8-8/pgo-readonly-8.4.8-8-rdb-both-20260317.md) |
| `8.0.45-36` | `AlmaLinux 8`，`WITH_ROCKSDB=ON` | `InnoDB read_only +42.72%`，`RocksDB read_only +62.19%` | [release](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.0.45-36)，[result](https://github.com/bash99/pgobuild_percona_server/releases/download/8.0.45-36/pgo-readonly-8.0.45-36-rdb-both-20260318.md) |
| `5.7.44-54` | `CentOS 7` | `read_only +28.29%`，`point_select +28.34%` | [release](https://github.com/bash99/pgobuild_percona_server/releases/tag/5.7.44-54)，[result](https://github.com/bash99/pgobuild_percona_server/releases/download/5.7.44-54/pgo-readonly-5.7.44-54-20260309.md) |

混合读写负载也并不是完全没有收益：

- 项目历史里的 `8.0 read_write` 结果曾经达到约 `+22.97%`
- 当前 Docker 对比官方镜像的 head-to-head 测试里，`read_write` 也出现了 `+3.39% ~ +21.38%` 的提升

## 快速自行验证

如果只是想快速验证，Docker 往往比下载 tarball 再手动安装更直接。

Docker Hub 地址：

- <https://hub.docker.com/r/bash99/percona-server-8.4-pgoed>

当前已发布镜像 tag：

- `bash99/percona-server-8.4-pgoed:8.4.8-8`
- `bash99/percona-server-8.4-pgoed:8.4`

对应 GitHub Release：

- [Percona Server 8.4.8-8 release](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.4.8-8)

基本 smoke test：

```bash
docker pull bash99/percona-server-8.4-pgoed:8.4.8-8

docker run --name ps8488 --rm \
  -e MYSQL_ROOT_PASSWORD=root \
  -p 13306:3306 -p 13360:33060 \
  -d bash99/percona-server-8.4-pgoed:8.4.8-8

docker exec -it ps8488 mysql -uroot -proot -e "SELECT VERSION();"
```

预期版本：

- `8.4.8-8`

如果你还想顺手验证 MyRocks：

```bash
docker exec -it ps8488 mysql -uroot -proot \
  -e "INSTALL PLUGIN ROCKSDB SONAME 'ha_rocksdb.so'; SHOW PLUGINS LIKE 'ROCKSDB';"
```

镜像功能验证记录：

- [docker/percona-server-8.4-pgoed/verification.md](docker/percona-server-8.4-pgoed/verification.md)

## Docker 性能快速对比

如果你想快速验证“和官方镜像相比到底快多少”，可以直接运行仓库里的 head-to-head sysbench 脚本：

```bash
git clone https://github.com/bash99/pgobuild_percona_server.git
cd pgobuild_percona_server

PGOED_IMAGE=bash99/percona-server-8.4-pgoed:8.4.8-8 \
OFFICIAL_IMAGE=percona/percona-server:8.4.7-7.1 \
bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh
```

这套 harness 当前给出的结果摘要：

- `point_select`：约 `+32.74% ~ +37.16%`
- `read_only`：约 `+26.09% ~ +31.94%`
- `read_write`：约 `+3.39% ~ +21.38%`

相关文档：

- [docker/percona-server-8.4-pgoed/bench/README.md](docker/percona-server-8.4-pgoed/bench/README.md)
- [docker/percona-server-8.4-pgoed/bench/report-sysbench-vs-official-8.4.7-7.1.md](docker/percona-server-8.4-pgoed/bench/report-sysbench-vs-official-8.4.7-7.1.md)

## Release 下载

GitHub Releases 是当前公开二进制的主下载入口：

- releases 页面：<https://github.com/bash99/pgobuild_percona_server/releases>
- latest shortcut：<https://github.com/bash99/pgobuild_percona_server/releases/latest>

当前 release 资产命名规则：

- `Percona-Server-<version>-PGOed.Linux.x86_64.<distro>.mini.tar.zst`
- `SHA256SUMS.txt`
- 对应的 benchmark 摘要，例如 `pgo-readonly-<version>-<date>.md`

当前已发布版本：

| 版本 | 平台 | Tarball | Benchmark 摘要 |
| --- | --- | --- | --- |
| [`8.4.8-8`](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.4.8-8) | `AlmaLinux 9` | [download](https://github.com/bash99/pgobuild_percona_server/releases/download/8.4.8-8/Percona-Server-8.4.8-8-PGOed.Linux.x86_64.almalinux9.mini.tar.zst) | [summary](https://github.com/bash99/pgobuild_percona_server/releases/download/8.4.8-8/pgo-readonly-8.4.8-8-rdb-both-20260317.md) |
| [`8.0.45-36`](https://github.com/bash99/pgobuild_percona_server/releases/tag/8.0.45-36) | `AlmaLinux 8` | [download](https://github.com/bash99/pgobuild_percona_server/releases/download/8.0.45-36/Percona-Server-8.0.45-36-PGOed.Linux.x86_64.almalinux8.mini.tar.zst) | [summary](https://github.com/bash99/pgobuild_percona_server/releases/download/8.0.45-36/pgo-readonly-8.0.45-36-rdb-both-20260318.md) |
| [`5.7.44-54`](https://github.com/bash99/pgobuild_percona_server/releases/tag/5.7.44-54) | `CentOS 7` | [download](https://github.com/bash99/pgobuild_percona_server/releases/download/5.7.44-54/Percona-Server-5.7.44-54-PGOed.Linux.x86_64.centos7.mini.tar.zst) | [summary](https://github.com/bash99/pgobuild_percona_server/releases/download/5.7.44-54/pgo-readonly-5.7.44-54-20260309.md) |

## Stability

当前可以公开给出的稳定性说明是：

- 历史信号：项目早期一版基于 `5.7.19` 的 PGO 二进制，曾在大约 `100+` 台生产机器上运行约 `1.5 年`，没有 crash report
- 当前发布标准：只有在 smoke test、运行时身份检查、profile generation 检查、profile-use 检查、benchmark 一致性检查都通过之后，构建结果才会被视为可发布
- 实际使用建议：这仍然是社区构建版，在进入生产前，建议按你自己的系统版本、配置和 workload 做基准与灰度验证

可参考：

- [docs/pgo_validation_checklist.md](docs/pgo_validation_checklist.md)
- [docs/pgo_train_modes.md](docs/pgo_train_modes.md)

## 从源码构建

克隆仓库：

```bash
git clone https://github.com/bash99/pgobuild_percona_server.git
cd pgobuild_percona_server
```

设置目标版本：

```bash
export MYSQL_VER=8.4
export MYSQL_MINI_VER=8-8
export WORK_ROOT="$PWD/work"
```

执行完整流程：

```bash
bash run.sh -i -d -n -p
```

说明：

- 参数要分开传
- `-i` 安装依赖，通常需要 `sudo`
- `-d` 下载源码
- `-n` 执行 normal build / smoke / benchmark / package
- `-p` 执行 PGO build / benchmark / package

## 常用环境变量

| 变量 | 含义 |
| --- | --- |
| `MYSQL_VER` | 主版本，例如 `5.7`、`8.0`、`8.4` |
| `MYSQL_MINI_VER` | 上游 Percona 小版本号，例如 `45-36`、`8-8` |
| `WORK_ROOT` | build / runtime / benchmark 工作目录 |
| `CPU_OPT_FLAGS` | 额外 CPU 优化参数 |
| `WITH_ROCKSDB` | 设为 `ON` 时启用 RocksDB 构建 |
| `ENABLE_LTO` | 设为 `ON` 时启用 LTO |
| `SKIP_FULLTEXT_MECAB` | 设为 `ON` 时跳过 MeCab 相关 fulltext 构建路径 |
| `PGO_TRAIN_MODE` | 覆盖 PGO 训练 workload |
| `PGO_BENCHMARK_MODE` | 覆盖 PGO 验证 workload |

## 支持矩阵

| Percona Server | 状态 | 说明 |
| --- | --- | --- |
| `8.4` | 主线支持 | 当前 release 与 Docker 的主目标 |
| `8.0` | 主线支持 | 当前 release 的主目标 |
| `5.7` | 维护中的历史目标 | 仍保留 `CentOS 7` 风格环境验证 |
| `5.6` | 历史 / 收尾目标 | 后续可能补最后一个 `CentOS 7` 兼容 build |

## 文档索引

- [ROADMAP.md](ROADMAP.md)
- [docs/pgo_validation_checklist.md](docs/pgo_validation_checklist.md)
- [docs/pgo_train_modes.md](docs/pgo_train_modes.md)
- [docs/pgo_crossdb_non_io_bound_oltp_design.md](docs/pgo_crossdb_non_io_bound_oltp_design.md)
- [docker/percona-server-8.4-pgoed/README.md](docker/percona-server-8.4-pgoed/README.md)
- [docs/release_upload_workflow.md](docs/release_upload_workflow.md)

## License

仓库中的脚本与文档采用 [MIT](LICENSE)。

`Percona Server` 本体及其 bundled 第三方组件仍遵循各自上游许可证。

## 历史 README

旧版 README 保存在 [README_old.md](README_old.md)。
