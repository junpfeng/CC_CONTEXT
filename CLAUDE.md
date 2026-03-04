# 项目目录结构

当前无子工程。新增时在此补充目录表。

> **按需加载规则**：仅在需要时才读取子工程的 `CLAUDE.md`，不要一次性全部加载。

# 工作规范

- **最小上下文原则**：优先用 subagent 完成任务，主 agent 只做调度与总结，不堆积中间结果
- 先阅读代码再改，不要猜测未检查的代码
- 代码注释用中文，变量命名用英文
- 不确定的地方询问我，不要瞎猜

# 项目文档

`docs/` 目录存放设计方案、经验总结、工程领域知识、参考资料，详见 [`docs/README.md`](docs/README.md)。

# 工具脚本

| 脚本 | 说明 |
|------|------|
| [`scripts/claude-git.sh`](scripts/claude-git.sh) | Claude 上下文文件版本控制辅助脚本（基于 bare repo，自动处理嵌套 .git） |

# .claude 目录

| 路径 | 说明 |
|------|------|
| `rules/constitution.md` | 工作空间宪法（最高优先级规则） |
| `skills/` | 工作流技能（dev-workflow、dev-debug 等） |
| `templates/` | 通用文档模板套件，用于快速搭建新项目的 Claude Code 文档体系 |
| `INDEX.md` | 完整索引 |

> 各子工程有各自的 `.claude/rules/` 宪法文件。
