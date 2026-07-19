# Percona Server 5.7.44-57 PGO Validation

- platform class: `CentOS 7 compatible`
- pgo train mode: `joint_read`
- pgo benchmark mode: `readonly`
- database engine: `InnoDB`
- dataset: `16` tables × `2,000,000` rows, `16` threads
- normal `SELECT VERSION()`: `5.7.44-57`
- pgo `SELECT VERSION()`: `5.7.44-57-pgo`
- final `mysqld --version`: `Ver 5.7.44-57-pgo for Linux on x86_64 (Source distribution)`
- profile generation: `895` `.gcda` files, all non-zero, all matching the PGO build root
- profile-use compile: `PASS` (`-fprofile-use` and the generated profile directory were found)
- final package: `Percona-Server-5.7.44-57-PGOed.Linux.x86_64.centos7.mini.tar.zst`
- final package SHA256: `713936a22dc048a38116d05c73a6517854f63b0ba9ad52a3317b993d3b343ed0`
- final package runtime smoke: `PASS`; extracted `mysqld` initialized a temporary datadir, answered `SELECT VERSION()`, and shut down cleanly
- final verdict: `PASS`
- review note: normal `read_only` baseline was slightly above the 10% stability-warning threshold; the PGO run itself was stable, so repeat before production promotion if stricter reproducibility is required

## TPS Summary

| workload | normal | pgo | improvement |
| --- | ---: | ---: | ---: |
| point_select | 143811.21 | 206700.45 | 43.73% |
| read_only | 5956.60 | 7714.37 | 29.51% |

## Observed Stage Durations

These are measured from the stage logs and compile-time markers; rounded values are intentional.

| stage | elapsed |
| --- | ---: |
| source download, fallback, extraction and Boost handoff | about 4 min |
| normal build and install | 6 min 19 sec |
| normal startup/quiesce | about 12 sec |
| sysbench compile | about 1 min |
| sysbench dataset initialization | 13 min 22 sec |
| normal baseline benchmark (`50s + 160s + 160s`) | 6 min 11 sec |
| normal package | about 40 sec |
| profile-generate build and install | 7 min 21 sec |
| profile-generate startup/quiesce | about 4 min |
| `joint_read` profile workload (`50s + 160s`) | 3 min 36 sec |
| profile validation | under 1 sec |
| profile-use build and install | 4 min 23 sec |
| PGO startup/quiesce | about 3 min 34 sec |
| readonly PGO benchmark (`50s + 160s`) | 3 min 39 sec |
| PGO package and checksum | under 1 min |

## Recommended Remote Polling Cadence

For a future detached run, wait for the expected stage duration before checking remote state:

- build stages: first check after `8–10 min`, then every `3 min`;
- sysbench initialization: first check after `10 min`, then every `3–5 min`;
- full normal benchmark: check after `7 min`;
- joint-read profile or readonly validation: check after `4 min`;
- package/checksum: check after `1 min`;
- check earlier only for a known failure signal such as a stopped process, disk pressure, or an explicit timeout.

The 5-second sleep inside the startup-quiesce loop is an internal readiness check and should remain separate from the much slower operator-side remote polling interval.

This validation record accompanies the public GitHub release for `5.7.44-57`.
