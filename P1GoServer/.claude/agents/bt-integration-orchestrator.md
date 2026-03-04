# 行为树集成执行指南

## 概述

本文档描述如何使用 2 个 Agent 并行执行行为树集成计划。

**计划文件**：`.claude/plans/behavior-tree-integration-plan.md`

---

## Agent 列表

| Agent | 文件 | 职责 | 任务范围 |
|-------|------|------|----------|
| bt-core-framework | `bt-core-framework.md` | 核心框架 | 1.1 BtContext → 1.2 BtRunner → 3.1 Executor |
| bt-nodes-system | `bt-nodes-system.md` | 节点与系统 | 1.3 评估 → 2.1~2.8 叶子节点 → 3.2 BtTickSystem |

---

## 执行时间线

```
时间 ─────────────────────────────────────────────────────────────────►

Agent A: [1.1 BtContext]──►[1.2 BtRunner]─────────────►[3.1 Executor]──►┐
              │                                                         │
              │ Sync 1: 接口定义完成                                      │
              ▼                                                         │
Agent B: [1.3 评估]──►[2.1~2.8 叶子节点实现]──────────►[3.2 BtTickSystem]┤
                                                                        │
                                                                        ▼
                                                              [Part 4 验证]
```

---

## 同步点

| 同步点 | 触发条件 | Agent A 动作 | Agent B 动作 |
|--------|----------|--------------|--------------|
| **Sync 1** | Agent A 完成 1.1 BtContext | 继续 1.2 BtRunner | 开始 2.1~2.8 叶子节点 |
| **Sync 2** | 两个 Agent 完成 Part 1+2 | 开始 3.1 Executor | 开始 3.2 BtTickSystem |
| **Sync 3** | 两个 Agent 完成 Part 3 | 合并代码 | 合并代码 |

---

## 执行命令

### 阶段一：并行启动

```bash
# 终端 1 - Agent A: 核心框架
claude "执行 @.claude/agents/bt-core-framework.md 任务 1.1 BtContext"

# 终端 2 - Agent B: 节点与系统（可同时启动）
claude "执行 @.claude/agents/bt-nodes-system.md 任务 1.3 评估现有代码"
```

### 阶段二：Sync 1 后继续

```bash
# 终端 1 - Agent A 继续
claude "执行 @.claude/agents/bt-core-framework.md 任务 1.2 BtRunner"

# 终端 2 - Agent B 开始叶子节点
claude "执行 @.claude/agents/bt-nodes-system.md 任务 2.1~2.8 叶子节点"
```

### 阶段三：Part 3 系统集成

```bash
# 终端 1 - Agent A
claude "执行 @.claude/agents/bt-core-framework.md 任务 3.1 修改 Executor"

# 终端 2 - Agent B
claude "执行 @.claude/agents/bt-nodes-system.md 任务 3.2 BtTickSystem"
```

### 阶段四：验证

```bash
# 合并后共同验证
claude "执行 @.claude/plans/behavior-tree-integration-plan.md Part 4 验证"
```

---

## 接口契约

Agent A 完成 1.1 后需提供的接口（Agent B 依赖）：

```go
// bt/context/context.go
type BtContext struct {
    Scene      common.Scene
    EntityID   uint64
    Blackboard map[string]any
    DeltaTime  float32
}

func (c *BtContext) GetMoveComp() *cnpc.NpcMoveComp
func (c *BtContext) GetDecisionComp() *caidecision.DecisionComp
func (c *BtContext) GetTransformComp() *ctrans.Transform
func (c *BtContext) SetBlackboard(key string, value any)
func (c *BtContext) GetBlackboard(key string) (any, bool)

// bt/node/interface.go
type IBtNode interface {
    OnEnter(ctx *BtContext) BtNodeStatus
    OnTick(ctx *BtContext) BtNodeStatus
    OnExit(ctx *BtContext)
    Status() BtNodeStatus
    Reset()
    Children() []IBtNode
    NodeType() BtNodeType
}
```

---

## 验收标准

### Part 1 验收
- [ ] BtContext 能正确获取 Entity 组件
- [ ] BtRunner 能注册、启动、停止行为树
- [ ] 编译通过：`make build APPS='scene_server'`

### Part 2 验收
- [ ] 8 个叶子节点都实现 IBtNode 接口
- [ ] 每个节点有基本的单元测试
- [ ] 编译通过

### Part 3 验收
- [ ] Executor 能判断 Plan 是否使用行为树
- [ ] BtTickSystem 正确驱动行为树 Tick
- [ ] Plan 转移时正确 Stop/Start 行为树
- [ ] 编译通过

### Part 4 验收
- [ ] 示例行为树能正常运行
- [ ] NPC 行为符合预期
- [ ] 性能无明显下降

---

## 注意事项

1. **接口稳定性**：Agent A 完成 1.1 后，接口定义不应再改动
2. **编译验证**：每个任务完成后执行 `make build APPS='scene_server'`
3. **代码位置**：所有新文件放在 `servers/scene_server/internal/common/ai/bt/` 下
4. **日志规范**：使用 `common/log` 包，遵循项目日志规范
5. **命名规范**：文件名小写下划线，类型名大驼峰
