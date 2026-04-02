---
description: 给一个需求，AI自动完成调研→方案→开发全流程
argument-hint: <version_id> <feature_name> [需求描述]
---

## 设计原则（优化 auto-work 时必须遵守）

所有 AI 模型都有上下文窗口限制，而 auto-work 是一个流程很长的工作流。
**任何对 auto-work 的优化都必须遵守以下原则：**

### 0. 原子化与可观测性（最高原则）

> 原子化 = 把每个变更控制为最小可独立评估的单位。
> 不是"要小"，是"要能单独判断对错"。

AI 的输出能力是无限的，但判断改动好坏的能力是有限的。原子化是让每次改动可观测、可归因、可自动化的前提。

**三个前提条件（缺一不可）：**

| 条件 | 说明 | auto-work 中的实现 |
|------|------|-------------------|
| 固定评估基准 | 评估方法不变，变的只有被测对象 | 编译通过 + Review counts 作为固定基准 |
| 单一变量 | 每次只改一个东西 | 一个 task = 一个 commit = 一个独立评估单元 |
| 机械判定标准 | 好坏有明确数值门槛 | 编译=0 errors, Review=Critical=0 && High<=2 |

**原子化循环（每个 task 的核心流程）：**

```
保存 git 检查点(checkpoint)
  → 编码(单一 task)
  → 机械验证(编译 — 便宜、快、确定性)
  → 通过? → 主观评估(Review — 贵、慢、概率性)
  → 质量达标? → commit(keep) + 记录 results.tsv
  → 质量恶化? → git reset(discard) + 记录 results.tsv
```

**Keep/Discard 机制：**
- 每个 task 开始前保存 git 检查点（各仓库的 HEAD commit hash）
- 编译失败 3 次后：discard（回滚到检查点），记录失败原因
- Review 修复后质量反而恶化：discard 本轮修复（回滚到修复前），接受当前质量
- 所有 keep/discard 决策记录到 `results.tsv`，每行可追溯

**Fail-fast 原则：**
- 机械验证（编译、测试）在前，AI 评审（Review）在后
- 编译不过 → 立即修复或 discard，不浪费 Review 的 token 预算
- 便宜的检查挡住坏代码，昂贵的检查只用于已编译通过的代码

**质量棘轮：**
- 跟踪每个 task 的最佳 Review 成绩
- 修复轮次后，如果 Critical+High 总数不减反增 → 丢弃修复，回滚到修复前状态
- 质量只能提升或持平，不允许恶化

**统一结果追踪（results.tsv）：**
- 位于 `{FEATURE_DIR}/results.tsv`
- 每个 task 的每次尝试记录一行：phase, task_id, wave, attempt, action, duration, compile_ok, review_critical, review_high, decision(keep/discard), reason
- 无论成功失败都记录，实验历史一目了然

### 1. 独立 CLI 进程，独立上下文
- 每个可独立完成的工作阶段，必须启动**独立的 `claude` CLI 进程**来执行（通过 shell 脚本调用 `claude -p`）
- **不是 subagent（Agent tool）**，而是全新的 CLI 进程——拥有完全独立的上下文窗口，零历史污染
- 禁止在一个 CLI 进程中堆积多个阶段的工作，避免长流程上下文膨胀导致质量下降
- 进程之间**不共享运行时上下文**，只通过持久化文档交流

### 2. 文档是唯一的跨进程通信方式
- 每个 CLI 进程的输入必须来自文件系统中的文档（需求文档、plan、task 定义等）
- 每个 CLI 进程的输出必须持久化为文档（调研报告、plan、review 结果、代码 + commit 等）
- 禁止依赖"上一轮对话的记忆"来传递信息，所有必要信息必须写入文件
- **文档契约**：每个阶段必须明确定义输入文档和输出文档的结构（文件名、必需字段、格式）。编排层和各阶段提示词都依赖这套契约，修改契约时必须同步更新所有引用方

