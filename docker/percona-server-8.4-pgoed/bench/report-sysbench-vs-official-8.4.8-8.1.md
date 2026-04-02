# Sysbench head-to-head: `ps-8.4.8-8-pgoed` vs `percona/percona-server:8.4.8-8.1`

## Summary

- date: `2026-04-02`
- goal: 本机环境对 `PGOed` 镜像与 Percona 官方同版本镜像做 head-to-head `sysbench` 对比（`point_select / read_only / read_write`）
- run id: `20260402-111042`
- artifacts root: `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/`
- conclusion (TPS, higher is better):
  - `point_select`: `+34.56% ~ +43.98%`
  - `read_only`: `+31.08% ~ +37.50%`
  - `read_write`: `+6.56% ~ +18.58%`

## Testbed / Identity

Host snapshot:

- `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/env.md`

Images:

- official: `percona/percona-server:8.4.8-8.1`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/official/image-inspect.json`
- pgoed: `ps-8.4.8-8-pgoed:latest`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/pgoed/image-inspect.json`

Server version snapshots:

- official: `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/official/server-version.txt`
- pgoed: `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/pgoed/server-version.txt`

说明：

- 官方 Docker tag 为 `8.4.8-8.1`，容器内 `mysqld` 版本字符串为 `8.4.8-8`
- 本次 PGO 镜像为本机已有的 `ps-8.4.8-8-pgoed:latest`

## Config / Parameters

Benchmark my.cnf（两边共用）：

- `docker/percona-server-8.4-pgoed/bench/zz-benchmark.cnf`

本次 run 参数快照：

- `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/params.env`

关键点：

- `innodb_buffer_pool_size`: `5368709120`（约 `5GiB`，两边一致）
- `performance_schema=OFF`
- `innodb_flush_log_at_trx_commit=2` + `sync_binlog=0` + `skip-log-bin`（降低 durability / I/O 噪声）
- `innodb_flush_method=O_DIRECT`（避免 OS page cache 干扰）
- sysbench client：`perconalab/sysbench:latest` (`sysbench 1.1.0`)
- sysbench 连接使用 `--mysql-ssl=required`：`caching_sha2_password` 需要安全连接（两边一致）

## Dataset Size / Non-I/O Bound Check

数据集参数：

- `tables=16`
- `table_size=500000`（总计 `8,000,000` 行）

准备完成后测得的（`data+index`）大小：

- official: `1036.8 MB`（`docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/official/dataset-size-mb.txt`）
- pgoed: `1022.8 MB`（`docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/pgoed/dataset-size-mb.txt`）

说明：

- `innodb_buffer_pool_size (~5GiB)` 显著大于数据集（约 `1.0GiB`），因此 `point_select/read_only` 在 warmup 之后应主要为 CPU-bound
- `read_write` 仍会产生 redo/flush 写入，整体提升仍明显低于只读 workload

采样证据（每个 workload/threads 都有一份 `vmstat/iostat/pidstat`）：

- official samples: `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/official/samples/`
- pgoed samples: `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/pgoed/samples/`

建议先快速核验两个只读 workload 的 `vmstat`，再看 `read_write` 的波动：

- official:
  - `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/official/samples/point_select_t16/vmstat.log`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/official/samples/read_only_t16/vmstat.log`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/official/samples/read_write_t16/vmstat.log`
- pgoed:
  - `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/pgoed/samples/point_select_t16/vmstat.log`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/pgoed/samples/read_only_t16/vmstat.log`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/pgoed/samples/read_write_t16/vmstat.log`

## Results (TPS)

完整汇总（自动解析生成）：

- markdown: `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/summary.md`
- json: `docker/percona-server-8.4-pgoed/bench/runs/20260402-111042/summary.json`

### `point_select`

| threads | official tps | pgoed tps | delta tps | official avg ms | pgoed avg ms | official p95 ms | pgoed p95 ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 7885.99 | 11033.39 | +39.91% | 0.13 | 0.09 | 0.18 | 0.12 |
| 4 | 23640.09 | 34036.02 | +43.98% | 0.17 | 0.12 | 0.23 | 0.15 |
| 8 | 23936.15 | 32754.13 | +36.84% | 0.33 | 0.24 | 0.70 | 0.62 |
| 16 | 24229.94 | 32604.53 | +34.56% | 0.66 | 0.49 | 1.79 | 1.42 |

### `read_only`

| threads | official tps | pgoed tps | delta tps | official avg ms | pgoed avg ms | official p95 ms | pgoed p95 ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 374.58 | 515.05 | +37.50% | 2.67 | 1.94 | 3.13 | 2.30 |
| 4 | 1189.99 | 1616.86 | +35.87% | 3.36 | 2.47 | 4.91 | 3.36 |
| 8 | 1263.64 | 1656.34 | +31.08% | 6.33 | 4.83 | 12.30 | 10.84 |
| 16 | 1257.09 | 1652.27 | +31.44% | 12.72 | 9.68 | 29.19 | 25.74 |

### `read_write`

| threads | official tps | pgoed tps | delta tps | official avg ms | pgoed avg ms | official p95 ms | pgoed p95 ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 237.41 | 281.53 | +18.58% | 4.21 | 3.55 | 4.82 | 3.89 |
| 4 | 535.95 | 571.10 | +6.56% | 7.46 | 7.00 | 10.84 | 10.46 |
| 8 | 530.63 | 585.76 | +10.39% | 15.07 | 13.65 | 33.72 | 33.72 |
| 16 | 592.92 | 641.98 | +8.27% | 26.96 | 24.80 | 81.48 | 74.46 |

## How To Reproduce

一键复跑（会拉镜像、初始化数据集、warmup、跑 3 workloads，并生成 summary）：

```bash
OFFICIAL_IMAGE=percona/percona-server:8.4.8-8.1 \
PGOED_IMAGE=ps-8.4.8-8-pgoed:latest \
bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh
```

如需复跑并保留同一 run id（例如分两段跑 official / pgoed）：

```bash
RUN_ID=20260402-111042 RUN_VARIANTS=official \
OFFICIAL_IMAGE=percona/percona-server:8.4.8-8.1 \
PGOED_IMAGE=ps-8.4.8-8-pgoed:latest \
bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh

RUN_ID=20260402-111042 RUN_VARIANTS=pgoed \
OFFICIAL_IMAGE=percona/percona-server:8.4.8-8.1 \
PGOED_IMAGE=ps-8.4.8-8-pgoed:latest \
bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh
```
