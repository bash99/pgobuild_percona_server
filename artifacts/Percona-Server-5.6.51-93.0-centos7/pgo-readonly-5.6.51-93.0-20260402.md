# Percona Server 5.6.51-93.0 PGO Validation

- platform class: `CentOS 7 compatible`
- pgo train mode: `joint_read`
- pgo benchmark mode: `readonly`
- database engine: `InnoDB`
- final package: `Percona-Server-5.6.51-93.0-pgo-PGOed.Linux.x86_64.centos7.mini.tar.zst`
- final package SHA256: `849246eca6256c9d4eabaa9e8e1041a7f7082d491d76e9ac4fc71003617ce756`
- profile generation and profile-use build: `PASS`
- readonly benchmark stability: `PASS`
- final verdict: `PASS`

## TPS Summary

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | 117144.09 | 170252.21 | 45.34% |
| read_only | 5529.00 | 7347.95 | 32.90% |

## Notes

- This validation record intentionally omits internal build paths and raw logs.
- This validation record accompanies the public GitHub release for `5.6.51-93.0`.
