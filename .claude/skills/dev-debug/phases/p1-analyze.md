## Phase 1：信息采集与 Bug 分析

### 1.0 输入解析

根据输入类型进行解析：

| 输入类型 | 解析方式 |
|----------|----------|
| Bug 描述文本 | 提取关键实体（模块、服务、组件）和现象描述 |
| 日志片段 | 提取错误级别、源文件、行号、错误信息、关键 ID |
| 截图路径 | 使用 Read 工具查看截图，提取可见的错误信息 |

---

### 1.0.3 Acceptance 模式快速通道

若输入参数包含 `--mode acceptance`，跳过标准的 1.1-1.3 信息采集流程，改为执行以下 spec-vs-code 分析：

1. **读取规格基准**：
   - 从 Bug 描述中提取关联的 idea.md 路径，读取 `### 锁定决策` 获取用户确认的技术规格
   - 从 acceptance-bug-map.md 读取失败的 AC 条目列表
2. **Spec-vs-Code 对比**：对每个失败 AC 条目：
   - grep/glob 检查规格中要求的符号（函数名、消息类型、配置字段）是否存在于代码中
   - 若存在，Read 相关代码确认实现是否与规格一致
3. **分类**：将每个 AC 失败归类为：
   - `missing_implementation`：规格要求的代码/配置不存在
   - `wrong_implementation`：代码存在但逻辑/结构与规格不符
   - `incomplete_implementation`：核心逻辑正确但缺少边界处理/错误处理
4. **输出**：生成 spec-vs-code 对比报告（替代标准的 P1 分析报告），直接进入 P2

> Acceptance 模式不收集运行时日志（P1.1）和运行时分析（P1.3），因为问题本质是"实现不符合规格"而非"运行时错误"。

---

### 1.0.2 上游诊断数据加载

若输入参数包含 `--diagnostics <path>`，在进入 1.1 采集前执行：

1. 读取指定路径的 JSON 文件，解析以下字段：
   - `screenshots`（string[]）：截图绝对路径列表
   - `logs`（object）：`unity_console`、`server_log` 等源的日志文本
   - `mcp_state`（object）：`editor_state` 等源的状态文本
   - `runtime_data`（object）：script-execute 采集的运行时数据（NPC 数量、Manager 状态等）
   - `collection_timestamp`（ISO8601）：总体采集时间
   - `source_timestamps`（object）：各数据源的独立采集时间
   - `reproduction_done`（string[]）：上游已执行的主动复现操作列表
   - `bug_category`（string）：上游初步分类（视觉表现/逻辑错误/性能/崩溃/数据异常）
   - `covered_dimensions`（string[]）：上游已覆盖的信息维度
2. **两层时效性检查**：
   - 优先检查各数据源的独立时间戳 `source_timestamps.{source_id}`（如 `source_timestamps.unity_console`）：若该源时间戳距当前时间 **≤30 分钟**，标记为"已收集"
   - 若无独立时间戳，fallback 到 `collection_timestamp`：若距当前时间 **≤30 分钟**，将对应数据源标记为"已收集"
   - 超过 30 分钟的数据源视为过期，不复用（按原逻辑重新采集）
3. 在 1.1 通用采集中，**跳过已收集的数据源**：
   - `logs.unity_console` 非空且未过期 → 跳过 unity_console 源
   - `logs.server_log` 非空且未过期 → 跳过 srv_log 源
   - `mcp_state.editor_state` 非空且未过期 → 跳过 editor_state 源
   - `screenshots` 非空且未过期 → 直接引用上游截图路径，不重新截图
   - `runtime_data` 非空且未过期 → 合并到 1.2 分析数据中，不重复 script-execute
4. **跳过已完成的复现操作**：
   - `reproduction_done` 中的操作在 P1/P2 中不重复执行（如上游已传送到目标位置并截图，dev-debug 不再重复传送截图）
   - 若需要在已复现基础上做进一步操作（如上游截了静态图，dev-debug 需要多帧对比），仍可追加
5. **利用上游分类加速 P1.2**：
   - `bug_category` 非空时，直接作为 P1.2 错误分类的初始值（仍可被采集数据修正）
   - `covered_dimensions` 帮助 P1.2 判断信息是否充分，减少不必要的第二阶段采集
6. 若 JSON 文件不存在或解析失败 → 静默忽略，按原有逻辑全量采集
7. 将上游数据合并到 P1 分析报告中，标注来源为"上游采集（bug-explore）"

