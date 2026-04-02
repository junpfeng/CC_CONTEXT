# bug-explore 指标体系

## 指标文件

路径：`docs/skills/bug-explore-metrics.jsonl`（一行一条 JSON）

## 字段定义

| 字段 | 类型 | 说明 |
|------|------|------|
| `timestamp` | string (ISO8601) | 完成时间 |
| `version` | string | 游戏版本号 |
| `module` | string | bug 所属模块 |
| `fix_result` | enum | `"success"` / `"failed"` / `"not_a_bug"` |
| `failure_reason` | string? | 仅 failed 时填写：`"root_cause_unknown"` / `"fix_regression"` / `"compile_error"` |
| `harness_gap` | string? | 仅 failed 时填写：诊断策略/工具/复现能力的具体缺口 |
| `strategies_matched` | string[] | Phase 1 命中的诊断策略关键词列表 |
| `phase1_actions` | int | Phase 1 执行的采集动作总数 |
| `phase1_rounds` | int | Phase 1 采集轮次（1 或 2） |
| `phase1_actions_cited` | int | 被 dev-debug 实际引用的采集动作数 |
| `phase2_rounds` | int | Phase 2 提问轮次 |
| `phase2_early_exit` | bool | 是否提前退出（不是 bug） |
| `phase4_retries` | int | dev-debug 重试次数（0 或 1） |
| `variant` | string | 执行的 SKILL 版本：`"main"` 或变体名（如 `"aggressive-collection"`） |

## 派生指标（Step 5 自反馈时计算）

| 指标 | 公式 | 健康阈值 |
|------|------|---------|
| 诊断命中率 | `phase1_actions_cited / phase1_actions` | ≥40% |
| 修复成功率 | `count(success) / count(total)` | ≥70% |
| 平均提问轮次 | `avg(phase2_rounds)` | ≤2.5 |
| 二轮采集比例 | `count(phase1_rounds==2) / count(total)` | ≤30% |

## 诊断策略进化规则

### 计数更新
- Phase 1 匹配到策略时：对应策略 `命中次数 +1`
- dev-debug 修复成功且引用了该策略采集的证据时：对应策略 `有效次数 +1`

### 淘汰规则
- `命中次数 ≥5` 且 `有效次数/命中次数 < 20%` → 标记 `低效`
- 下次 Step 5 自反馈时，如果仍为低效 → 替换为新策略（基于本次 bug 经验）或删除
- 策略表上限 25 条，满时替换有效率最低的一条

### 约束
- 每次 Step 5 最多改 3 处诊断策略
- 改动必须基于本次实际经历 + 指标数据，禁止臆测性优化

## Phase 2 维度优先级（可进化）

Phase 2 提问按以下权重排序，优先问权重高且未覆盖的维度。evolve.py 可基于指标数据调整权重。

| 维度 | 默认权重 | 说明 |
|------|---------|------|
| 复现（When/How） | 5 | 复现步骤对修复价值最高 |
| 现象（What） | 4 | 精确描述缩小排查范围 |
| 证据（Evidence） | 3 | Phase 1 已采集的跳过 |
| 范围（Who/Where） | 2 | 缩小影响面 |
| 影响（Impact） | 1 | 优先级判断，非修复必需 |

### 进化规则
- 当某维度在最近 10 次中 Phase 2 提问后对修复无贡献（即 dev-debug 未引用该维度信息）≥8 次 → 权重 -1（最低 1）
- 当某维度信息频繁被 dev-debug 引用 → 权重 +1（最高 5）
- 每次 evolve.py 运行时自动评估，记录在 changelog

## A/B 实验

主流程变体实验记录。同时最多 1 个活跃变体。

| 变体名 | 假设 | 开始日期 | 样本数 | 结果 |
|--------|------|---------|--------|------|
| *(暂无活跃实验)* | | | | |

### A/B 规则
- 触发条件：evolve.py `health_alerts` 连续 3 次以上出现相同告警
- 创建：复制 `SKILL.md` 为 `SKILL.variant-{名称}.md`，只改 Phase 1 采集逻辑或 Phase 4 重试逻辑
- 执行：存在变体时 50/50 随机选择，metrics 中记录 `variant` 字段
- 判定：≥5 样本后比较派生指标。优于主版本 → 合并回 SKILL.md；否则删除
- 早停：前 3 次若变体综合得分低于主版本 >15%，提前淘汰（不等满样本）
- 安全：不能修改 Phase 2/3 交互流程（但维度优先级权重可由进化机制调整）

## 自动化脚本

进化逻辑由 `evolve.py` 驱动（Step 5a 调用），脚本负责：
1. 读取 metrics.jsonl → 计算派生指标 → 对比健康阈值
2. 识别低效策略 → 提取重复 harness_gap → 输出 JSON 建议
3. AI 根据 JSON 建议执行实际的文件编辑（Step 5b）
