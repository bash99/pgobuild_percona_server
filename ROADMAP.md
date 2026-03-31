# Roadmap

## Positioning

This is a community-maintained repository for building, benchmarking, packaging, and validating PGOed Percona Server binaries.

It is not an official Percona distribution channel.

## Public Support Matrix

| Percona Server | Status | Notes |
| --- | --- | --- |
| `8.4` | Active | Current primary target for release assets and Docker work |
| `8.0` | Active | Current primary target for release assets |
| `5.7` | Maintained legacy target | Still validated for `CentOS 7` style workflows |
| `5.6` | Historical / final-note target | Not a mainline target; one last `CentOS 7` release may still be produced |

## Verified Highlights

- `8.4.8-8`: PGO validation, Docker image recipe, RocksDB-enabled build validation
- `8.0.45-36`: PGO validation on modern Linux, including RocksDB-enabled dual-engine training
- `5.7.44-54`: recovered readonly PGO flow on `CentOS 7` compatible hosts

## Next Milestones

1. Publish GitHub Releases as the primary binary download channel.
2. Publish Docker Hub images derived from release assets.
3. Keep public evidence concise and sanitized while preserving detailed maintainer records in the private repo.
4. Revisit one final `5.6` / `CentOS 7` build as a historical closing release.
