# Auto-Work Meta-Review — 0.0.1/V2_NPC

## Meta-Review #1 (2026-03-27)

### 数据概览

| 任务 | 轮次 | 结果 | HIGH | 耗时 |
|------|------|------|------|------|
| task-01 | 2 | keep | 0 | 快速通过（worktree 并行） |
| task-05 | 4 | discard（棘轮回退） | 3→4 | ~2900s（含 2 轮浪费） |

### 模式识别

#### 模式 1：修复导致质量恶化（task-05）

task-05 第 2 轮 review 发现 3 个 HIGH，修复后第 4 轮变成 4 个 HIGH，触发棘轮 discard。

**具体 HIGH 问题**：
1. LOD 插值参数未按 plan 实现（帧间隔跳帧 vs plan 要求的插值时间窗口+曲线）
2. AppearanceComp 缺少内部 CancellationTokenSource（违反已有 `feedback_unitask_cancellation` 规则）
3. TransformComp 跳帧时间轴断裂（LOD 切换时插值速度异常）
4. （修复后新增）第 4 个 HIGH

**根因**：修复时未整体规划，逐个修补导致连锁问题。修一个组件的问题时影响了另一个组件。

#### 模式 2：Plan 偏离未被提前发现（task-05）

task-05 的 HIGH #1 明确指出"LOD 插值参数未按 plan 实现"。开发阶段用简化方案（硬编码帧间隔）替代了 plan 要求的完整插值策略，但未在 develop-log 中记录偏离原因，直到 review 才被发现。

**根因**：编码完成后未回头对照 plan 检查关键设计点。

#### 模式 3：已有规则未被遵守（task-05）

CancellationTokenSource 缺失问题已有 `feedback_unitask_cancellation` 规则，但 develop 阶段仍然遗漏。说明编码时未主动检查 `.claude/rules/` 和 memory 中的已有约束。

### 生成规则

1. **auto-work-lesson-003**: Review 修复必须整体规划，禁止逐个盲修
2. **auto-work-lesson-004**: 编码后必须对照 Plan 自查关键设计点

### 改进效果预估

- lesson-003 可避免 task-05 的修复恶化（节省 2 轮迭代 ~800s）
- lesson-004 可在 review 前自行发现 plan 偏离和已有规则违反（task-05 的 4 个 HIGH 中至少 2 个可提前修复）

> **注意**：MR#1 提议的 lesson-003/004 未实际创建为文件，在 MR#2 中补充落地。

## Meta-Review #2 (2026-03-27)

### 数据概览

| 任务 | 轮次 | 结果 | HIGH | 关键问题 |
|------|------|------|------|----------|
| task-01 | 2 | keep | 0 | 无问题，worktree 并行完成 |
| task-02 | 2 | keep | 2 | 全局 nav 状态锁安全 + 情绪衰减 DRY |
| task-05 | 4 | discard（棘轮） | 3→4 | LOD 未按 plan + CTS 缺失 + 修复恶化 |
| task-06 | 2 | keep | 2 | 日志 `$""` 插值（2 处） |

### 模式识别

#### 模式 1：C# 日志 `$""` 字符串插值（task-06，2 HIGH）

task-06 的全部 2 个 HIGH 都是同一类问题：日志使用 `$""` 插值而非 `+` 拼接。`unity-csharp.md` 规定了用 MLog 不用 Debug.Log，但**未明确禁止 `$""` 插值**，导致编码时没有触发规则检查。

**根因**：编码规范中缺少对日志字符串拼接方式的显式约束，开发阶段无意识使用了惯性写法。

#### 模式 2：MR#1 提议的规则未落地

MR#1 提议了 lesson-003（修复纪律）和 lesson-004（Plan 自查），但规则文件从未创建。task-05 的修复恶化问题（3→4 HIGH）正是 lesson-004 要防止的场景。

**根因**：meta-review 流程只生成了提议，缺少创建文件的执行步骤。

#### 模式 3：DRY 违反（task-02，1 HIGH）

情绪衰减逻辑在 3 处重复，属于常见的代码质量问题。但这类问题过于通用，不适合用机械规则约束（判断何时抽取函数需要上下文），标记为观察项。

### 生成规则

1. **auto-work-lesson-003**: C# 日志禁止 `$""` 字符串插值，必须用 `+` 拼接 ✅ 已创建
2. **auto-work-lesson-004**: Review 修复纪律——只改标记问题，禁止扩散 ⚠️ 权限阻塞，待手动创建

### 改进效果预估

