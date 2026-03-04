# .claude 目录索引

| 路径 | 说明 |
|------|------|
| `rules/constitution.md` | 工作空间宪法（最高优先级规则） |
| `rules/evolution.md` | 文档持续演进规则 |
| `templates/` | 通用文档模板套件，用于新项目快速搭建 Claude Code 文档体系 -> [`README.md`](templates/README.md) |
| `skills/dev-workflow/` | 软件工程全流程工作流（需求->设计->实现->验收）— 用法：`/dev-workflow` |
| `skills/dev-debug/` | Bug 调试修复工作流（分析->定位->修复->沉淀）— 用法：`/dev-debug` |
| `skills/perf-analyze/` | 代码性能分析与优化助手（瓶颈定位->热点优化->内存审查）— 用法：`/perf-analyze` |
| `skills/wsl-env/` | WSL 环境管理助手（仅限 Windows+WSL）— 用法：`/wsl-env` |
| `skills/create-context/` | Claude Code 上下文文档生成与补充（CLAUDE.md / rules 自动生成）— 用法：`/create-context` |
| `settings.local.example.json` | 权限配置示例（复制为 `settings.local.json` 后按项目语言取消注释对应工具） |

## 可选依赖

| 依赖 | 用途 | 必需？ |
|------|------|--------|
| claude-mem MCP | dev-workflow / dev-debug 的 Phase 0（历史记忆查询）依赖此 MCP 服务 | 否（不可用时自动跳过 Phase 0） |

> claude-mem 配置方式：在 `.claude/settings.local.json` 的 `mcpServers` 中添加 claude-mem 服务地址。具体安装和配置请参阅 claude-mem 项目文档。

## 关联文档

| 路径 | 说明 |
|------|------|
| [`docs/README.md`](../docs/README.md) | 项目文档总入口（设计、工程领域知识、参考资料、经验总结） |
| [`docs/design/INDEX.md`](../docs/design/INDEX.md) | 设计方案索引 |
| [`docs/knowledge/INDEX.md`](../docs/knowledge/INDEX.md) | 工程领域知识索引 |
| [`docs/reference/INDEX.md`](../docs/reference/INDEX.md) | 参考资料索引 |
| [`docs/postmortem/INDEX.md`](../docs/postmortem/INDEX.md) | 经验总结索引 |

> Skills 内部结构见各自 `SKILL.md`，按需加载，不在此展开。