**上游 briefing 加载**：若 `--diagnostics` 路径同目录下存在 `bug-briefing.md`，读取并作为 P1.0 输入的补充上下文。briefing 中的"初步怀疑方向"直接作为 P1.4 根因假设的候选之一。

> 此机制避免 bug-explore 已采集的截图/日志/MCP 状态/复现操作被 dev-debug 重复执行。
> 过期阈值 30 分钟兼顾 bug-explore 多轮交互耗时（典型 15-20 分钟）和数据新鲜度。

---

### 1.0.1 MCP 连接前置检查

涉及客户端 bug 时，在采集前**必须确保 MCP 可用**：

1. `python3 scripts/mcp_call.py list-tools` 检测连接
2. 返回正常 → 继续采集
3. 返回 "Response data is null" 或超时 → 执行恢复：
   - `powershell.exe -File scripts/unity-restart.ps1 restart-mcp`，等待 10s 后重试
   - 仍失败 → `powershell.exe -File scripts/unity-restart.ps1 restart-all`
   - 连续 3 次失败 → 向用户汇报，不要静默跳过所有 MCP 源

### 1.1 第一阶段：通用采集

无条件采集以下 6 个源。分两批执行：第一批 3 个 subagent 并行（srv_log + unity_console + client_mlog + git_recent，其中 unity_console 与 client_mlog 可合并到同一 subagent），第二批 2 个由主 agent 直接执行（editor_state + server_config，均为单次工具调用，无需 subagent）：

> 客户端日志源的完整路径和平台差异详见 [`docs/knowledge/debug-guide.md`](../../../docs/knowledge/debug-guide.md)。

| 源 | 采集方法 | 行数限制 | 降级 |
|----|---------|---------|------|
| srv_log | Grep `P1GoServer/bin/log/` 目录下最新 ERROR/WARNING 文件，tail 最后 200 行 + grep 用户关键词 | 50 行 | 目录不存在则跳过 |
| unity_console | MCP `console-get-logs(logTypeFilter="Error,Warning", lastMinutes=5, maxEntries=30)` | 30 行 | MCP 不可用且恢复失败则跳过，提示检查 Player.log |
| client_mlog | Glob `freelifeclient/Dist/Logs/*.log` 找最新文件，tail 最后 200 行 + grep 用户关键词 | 50 行 | 目录不存在则跳过（运行时路径见 debug-guide.md） |
| git_recent | `git log --oneline -10` + `git diff HEAD~3` 相关文件 | 40 行 | 非 git 仓库则跳过 |
| editor_state | MCP `editor-application-get-state` 查编译状态和 Play mode | 15 行 | MCP 不可用且恢复失败则跳过 |
| server_config | Read `P1GoServer/bin/config.toml` 关键配置段 | 15 行 | 文件不存在则跳过 |

采集约束：
- 每个 subagent prompt 中必须包含行数限制
- 降级时记录"[源名] 不可用：原因"，继续采集其他源
- 采集完成后汇总为结构化摘要

---

### 1.2 初步分析

基于采集数据进行初步判断：

**错误分类**（将 bug 归类到以下类型之一）：

| 类型 | 特征 | 典型处理方式 |
|------|------|-------------|
| 编译错误 | 构建失败 | 修复语法/类型错误 |
| 运行时 panic | `panic:` / `runtime error:` | 添加 nil 检查、边界检查 |
| 逻辑错误 | 行为不符合预期，无报错 | 追踪数据流和状态变更 |
| 性能问题 | 高延迟、高 CPU/内存 | profiling 分析热点 |
| 数据异常 | 数据不一致、丢失 | 检查存储和同步逻辑 |
| 配置错误 | 配置加载失败或值异常 | 检查配置文件和加载逻辑 |

**影响范围评估**（评估以下维度）：
- **涉及模块**：哪些包/文件可能相关
- **涉及进程**：哪些服务受影响
- **涉及工程**：参照项目 `CLAUDE.md` 中的工程列表
- **严重程度**：是否影响核心流程、是否有数据风险

**判断是否需要第二阶段采集**：根据错误分类和影响范围，确定需要追加哪些特定源。

---

### 1.2.5 快速路径判断

