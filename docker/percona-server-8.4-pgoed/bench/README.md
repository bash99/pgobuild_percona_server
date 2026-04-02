# Sysbench Head-To-Head For Docker Images

This harness compares:

- the community PGOed image built from this repository
- the upstream `percona/percona-server` image

Covered workloads:

- `oltp_point_select`
- `oltp_read_only`
- `oltp_read_write`

## Prerequisites

- `docker`
- optional: `sysstat` for `iostat` and `pidstat`

## Run

From the repository root:

```bash
bash docker/percona-server-8.4-pgoed/bench/run_head2head_sysbench.sh
```

The script uses `--network host` and expects to bind `127.0.0.1:3306`, so run it on a host without another MySQL instance listening there.

Default tunables:

- `OFFICIAL_IMAGE=percona/percona-server:8.4.8-8.1`
- `PGOED_IMAGE=ps-8.4.8-8-pgoed:latest`
- `SB_TABLES=16`
- `SB_TABLE_SIZE=500000`
- `SB_THREADS_LIST="1 4 8 16"`
- `SB_TIME=60`
- `SB_WARMUP_TIME=30`
- `SB_MYSQL_SSL=required`
- `SYSBENCH_IMAGE=perconalab/sysbench:latest`

Output directory:

- `docker/percona-server-8.4-pgoed/bench/runs/<RUN_ID>/`
  - `env.md`
  - `params.env`
  - `sysbench-version.txt`
  - `official/`
  - `pgoed/`
  - `summary.json`
  - `summary.md`

## Shared Benchmark Config

- `docker/percona-server-8.4-pgoed/bench/zz-benchmark.cnf`

This config intentionally relaxes durability for throughput comparison. It is not a production recommendation.
