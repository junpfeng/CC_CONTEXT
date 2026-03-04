# claude-mem — Claude Code 持久化记忆插件

## 概述

claude-mem 是 Claude Code 的**持久化记忆压缩系统**，解决 Claude Code 会话间上下文丢失的问题。

**核心能力：**

- **跨会话记忆**：自动捕获每次会话的工作内容，生成语义摘要
- **自然语言搜索**：通过语义搜索回忆过去做过的事
- **智能代码探索**：基于 AST 解析的代码结构搜索，比全文读取节省 4-8 倍 Token
- **计划驱动开发**：创建文档驱动的实施计划，用子代理分阶段执行

**技术栈：**

| 组件 | 技术 | 作用 |
|------|------|------|
| Worker Service | HTTP API (端口 37777) | 接收 Hook 数据，生成摘要 |
| 数据存储 | SQLite | 存储会话、观察记录、摘要 |
| 向量搜索 | Chroma | 混合语义 + 关键词搜索 |
| MCP Server | Node.js | 提供搜索工具给 Claude Code |
| AST 解析 | tree-sitter | 代码结构化分析 |

**作者：** Alex Newman (@thedotmack)
**版本：** 10.5.2
**许可证：** AGPL-3.0
**仓库：** https://github.com/thedotmack/claude-mem
**文档站：** https://docs.claude-mem.ai/

---

## 安装方法

### 前置条件

- Claude Code CLI 已安装并可用
- 插件系统已启用（需要较新版本的 Claude Code）

### 安装步骤

```bash
# 1. 添加 marketplace 源
/plugin marketplace add thedotmack

# 2. 安装插件
/plugin install claude-mem
```

安装完成后，插件会自动：

1. 注册 5 个生命周期 Hook（SessionStart / UserPromptSubmit / PostToolUse / Stop / SessionEnd）
2. 配置 MCP Server（提供搜索能力）
3. 在首次会话启动时自动安装依赖（Bun、uv、tree-sitter 解析器等）
4. 启动 Worker Service（HTTP API，端口 37777）

### 安装后的文件结构

```
~/.claude/plugins/cache/thedotmack/claude-mem/<version>/
├── .claude-plugin/plugin.json    # 插件元数据
├── .mcp.json                     # MCP 服务器配置
├── hooks/hooks.json               # 生命周期 Hook 定义
├── scripts/
│   ├── claude-mem                 # CLI 可执行文件
│   ├── mcp-server.cjs             # MCP 搜索服务
│   ├── worker-service.cjs         # Worker HTTP API
│   └── smart-install.js           # 依赖自动安装
└── skills/
    ├── make-plan/SKILL.md         # 创建计划技能
    ├── do/SKILL.md                # 执行计划技能
    ├── mem-search/SKILL.md        # 搜索记忆技能
    └── smart-explore/SKILL.md     # 代码探索技能

~/.claude-mem/settings.json        # 用户设置（自动创建）
```

---

## 四个核心技能

### 1. `/make-plan` — 创建实施计划

**用途：** 在编码前创建文档驱动的分阶段实施计划

**触发方式：** 输入 `/make-plan` 或要求 "帮我规划一个功能"

**工作原理：**

1. 使用子代理进行事实收集和文档发现
2. 始终从 **Phase 0: 文档发现** 开始
3. 确保计划引用具体的文档来源
4. 通过文档验证防止 API 臆造

**设计原则：**

- **文档可用 ≠ 已使用**：显式要求阅读文档
- **任务框架很重要**：引导代理去看文档，而不只是交代结果
- **验证 > 假设**：要求证据，不要假设
- 每个阶段自包含，有自己的文档引用

**示例：**

```
用户：/make-plan 为 NPC 添加巡逻行为
Claude：会创建一个分阶段的计划，先发现相关文档，再逐步设计实现方案
```

---

### 2. `/do` — 执行计划

**用途：** 执行由 `/make-plan` 创建的计划

**触发方式：** 输入 `/do` 或要求 "执行计划"

**执行协议（每个阶段）：**

| 步骤 | 子代理 | 职责 |
|------|--------|------|
| 1 | Implementation Agent | 编写代码 |
| 2 | Verification Agent | 证明代码工作正常 |
| 3 | Anti-pattern Agent | 检查是否有不良模式 |
| 4 | Code Quality Agent | 审查代码质量 |
| 5 | Commit Agent | 验证通过后才提交 |

**关键特性：**

- 每个步骤都需要证据（运行的命令、输出、修改的文件）
- 每个阶段使用全新子代理，避免上下文污染
- 只有验证通过后才创建 Git 提交

---

### 3. `/mem-search` — 搜索记忆

**用途：** 搜索之前会话中的工作记录

**触发方式：** 输入 `/mem-search` 或问 "我们之前怎么解决的 X？"

**适用场景：**

- "我们上次怎么修的这个 bug？"
- "之前做过类似的功能吗？"
- "上周做了什么？"

**三层搜索流程（必须按顺序）：**

**第 1 层：Search（搜索索引）** — 每条结果约 50-100 tokens

```
search(query="authentication", limit=20, project="my-project")
```

返回包含 ID、时间戳、类型、标题的索引表

**第 2 层：Timeline（时间线上下文）** — 获取前后文

```
timeline(anchor=11131, depth_before=3, depth_after=3, project="my-project")
```

返回锚点观察记录前后的时间线上下文

**第 3 层：Fetch（获取详情）** — 每条约 500-1000 tokens