### 3. 最小化单个进程的职责（但不过度拆分）
- 一个 CLI 进程只做一件事：调研、写 plan、review plan、写代码、review 代码……
- 职责越单一，提示词越精准，输出质量越高
- **拆分判断标准**：当一个进程的输入上下文 + 预期工作量可能超过上下文窗口的 60% 时才拆分。短任务（如单轮 review）不必拆为独立进程，避免冷启动开销（每个 CLI 进程都会加载系统提示 + 项目文档）超过收益
- **反面原则**：不要为了拆而拆。如果一个迭代循环中每轮上下文增量很小（如 review 反馈只有几百字），在同一个进程内循环即可

### 4. 编排层只做调度，不做业务
- 外层编排脚本（如 `auto-work-loop.sh`）只负责：阶段判断、启动 CLI 进程、检查产出物、决定下一步
- 编排层不应包含业务逻辑（如"如何写 plan"、"如何 review"），这些全部下沉到各阶段的提示词中
- 编排层通过检查**完成标记**来判断阶段是否完成，实现断点续跑（见原则 6）

### 5. 质量优先的上下文管理
- **质量优先于成本**：当质量和成本冲突时，永远选择质量。多启动一个 CLI 进程的 token 开销远小于上下文污染导致的返工成本
- 设计每个 CLI 进程的输入时，只注入**该阶段必需的最小上下文**
- 例如：开发阶段只需要当前 task 定义 + plan 中相关部分，不需要调研报告全文
- 大文档应提供摘要或只注入相关章节，而非全量灌入
- 注意：每个独立 CLI 进程有固定 token 开销（系统提示 + CLAUDE.md + constitution 加载），但这是为质量付出的合理代价，不应因此而合并本该隔离的阶段

### 6. 容错与原子性
- 每个阶段完成后，必须写入明确的**完成标记**（如在输出文档末尾写入 `<!-- STATUS: COMPLETE -->`，或生成独立的 `.done` 标记文件）
- 编排层判断阶段完成时，必须检查完成标记，而非仅检查文件是否存在（文件存在 ≠ 内容完整，进程可能中途崩溃留下半成品）
- 检测到不完整的产出物时，编排层应删除半成品并重新执行该阶段，而非基于损坏文档继续

---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则：**

参数格式：`<version_id> <feature_name> [需求描述（剩余部分，可选）]`

1. **第一个词**：`version_id`（版本号，如 `v0.0.3`）
2. **第二个词**：`feature_name`（功能名称，如 `cooking-system`，用于创建目录）
3. **剩余部分**（可选）：补充需求描述（自然语言）

**需求来源（按优先级合并）：**
1. 自动读取 `docs/version/{version_id}/{feature_name}/idea.md`（如果存在）
2. 用户传入的需求描述（第三个参数及之后的部分）
3. 两者都存在时，idea.md 为基础需求，用户输入为补充说明，合并传入
4. 两者都不存在时，使用 AskUserQuestion 让用户提供需求

**示例：**
- `v0.0.3 cooking-system` — 仅靠 idea.md 驱动
- `v0.0.3 cooking-system 额外要求：支持组队烹饪` — idea.md + 补充需求
- `v0.0.2-mvp npc-dialog NPC对话系统，支持多轮对话` — 无 idea.md 时纯参数驱动

**验证：**
- 如果参数不足 2 部分，使用 AskUserQuestion 让用户补充
- 确认 `docs/version/{version_id}/` 目录存在（不存在则创建）

解析完成后，设定以下变量：
- `VERSION_ID` = 版本 ID
- `FEATURE_NAME` = 功能名称
- `REQUIREMENT` = 合并后的需求描述文本（idea.md 内容 + 用户补充）
- `FEATURE_DIR` = `docs/version/{VERSION_ID}/{FEATURE_NAME}`

---

## 执行

参数解析完成后，使用 Bash 工具执行以下命令启动全自动流程：

