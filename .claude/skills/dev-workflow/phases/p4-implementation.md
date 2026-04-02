# Phase 4：实现

> 领域依赖：无

## 4.1 Wave 执行循环

按 P3 输出的 wave 顺序逐 wave 执行。每个 wave 内的任务并行。

```
for each wave (0, 1, 2, ...):
  更新 heartbeat.json（当前 wave + 时间戳）
  4.1.1  保存 git 检查点（wave 级 + task 级）
  4.1.2  按任务数选择执行模式（subagent / CLI 进程）
  4.1.3  收集结果 → 更新 progress.json + heartbeat.json
  4.1.4  有超时 → Discard（见 4.3）
  4.1.5  记录到 results.tsv
  4.1.6  波次间 Meta-Review（条件触发）
  4.1.7  Post-wave 编译验证（fail-fast）
```

### 4.1.1 保存 git 检查点

**双层检查点**（wave 级 + task 级）：

```bash
cd P1GoServer && git rev-parse HEAD    # → CKPT_server
cd freelifeclient && git rev-parse HEAD # → CKPT_client
cd old_proto && git rev-parse HEAD      # → CKPT_proto
```

1. **Wave 级**：每 wave 开始前保存到 `git_checkpoints.wave-N`（整 wave Discard 时使用）
2. **Task 级**：每个 task 派发前保存到 `git_checkpoints.TASK-XXX`（单 task Discard 时使用）

**回滚策略**：
- 单个 task 失败 → 回滚到该 task 的检查点（`git_checkpoints.TASK-XXX`），仅撤销该 task 的变更
- 同 wave 内多个 task 有文件重叠 → 退化为 wave 级回滚（`git_checkpoints.wave-N`）
- 整 wave 编译失败且无法定位到单个 task → wave 级回滚

### 4.1.2 执行模式选择

| Wave 任务数 | 执行模式 | 说明 |
|-------------|----------|------|
| 1 | 主 agent 直接执行 | 零开销 |
| 2-3 | subagent 并行 | `dev-workflow-implementer`，会话内隔离 |
| 4+ | **CLI 进程并行** | `claude -p` 独立进程，突破 subagent 上限 |

**CLI 进程模式**（4+ 任务时）：

每个任务用 Bash `run_in_background` 启动独立 `claude -p` 进程：
- prompt 包含：设计文档路径 + 任务编号 + 工程路径 + 编译命令 + 结果写入路径
- 参数：`--output-format json --max-turns 80`
- 涉及客户端的任务优先留给 subagent（保留 MCP 访问能力）
- 主 agent 等所有进程完成后读取各结果文件

### 4.1.3 结果收集

每个 subagent/CLI 进程完成后，主 agent 只记录摘要，**不读实现代码**：
- 修改了哪些文件（路径列表）
- 编译是否通过
- 遇到的问题（如有）

更新 progress.json 中对应 task 的 status。

### 4.1.5 记录到 results.tsv

P4 开始时在 `{design_doc_dir}/results.tsv` 创建（如不存在）：

```
phase	task_id	wave	attempt	action	duration_s	compile_ok	review_critical	review_high	decision	reason
```

每个 task 完成/discard/timeout 时追加一行：
- `phase`：P4 / P5 / P6（标识数据来源，避免混淆）
- `action`：develop / compile / discard / timeout
- `compile_ok`：true / false
- `review_critical` / `review_high`：P4/P5 阶段填 `0`（数值类型统一），P6 审查时填实际值
- `decision`：keep / discard
- `reason`：简要原因

> P5 和 P6 也向同一 results.tsv 追加行，通过 `phase` 列区分来源。所有数值列统一为整数（不使用 `-`），便于 P7 聚合分析。

**attempt 列语义**：同一 task_id 的连续行共享递增的 attempt 编号。首次开发 attempt=1，每次 Discard 后重试 attempt+1，编译修复轮 attempt 不变（同一次尝试内的修复）。attempt 值从 results.tsv 的已有行推导，不另存 progress.json。

### 4.1.6 波次间 Meta-Review（条件触发）

每个 wave 完成后，检查是否需要触发 Meta-Review：

**触发条件**（任一满足）：
1. 本 wave 有 task 被 discard
2. results.tsv 累计行数 ≥ 4（有重试发生）
3. 任何 task 的 attempt ≥ 3（触达修复上限）

**执行方式**：启动一个独立 subagent（不污染主 agent 上下文），输入：
- results.tsv 最近 30 行
- 最近 2 个 task 的错误摘要（从 progress.json 的 `error_summary`）
- 现有 `.claude/rules/auto-work-lesson-*.md` 文件列表

**输出**：最多 2 条新规则写入 `.claude/rules/auto-work-lesson-*.md`，分析摘要追加到 `{design_doc_dir}/meta-review.md`。

