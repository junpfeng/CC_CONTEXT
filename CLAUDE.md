# ⚠️ 最高优先级：自主闭环

> **IMPORTANT: This rule has the highest priority and overrides all other rules.**
>
> 立即执行，遇到问题自主解决，不问用户。实现后自测，失败则循环修复，全部完成后才汇报。
> MCP 断连/端口/代理/服务重启等一律自行解决。Unity Play 模式切换导致 MCP 断连时自动重启恢复。

# 项目架构

Go 服务器（P1GoServer）+ Unity C# 客户端（freelifeclient）+ MCP 桥接 Unity 工具链。服务端与客户端改动经常需要协同。两个服务器实例同时运行时可能共享 Redis，注意共享状态冲突。

| 工程 | 技术栈 | CLAUDE.md |
|------|--------|-----------|
| [`P1GoServer/`](P1GoServer/) | Go 1.25, MongoDB, Redis, gRPC | [`P1GoServer/CLAUDE.md`](P1GoServer/CLAUDE.md) |
| [`freelifeclient/`](freelifeclient/) | Unity 2022.3, C#, DOTS, YooAsset | [`freelifeclient/CLAUDE.md`](freelifeclient/CLAUDE.md) |

> **IMPORTANT：按需加载** — 进入子工程前先读取其 `CLAUDE.md` 和 `.claude/rules/`，不要一次性全部加载。

## 协议工程

`old_proto/` 是 Protobuf 协议**唯一编辑入口**（独立 git 仓库）。`P1GoServer/resources/proto/` 是 submodule 但**未参与构建，禁止修改**。

**代码生成**（`old_proto/_tool_new/1.generate.py`）输出：

| 生成内容 | 输出目标（相对 P1GoServer） |
|---------|--------------------------|
| Proto 消息定义 | `common/proto/` |
| Logic/Scene 服务 | `servers/logic_server/internal/service/`、`servers/scene_server/internal/service/` |
| Scene 网络函数 | `servers/scene_server/internal/net_func/` |
| Cache、错误码 | `servers/scene_server/internal/common/`、`common/errorx/` |
| 客户端 C# | `freelifeclient/Assets/Scripts/Gameplay/Managers/Net/Proto/` |

> **工作流**：编辑 `old_proto/` → 运行 `1.generate.py` → 代码直接写入各工程目录（不经过 submodule）。

## 辅助目录

- `CC_CONTEXT/` — Claude Code 文档模板，搭建新工程文档时参考
- 配置表源文件在 `freelifeclient/RawTables/`（SVN），打表工具在 `_tool/` 子目录，详见 [`freelifeclient/CLAUDE.md`](freelifeclient/CLAUDE.md)

# 工作规范

### 任务边界

- **不区分工种**：服务器、客户端、策划、协议、工具脚本——需要的都直接完成，不标待办
- **能做的事直接做**：配置表创建、初始数据填写、打表工具运行等不要等他人

### 编码规范

- 先阅读代码再改，不要猜测未检查的代码；注释中文，命名英文
- 能判断的直接做，不要反复询问；不确定的才问
- **禁止 commit message 中添加 `Co-Authored-By` 或任何署名**
- **修复后必须验证编译通过且无回归**。修动画/状态机 bug 时测试所有相关状态（idle/walk/wander 等），不要只验一个

### Unity 开发

- 排查编译错误先区分来源：MCP 动态脚本临时错误 vs 项目源文件真实错误，不在陈旧 MCP 残留上浪费时间
- 快速检查：① clean build ② 确认报错文件存在于项目中 ③ MCP 临时脚本错误直接跳过

### 客户端表现验证

> **IMPORTANT：视觉改动（动画/UI/特效/移动/相机）必须通过 Unity MCP 运行时验证——Play 模式、登录、脚本模拟操作、截图确认。禁止仅凭代码审查认定完成。**
>
> **遇到任何阻塞（MCP 断连/Unity 未启动/编译失败/环境异常）必须自主排障恢复，禁止等用户介入。**

