# 项目文档

## 目录结构

| 目录 | 用途 | 说明 |
|------|------|------|
| `design/` | 设计方案 | 架构设计、功能设计、任务拆解、需求文档 → [`INDEX.md`](design/INDEX.md) |
| `postmortem/` | 经验总结 | 踩坑复盘、调试记录、事故回顾 → [`INDEX.md`](postmortem/INDEX.md) |
| `knowledge/` | 知识图谱 | 系统原理、模块关系、架构概览 → [`INDEX.md`](knowledge/INDEX.md) |
| `reference/` | 参考资料 | 第三方技术、语言特性、工具用法 → [`INDEX.md`](reference/INDEX.md) |

## 文档模板

新建文档时可参考 `.claude/templates/` 中的模板套件：

- 工作空间级 CLAUDE.md → [`.claude/templates/CLAUDE.md.template`](../.claude/templates/CLAUDE.md.template)
- 子工程级 CLAUDE.md → [`.claude/templates/sub-project-CLAUDE.md.template`](../.claude/templates/sub-project-CLAUDE.md.template)
- 更多模板说明 → [`.claude/templates/README.md`](../.claude/templates/README.md)

## 命名规范

- 设计方案：`design-[feature-name].md`
- 任务拆解：`tasks-[feature-name].md`（与设计文档配对）
- 需求文档：`requirements-[feature-name].md`
- 架构文档：`architecture-[module-name].md`
- 经验总结：`postmortem-[topic].md`
- 调研报告：`research-[topic].md`
