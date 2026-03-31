# PGO Validation Checklist

## Purpose

这份清单用于验证 `Percona Server` 的 `PGO` 结果是否可信，避免出现：

- profile 实际没有被消费；
- benchmark 取错 workload；
- 读到了错误阶段或错误二进制的结果；
- 数据集/参数不一致导致对比失真；
- 因环境抖动把异常结果误判为“成功”或“失败”。
- runtime 配置缺口把“预期 CPU-bound 的 OLTP 负载”跑成 I/O bound，导致 baseline 与 PGO 结论失真。

## Core Conclusion

- 目前已验证 `Percona Server 8.0 / 5.7 / 更早的 5.6` 在 `sysbench oltp readonly` 负载上，`PGO` 的常见有效提升区间大致在 `15% ~ 45%`。
- 从 `2026-03-11` 起，常规 `profile-generate` 默认模式建议使用 `joint_read`，验证仍保持 `readonly`。
- 如果提升显著低于 `10%`，或显著高于 `100%`，通常都应视为异常信号。
- 遇到异常结果时，优先排查问题，不要因为“流程跑完了”就接受结果。

## Recommended Train Mode

默认建议：

- `PGO_TRAIN_MODE=joint_read`
- `PGO_BENCHMARK_MODE=readonly`

原因：

- 同时覆盖 `point_select` 与 `read_only`
- 避免把 `read_write` 的额外波动引入默认 profile
- 在 `8.4.7-7` 四模式矩阵里，`joint_read` 给出了最平衡的综合结果

如果需要复查这个决策，不要直接争论，直接重跑：

- `tools/run_pgo_train_matrix.sh`

四模式说明见：

- `docs/pgo_train_modes.md`

## Fast Triage

出现以下任一情况时，优先判为“结果可疑，需要排查”：

- `readonly` 提升 `< 10%`
- `readonly` 提升 `> 100%`
- `point_select` / `read_only` / `read_write` 的相对趋势异常反常
- `pgo-gen` 与 `pgo-use` 的结果非常接近 normal，像没吃到 profile
- benchmark 日志里无法明确区分 workload 或 phase
- 构建日志里虽然出现 `-fprofile-use`，但 profile 路径和 build root 对不上
- `point_select` 等预期 CPU-bound 的 case 出现明显 I/O bound 信号（例如高 `iowait` / 高磁盘读 / `mysqld` CPU 利用率偏低），通常意味着 runtime 配置或系统状态有问题，先不要讨论 PGO。

## Required Checks

### 1. Source And Build Layout

确认以下信息一致且可追溯：

- source tree 路径
- build root 路径
- install root 路径
- profile-data 路径
- package 输出路径

对于 `5.7`，尤其要确认：

- `profile-generate` 与 `profile-use` 是否使用同一棵 build root
- 或者 profile 文件路径是否明确与 `profile-use` 阶段对象路径匹配

## 2. Profile Generation

至少确认：

- `gcda` 文件已生成
- `gcda` 文件不是全 0
- `gcda` 文件路径与 build root 匹配

最低检查项：

```bash
find "$PGO_PROFILE_DIR" -name '*.gcda' | wc -l
find "$PGO_PROFILE_DIR" -name '*.gcda' -size +0c | wc -l
```

如果有必要，再检查 profile 文件名中是否编码了正确的 build root。

## 3. Profile Use

不能只看“构建成功”，至少还要确认：

- 构建日志里有 `-fprofile-use`
- 构建日志里有正确的 `-fprofile-dir=...`
- 使用阶段的对象路径和 profile-data 可匹配

最低检查项：

```bash
grep -F -- '-fprofile-use' "$BUILD_LOG"
grep -F -- "$PGO_PROFILE_DIR" "$BUILD_LOG"
```

如果结果异常，进一步核对：

- `pgo-gen` build root
- `pgo-use` build root
- `.gcda` 文件名编码的路径

## 4. Workload Parsing

不要再依赖“第几个 `transactions:`”来解析结果。

推荐做法：

- 在日志里输出明确 marker
- 对每个 workload 单独包裹 begin/end 标记
- 日志中记录 phase：`normal` / `pgo-gen` / `pgoed`
- 日志中记录 `SELECT VERSION()`，确认跑的是哪一个二进制

推荐 marker：

- `SYSBENCH_CASE_BEGIN`
- `SYSBENCH_CASE_END`
- `TRAIN_PHASE_BEGIN`
- `TRAIN_PHASE_END`
- `MYSQL_VERSION_BEGIN`
- `MYSQL_VERSION_END`

## 5. Baseline Consistency

normal 与 pgo 对比必须保证以下参数一致：

- `table_size`
- `table_count`
- `oltp_threads`
- `warmup_time`
- `max_point_select_time`
- `max_oltp_time`
- `db engine`
- dataset 内容

常见错误：

