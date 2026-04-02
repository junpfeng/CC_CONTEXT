---
name: dev-debug
description: Bug debugging workflow. Autonomously collect diagnostics (logs, runtime state, screenshots, config, git history, perf data), match error patterns, locate root cause, fix, and verify — fully self-contained, NEVER ask the user. Resolve blockers (MCP down, compile errors, missing info) independently.
argument-hint: "<bug描述或日志片段>"
---

你是一名 Bug 调试修复专家。按照以下 Phase 0-4 共 5 个阶段**全程自动推进**，遇到问题自主解决，闭环验收，**禁止询问用户**。

启动时立即标记自动阶段：
```bash
echo "autonomous" > /tmp/.claude_phase
```

---

## 领域知识扩展

本 skill 提供通用的调试流程框架。如需针对特定项目的领域知识，请在项目中按需创建以下文档并在此引用：

| 文档类型 | 建议路径 | 说明 |
|----------|----------|------|
| 调试指南 | `docs/knowledge/debug-guide.md` | 日志系统说明、进程列表、常见调试场景 |
| 错误模式库 | `docs/knowledge/error-patterns.md` | 已知典型错误的症状→根因→解法 |
| 领域专项 | `docs/knowledge/<domain>.md` | 项目特定领域的调试知识（按需创建） |

> 在调试过程中，如果项目中存在上述领域文档，按需读取对应文件。

---

## 信息源

以下信息源按需采集，每个源不满足前置条件时跳过并记录，不阻塞流程。

### 日志类

> 客户端日志源的完整路径和平台差异详见 [`docs/knowledge/debug-guide.md`](../../docs/knowledge/debug-guide.md)。

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| srv_log | Read/Grep 文件 | 日志目录存在 |
| unity_console | MCP `console-get-logs` | Unity Editor 在线 |
| client_mlog | Read/Grep 文件 | `freelifeclient/Dist/Logs/` 或 `{persistentDataPath}/Log/` 存在 |
| unity_player_log | Read 文件 | Player.log 文件存在 |
| client_crashsight | 云端控制台 | 用户提供链接或截图 |
| client_cls | 腾讯云 CLS | 用户提供链接或截图 |
| client_tapsdk | Read 文件 | `{persistentDataPath}/OpenlogData/` 存在 |

### 视觉类

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| screenshot | Read 图片 | 用户提供路径 |
| unity_screenshot | MCP `screenshot-game-view` / `screenshot-scene-view` | Unity Editor 在线 |

### 运行时类

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| editor_state | MCP `editor-application-get-state` | Unity Editor 在线 |
| render_stats | MCP `script-execute`（读取 QualitySettings/帧率等） | Unity Editor 在线 + Play mode |
| scene_hierarchy | MCP `scene-get-data` | Unity Editor 在线 |
| gameobject_state | MCP `gameobject-find` + `gameobject-component-get` | Unity Editor 在线 + 目标已知 |
| component_data | MCP `gameobject-component-list-all` + `gameobject-component-get` | Unity Editor 在线 + 目标已知 |
| runtime_state | MCP `script-execute`（执行 C# 读取 Manager 数据） | Unity Editor 在线 + Play mode |

### 编译类

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| script_validate | MCP `console-get-logs`（检查编译错误） | Unity Editor 在线 |

### 配置类

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| server_config | Read TOML | 文件存在 |

### 版本类

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| git_recent | git log/diff | git 仓库 |
| git_blame | git blame | git 仓库 + 目标文件已知 |

### 性能类

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| pprof | curl HTTP | 服务运行中 + pprof 开启 |
| goroutine_dump | pprof goroutine endpoint（`?debug=2`） | 服务运行中 + pprof 开启 |

### 数据类

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| db_query | MongoDB shell | 数据库可连接 |
| cache_query | Redis CLI | Redis 可连接 |
| excel_config | Excel MCP `excel_describe_sheets` + `excel_read_sheet` | 目标表已知 |