- lesson-003 可消除 task-06 的全部 2 个 HIGH（纯机械性规则，零误判）
- lesson-004 可避免 task-05 的修复恶化（节省 2 轮迭代 ~800s）
- 总体：6 个任务 HIGH 中 4 个（67%）可通过这 2 条规则避免

### 流程改进

- meta-review 提议规则后，**必须在同一流程中创建规则文件**，不能只记录提议

## Meta-Review #3 (2026-03-27)

### 数据概览

| 任务 | 轮次 | 结果 | Critical | HIGH | 关键问题 |
|------|------|------|----------|------|----------|
| task-01 | 2 | keep | 0 | 0 | 无问题，worktree 并行完成 |
| task-02 | 2 | keep | 0 | 2 | 全局 nav 状态锁安全 + 情绪衰减 DRY |
| task-03 | 4 | discard（棘轮） | 0→1 | 3→3 | 修复引入 CRITICAL：生成位置未写入实体 |
| task-05 | 4 | discard（棘轮） | 0 | 3→4 | LOD 未按 plan + CTS 缺失 + 修复恶化 |
| task-06 | 2 | keep | 0 | 2 | 日志 `$""` 插值（2 处，lesson-003 覆盖） |
| task-07 | 4 | keep | 1→0 | 2→1 | OnShutdown Dispose 后未 ReturnToPool |

### 统计

- 总任务：6 个，通过 4 个（67%），discard 2 个（33%）
- 总迭代轮次：18 轮，其中 8 轮为 fix+re-review（44% 为返工）
- Discard 浪费：task-03 + task-05 共 4 轮 fix 迭代全部浪费

### 模式识别

#### 模式 1：Fix 轮引入新 bug（task-03 + task-05，2/6=33%）

**数据**：
- task-05：Round 2 = 0C/3H → fix → Round 4 = 0C/4H（+1H），discard
- task-03：Round 2 = 0C/3H → fix → Round 4 = 1C/3H（+1C），discard
- task-03 的新 CRITICAL 是 `spawnNpcAt` 重构时遗漏将 pos 写入实体，核心功能失效

**根因**：fix 轮修改范围过大，超出 review 标记的问题，触碰了本不需要改的代码路径。task-03 尤其典型——修复 3 个 HIGH 时顺带重构了 spawn 流程，引入了全新的 CRITICAL。

**规则**：→ **lesson-004**（Review 修复纪律）

#### 模式 2：Plan 偏离未被编码阶段发现（task-05）

**数据**：
- task-05 最大 HIGH = "LOD 插值参数未按 plan 实现"——plan 要求三级 LOD 对应不同插值时间窗口和曲线，代码只做了帧间隔跳帧

**根因**：编码完成后未回头对照 plan 检查，直到 review 才发现偏离。同时 task-06 的 2 个 HIGH（`$""` 插值）属于 lesson-003 可机械检查的问题，说明编码阶段缺少规则扫描步骤。

**规则**：→ **lesson-005**（编码后 Plan 合规自查）

#### 已有规则覆盖的问题（不新增规则）

- task-06 的 `$""` 日志插值：lesson-003 已覆盖（创建时间晚于 task-06 编码，属于时序问题）
- task-07 的 OnShutdown 未 ReturnToPool：属于一次性逻辑遗漏，不构成反复模式

### 生成规则

| 规则 | 文件 | 状态 |
|------|------|------|
| Review 修复纪律 | `auto-work-lesson-004.md` | ✅ 已创建 |
| 编码后 Plan 合规自查 | `auto-work-lesson-005.md` | ✅ 已创建 |

### 改进效果预估

- lesson-004 可避免 task-03 和 task-05 的 fix 轮回退（节省 4 轮迭代，约 1600s）
- lesson-005 可在 review 前拦截 plan 偏离（task-05 至少 1 HIGH）和机械性规则违反（task-06 全部 2 HIGH）
- 总体：6 个任务产生的 11 个 HIGH 中 5 个（45%）可通过这 2 条规则+已有 lesson-003 避免
- discard 率预计从 33%→0%（假设修复不再引入新问题）

### 流程改进（延续 MR#2）

- ✅ 规则提议后立即创建文件（本轮已执行）
- 建议：feature:developing 完成后增加 pre-review gate，自动执行 lesson-005 的检查清单

## Meta-Review #4 (2026-03-27)

### 数据概览

