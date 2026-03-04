# 项目目录结构

Workspace 级 monorepo，包含游戏服务器全部工程。

| 目录 | 说明 | CLAUDE.md |
|------|------|-----------|
| `P1GoServer/` | 主业务工程（Go 游戏服务器） | `P1GoServer/CLAUDE.md` |
| `server_old/` | 旧版服务器（Rust），目前仅 scene 进程在使用 | `server_old/CLAUDE.md` |
| `config/` | 策划配置（自动生成，勿手动改） | `config/CLAUDE.md` |
| `proto/` | 协议工程（Protocol Buffers） | `proto/CLAUDE.md` |
| `tools/generate_tool/` | 代码生成器（配置/实体/协议解析） | — |
| `docs/` | 项目文档（设计方案/经验总结/知识图谱/参考资料） | `docs/README.md` |

> **按需加载规则**：仅在需要阅读或修改某个子工程时，才读取其 `CLAUDE.md`。不要一次性加载所有子工程的说明。

# 工作规范

- **最小上下文原则：优先用 subagent 完成任务，主 agent 只做调度和总结，不堆积中间结果**
- 先阅读代码再改，不要猜测未检查的代码
- 代码注释用中文，变量命名用英文
- 不确定的地方询问我，不要瞎猜

# 服务器


# .claude 目录

| 路径 | 说明 |
|------|------|
| `rules/constitution.md` | 工作空间宪法（最高优先级规则） |
| `skills/` | 工作流技能（dev-workflow、dev-debug 等） |
| `INDEX.md` | 完整索引 |

> 各子工程有各自的 `.claude/rules/` 宪法文件。
