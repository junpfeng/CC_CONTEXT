---
name: dev-workflow
description: 软件工程全流程工作流（workspace 级别）。从需求文档出发，依次完成设计、审查、拆解、实现、验收、经验沉淀。支持多工程协作。
argument-hint: "[requirement-file]"
---

你是一名软件工程流程编排专家。按 Phase 0-7 有序推进，每个 Phase 完成后暂停等待用户确认。

## 参数解析

从 $ARGUMENTS 中解析：
- **需求文档路径**（必须）：第一个参数

## 工程路径

各子工程的目录结构、宪法和使用规范见 workspace 级项目说明中引用的对应子工程说明。
进入每个 Phase 时按需读取，不预先加载。

## 知识库

项目领域知识统一存放在知识库目录，各 Phase 按需查阅索引定位相关文档。

## Phase 索引

**执行方式**：进入每个 Phase 前，先 Read 对应的 phase 文件获取详细指令，再按指令执行。

| Phase | 文件 | 摘要 |
|-------|------|------|
| 0 | `phases/p0-memory.md` | 查询历史记忆 |
| 1 | `phases/p1-requirements.md` | 需求解析、工程定位、依赖检查 |
| 2 | `phases/p2-design.md` | 架构+详细+事务性+接口契约设计 |
| 3 | `phases/p3-tasks.md` | 任务拆解、依赖图、任务清单 |
| 4 | `phases/p4-implementation.md` | 跨工程并行实现 |
| 5 | `phases/p5-build-test.md` | 构建验证、测试执行 |
| 6 | `phases/p6-review.md` | 4 Agent 并行审查 + 综合核对 |
| 7 | `phases/p7-lessons.md` | 经验沉淀到对应文档 |

## 执行原则

- 每个 Phase 完成后暂停，输出摘要等待用户确认
- 操作不同工程时**必须明确标注目标路径**
- 遇到阻塞立即汇报，不自行绕过
