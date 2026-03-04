# 项目文档

## 目录结构

| 目录 | 用途 | 说明 |
|------|------|------|
| `design/` | 设计方案 | 架构设计、功能设计、任务拆解、需求文档 -> [`INDEX.md`](design/INDEX.md) |
| `postmortem/` | 经验总结 | 踩坑复盘、调试记录、事故回顾 -> [`INDEX.md`](postmortem/INDEX.md) |
| `knowledge/` | 工程领域知识 | 各工程相关的调试指南、测试规范、架构概览等，按需加载 -> [`INDEX.md`](knowledge/INDEX.md) |
| `reference/` | 参考资料 | 第三方技术、语言特性、工具用法、调研报告 -> [`INDEX.md`](reference/INDEX.md) |

## 命名规范

| 文档类型 | 命名格式 | 所属目录 |
|----------|----------|----------|
| 设计方案 | `design-[feature-name].md` | `design/` |
| 任务拆解 | `tasks-[feature-name].md`（与设计文档配对） | `design/` |
| 需求文档 | `requirements-[feature-name].md` | `design/` |
| 架构文档 | `architecture-[module-name].md` | `design/` |
| 经验总结 | `postmortem-[topic].md` | `postmortem/` |
| 调研报告 | `research-[topic].md` | `reference/` |
