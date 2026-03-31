# PGO Readonly Validation

- date: 2026-03-18T16:06:14+00:00
- mysql_version: 8.0.45-36
- pgo_train_mode: joint_read
- pgo_benchmark_mode: readonly
- pgo_train_db_engines: innodb rocksdb
- pgo_validate_db_engines: innodb rocksdb
- pgo_verdict_engine: innodb
- strict_pgo_verdict: ON
- reuse_normal_dataset_for_pgo: ON
- pgo_dataset_mode: shared_normal_datadir
- gcda_count: 2370
- gcda_nonzero_count: 2370
- gcda_total_bytes: 25387580
- gcda_matching_build_root_count: 2370
- pgo_use_missing_profile_count: 248

## Scope

- target: `Percona Server 8.0.45-36`
- build option: `WITH_ROCKSDB=ON`
- train engines: `innodb rocksdb`
- validate engines: `innodb rocksdb`

## TPS Summary

### db_engine=innodb

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | 70502.46 | 110067.86 | 56.12% |
| read_only | 3528.90 | 5036.29 | 42.72% |

### db_engine=rocksdb

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | 51188.65 | 81225.69 | 58.68% |
| read_only | 2179.51 | 3534.88 | 62.19% |

## Verdict

- verdict_engine: innodb
- readonly_vs_normal: PASS
- readonly improvement vs normal: 42.72%

## Notes

- Public summary intentionally omits maintainer host paths and raw internal log locations.
- This run confirmed that dual-engine training did not reduce the `InnoDB read_only` uplift versus the historical no-RocksDB reference.
