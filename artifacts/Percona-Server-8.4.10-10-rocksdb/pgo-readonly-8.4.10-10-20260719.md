# PGO Readonly Validation

- date: 2026-07-19
- mysql_version: 8.4.10-10
- platform: AlmaLinux 9 x86_64
- compiler: GCC Toolset 12
- cpu_flags: `-march=nehalem -mtune=haswell`
- build_options: `WITH_ROCKSDB=ON`, LTO enabled
- pgo_train_mode: `joint_read`
- pgo_benchmark_mode: `readonly`
- engines: InnoDB and RocksDB
- dataset_policy: shared normal dataset reused for PGO validation
- profile_data: 2,442 non-zero `.gcda` files, 27,061,808 bytes
- profile_use_missing_profile_warnings: 210
- strict_verdict: `PASS`

## TPS Summary

| Engine | Workload | Normal TPS | PGO TPS | Improvement |
| --- | --- | ---: | ---: | ---: |
| InnoDB | `point_select` | 69,759.76 | 109,965.83 | 57.64% |
| InnoDB | `read_only` | 3,431.67 | 5,051.77 | 47.21% |
| RocksDB | `point_select` | 45,566.35 | 69,465.24 | 52.45% |
| RocksDB | `read_only` | 2,227.12 | 3,542.73 | 59.07% |

All validation workloads completed with zero ignored errors and stable TPS samples. The strict verdict uses the InnoDB `read_only` comparison and passed with a 47.21% improvement over the normal build.