**未触发则跳过**（零开销）。

### 4.1.7 Post-wave 编译验证（fail-fast）

每个 wave 所有 task 完成后，**立即执行编译验证**（不等到 P5）：

1. **Server**：`cd P1GoServer && make build`
2. **Client**（如有 .cs 变更）：
   - 通过 `console-get-logs` 检查 Unity 编译错误
   - **MCP 可用性检查**：`mcp_call.py list-tools` 确认 tool count > 0。返回 0 表示 Unity 处于 SAFE MODE（编译有残留错误），需执行 `scripts/unity-restart.ps1` 重启后重试
3. **Proto**（如有协议变更）：确认生成代码已更新

**失败处理**：
- 定位到具体 task 的变更引起 → 主 agent 修复，最多 3 轮
- 无法定位 → wave 级修复，最多 3 轮
- 3 轮仍失败 → Discard（回滚检查点）

**状态写入**：编译通过后，在 progress.json 中写入 `waves.wave-N.compile_ok: true`。P5 检查此标记，为 true 则跳过重复编译。

**收益**：不编译的代码不进入 P5/P6，节省测试和 review 的 token 预算。

### 4.1.8 Post-wave 原子提交

> **原则**：每个 task 对应一个原子 commit，可独立评估和回滚（`feedback_git_atomic_commit`）。

编译通过后，对本 wave 中每个 Keep 的 task **逐个创建 commit**：

1. 从 subagent/CLI 返回的 `files_changed` 列表获取该 task 修改的文件
2. `git add <file1> <file2> ...`（精确暂存，禁止 `git add .`）
3. commit message 格式：`<feat/fix>(模块) TASK-XXX: 简要描述`
4. 同一 wave 内多个 task 按编号顺序依次提交

**跨工程 task**（如协议生成涉及 old_proto + P1GoServer + freelifeclient）：每个工程独立 commit，message 相同。

**Discard 的 task**：已回滚，无文件可提交，跳过。

**与 4.1.1 检查点的关系**：原子提交后，该 task 的 git 检查点可清理（commit 本身就是检查点）。

## 4.2 隔离规范与完成性断言

无论 subagent 还是 CLI 进程，每个执行单元的输入只包含：

1. **开发指南路径**：`phases/developing-guide.md`（标准化 7 步流程 + 机械规则扫描清单）
2. **设计文档路径**（自行 Read，不从主 agent 上下文继承）
3. **任务编号和定义**
4. **目标工程路径**
5. **编译命令**（Server: `cd P1GoServer && make build`；Client: `console-get-logs`）

**完成性断言**：
- **subagent 模式**：prompt 中要求返回结果包含 `ALL_FILES_IMPLEMENTED: true/false` + 文件列表。主 agent 从 subagent 返回文本中 grep 此标记
- **CLI 进程模式**：prompt 要求将结果写入 `{design_doc_dir}/task-results/TASK-XXX.json`，格式：`{"all_files_implemented": bool, "files_changed": [...], "compile_ok": bool, "issues": [...]}`
- 未声明或为 false → 重新派发该任务（最多追加 2 次）
- 配置参数必须从设计文档 + 已有代码模式推断填写，**禁止留 TODO/占位符**

## 4.3 超时与 Discard

| 情况 | 处理 |
|------|------|
| 编译通过（4.1.7） | 标记 task status = "compiled"，进入 P5 |
| 编译失败（4.1.7） | 主 agent 修复，最多 3 轮 |
| 修复 3 轮仍失败 | **Task Discard**：回滚 task 检查点（`git_checkpoints.TASK-XXX`），标记 status = "discarded" |
| 文件重叠无法单 task 回滚 | **Wave Discard**：回滚 wave 检查点（`git_checkpoints.wave-N`） |
| **任务超时**（10 分钟无响应） | **Task Discard**：标记 status = "timeout"，回滚 task 检查点 |

> **Discard 语义区分**：P4/P5 的 Task Discard = 放弃该任务（终态）。P5/P6 的修复回滚 = 仅撤销本轮修复尝试，task 保留，继续下一轮或接受当前质量。

CLI 进程用 `timeout 600` 包裹。subagent 用 `run_in_background` 启动，主 agent 设 10 分钟等待上限。

## 4.4 上下文预算

- 主 agent 在 P4 中**不读取实现代码**，只读结果摘要
- 设计文档、编码规范由执行单元自行加载
- 保留上下文窗口给 P5/P6/P7

## 4.5 编码要点

执行单元实现时遵守各子工程编码规范，额外关注：
- **事务性**：先验证后执行、失败回滚、请求 ID 追踪
- **错误处理**：不忽略错误、包装上下文信息
- **并发安全**：共享变量加锁、及时释放
- **资源管理**：确保资源释放、超时控制

**所有 wave 执行完成后自动进入 Phase 5。**
