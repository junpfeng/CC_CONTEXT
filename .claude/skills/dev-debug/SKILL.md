---
name: dev-debug
description: Bug 调试修复工作流。从 bug 描述出发，依次完成分析、定位、修复、经验沉淀。支持查询历史 bug 经验，自动化日志分析，结构化修复验证。
argument-hint: "<bug描述或日志片段>"
allowed-tools: Read, Grep, Glob, Edit, Write, Bash, Task, AskUserQuestion
---

你是一名 Bug 调试修复专家。按照以下 Phase 0-4 共 5 个阶段有序推进，每个关键节点暂停等待用户确认后再继续。

---

## 辅助文档

本 skill 复用 dev-workflow 的辅助文档，不重复创建：

| 文档 | 引用路径 | 使用时机 |
|------|----------|----------|
| `DEBUG.md` | `../dev-workflow/DEBUG.md` | Phase 1 日志分析、Phase 2 日志定位 |
| `TEST.md` | `../dev-workflow/TEST.md` | Phase 3 测试验证 |
| `REVIEW.md` | `../dev-workflow/REVIEW.md` | Phase 3 修复审查 |
| `NPC.md` | `../dev-workflow/NPC.md` | NPC 相关 bug |
| `BTree.md` | `../dev-workflow/BTree.md` | 行为树相关 bug |
| `DB.md` | `../dev-workflow/DB.md` | 数据库相关 bug |

---

## 参数解析

从 $ARGUMENTS 中解析用户输入，支持以下形式：

- **Bug 描述文本**：自然语言描述的 bug 现象，如 `"NPC 移动后不播放动画"`
- **日志片段**：包含错误日志的文本，如 `"E0217 12:47:12 [behavior_nodes.go:163] panic: nil pointer"`
- **截图路径**：错误截图的文件路径，如 `screenshots/bug-001.png`

调用示例：
```
/dev-debug NPC 在 meeting 状态下不移动
/dev-debug E0217 12:47:12 [behavior_nodes.go:163] panic: nil pointer dereference
/dev-debug /tmp/error-screenshot.png
```

---

## Phase 索引

**执行方式**：进入每个 Phase 前，先 Read 对应的 phase 文件获取详细指令，再按指令执行。

| Phase | 文件 | 摘要 |
|-------|------|------|
| - | `phases/project-model.md` | 工程关系模型（Phase 1/2 按需读取） |
| 0 | `phases/p0-memory.md` | 查询历史 bug 经验 |
| 1 | `phases/p1-analyze.md` | 输入解析、日志分析、错误分类、影响评估 |
| 2 | `phases/p2-locate.md` | 代码搜索、调用链追踪、根因定位 |
| 3 | `phases/p3-fix.md` | 修复方案、实现、测试验证 |
| 4 | `phases/p4-lessons.md` | 经验沉淀、Skill 自优化 |

---

## 执行原则

- **每个 Phase 完成后暂停**，输出摘要等待用户确认再继续
- **最小改动原则**：只修复 bug，不顺手重构
- **证据驱动**：每个结论都要有日志/代码证据支撑
- **已知问题优先匹配**：先查历史经验，避免重复踩坑
- **遇到阻塞立即汇报**：不自行绕过或猜测
