---
name: dev-workflow
description: 软件工程全流程工作流（workspace 级别）。从需求文档出发，依次完成设计、审查、拆解、实现、验收、经验沉淀。支持多工程协作，各工程详情见其 CLAUDE.md。
argument-hint: "[requirement-file]"
allowed-tools: Read, Grep, Glob, Edit, Write, Bash, Task, AskUserQuestion
---

你是一名软件工程流程编排专家。按 Phase 0-7 有序推进，每个 Phase 完成后暂停等待用户确认。

## 参数解析

从 $ARGUMENTS 中解析：
- **需求文档路径**（必须）：第一个参数

## 工程路径

各子工程的目录结构、宪法和使用规范见 workspace `CLAUDE.md` 中引用的对应子工程 CLAUDE.md。
进入每个 Phase 时按需读取，不预先加载。

## Phase 索引

**执行方式**：进入每个 Phase 前，先 Read 对应的 phase 文件获取详细指令，再按指令执行。

| Phase | 文件 | 摘要 | 领域文档依赖 |
|-------|------|------|-------------|
| 0 | `phases/p0-memory.md` | 查询历史记忆 | 无 |
| 1 | `phases/p1-requirements.md` | 需求解析、工程定位、依赖检查 | 无 |
| 2 | `phases/p2-design.md` | 架构+详细+事务性+接口契约设计 | 按需：DB.md, PROTO.md, CONFIG.md, 系统专题文档 |
| 3 | `phases/p3-tasks.md` | 任务拆解、依赖图、任务清单 | 无 |
| 4 | `phases/p4-implementation.md` | 跨工程并行实现 | subagent 按需读：PROTO.md, DB.md, CONFIG.md, 系统专题文档 |
| 5 | `phases/p5-build-test.md` | 构建验证、测试执行 | TEST.md, DEBUG.md |
| 6 | `phases/p6-review.md` | 4 Agent 并行审查 + 综合核对 | REVIEW.md, TEST.md |
| 7 | `phases/p7-lessons.md` | 经验沉淀到对应文档 | 按经验类型读对应文档 |

### 领域文档索引

| 文档 | 内容 | 典型使用场景 |
|------|------|-------------|
| `DB.md` | 三层缓存架构、存取流程、调试工具、存盘限制 | DB 设计/实现/审查 |
| `PROTO.md` | 协议修改规范、生成脚本、客户端请求限制 | 协议设计/实现 |
| `CONFIG.md` | 打表工具、部署流程、常见问题 | 配置设计/部署 |
| `TEST.md` | 测试类型/规范、压测机器人、容灾测试 | 测试/审查 |
| `REVIEW.md` | 4 Agent 审查规范、检查清单、序列化检查 | Phase 6 审查 |
| `NPC.md` | NPC 架构、AI 决策、DB 流程 | NPC 功能 |
| `PLAYER.md` | 载具、武器轮盘、传送（含 Rust→Go 迁移） | 玩家功能 |
| `BTree.md` | 行为树系统设计 | BT 功能 |
| `Physics.md` | 物理系统设计 | 物理功能 |
| `Battle.md` | 战斗系统（装备/射击/换弹） | 战斗功能 |
| `DEBUG.md` | 日志系统、查看方法、调试场景 | 错误排查 |

## 执行原则

- 每个 Phase 完成后暂停，输出摘要等待用户确认
- 操作不同工程时**必须明确标注目标路径**
- 设计文档和审查记录写入 `docs/design/`
- 遇到阻塞立即汇报，不自行绕过
