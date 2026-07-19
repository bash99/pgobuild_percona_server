# PGO Readonly Validation

- date: 2026-07-19T12:33:19+00:00
- mysql_version: 8.0.46-37
- build_distro: AlmaLinux 8
- compiler: GCC Toolset 12
- build_options: `WITH_ROCKSDB=ON`, `ENABLE_LTO=ON`
- pgo_train_mode: joint_read
- pgo_benchmark_mode: readonly
- pgo_train_db_engines: innodb
- pgo_validate_db_engines: innodb
- pgo_verdict_engine: innodb
- strict_pgo_verdict: ON
- reuse_normal_dataset_for_pgo: ON
- pgo_dataset_mode: clone
- gcda_count: 2080
- gcda_nonzero_count: 2080
- gcda_total_bytes: 19116016
- gcda_matching_build_root_count: 2080
- pgo_use_missing_profile_count: 533

## TPS Summary

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | 71222.93 | 110768.20 | 55.52% |
| read_only | 3512.71 | 5106.34 | 45.37% |

## Verdict

- verdict_engine: innodb
- readonly_vs_normal: PASS
- readonly improvement vs normal: 45.37%

## Notes

- Public evidence omits maintainer host paths, remote access details, and raw private log locations.
- The profile-generation workload used `point_select` plus `read_only`; validation used the same InnoDB benchmark shape.