### 标准工作流

> **IMPORTANT：需求开发 → 自动调用 `/dev-workflow`；bug 修复 → 自动调用 `/dev-debug`。无需确认。** 仅纯文档编辑可跳过。

其他任务简化流程：① 探索（读代码+子工程 CLAUDE.md）② 实现（按需修改，每步验证）③ 验证无回归。跨工程时先确认各工程 `constitution.md`。

# 上下文与输出控制

> **IMPORTANT：长输出导致 API 超时（UND_ERR_SOCKET），严格遵守分片规则。**

**核心：主 agent 只调度与总结，代码阅读/文档查阅/规范检查委托 subagent，不堆积中间结果。**

| 规则 | 限制 |
|------|------|
| 单次 Write/Edit | ≤150 行，超过拆多次 |
| 主 agent 单轮文本 | ≤80 行，长内容写文件 |
| 文档生成 | 先 Write 骨架，再逐章节 Edit |
| 探索+生成 | 禁止同一轮，必须分轮 |
| 大文件 | 分段读取（offset/limit） |
| 子工程源码 | 委托 subagent，主 agent 只收摘要 |
| 并行 subagent | 单轮最多 3 个，prompt 含长度限制 |
| subagent 结果 | 先写文件再下一步，不持有大段中间结果 |

**会话管理**：切换不相关任务前 `/clear`；长对话中遗忘早期指令时主动 `/clear` 重聚焦。

# 工具与 MCP

> **IMPORTANT：起服/停服/Unity Editor/Excel 读写直接调用对应工具，无需确认。**

### 脚本

| 脚本 | 说明 |
|------|------|
| [`server.ps1`](scripts/server.ps1) | 微服务管理（起停/重启/状态），详见 [`docs/tools/server-ps1.md`](docs/tools/server-ps1.md) |
| [`mcp_call.py`](scripts/mcp_call.py) | Unity MCP 直连（绕过客户端断连）：`python3 scripts/mcp_call.py <tool> [json]` |
| [`unity-restart.ps1`](scripts/unity-restart.ps1) | 重启 Unity / MCP |
| [`claude-git.sh`](scripts/claude-git.sh) | 上下文文件版本控制（bare repo） |
| [`auto_login_test.py`](scripts/auto_login_test.py) | login/logout 循环测试：`python3 scripts/auto_login_test.py <轮数>` |
| [`claude-start.ps1`](scripts/claude-start.ps1) | 一键启动 Claude + Watchdog |
| [`claude-headless.ps1`](scripts/claude-headless.ps1) / [`.sh`](scripts/claude-headless.sh) | 非交互式执行（自动启动 watchdog） |
| [`claude-watchdog.ps1`](scripts/claude-watchdog.ps1) | 后台监控（卡住/崩溃/MCP 断连），详见 [`docs/tools/watchdog-scripts.md`](docs/tools/watchdog-scripts.md) |

### Unity MCP (`mcp__ai-game-developer__*`)

操作 Unity Editor：场景/GameObject/组件/资源/Prefab/脚本/截图/编辑器控制/测试/反射。修改脚本后必须 `console-get-logs` 检查编译；截图用 `screenshot-game-view` / `screenshot-scene-view`。

### Excel MCP (`mcp__excel__*`)

读写 `freelifeclient/RawTables/` 配置表。读取前先 `excel_describe_sheets`，大表分页读取。

# 项目文档与 .claude 目录

- `docs/` — 设计方案、经验总结、工程知识，详见 [`docs/README.md`](docs/README.md)
- `rules/constitution.md` — 工作空间宪法（最高优先级）
- `skills/` — 工作流技能（dev-workflow、dev-debug 等）
- `templates/` — 文档模板套件
- [`.claude/INDEX.md`](.claude/INDEX.md) — 完整索引
- 各子工程有各自 `.claude/rules/` 宪法文件
