---
name: dev-workflow
description: 软件工程全流程工作流（workspace 级别）。从需求文档出发，依次完成设计、审查、拆解、实现、验收、经验沉淀。支持多工程协作。
argument-hint: "[requirement-file]"
---

你是一名软件工程流程编排专家。按 Phase 0-7 有序推进，每个 Phase 完成后输出摘要并自动进入下一阶段。

## 阶段信号

启动时立即标记自动阶段（dev-workflow 全程自动，禁止询问用户）：
```bash
echo "autonomous" > /tmp/.claude_phase
```

## 参数解析

从 $ARGUMENTS 中解析：
- **需求文档路径**（必须）：第一个参数

## 断点恢复与心跳

启动时检查需求文档同目录下的 `progress.json`：
- **存在且未完成** → 读取已完成的 Phase/Task，跳过已完成部分，从中断点继续
- **不存在** → **立即创建** progress.json + heartbeat.json（P0 之前），然后从 P0 开始

**心跳**：每个 Phase/Task 开始和结束时更新 heartbeat.json（`{"phase","task","ts"}`），供 watchdog 检测。

**进度摘要**：每个 Phase 完成时，将当前进度写入 `{design_doc_dir}/dashboard.txt`（单文件覆盖），格式：当前阶段、已完成/总任务数、Keep/Discard 统计、耗时。用户可 `tail -f dashboard.txt` 实时观测。

Schema：`{ requirement_doc, design_doc_dir, current_phase, started_at, updated_at, phases: {P0..P7: {status, completed_at?}}, tasks: {TASK-XXX: {wave, status, decision, fix_rounds, reason, error_summary}}, waves: {"wave-N": {compile_ok}}, git_checkpoints: {"wave-N": {repo: sha}, "TASK-XXX": {repo: sha}}, review_rounds: [{round, critical, high}] }`

**Phase 完成标记**：每个 Phase 完成时写入 `phases.PX.completed_at` ISO 时间戳。断点恢复时优先检查 `completed_at` 而非仅靠 status 字段，确保原子性。

**Checkpoint GC**：task 确认 keep 后，删除该 task 的 `git_checkpoints.TASK-XXX`；wave 内所有 task 完成后，删除 `git_checkpoints.wave-N`。防止 progress.json 无限膨胀。

**results.tsv**：`{design_doc_dir}/results.tsv`，结构化实验追踪（P4 创建，P4/P5/P6 追加），含 `phase` 列区分来源，schema 见 P4 4.1.5。
- task status: pending → compiled → tested → completed / discarded / timeout
- phase status: pending → in_progress → completed

## 工程路径

各子工程的目录结构、宪法和使用规范见 workspace 级项目说明中引用的对应子工程说明。
进入每个 Phase 时按需读取，不预先加载。

## 知识库

项目领域知识统一存放在 `docs/` 目录，各 Phase 按需查阅 `docs/README.md` 索引定位相关文档。

## Phase 索引

**执行方式**：进入每个 Phase 前，先 Read 对应的 phase 文件获取详细指令，再按指令执行。

| Phase | 文件 | 摘要 |
|-------|------|------|
| 0 | `phases/p0-memory.md` | 查询历史记忆 |
| 1 | `phases/p1-requirements.md` | 需求解析、工程定位、依赖检查 |
| 2 | `phases/p2-design.md` | 架构+详细+事务性+接口契约+验收测试方案设计+自审循环 |
| 3 | `phases/p3-tasks.md` | 任务拆解、依赖图、任务清单 |
| 4 | `phases/p4-implementation.md` | 跨工程并行实现 |
| 5 | `phases/p5-build-test.md` | 构建验证、测试执行、Unity MCP 验收测试 |
| 6 | `phases/p6-review.md` | 3 Agent 并行审查 + 综合核对 + 审查循环 |
| 7 | `phases/p7-lessons.md` | 经验沉淀到对应文档 |

## 上下文管理

主 agent 是**纯编排者**，不持有大段中间结果。原则：

| 阶段 | 主 agent 职责 | 重活委托给 |
|------|--------------|-----------|
| P0-P1 | 直接执行（轻量） | — |
| P2 | 启动 + 收结论 | subagent（设计+审查循环） |
| P3 | 直接执行（输出短） | — |
| P4 | 调度 + 收摘要 | subagent / CLI 进程 |
| P5 | 编译命令 + 收日志 | subagent（MCP 验收测试） |
| P6 | 调度 + 收报告 | 3 review subagent |
| P7 | 直接执行 | — |

**状态卸载**：P2 设计文档、P3 任务清单、P4 实现结果全部持久化到文件。后续 Phase 从文件读取，不依赖会话上下文中的早期内容。

**设计文档冻结**：P2 完成后设计文档不再修改（仅 P6 可追加「遗留问题」节）。P4/P5/P6 subagent 引用设计文档路径自行读取，不从主 agent 传递内容。

**Phase 转换摘要上限**：主 agent 在每个 Phase 完成→下一 Phase 开始之间，输出**不超过 10 行**摘要（当前 phase 结论 + 下一步动作）。长内容写入文件，不占用会话上下文。

**大需求额外措施**（task ≥ 6 时）：
- P5 构建验证委托给 subagent，主 agent 只收 pass/fail
- P6 综合审查也委托给 subagent（第 4 个），主 agent 只做修复调度
- 每个 Phase 转换时，主 agent 输出不超过 10 行摘要

## 执行原则

- 每个 Phase/Task 开始和结束时**更新 heartbeat.json + progress.json**
- **任务超时保护**：CLI 进程用 `timeout 600` 包裹；subagent 用 `run_in_background` 启动后主 agent 设 10 分钟等待上限，超时则标记 `status: "timeout"` 并 Discard
- **Keep/Discard 原子性**：每个 Task 有 git 检查点，失败/超时可回滚，坏代码不污染后续任务
- 操作不同工程时**必须明确标注目标路径**
- **自主闭环，禁止中途询问用户**：遇到任何问题自行诊断修复并继续。只有穷尽所有合理方案（至少 3 种不同思路）仍无法解决时才停下汇报，附上：① 问题描述 ② 已尝试方案及失败原因 ③ 建议方向
- 完成后清理阶段信号：`rm -f /tmp/.claude_phase 2>/dev/null`