- normal 用 `8 tables`，pgo 验证误用了默认 `16 tables`
- normal 和 pgo 使用不同 socket / datadir
- pgo clone 的数据目录不是 baseline 对应数据

## 6. Runtime Config Sanity (Avoid I/O Bound OLTP)

在讨论 PGO 之前，必须先确认“压测负载形态”是你想要的。

本项目的核心目标是验证 **非 I/O bound 的 OLTP 负载**（尤其 `point_select`/`read_only`）在 PGO 下是否受益；如果运行时配置缺失导致负载变成 I/O bound，那么：

- baseline 会被磁盘吞吐/延迟主导；
- 训练 profile 会混入大量 I/O 等待路径；
- PGO 提升/回退都可能是“假象”；
- 这类数据应优先判为无效，修复配置后重跑。

最低要求（MySQL/Percona 8.x）：

1. 记录并核对关键变量（至少写入日志或结果摘要）：
   - `SHOW VARIABLES LIKE 'innodb_buffer_pool_size'`
   - `SHOW VARIABLES LIKE 'performance_schema'`
   - `SHOW VARIABLES LIKE 'innodb_flush_method'`
2. 对 `point_select`/`read_only` 启用 active benchmark 采样（`mpstat/iostat/pidstat`），确认：
   - `iowait` 长时间显著偏高时（经验阈值：`> 10%`），该 case 很可能 I/O bound；
   - 磁盘读吞吐持续很高（例如数十到上百 MB/s）也通常意味着 I/O bound；
   - 预期 CPU-bound 的场景里，`mysqld` CPU 应该高、`iowait` 应该低。

本项目已出现过真实踩坑案例（`Percona Server 8.4.7-7` / `AlmaLinux 9.7`）：

- 重构后的 `8.x` runtime 配置遗漏旧 benchmark 调优，导致 `innodb_buffer_pool_size` 回落到上游默认 `128MB`；
- `point_select` baseline 约 `29k TPS`，采样显示 `iowait` 峰值 `70%~80%`、磁盘读约 `175 MB/s`，明显 I/O bound；
- 修复后（恢复 benchmark 调优并自动 sizing buffer pool 到约 `5GiB`），`point_select` baseline 恢复到约 `67k TPS`，`iowait` 接近 `0%`。

证据与复盘见：

- `artifacts/Percona-Server-8.4.7-7/pgo-matrix-analysis-20260311.md`

配置依据说明：

- 8.x 的 benchmark runtime `my.cnf` 由 `lib/mysql.sh:mysql_emit_config()` 生成；
- 历史上同类调优来自旧脚本模板 `build-normal/init_conf.sh`；
- 维护原则：如果 runtime 生成配置替代了旧模板，必须显式复用/迁移这些“影响负载形态”的关键参数（否则很容易跑偏成 I/O bound）。

## 7. Runtime Identity

要确认 benchmark 运行时确实是目标二进制：

- `mysqld --version` 或 `SELECT VERSION()`
- socket / pid / datadir 路径
- 当前 runtime profile 名称

如果版本字符串里有 `-pgo` 标记，更容易识别。

## 8. Startup Stability

不要在 MySQL 刚启动完就立刻开跑 benchmark。

至少确认：

- InnoDB buffer pool load completed
- pending writes 基本归零
- 服务已进入 quiesced 状态

否则容易出现：

- `point_select` 特别低
- 波动极大
- 首轮 PGO 结果看起来失真

## 9. Accept / Reject Rules

### Accept

可以判定为“PGO 有效”的最低条件：

- profile-data 生成有效
- profile-use 编译明确消费 profile
- benchmark 对比参数一致
- workload/phase/二进制身份可明确追溯
- 核心 workload 落在合理收益区间，或与历史结果趋势一致

### Reject Or Recheck

以下情况应先排查，不要直接交差：

- 提升 `< 10%`
- 提升 `> 100%`
- profile 路径和 build root 对不上
- benchmark 结果只能靠 grep 第几行猜测
- normal / pgo 参数不一致
- phase 或二进制身份无法确认

## 10. Suggested Evidence Bundle

一次完整交付至少保留：

- normal benchmark log
- pgo-gen benchmark log
- pgo-use benchmark log
- pgo-use build log
- result summary markdown
- final mini package

## 11. Recommended Response When Result Looks Wrong

建议按这个顺序排查：

1. 先确认是不是取错 workload / 取错 phase / 取错二进制
2. 再确认 profile 是否真的被消费
3. 再确认 normal / pgo 参数与数据集是否一致
4. 再确认 runtime 配置与负载形态是否正确（避免 I/O bound）
5. 再确认 startup 是否稳定
6. 最后才考虑是否真的是 workload 上收益较低

核心原则：

- 先验证“结果可信”
- 再评价“结果好不好”
- 不要为了流程闭环而接受明显异常的数字
