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
| `skills/docs-review/` | 文档审查合并整理（扫描->审查->合并->重建索引）— 用法：`/docs-review` |
| `skills/git-pull/` | 拉取各工程最新代码（Git+SVN，支持选择性拉取）— 用法：`/git-pull` |
| `skills/clone-workspace/` | 快速复刻整个工作空间到新目录（clone+复制+验证）— 用法：`/clone-workspace <目标路径>` |
| `skills/entity-config/` | 场景物体配置规范（entity/map JSON 格式、组件字段、新增类型步骤）— 用法：`/entity-config` |
| `skills/protocol/` | 协议设计规范（自定义 proto 格式、消息序列化、代码生成）— 用法：`/protocol` |
| `skills/skill-creator/` | 技能创建/评测/基准测试工具链 — 用法：`/skill-creator` |
| `settings.json` | Hooks 配置（PostToolUse: Go 编译检查 + C# lint） |
| `settings.local.example.json` | 权限配置示例（复制为 `settings.local.json` 后按项目语言取消注释对应工具） |
| `hooks/` | 质量门控脚本（go-build-after.sh, lint-cs-after.sh） |
| `commands/` | 斜杠命令入口（auto-work, feature/*, bug/*, git/*, research/*） |
| `scripts/` | 多进程编排脚本（auto-work-loop, feature-plan-loop, feature-develop-loop 等） |

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
