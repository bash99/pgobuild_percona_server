# PGO Train Modes

## Standard Decision

从 `2026-03-11` 起，后续常规 `PGO profile-generate` 默认模式统一改为 `joint_read`：

- `profile-generate`: `joint_read`
- `profile-use` 后验证: `readonly`

实现位置：

- `stages/build_pgo_80.sh`
- `stages/build_pgo_57.sh`

兼容性约束：

- 如果历史调用方显式传入 `TRAIN_MODE=...`，仍保持旧语义：训练和验证都跟随同一个 `TRAIN_MODE`
- 如果需要拆开控制，可显式传入：
  - `PGO_TRAIN_MODE=...`
  - `PGO_BENCHMARK_MODE=...`

## Why `joint_read`

这次在 `AlmaLinux 9.7 + Percona Server 8.4.7-7` 上跑了四种 profile-gen 训练模式矩阵：

| mode | point_select delta | read_only delta | note |
| --- | ---: | ---: | --- |
| `point_select_only` | `+66.59%` | `+44.80%` | point_select 最强，但 read_only 明显偏弱 |
| `read_only_only` | `+63.57%` | `+55.76%` | read_only 很强，但 point_select 略弱于 point_select_only |
| `joint_read` | `+63.78%` | `+56.47%` | 两个核心只读 workload 同时表现最好或接近最好 |
| `full` | `+59.18%` | `+54.62%` | 加入 read_write 后收益略低，且训练噪声更大 |

选择 `joint_read` 作为标准模式的原因：

1. 同时覆盖 `point_select` 和 `read_only` 两条核心只读执行路径
2. `read_only` 结果是四种模式里最优
3. `point_select` 结果接近最优，没有出现退化
4. 避开 `full` 模式中 `read_write` 带来的额外刷盘与波动
5. 比单一 workload 训练更适合作为通用默认值

本轮结论与证据汇总见：

- `artifacts/Percona-Server-8.4.7-7/pgo-matrix-analysis-20260311.md`
- `artifacts/Percona-Server-8.4.7-7/profile-matrix-8.4.7-7-20260311-045343-bpfix/matrix-summary.md`

## Four Supported Modes

四种训练模式仍然全部保留，不删除脚本能力：

### `point_select_only`

- 内容：只训练 `oltp_point_select.lua`
- 时长：`60s`
- 适用场景：只关心极致点查吞吐，或怀疑某次 regression 只出现在点查路径

### `read_only_only`

- 内容：只训练 `oltp_read_only.lua`
- 时长：`160s`
- 适用场景：只关心标准 readonly 验证，或想对比历史 readonly-only 数据

### `joint_read`

- 内容：`point_select 50s + read_only 160s`
- 适用场景：常规默认模式；兼顾点查与复杂只读

### `full`

- 内容：`point_select 50s + read_only 160s + read_write 160s`
- 适用场景：需要观察 read_write 混入 profile 后的方向性变化
- 注意：`read_write` 波动更大，不适合作为常规默认 profile-gen 模式

## How To Re-Test The Matrix

矩阵脚本保留为：

- `tools/run_pgo_train_matrix.sh`

用途：

- 固定跑 `point_select_only / read_only_only / joint_read / full` 四模式
- 记录 normal baseline、pgo-gen、pgoed 的 sysbench 原始日志
- 记录 active benchmark `mpstat / iostat / pidstat`
- 自动汇总到 `matrix-summary.md`

示例：

```bash
MATRIX_ROOT=/mnt/localssd/pgobuild_percona_server/work-alma9-847-mecab/profile-matrix-8.4.7-7-YYYYMMDD-HHMMSS \
WORK_ROOT=/mnt/localssd/pgobuild_percona_server/work-alma9-847-mecab \
bash tools/run_pgo_train_matrix.sh
```

如果只是基于已有结果重刷 summary：

```bash
MATRIX_ROOT=/path/to/existing/profile-matrix \
MATRIX_SUMMARY_ONLY=ON \
bash tools/run_pgo_train_matrix.sh
```

## Notes

- `joint_read` 是“默认值”，不是“唯一允许值”
- 四模式对比前，先确认 baseline 负载形态正确（避免把 `point_select/read_only` 跑成 I/O bound）；检查项见 `docs/pgo_validation_checklist.md`
- 后续如果换版本、换发行版、换 CPU 平台后结果趋势变化，仍应优先使用矩阵脚本复测四种模式，而不是假定结论永远不变
