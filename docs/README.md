# 项目文档

## 目录结构

| 目录 | 用途 | 说明 |
|------|------|------|
| `design/` | 设计方案 | 架构设计、功能设计、任务拆解、需求文档 -> [`INDEX.md`](design/INDEX.md) |
| `postmortem/` | 经验总结 | 踩坑复盘、调试记录、事故回顾 -> [`INDEX.md`](postmortem/INDEX.md) |
| `knowledge/` | 工程领域知识 | 各工程相关的调试指南、测试规范、架构概览等，按需加载 -> [`INDEX.md`](knowledge/INDEX.md) |
| `reference/` | 参考资料 | 第三方技术、语言特性、工具用法、调研报告 -> [`INDEX.md`](reference/INDEX.md) |
| `tools/` | 工具文档 | 脚本使用说明、配置指南 |
| `temp/` | 临时数据 | 调试用的临时 JSON/脚本，不纳入正式文档 |

## 外部参考文档

| 外部工程 | 路径 | 说明 |
|----------|------|------|
| GTA5 逆向工程文档 | `E:\workspace\PRJ\GTA\GTA5\docs\` | GTA5 引擎与游戏系统分析，NPC 行为系统参考 |

外部文档不复制到本项目，通过绝对路径引用。详细索引见 [`reference/INDEX.md`](reference/INDEX.md)。

## 命名规范

| 文档类型 | 命名格式 | 所属目录 |
|----------|----------|----------|
| 设计方案 | `design-[feature-name].md` | `design/` |
| 任务拆解 | `tasks-[feature-name].md`（与设计文档配对） | `design/` |
| 需求文档 | `requirements-[feature-name].md` | `design/` |
| 架构文档 | `architecture-[module-name].md` | `design/` |
| 经验总结 | `postmortem-[topic].md` | `postmortem/` |
| 调研报告 | `research-[topic].md` | `reference/` |
