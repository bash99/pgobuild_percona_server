# Sysbench head-to-head: `ps-8.4.7-pgoed` vs `percona/percona-server:8.4.7-7.1`

> Historical report retained for reference. Current same-version checks should be rerun against `percona/percona-server:8.4.8-8`.

## Summary

- date: `2026-03-14`
- goal: 本机环境对 `PGOed` 镜像与 Percona 官方镜像做 head-to-head `sysbench` 对比（`point_select / read_only / read_write`）
- run id: `20260314-133201`
- artifacts root: `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/`
- conclusion (TPS, higher is better):
  - `point_select`: `+32.74% ~ +37.16%`
  - `read_only`: `+26.09% ~ +31.94%`
  - `read_write`: `+3.39% ~ +21.38%`（写入路径受 redo/flush 影响更明显，提升较小且更易抖动）

## Testbed / Identity

Host snapshot:

- `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/env.md`

Images:

- official: `percona/percona-server:8.4.7-7.1`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/official/image-inspect.json`
- pgoed: `ps-8.4.7-pgoed:latest`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/pgoed/image-inspect.json`

Server version snapshots:

- official: `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/official/server-version.txt`
- pgoed: `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/pgoed/server-version.txt`

## Config / Parameters

Benchmark my.cnf（两边共用）：

- `docker/percona-server-8.4-pgoed/bench/zz-benchmark.cnf`

本次 run 参数快照：

- `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/params.env`

关键点：

- `innodb_buffer_pool_size`: `5368709120`（约 `5GiB`，两边一致）
- `performance_schema=OFF`
- `innodb_flush_log_at_trx_commit=2` + `sync_binlog=0` + `skip-log-bin`（降低 durability / I/O 噪声）
- `innodb_flush_method=O_DIRECT`（避免 OS page cache 干扰）
- sysbench client：`perconalab/sysbench:latest` (`sysbench 1.1.0`)
- sysbench 连接使用 `--mysql-ssl=required`：`caching_sha2_password` 需要安全连接（两边一致）

## Dataset size / Non-I/O bound check

数据集参数：

- `tables=16`
- `table_size=500000`（总计 `8,000,000` 行）

准备完成后测得的（`data+index`）大小：

- official: `1267.5 MB`（`docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/official/dataset-size-mb.txt`）
- pgoed: `1082.4 MB`（`docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/pgoed/dataset-size-mb.txt`）

说明：

- `innodb_buffer_pool_size (~5GiB)` 显著大于数据集（~`1.1 ~ 1.3GiB`），因此 `point_select/read_only` 在 warmup 之后应主要为 CPU-bound。
- `read_write` 仍会产生 redo/flush 写入，采样中可见一定 `iowait` 波动；这也是该 workload 提升更小的主要原因之一。

采样证据（每个 workload/threads 都有一份 `vmstat/iostat/pidstat`）：

- official samples: `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/official/samples/`
- pgoed samples: `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/pgoed/samples/`

建议先快速核验两个只读 workload 的 `vmstat`（一般应接近 `wa=0`），再看 `read_write` 的波动：

- official:
  - `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/official/samples/point_select_t16/vmstat.log`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/official/samples/read_only_t16/vmstat.log`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/official/samples/read_write_t16/vmstat.log`
- pgoed:
  - `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/pgoed/samples/point_select_t16/vmstat.log`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/pgoed/samples/read_only_t16/vmstat.log`
  - `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/pgoed/samples/read_write_t16/vmstat.log`

## Results (TPS)

完整汇总（自动解析生成）：

- markdown: `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/summary.md`
- json: `docker/percona-server-8.4-pgoed/bench/runs/20260314-133201/summary.json`

### `point_select`

| threads | official tps | pgoed tps | delta tps | official avg ms | pgoed avg ms | official p95 ms | pgoed p95 ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 7823.43 | 10730.35 | +37.16% | 0.13 | 0.09 | 0.17 | 0.12 |
| 4 | 23346.88 | 31911.41 | +36.68% | 0.17 | 0.12 | 0.24 | 0.17 |
| 8 | 24227.07 | 32228.46 | +33.03% | 0.33 | 0.25 | 0.70 | 0.62 |
| 16 | 24085.65 | 31971.52 | +32.74% | 0.66 | 0.50 | 1.82 | 1.55 |

### `read_only`

| threads | official tps | pgoed tps | delta tps | official avg ms | pgoed avg ms | official p95 ms | pgoed p95 ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 371.46 | 487.62 | +31.27% | 2.69 | 2.05 | 3.13 | 2.43 |
| 4 | 1207.59 | 1593.33 | +31.94% | 3.31 | 2.51 | 4.74 | 3.43 |
| 8 | 1255.96 | 1626.36 | +29.49% | 6.37 | 4.92 | 12.98 | 11.45 |
| 16 | 1253.97 | 1581.07 | +26.09% | 12.75 | 10.11 | 30.26 | 25.74 |

### `read_write`

| threads | official tps | pgoed tps | delta tps | official avg ms | pgoed avg ms | official p95 ms | pgoed p95 ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 240.11 | 291.45 | +21.38% | 4.16 | 3.43 | 4.82 | 3.89 |
| 4 | 533.82 | 580.98 | +8.83% | 7.49 | 6.88 | 11.45 | 10.84 |
| 8 | 543.13 | 561.53 | +3.39% | 14.72 | 14.24 | 34.33 | 33.12 |
| 16 | 566.73 | 642.71 | +13.41% | 28.22 | 24.88 | 81.48 | 73.13 |

## How to reproduce

一键复跑（会拉镜像、初始化数据集、warmup、跑 3 workloads，并生成 summary）：

```bash
bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh
```

如需复跑并保留同一 run id（例如分两段跑 official / pgoed）：

```bash
RUN_ID=20260314-133201 RUN_VARIANTS=official bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh
RUN_ID=20260314-133201 RUN_VARIANTS=pgoed   bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh
```