```bash
# 有用户补充需求时
bash .claude/scripts/auto-work-loop.sh "{VERSION_ID}" "{FEATURE_NAME}" "{用户输入的补充需求}"

# 无补充需求时（纯 idea.md 驱动）
bash .claude/scripts/auto-work-loop.sh "{VERSION_ID}" "{FEATURE_NAME}"
```

**注意**：idea.md 的读取和合并由脚本内部处理，command 只传用户输入的补充部分（第三个参数）。

脚本会自动完成以下阶段：

### 阶段零：需求分类
- 分析需求内容，判断工作类型：
  - **research**（需要调研）：全新系统设计、需要技术选型、涉及不熟悉领域
  - **direct**（直接开发）：Bug 修复、已有系统优化/扩展、需求明确且有参考实现
- 分类结果缓存到 `classification.txt`，重跑时跳过

### 阶段零-B：技术调研（仅 research 类型）
- 仅当需求分类为 `research` 时执行
- 复用 `research-loop.sh` 进行自动调研（对应 research/loop 命令） + Review 迭代（最多 6 轮）
- 调研结论会自动注入后续阶段的上下文中
- `direct` 类型直接跳过此阶段

### 阶段一：生成 feature.json
- 启动 Claude 实例，根据需求描述自动生成结构化的 `feature.json`
- JSON 格式组织具体需求与验收标准，对模型有更强约束力
- 包含 requirements（含 acceptance_criteria）、interaction_design、technical_constraints 等
- 如果有调研结论，会作为技术参考输入