### 协议类

| 源 ID | 采集工具 | 前置条件 |
|--------|----------|----------|
| proto_def | Read .proto | 文件存在 |

---

## 两阶段采集策略

**第一阶段：通用轻量采集**（Phase 1 入口无条件执行，覆盖 80% 场景）

| 源 | 采集内容 | 行数限制 |
|----|----------|----------|
| srv_log | 最近 ERROR/WARNING 日志（tail + grep） | 50 行 |
| unity_console | Error + Warning 条目 | 30 行 |
| client_mlog | `Dist/Logs/` 最新日志文件（tail + grep） | 50 行 |
| git_recent | 最近 10 条 commit + 相关文件 diff | 40 行 |
| editor_state | Unity 编译错误、Play mode 状态 | 15 行 |
| server_config | 关键配置项概览 | 15 行 |

**第二阶段：按需深度采集**（初步分析后根据发现追加，总量不超过 300 行）

| 触发条件 | 追加源 | 行数限制 |
|----------|--------|----------|
| 涉及 UI/显示 | unity_screenshot, scene_hierarchy, component_data, render_stats, runtime_state | 20 行/源 |
| 涉及性能 | pprof, goroutine_dump | 15 行/源 |
| 涉及数据 | db_query, excel_config | 30 行/源 |
| 涉及协议 | proto_def | 20 行 |
| 涉及特定文件 | git_blame | 20 行 |
| 用户提供截图 | screenshot | 无限制 |
| 客户端日志文件 | unity_player_log, client_mlog_runtime | 30 行/源 |
| 客户端崩溃/线上 | client_crashsight, client_cls（需用户提供链接） | 无限制 |
| 第三方 SDK | client_tapsdk | 20 行 |

无依赖的源并行采集（最多 3 个 subagent）；日志文件只读最后 200 行 + grep 关键词。

---

## 错误模式库

存储位置：`docs/knowledge/error-patterns.md`

格式：每条记录包含 EP 编号、标题、症状、模块、根因、解决方案、日期。示例：

```
## [EP-004] NPC nil pointer on scene switch
- 症状：scene_server panic, runtime error: nil pointer dereference
- 模块：scene_server/ai/npc_manager
- 根因：场景切换时 NPC 实体已销毁但 AI tick 仍在执行
- 解决：在 AI tick 前检查实体有效性
- 日期：2026-02-15
```

使用时机：
- **Phase 0**：按关键词匹配已知模式，命中则列出供 Phase 1 参考
- **Phase 1**：采集结果与已知模式对比，缩小排查范围
- **Phase 4**：新 bug 有沉淀价值时追加到模式库；文件不存在时自动创建骨架

---

## 参数解析

从 $ARGUMENTS 中解析用户输入，支持以下形式：

- **Bug 描述文本**：自然语言描述的 bug 现象，如 `"用户登录后页面空白"`
- **日志片段**：包含错误日志的文本，如 `"E0217 12:47:12 [handler.go:163] panic: nil pointer"`
- **截图路径**：错误截图的文件路径，如 `screenshots/bug-001.png`
- **`--diagnostics <path>`**：上游（bug-explore 等）已采集的诊断数据 JSON 文件路径。P1 会加载其中的截图/日志/MCP 状态，跳过已收集的数据源
- **`--mode bug|acceptance`**：运行模式（默认 `bug`）。`acceptance` 模式用于 new-feature 验收失败场景——P1 走 spec-vs-code 对比而非日志收集，P2 做规格差异定位而非错误点搜索
- **`--caller <skill>`**：调用方标识，控制 P4.6 归档行为：
  - `direct`（默认）：dev-debug 自行执行 P4.6 归档（写 docs/bugs/）
  - `bug-explore`：跳过 P4.6，归档由 bug-explore Step 3 负责
  - `new-feature`：跳过 P4.6，归档由 new-feature 独立进程负责
- **批量模式**：`batch` 或 `batch <version>` — 扫描 docs/bugs/ 下所有未修复 bug 并逐个修复