```
get_observations(ids=[11131, 10942])
```

只获取筛选后的完整观察记录

**MCP 工具列表：**

| 工具 | 参数 | 说明 |
|------|------|------|
| `search` | query, type, obs_type, dateStart, dateEnd, limit, offset, orderBy | 搜索索引 |
| `timeline` | anchor/query, depth_before, depth_after, project | 时间线上下文 |
| `get_observations` | ids (数组) | 批量获取详情 |

这种三层设计可以节省约 **10 倍 Token** 消耗。

---

### 4. `/smart-explore` — AST 代码探索

**用途：** 用 tree-sitter AST 解析进行结构化代码搜索，替代全文件读取

**触发方式：** 输入 `/smart-explore` 或需要高效探索代码结构时

**核心原则：** 先获取代码地图，再按需加载实现细节

**三层探索流程：**

**第 1 层：Search（发现文件和符号）** — 约 2,000-6,000 tokens

```
smart_search(query="shutdown", path="./src", max_results=15)
```

返回排序后的符号列表（签名、行号、匹配原因）及折叠的文件视图

**第 2 层：Outline（文件结构骨架）** — 约 1,000-2,000 tokens

```
smart_outline(file_path="services/worker-service.ts")
```

返回完整的结构骨架（如果第 1 层的折叠视图已足够，可跳过）

**第 3 层：Unfold（查看实现）** — 约 400-2,100 tokens

```
smart_unfold(file_path="services/worker-service.ts", symbol_name="shutdown")
```

返回指定符号的完整源代码

**Token 消耗对比：**

| 方法 | Token 消耗 |
|------|------------|
| smart_outline | ~1,000-2,000 |
| smart_unfold | ~400-2,100 |
| smart_search | ~2,000-6,000 |
| search + unfold 组合 | ~3,000-8,000 |
| Read（全文件读取） | ~12,000+ |
| Explore agent | ~39,000-59,000 |

**何时用标准工具替代：**

- **Grep**：精确字符串 / 正则搜索
- **Read**：小文件（< 100 行）、非代码文件（JSON、Markdown、配置）
- **Glob**：文件路径模式匹配
- **Explore agent**：需要跨文件综合叙述

---

## 工作原理

### 数据流

```
Claude Code 会话
    │
    ├─ SessionStart Hook ──→ Worker Service 启动
    ├─ UserPromptSubmit Hook ──→ 记录用户输入
    ├─ PostToolUse Hook ──→ 记录工具调用结果
    ├─ Stop Hook ──→ 记录停止事件
    └─ SessionEnd Hook ──→ 生成会话摘要
            │
            ▼
     Worker Service (端口 37777)
            │
            ├──→ SQLite（结构化存储）
            └──→ Chroma（向量索引，语义搜索）
            │
            ▼
     MCP Server ←── Claude Code 查询
```

### 自动捕获的内容

- 用户的每次提问
- 工具调用的结果（文件读写、命令执行等）
- 会话开始和结束事件
- 自动生成的会话摘要

### Web 查看器

启动后可通过浏览器访问 `http://localhost:37777` 查看记忆数据库的内容。

---

## 在其他 Skill 中集成记忆查询

claude-mem 的 4 个 Skill 之间**不能嵌套调用**，但任何 Skill 执行时都可以直接调用 claude-mem 的 MCP 工具（search、timeline、get_observations）。

**集成方法：** 在自定义 Skill 的 SKILL.md 中添加记忆查询步骤，直接调用 MCP 工具即可。

**示例（dev-workflow 中的集成）：**

在 Phase 1 需求解析阶段，读取需求文档后、工程定位前，插入记忆查询步骤：

```markdown
### 1.2 记忆查询

1. 调用 search(query="<功能关键词>", limit=10) 搜索相关记忆
2. 对命中结果调用 timeline(anchor=<id>, depth_before=3, depth_after=3) 获取上下文
3. 对确认相关的记录调用 get_observations(ids=[...]) 获取完整详情
4. 输出历史记忆参考摘要

注意：如果 claude-mem MCP 工具不可用，跳过此步骤继续执行。
```

**注意事项：**

- 这不是最佳实践（Best Practice），而是一种实用的集成方式
- Skill 之间无法嵌套，但 MCP 工具是全局可用的底层能力
- 建议加上容错处理：MCP 工具不可用时跳过，不阻塞主流程

---

## 常见问题

**Q: 记忆数据存在哪里？**
A: `~/.claude-mem/` 目录下的 SQLite 数据库。

**Q: 会自动记录所有会话吗？**
A: 是的，安装后通过 Hook 自动记录，无需手动操作。

**Q: 如何查看当前记忆内容？**
A: 浏览器打开 `http://localhost:37777`，或使用 `/mem-search` 技能搜索。

**Q: Token 消耗大吗？**
A: 三层搜索设计将 Token 消耗降到最低。索引搜索每条仅 50-100 tokens，只在确认需要时才获取完整详情。

**Q: 不使用 Skill 能用到记忆吗？**
A: 录入是自动的（Hook 驱动），但查询必须主动调用 `/mem-search` 或直接使用 MCP 工具。不主动搜就等于没记。

**Q: Skill 之间能嵌套调用吗？**
A: 不能。但任何 Skill 执行时都可以直接调用 claude-mem 的 MCP 工具，实现类似效果。

**Q: 支持哪些编程语言的 AST 解析？**
A: 依赖 tree-sitter，支持大多数主流语言（Go、TypeScript、Python、Rust、Java 等）。
