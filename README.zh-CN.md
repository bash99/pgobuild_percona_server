[English README / 英文说明](README.md)

# pgobuild_percona_server

这是一个社区维护的仓库，用来构建、压测、打包并验证带 `PGO` 的 `Percona Server` 二进制。

它不是 Percona 官方发布渠道。

## 仓库能力

- 准备支持发行版上的构建环境
- 下载 `Percona Server` 源码包
- 构建 normal / PGOed 二进制
- 用 `sysbench` 做基准测试
- 生成可发布的精简二进制 tarball
- 保留可公开引用的 benchmark / package 证据

主入口脚本是 `run.sh`。

## 已验证矩阵

| Percona Server | 状态 | 公开参考 |
| --- | --- | --- |
| `8.4` | 主线支持 | [8.4.8-8 PGO + Docker](task_archives/8.4.8-8-alma9-pgo-docker-completed.md), [8.4.8-8 RocksDB 验证](artifacts/Percona-Server-8.4.8-8-rocksdb/pgo-readonly-8.4.8-8-rdb-both-20260317.md) |
| `8.0` | 主线支持 | [8.0.45-36 RocksDB 验证](artifacts/Percona-Server-8.0.45-36-rocksdb/pgo-readonly-8.0.45-36-rdb-both-20260318.md) |
| `5.7` | 维护中的历史目标 | [5.7.44-54 readonly PGO 恢复](task_archives/5.7.44-54-centos7-readonly-pgo-fixed.md) |
| `5.6` | 历史 / 收尾目标 | 目前不作为主线支持对象，但计划补一个面向 `CentOS 7` 风格环境的最后版本说明 |

更高层的公开路线见 [ROADMAP.md](ROADMAP.md)。

## 性能结论摘录

| 目标 | 范围 | 结果 |
| --- | --- | --- |
| `8.4.8-8` | `AlmaLinux 9` 上的 readonly PGO | `read_only +49.61%`，`point_select +58.53%` |
| `8.0.45-36` | `WITH_ROCKSDB=ON` 的双引擎训练 | `InnoDB read_only +42.72%`，`RocksDB read_only +62.19%` |
| `5.7.44-54` | `CentOS 7` 兼容环境上的 readonly PGO 恢复 | `read_only +28.29%`，`point_select +28.34%` |

公开仓库只保留脱敏后的证据摘要，完整维护者运行日志不放在 public tree 中。

## 下载与发布

预编译二进制以 GitHub Releases 作为主下载入口：

- releases 页面：<https://github.com/bash99/pgobuild_percona_server/releases>
- latest shortcut：<https://github.com/bash99/pgobuild_percona_server/releases/latest>

预计发布资产命名：

- `Percona-Server-<version>-PGOed.Linux.x86_64.<distro>.mini.tar.zst`
- `SHA256SUMS.txt`
- 对应结果摘要，例如 `pgo-readonly-<version>-<date>.md`

README 不再保留任何私人下载镜像地址。

## 快速开始

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

注意：

- 参数要分开传，不再使用历史 README 里的 `-idnp` 组合写法
- `-i` 会安装依赖，通常需要 `sudo`
- `-d` 会下载源码包
- `-n` 会执行 normal build / smoke / benchmark / package
- `-p` 会执行 PGO build / benchmark / package

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

当前默认 PGO 策略：

- `PGO_TRAIN_MODE=joint_read`
- `PGO_BENCHMARK_MODE=readonly`

原因见 [docs/pgo_train_modes.md](docs/pgo_train_modes.md)。

## Docker

公开 release 对应的镜像计划发布到 Docker Hub，同时仓库内保留本地可复现的 Docker recipe，保证即使没有预制镜像也能从 release asset 重建。

- Docker recipe: [docker/percona-server-8.4-pgoed/README.md](docker/percona-server-8.4-pgoed/README.md)
- 验证记录: [docker/percona-server-8.4-pgoed/verification.md](docker/percona-server-8.4-pgoed/verification.md)
- Docker 对 Docker 的 sysbench 对比: [docker/percona-server-8.4-pgoed/bench/README.md](docker/percona-server-8.4-pgoed/bench/README.md)

当前 Docker recipe 默认面向 `8.4.8-8`，并依赖对应的 PGOed `mini.tar.zst` release asset。

## 文档索引

- [ROADMAP.md](ROADMAP.md)
- [docs/pgo_validation_checklist.md](docs/pgo_validation_checklist.md)
- [docs/pgo_train_modes.md](docs/pgo_train_modes.md)
- [docs/remote_pgo_workflow.md](docs/remote_pgo_workflow.md)
- [docs/how_to_refresh_latest_8_0.md](docs/how_to_refresh_latest_8_0.md)
- [task_archives/README.md](task_archives/README.md)

## License

仓库中的脚本与文档采用 [MIT](LICENSE)。

`Percona Server` 本体及其 bundled 第三方组件仍遵循各自上游许可证。

## 历史 README

旧版 README 保存在 [README_old.md](README_old.md)。