| 任务 | 轮次 | 结果 | Critical | HIGH | 关键问题 |
|------|------|------|----------|------|----------|
| task-01 | 2 | keep | 0 | 0 | 无问题，worktree 并行完成 |
| task-02 | 2 | keep | 0 | 2 | 全局 nav 状态锁安全 + 情绪衰减 DRY |
| task-03 | 4 | discard（棘轮） | 0→1 | 3→3 | 修复引入 CRITICAL：生成位置未写入实体 |
| task-04 | **8** | discard（棘轮） | 2→0 | 7→5 | **4 轮 fix 不收敛，全部是日志格式违规** |
| task-05 | 4 | discard（棘轮） | 0 | 3→4 | LOD 未按 plan + CTS 缺失 + 修复恶化 |
| task-06 | 2 | keep | 0 | 2 | 日志 `$""` 插值（lesson-003 覆盖） |
| task-07 | 4 | keep | 1→0 | 2→1 | OnShutdown Dispose 后未 ReturnToPool |

### 统计

- 总任务：7 个，通过 4 个（57%），discard 3 个（43%）
- 总迭代轮次：26 轮，其中 14 轮为 fix+re-review（54% 为返工）
- **最大浪费**：task-04 = 8 轮（4 轮 fix），全部 HIGH 为已有规则覆盖的机械性问题
- Discard 浪费：task-03(4轮) + task-04(8轮) + task-05(4轮) = 16 轮全部浪费

### 模式识别

#### 模式 1：已有 Go 日志规则未在编码阶段检查（task-04，5/5 HIGH）

**数据**：
- task-04 初次 review = 2C/7H，其中 5 HIGH 全部是日志格式违规（`%d`/`%s` → `%v`、字段命名 `entityID` → `npc_entity_id`）
- `P1GoServer/.claude/rules/logging.md` 已明确禁止 `%d`/`%s`，要求 NPC 日志用 `npc_entity_id`/`npc_cfg_id`
- lesson-005 的"已有规则扫描"只列了 C# 规则，**零 Go 规则**

**根因**：lesson-005 创建时只基于 C# 侧数据（task-05/06），遗漏了 Go 侧的机械性规则。task-04 是第一个暴露 Go 规则盲区的任务。

**修复**：→ 更新 lesson-005，补充 Go 日志格式扫描项（`%v`、字段命名、模块标签）

#### 模式 2：Fix 轮只修标记点，同类违规残留（task-04，8 轮不收敛）

**数据**：
- task-04 轮次变化：2C/7H → 1C/3H → 0C/3H → 0C/5H
- Round 4→6 看似改善（1C/3H → 0C/3H），但 MEDIUM 从 4→7（fix 把 HIGH 降级为 MEDIUM 但未根治）
- Round 6→8 反弹（0C/3H → 0C/5H），review 在同文件发现了之前遗漏的同类违规

**根因**：fix 只修 review 明确标记的行号，但同一文件其他行存在相同违规。下轮 review 的 reviewer 视角不同，发现新的同类违规并标记为新 HIGH。lesson-004 要求"只改标记问题"是正确的（防止跨类型扩散），但对同类型问题需要全量覆盖。

**规则**：→ **lesson-006**（同类型机械性问题全量扫描修复）

#### 已有规则覆盖的问题（不新增规则）

- task-03 fix 引入 CRITICAL（生成位置未写入实体）：lesson-004 覆盖（fix 纪律）
- task-05 LOD 未按 plan + CTS 缺失：lesson-005 覆盖（Plan 自查 + 规则扫描）
- task-06 `$""` 日志插值：lesson-003 覆盖

### 生成规则

| 规则 | 文件 | 状态 |
|------|------|------|
| 同类型机械性问题全量扫描修复 | `auto-work-lesson-006.md` | ✅ 已创建 |
| lesson-005 补充 Go 扫描项 | `auto-work-lesson-005.md` | ✅ 已更新 |

### 改进效果预估

- lesson-006 可避免 task-04 的 fix 轮振荡（节省 6 轮迭代，约 1300s review 时间）
- lesson-005 更新后可在编码阶段拦截 task-04 的全部 5 HIGH（Go 日志格式）
- 总体：如果 lesson-005(含Go扫描) + lesson-006 同时生效，task-04 预计首轮 review 即可通过（0C/0H）
- discard 率预计从 43%(3/7) → 14%(1/7)，仅 task-03 的"fix 引入 CRITICAL"仍需 lesson-004 约束

### 累积规则效果矩阵

| 规则 | 覆盖任务 | 可避免的 HIGH |
|------|----------|--------------|
| lesson-003（C# 日志插值） | task-06 | 2 |
| lesson-004（fix 纪律） | task-03, task-05 | 间接（防止恶化） |
| lesson-005（Plan 自查 + 规则扫描） | task-05, task-04(Go补充) | 3 + 5 |
| lesson-006（同类型全量修复） | task-04 | 5（fix 阶段） |

