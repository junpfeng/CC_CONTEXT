# Meta-Review — 0.0.3/V2_NPC

## #6（2026-03-28）

### 数据来源
- tasks: task-01 ~ task-08（results.tsv，0.0.3/V2_NPC）
- review reports: task-06、task-07、task-08
- iteration logs: task-06（2轮）、task-07（4轮）、task-08（2轮）

### 整体质量

| 指标 | 数值 |
|------|------|
| 任务总数 | 8 |
| discard 数 | 0 |
| 需要修复轮的任务 | 2（task-03、task-07，各需4轮） |
| 最终 Critical | 全部为 0 |
| 最终 High 残留 | task-01:1, task-02:2, task-03:1, task-05:2, task-06:2, task-07:2, task-08:1 |

**整体结论**：无 discard，编译全部通过，但 HIGH 残留率偏高（7/8 任务有 HIGH 未修复），说明质量达标阈值较宽松（0 Critical 即 keep）。

---

### 问题模式分析

#### 模式一：Animancer 共享层冲突（task-07 + task-08，跨2任务）

**表现**：
- task-07 HIGH-1：Flee Overlay 与 HitReaction 共用 UpperBody 层，`RestoreUpperBodyAnim` 无条件归零导致 Flee 动画叠加丢失
- task-08 HIGH-1：`OnHit()` 缺少 `_upperBodyLayer.StartFade(1f)` — 击中动画 99% 场景不可见
- task-08 MEDIUM-2：同一根因（RestoreUpperBodyAnim 无条件清层破坏 Flee 表现）

**根因**：task-07 引入了双系统共享 UpperBody 层的设计，未建立优先级机制；task-08 在此基础上继续开发，沿用了有缺陷的层管理模式。

**处置**：生成 auto-work-lesson-007.md（Animancer 共享层优先级保护）

---

#### 模式二：Override 生命周期方法漏调 base（task-06）

**表现**：
- task-06 HIGH-2：`OnRemove()` override 缺少 `base.OnRemove()`，导致基类资产句柄泄漏

**根因**：机械性遗漏，开发时未检查基类实现。

**处置**：生成 auto-work-lesson-008.md（Override 生命周期方法必须调用 base）

---

#### 模式三：共享资产直接修改（task-06，单次）

**表现**：
- task-06 HIGH-1：直接修改 `state.Clip.wrapMode`，污染所有使用该 Clip 的 NPC（200 NPC 规模）

**根因**：Unity Animancer Clip 是共享资产，修改属性会影响所有引用该资产的实例。

**处置**：单次出现，未生成规则。建议开发者在编码时对任何 `clip.XXX = ` 赋值均改为实例化副本（`Instantiate(clip)`）后再修改。

---

#### 模式四：测试覆盖缺失（task-07，宪法违规）

**表现**：
- task-07 HIGH-2：4 个新增公共接口均无测试（宪法要求"新增功能必须附带测试"）
- 开发日志注明为已知缺陷：BigWorld 模块无 NUnit 测试程序集，Animancer 运行时难以 mock

**根因**：测试基础设施缺失导致宪法约束无法落地。

**处置**：未生成规则（已有 constitution.md 覆盖，根因是基础设施问题而非规则缺失）。
建议：在 freelifeclient 中为 BigWorldNpc 相关组件创建 NUnit 测试程序集，至少覆盖纯逻辑部分。

---

### 新增规则

| 规则文件 | 针对问题 | 来源任务 |
|---------|---------|---------|
| auto-work-lesson-007.md | Animancer 共享层优先级保护 | task-07, task-08 |
| auto-work-lesson-008.md | Override 生命周期方法必须调用 base | task-06 |

### 跳过创建的规则

| 候选问题 | 跳过原因 |
|---------|---------|
| 共享资产直接修改 | 单次出现，证据不足；已有通用 Unity 开发规范覆盖 |
| 测试覆盖缺失 | constitution.md 已有要求；根因是基础设施缺失，规则无法解决 |
