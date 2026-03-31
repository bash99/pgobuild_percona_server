# Percona Server 5.7.44-54 PGO Validation

- target: `Percona Server 5.7.44-54`
- platform class: `CentOS 7 compatible`
- train mode: `readonly`
- final verdict: `PASS`

## TPS Summary

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | 50196.22 | 64419.51 | 28.34% |
| read_only | 2365.65 | 3034.91 | 28.29% |

## Notes

- This validation represents the recovered `5.7` PGO flow after restoring the required single-build-root behavior for GCC profile data matching.
- Public summary intentionally omits maintainer host paths and raw internal log locations.
