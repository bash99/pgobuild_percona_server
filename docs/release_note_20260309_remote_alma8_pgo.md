# Release Note - 2026-03-09 Remote AlmaLinux 8 PGO Round

## Summary

This update turns the AlmaLinux 8 remote PGO validation experience into reusable project workflow and guardrails.

## Highlights

- added reusable remote sync helper: `tools/remote_sync_to_host.sh`
- added reusable remote result collection helper: `tools/remote_collect_results.sh`
- documented remote SSH workflow: `docs/remote_pgo_workflow.md`
- unified startup quiesce guard for both normal and PGO benchmark flows
- added distro-aware package naming to avoid cross-distro overwrite

## Remote workflow changes

Remote code sync is now intentionally narrow:

- sync tracked repository files only
- sync Percona/Boost source tarballs only
- do not sync `work/`, unpacked source trees, caches, or generated packages

Remote result pull-back is also narrow:

- sync benchmark/result markdown files
- sync sysbench and startup wait logs
- sync final mini packages only

## Benchmark stability fix

`mysqld ready for connections` was not sufficient to start benchmark safely.

The benchmark gate now waits until:

1. buffer pool load is complete
2. InnoDB pending writes are zero
3. the zero-pending-write state is observed twice consecutively

This removes startup transient noise that previously distorted `point_select`.

## Packaging change

Mini package filenames now carry distro tag, for example:

- `mini_percona-server-8.0.45-36-linux-x86_64-pgoed_alma8.tar.xz`
- `mini_percona-server-8.0.45-36-linux-x86_64-pgoed_ubuntu22.tar.xz`

This prevents package overwrite and confusion across build hosts.

## AlmaLinux 8 confirmed outcome

With the final quiesced rerun on remote `AlmaLinux 8.10`:

- `point_select`: `63553.00 -> 94827.84` (`+49.21%`)
- `read_only`: `3124.55 -> 4659.76` (`+49.13%`)

These results are backed by the official quiesced rerun logs and result file already archived in the repository task records.