若 P0 的 0.6 节判定为快速路径（severity 为 `compile-error` 或 `config-missing`）：
- **跳过 1.3 第二阶段深度采集**，Stage 1 采集结果已足够定位此类问题
- 完成 1.2 初步分析后直接进入 1.4 深度分析，基于 Stage 1 数据输出分析报告，然后进入 P2

否则继续执行 1.3。

### 1.3 第二阶段：按需深度采集

根据 1.2 的分析结果，按触发条件追加特定源。**总量约束：第二阶段所有源的采集结果合计不超过 300 行。** 如果多个触发条件同时命中导致超限，按触发条件优先级截断（与 bug 类型最相关的条件优先）：

| 触发条件 | 追加源 | 采集方法 | 行数限制 |
|---------|--------|---------|---------|
| 涉及 UI/显示 | unity_screenshot | MCP `screenshot-game-view` / `screenshot-scene-view`（单次不超过 5 张） | 最多 5 张 |
| 涉及 UI/显示 | scene_hierarchy | MCP `scene-get-data` | 20 行 |
| 涉及 UI/显示 | component_data | MCP `gameobject-component-list-all` + `gameobject-component-get` | 20 行 |
| 涉及 UI/显示 | render_stats | MCP `script-execute`（读取 QualitySettings / 帧率等运行时数据） | 20 行 |
| 涉及性能 | pprof | 从对应服务的 TOML 配置中查找 pprof 相关字段获取端口，curl heap/cpu endpoint | 15 行摘要 |
| 涉及性能 | goroutine_dump | 通过 pprof goroutine endpoint（`?debug=2`）分析阻塞和死锁 | 15 行 |
| 涉及数据 | db_query | MongoDB shell 查询相关集合 | 30 行 |
| 涉及数据 | excel_config | Excel MCP `describe_sheets` + `read_sheet` | 30 行 |
| 涉及数据 | cache_query | Redis CLI 查询相关 key | 20 行 |
| 涉及协议 | proto_def | Read `old_proto/` 下相关 `.proto` 文件 | 20 行 |
| 涉及特定文件 | git_blame | `git blame` 可疑文件 | 20 行 |
| 用户提供截图 | screenshot | Read 图片文件进行视觉分析 | 无限制 |
| 客户端运行时 | gameobject_state | MCP `gameobject-find` + `gameobject-component-get` 查目标对象 | 20 行 |
| 客户端运行时 | runtime_state | MCP `script-execute` 执行 C# 读取 Manager/系统内部数据 | 20 行 |
| 客户端编译 | script_validate | MCP `console-get-logs(logTypeFilter="Error")` 检查编译错误 | 15 行 |
| 客户端日志文件 | unity_player_log | Read Unity Player.log 最后 200 行（路径见 debug-guide.md） | 30 行 |
| 客户端日志文件 | client_mlog_runtime | Read `{persistentDataPath}/Log/` 最新 .log 文件最后 200 行 | 30 行 |
| 客户端崩溃 | client_crashsight | CrashSight 云端控制台查看（需用户提供链接或截图） | 无限制 |
| 客户端线上日志 | client_cls | 腾讯云 CLS 控制台查询（需用户提供链接或截图） | 无限制 |
| 第三方 SDK | client_tapsdk | Read `{persistentDataPath}/OpenlogData/` 日志文件 | 20 行 |

---

### 1.4 深度分析

综合两阶段采集的所有数据：
- 交叉比对多源信息，识别矛盾点和关联
- 结合错误模式库匹配结果（Phase 0），缩小排查范围
- 生成 1-3 个根因假设，按可能性排序

---

### 1.5 已知问题匹配

结合 Phase 0 的历史经验，判断是否为已知问题：
- 如果是已知问题且有解决方案 → 直接引用方案，跳到 Phase 3
- 如果是已知问题的变体 → 标注关联，继续 Phase 2
- 如果是全新问题 → 继续 Phase 2

---

### 1.6 输出分析报告

输出格式：

```
Bug 分析报告：
- 采集摘要：[各源采集状态：成功/跳过/降级]
- 错误类型：[编译错误/panic/逻辑错误/性能问题/数据异常/配置错误]
- 现象描述：[用户描述 + 采集证据]
- 相关模块：[module1, module2]
- 相关进程：[service1, service2]
- 严重程度：[高/中/低]
- 错误模式匹配：[EP-xxx 或"无匹配"]
- 初步假设：[根因猜测 1-3 个，按可能性排序]
```

**自动进入 Phase 2。**