### 阶段二：Plan 迭代循环（输出 plan.json）
- 复用 `feature-plan-loop.sh` 的完整流程
- 自动创建方案 → Review → 修复 → 直到收敛
- 输出 plan.json（JSON 格式的技术规格），复杂方案拆分为 plan/*.json 子文件

### 阶段三：任务拆分
- 将 plan.json 拆分为可独立开发、验证、提交的最小任务单元
- 每个任务输出为 `tasks/task-NN.md`，包含范围、验证标准、依赖关系
- 任务按依赖顺序排列，确保每个任务完成后代码状态健康
- **并行友好拆分**：鼓励将服务端任务和客户端任务设计为同一前置依赖，使其可并行

### 阶段四：波次并行开发 + 提交（原子化循环 + git worktree）

**并行策略**：基于任务依赖关系进行拓扑排序，将任务分组为"波次"（wave）：
- 同一波次内的任务**无互相依赖**，可以并行开发
- 波次之间**严格顺序**执行（后续波次的任务依赖前序波次的输出）
- 典型拆分：Wave 0 (Proto定义) → Wave 1 (Server逻辑 + Client逻辑并行) → Wave 2 (集成)

**执行模式**：
- **单任务波次**：直接在主工作目录执行（零额外开销，等同原有逻辑）
- **多任务波次**（利用 git worktree 并行）：
  1. 选一个涉及客户端的任务在**主工作目录**执行（保留完整 Unity 编译验证）
  2. 其余任务各自创建 **git worktree** 独立工作空间，**后台并行**执行
     - 每个 worktree 包含 freelifeclient/P1GoServer/Proto 三个仓库的独立分支
     - Worktree 任务跳过 Unity 编译检查（`SKIP_CLIENT_COMPILE=1`），仅做服务端编译验证
  3. 所有任务完成后，**合并 worktree 分支**到主分支
  4. 合并后做一次**统一编译验证**，捕获合并引入的问题
  5. 如果合并冲突，**自动降级**为在主工作目录顺序重新执行冲突任务

**每个 task 仍是原子变更单位**，遵循 Keep/Discard 机制：
  1. **保存 git 检查点**（各仓库 HEAD commit hash）
  2. **编码**（复用 `feature-develop-loop.sh`，约束为当前任务范围）
  3. **机械验证**（编译 + 测试 — fail-fast，便宜检查先跑）
  4. **主观评估**（Review — 仅编译通过后才执行）
  5. **判定**：
     - 质量达标 → **Keep**：commit + 记录 results.tsv
     - 开发异常 → **Discard**：git reset 到检查点 + 记录 results.tsv
  6. **质量棘轮**：修复轮次中如果 Critical+High 不减反增 → 丢弃修复，回滚到修复前
- 所有 task 的结果（keep/discard/原因/耗时/质量指标）记录到 `{FEATURE_DIR}/results.tsv`
- 已完成/已丢弃的任务会被标记，中断后重新运行会跳过

### 阶段四-B：Unity MCP 验收测试（自动触发）
- 仅当同时满足两个条件时执行：① 有 .cs 文件变更 ② plan 中含 `[TC-XXX]` 验收用例
- 启动 `claude -p` 进程（带 MCP 访问），在 Unity Play 模式下逐用例执行操作+截图验证
- 有失败用例 → 自动修复+重测（最多 2 轮）
- 验收报告写入 `{FEATURE_DIR}/mcp-verify-report.md`

### 波次间 Meta-Review（自动改进）
- 每个波次结束后，启动 Meta-Review Agent 分析工作过程
- 检测反复出现的错误模式（编译失败类型、Review 中反复出现的同类问题、discard 原因等）
- 如发现可规避的系统性问题，自动生成规则文件到 `.claude/rules/auto-work-lesson-*.md`
- 后续 auto-work 运行时自动加载这些规则，提升首次成功率
- 触发条件：至少完成 2 个 task 且有 discard 或多次重试时才触发（节省 token）

### 阶段五：生成模块文档
- 将完成的功能总结归档到 `docs/knowledge/{模块}/` 对应目录
- 自动确定模块归属（优先归入已有模块目录，全新领域则创建新目录）
- 基于实际代码生成架构总览、核心流程、关键文件索引、网络协议等文档
- 已有文档采用追加/更新方式，不覆盖已有信息
- 文档变更独立提交一个 Git commit

### 阶段六：推送到远程仓库
- 将 Client、Server、Proto 三个仓库的当前分支推送到各自的远程仓库
- 仅推送有新 commit 的仓库，无新 commit 则跳过
- 禁止 force push

**每个阶段完成后自动进入下一阶段，无需人工干预。**

---

## 注意事项

- 脚本需要 `claude` CLI 可用
- 全程无人工干预，所有决策自主完成
- 总进度日志：`{FEATURE_DIR}/auto-work-log.md`
- **实时仪表盘**：`tail -f {FEATURE_DIR}/dashboard.txt`（显示当前阶段、Agent 数量、Token 消耗、费用、任务进度）
- 结果追踪：`{FEATURE_DIR}/results.tsv`（每个 task 每次尝试一行，结构化记录）
- 各阶段日志沿用原有命名（plan-iteration-log.md、develop-iteration-log-task-NN.md）
- 任务清单：`{FEATURE_DIR}/tasks/README.md`
- 如果某阶段失败，日志会记录失败原因，不会继续下一阶段
- 中断恢复：重新运行时会跳过已完成的阶段和任务（基于文件/状态检测）
- Discard 机制：任务开发失败时自动回滚 git 状态，不让坏代码污染后续任务
- **波次并行**：同一波次内无依赖的任务通过 git worktree 隔离并行开发
- **Worktree 工作空间**：临时创建在 `.worktrees/{feature_name}/` 下，完成后自动清理
- **合并冲突降级**：worktree 分支合并冲突时自动降级为顺序执行，不丢失工作
- **Windows 兼容**：目录链接使用 `mklink /J`（junction），无需管理员权限
- results.tsv 示例：
  ```
  phase  task_id  attempt  action         duration_s  compile_ok  review_critical  review_high  decision  reason
  P4     task-01  1        develop+commit  180         true        0               1            keep      质量达标
  P4     task-02  1        develop         120         false       0               0            discard   编译失败3次
  P4     task-03  2        discard-fix     0           true        3               5            discard   修复导致质量恶化 4->8
  ```