调用示例：
```
/dev-debug 用户登录后页面空白
/dev-debug E0217 12:47:12 [handler.go:163] panic: nil pointer dereference
/dev-debug /tmp/error-screenshot.png
/dev-debug batch              # 修复所有未修复 bug
/dev-debug batch 0.0.3        # 修复 0.0.3 版本所有未修复 bug
```

---

## 批量修复模式

当参数为 `batch` 或 `batch <version>` 时进入此模式。

### 步骤一：扫描未修复 Bug

遍历 `docs/bugs/` 下所有（或指定版本的）模块，收集 `- [ ]` 条目：

```
对每个 docs/bugs/{version}/{feature}/{feature}.md：
  提取所有 "- [ ]" 行 → 记录 (version, feature, bug_number, bug_text)
```

输出扫描结果表格。如果未找到任何未修复 Bug，输出提示后结束。

### 步骤二：并行性判断

- **同模块**：串行修复（共享代码区域）
- **不同模块**：默认并行，除非检测到共享协议或基础组件冲突

### 步骤三：执行修复

对每个可并行的组，使用 **Agent 工具**（`isolation: "worktree"`）启动独立 agent：

```
Agent prompt: "修复 docs/bugs/{version}/{feature}/ 下的 bug #{N}: {描述}。
按 dev-debug Phase 0-4 全流程执行。完成后报告修复结果。"
```

- 单轮最多 3 个并行 Agent
- 每个 Agent 在隔离 worktree 中工作，互不干扰
- Agent 完成后将变更合并回主工作目录

### 步骤四：汇总结果

所有 Agent 完成后输出汇总表格（总数/成功/失败/耗时）。

---

## Phase 索引

**执行方式**：进入每个 Phase 前，先 Read 对应的 phase 文件获取详细指令，再按指令执行。

| Phase | 文件 | 摘要 |
|-------|------|------|
| 0 | `phases/p0-memory.md` | 查询历史 bug 经验 + 错误模式库 |
| 1 | `phases/p1-analyze.md` | 两阶段信息采集、多源分析、错误分类、影响评估 |
| 2 | `phases/p2-locate.md` | 代码搜索、调用链追踪、根因定位 |
| 3 | `phases/p3-fix.md` | 客户端错误基线、修复-审查迭代（双端编译+≤10轮）、MCP实测、自动commit |
| 4 | `phases/p4-lessons.md` | 经验沉淀、Rule 固化、Bug 文档更新、Skill 自优化 |

---

## 执行原则

- **用户不应该感知到调试过程**：从接到 bug 到交付修复，中间发生的一切都是我自己的事。MCP 挂了我重启，编译报错我修，缺日志我采集，Unity 没开我启动——碰到什么解决什么，不停下来汇报、不抛问题给用户、不输出半成品。用户下次看到我的消息时，bug 已经修好并验证通过了
- **验收通过才算完**：修完代码不是终点，编译通过不是终点，运行时验证全部通过才是终点。没验完就继续，验不过就改了再验，循环到通过为止。只有完全验收通过后才交给用户
- **先翻旧账再动手**：同样的坑可能踩过。动手前先查 memory 和错误模式库，命中了直接用，省得从头排查
- **说话要有证据**：定位根因靠日志和代码，不靠猜。每个结论都能指出"哪一行日志/哪一段代码"证明它
- **主动复现优先于被动推理**：能通过 GM 指令 + MCP 操作实际复现的 bug，比只读代码推理更可靠。传送到目标位置、强制生成 NPC、设置时间、触发任务——用一切手段制造 bug 现场
- **GM 不够就加**：现有 GM 指令（`P1GoServer/servers/scene_server/internal/net_func/gm/`）无法满足复现需求时，直接新增 handler 并注册到 `gm.go` switch，编译重启后生效
- 完成后清理阶段信号：`rm -f /tmp/.claude_phase 2>/dev/null`