## Meta-Review #5 (2026-03-27)

### 数据概览

| 任务 | 轮次 | 结果 | Critical | HIGH | 关键问题 |
|------|------|------|----------|------|----------|
| task-01 | 2 | keep | 0 | 0 | 无问题，worktree 并行完成 |
| task-02 | 2 | keep | 0 | 2 | 全局 nav 状态锁安全 + 情绪衰减 DRY |
| task-03 | 4 | discard（棘轮） | 0→1 | 3→3 | 修复引入 CRITICAL（lesson-004 覆盖） |
| task-04 | **8** | discard（棘轮） | 2→0 | 7→5 | 日志格式振荡（lesson-005+006 覆盖） |
| task-05 | 4 | discard（棘轮） | 0 | 3→4 | LOD 偏离 plan + 修复恶化（lesson-004+005 覆盖） |
| task-06 | 2 | keep | 0 | 2 | 日志 `$""` 插值（lesson-003 覆盖） |
| task-07 | 4 | keep | 1→0 | 2→1 | OnShutdown 未 ReturnToPool（一次性遗漏） |
| task-08 | 4 | keep | 1→0 | 0→0 | OnClear 访问修饰符（一次性遗漏） |

### 统计

- 总任务：8 个，通过 5 个（62.5%），discard 3 个（37.5%）
- 总迭代轮次：30 轮，其中 16 轮为 fix+re-review（53% 为返工）
- 新增任务（vs MR#4）：task-08（4 轮，成功收敛）
- **所有 3 个 discard 均发生在 lesson-004/005/006 创建之前**

### 模式识别

#### 观察 1：规则创建后任务质量改善

post-rule 任务（task-07、task-08）均在 1 轮 fix 内收敛：
- task-07：1C/2H → fix → 0C/1H（CRITICAL 消除，HIGH 减半）
- task-08：1C/0H → fix → 0C/0H（CRITICAL 消除，零残留）

对比 pre-rule 的 fix 轮（task-03/04/05 全部恶化），fix 成功率从 0%→100%。样本量小（2 vs 3），但趋势积极。

#### 观察 2：无新机械性错误模式

最近 3 个 review 报告的 HIGH/CRITICAL 均为一次性逻辑遗漏：
- task-07：OnShutdown Dispose 后未 ReturnToPool（对象池生命周期特有）
- task-08：OnClear 访问修饰符错误（编译级错误，立即可见）
- task-06：`$""` 日志插值（lesson-003 已覆盖，创建时序晚于编码）

无跨任务重复的新模式，不满足规则创建条件。

#### 观察 3：已有规则覆盖矩阵完整

| 失败模式 | 覆盖规则 | 预期效果 |
|---------|---------|---------|
| fix 引入新 bug | lesson-004 | 限制修改范围 |
| plan 偏离 | lesson-005 | 编码后自查 |
| 机械性规则遗漏（C#/Go） | lesson-005 | grep 扫描清单 |
| 同类违规残留导致振荡 | lesson-006 | 全量扫描修复 |
| C# `$""` 日志 | lesson-003 | 编码时避免 |
| 角度单位混用 | lesson-002 | 命名+显式转换 |
| 跨端编译遗漏 | lesson-001 | 双端编译验证 |

8 个任务的所有 discard 根因均已被覆盖。

### 生成规则

**NO_NEW_RULES** — 无新的重复模式需要规则化。

### 改进效果预估

- 如果 lesson-003~006 在全部 8 个任务开始前就存在，预计：
  - task-03 的 fix 不会引入 CRITICAL（lesson-004），keep 概率高
  - task-04 的 5 HIGH 在编码阶段被 lesson-005 Go 扫描拦截，首轮即 pass
  - task-05 的 plan 偏离在提交 review 前被 lesson-005 发现
  - 理论 discard 率：37.5% → ~0%，返工率：53% → ~25%
- **建议**：在后续版本迭代中验证这一预测，如果 discard 率未下降，需审视规则执行力度

### 下一步

1. 继续观察 post-rule 任务数据（当前样本量=2，需 ≥5 个才能确认趋势）
2. 若连续 5 个任务均 first-pass 或 1 轮 fix 收敛，可考虑放宽棘轮阈值以减少保守性
3. 若出现新的 discard，优先检查是否为已有规则覆盖但未执行，还是真正的新模式
