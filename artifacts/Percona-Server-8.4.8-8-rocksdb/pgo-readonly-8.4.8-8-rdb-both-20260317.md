# PGO Readonly Validation (WITH_ROCKSDB=ON)

- date: 2026-03-17T20:28:40+00:00
- mysql_version: 8.4.8-8
- with_rocksdb: ON
- pgo_train_mode: joint_read
- pgo_benchmark_mode: readonly
- pgo_train_db_engines: innodb rocksdb
- pgo_validate_db_engines: innodb rocksdb
- pgo_verdict_engine: innodb
- reuse_normal_dataset_for_pgo: ON
- pgo_use_datadir_mode: shared_normal_datadir (no clone; disk safety)
- gcda_count: 2439
- gcda_nonzero_count: 2439
- gcda_total_bytes: 27079516
- gcda_matching_build_root_count: 2439
- pgo_use_missing_profile_count: 206

## Scope

- target: `Percona Server 8.4.8-8`
- build option: `WITH_ROCKSDB=ON`
- train engines: `innodb rocksdb`
- validate engines: `innodb rocksdb`

## TPS Summary

### db_engine=innodb

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | 68523.87 | 107720.03 | 57.20% |
| read_only | 3361.89 | 4930.08 | 46.65% |

### db_engine=rocksdb

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | 51759.84 | 76758.82 | 48.30% |
| read_only | 2190.25 | 3173.68 | 44.90% |

## Verdict

- verdict_engine: innodb
- readonly_vs_normal: PASS
- readonly improvement vs normal: 46.65%

## Notes

- Public summary intentionally omits maintainer host paths and raw internal log locations.
- This run showed that dual-engine training remained compatible with strong `InnoDB` and `RocksDB` gains on the `8.4.8-8` RocksDB-enabled build.
