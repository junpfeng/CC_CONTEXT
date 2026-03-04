# Part 6: BtRunner-Executor 集成执行指南

## 概述

本文档描述如何使用 2 个 Agent 并行执行 Part 6：BtRunner-Executor 集成实现。

**计划文件**：`.claude/plans/behavior-tree-integration-plan.md` (Part 6 章节)

---

## Agent 列表

| Agent | 文件 | 职责 | 任务范围 |
|-------|------|------|----------|
| bt-executor-core-agent | `bt-executor-core-agent.md` | 核心框架 | 6.2 BtContext → 6.4 BtRunner → 6.5 Executor |
| bt-executor-system-agent | `bt-executor-system-agent.md` | 接口与系统 | 6.1 SystemType → 6.3 IBtNode → 6.6 BtTickSystem → 6.7 场景初始化 → **6.9 行为树注册** |

---

## 任务依赖图

```
┌──────────────┐
│ 6.1 SystemType│ ─────────────────────────────────┐
│   (独立)      │                                   │
└──────────────┘                                   │
                                                    │
┌──────────────┐      ┌──────────────┐            │
│ 6.2 BtContext │ ────►│ 6.4 BtRunner │────┐       │
│   (独立)      │      │  (依赖6.2,6.3)│    │       │
└──────────────┘      └──────────────┘    │       │
                            ▲              │       │
┌──────────────┐            │              │       ▼
│ 6.3 IBtNode  │ ───────────┘              │  ┌──────────────┐
│   (独立)      │                           │  │6.6 BtTickSys │
└──────────────┘                           │  │(依赖6.1,6.4) │
                                            │  └──────┬───────┘
                                            ▼         │
                                      ┌──────────────┐│
                                      │ 6.5 Executor ││
                                      │  (依赖6.4)   ││
                                      └──────┬───────┘│
                                             │        │
                                             ▼        ▼
                                      ┌─────────────────┐
                                      │ 6.7 场景初始化   │
                                      │ (依赖6.5,6.6)   │
                                      └────────┬────────┘
                                               │
                                               ▼
                                      ┌─────────────────┐
                                      │ 6.8 编译验证    │
                                      └─────────────────┘
```

---

## 执行时间线

```
时间 ──────────────────────────────────────────────────────────────────────────►

Agent A   ┌─────────┐   ┌─────────────┐   ┌─────────────┐
(核心框架) │6.2      │──►│ 6.4         │──►│ 6.5         │───┐
          │BtContext│   │ BtRunner    │   │ Executor    │   │
          └─────────┘   └─────────────┘   └─────────────┘   │
                              ▲                             │
               Sync 1         │                             │
                    │         │                             │
Agent B   ┌─────────┴───────┐ │   ┌─────────────┐           │   ┌─────────┐
(接口系统) │6.1 + 6.3        │─┘──►│ 6.6         │───────────┴──►│ 6.7     │──► 6.8
          │SystemType+IBtNode│    │ BtTickSystem│               │ 场景初始化│
          └─────────────────┘    └─────────────┘               └─────────┘

同步点 ─────────────────────────►Sync 1─────────────────────►Sync 2─────────►
```

---

## 同步点

| 同步点 | 触发条件 | Agent A 动作 | Agent B 动作 |
|--------|----------|--------------|--------------|
| **Sync 1** | Agent A 完成 6.4 BtRunner | 继续 6.5 Executor | 开始 6.6 BtTickSystem |
| **Sync 2** | Agent A 完成 6.5 + Agent B 完成 6.6 | 完成 | 执行 6.7 场景初始化 |

---

## 执行命令

### 阶段一：并行启动 (Phase 1)

```bash
# 终端 1 - Agent A: 核心框架
claude "执行 @.claude/agents/bt-executor-core-agent.md 任务 6.2 BtContext"

# 终端 2 - Agent B: 接口与系统（同时启动）
claude "执行 @.claude/agents/bt-executor-system-agent.md 任务 6.1 SystemType 和 6.3 IBtNode"
```

### 阶段二：Sync 1 后继续 (Phase 2)

```bash
# 终端 1 - Agent A 继续
claude "执行 @.claude/agents/bt-executor-core-agent.md 任务 6.4 BtRunner"

# 终端 2 - Agent B 等待 Sync 1
# (等待 Agent A 完成 6.4)
```

### 阶段三：系统集成 (Phase 3)

```bash
# 终端 1 - Agent A
claude "执行 @.claude/agents/bt-executor-core-agent.md 任务 6.5 Executor"

# 终端 2 - Agent B
claude "执行 @.claude/agents/bt-executor-system-agent.md 任务 6.6 BtTickSystem"
```

### 阶段四：场景初始化与验证 (Phase 4)

```bash
# 终端 2 - Agent B (等待 Sync 2)
claude "执行 @.claude/agents/bt-executor-system-agent.md 任务 6.7 场景初始化"

# 编译验证
make build APPS='scene_server'
```

---

## 接口契约

Agent A 完成 6.2 BtContext 和 6.4 BtRunner 后，Agent B 依赖的接口：

```go
// bt/context/context.go
type BtContext struct {
    Scene      common.Scene
    EntityID   uint64
    Blackboard map[string]any
    DeltaTime  float32
}

func NewBtContext(scene common.Scene, entityID uint64) *BtContext
func (c *BtContext) Reset(entityID uint64, deltaTime float32)
func (c *BtContext) GetMoveComp() *cnpc.NpcMoveComp
func (c *BtContext) GetDecisionComp() *caidecision.DecisionComp
func (c *BtContext) GetTransformComp() *ctrans.Transform

// bt/runner/runner.go
type BtRunner struct { ... }
type TreeInstance struct { ... }

func NewBtRunner(scene common.Scene) *BtRunner
func (r *BtRunner) RegisterTree(planName string, root node.IBtNode)
func (r *BtRunner) HasTree(planName string) bool
func (r *BtRunner) Run(planName string, entityID uint64) error
func (r *BtRunner) Stop(entityID uint64)
func (r *BtRunner) Tick(entityID uint64, deltaTime float32) node.BtNodeStatus
func (r *BtRunner) GetRunningTrees() map[uint64]*TreeInstance
```

---

## 验收标准

### 6.2 BtContext 验收
- [ ] 能通过 EntityID 获取各类组件
- [ ] 黑板读写正常
- [ ] 编译通过

### 6.4 BtRunner 验收
- [ ] 能注册行为树
- [ ] Run/Stop/Tick 正常工作
- [ ] 编译通过

### 6.5 Executor 验收
- [ ] Executor 包含 btRunner 字段
- [ ] OnPlanCreated 优先检查行为树
- [ ] 编译通过

### 6.6 BtTickSystem 验收
- [ ] 正确遍历运行中的行为树
- [ ] 完成后触发决策重评估
- [ ] 编译通过

### 6.7 场景初始化验收
- [ ] BtTickSystem 正确注册
- [ ] 系统 Update 被正确调用
- [ ] 编译通过

### 6.9 行为树模板注册验收（关键！）
- [ ] 调用 `RegisterExampleTrees()` 注册硬编码示例树
- [ ] 调用 `RegisterTreesFromConfig()` 加载 JSON 配置树
- [ ] 启动日志显示 `registered X behavior trees`
- [ ] `BtRunner.trees` 不为空

### 最终验收
- [ ] `make build APPS='scene_server'` 编译通过
- [ ] 现有 Plan（无行为树）的执行逻辑不受影响
- [ ] **端到端验证**：Plan 名称与行为树名称匹配时，走行为树逻辑

---

## 文件结构

完成后的目录结构：

```
servers/scene_server/internal/
├── common/
│   ├── system_type.go          # 6.1 新增 SystemType_AiBt
│   └── ai/bt/
│       ├── context/
│       │   └── context.go      # 6.2 BtContext
│       ├── node/
│       │   └── interface.go    # 6.3 IBtNode 接口
│       └── runner/
│           └── runner.go       # 6.4 BtRunner
│
└── ecs/system/decision/
    ├── executor.go             # 6.5 修改：添加 btRunner
    └── bt_tick_system.go       # 6.6 新增：BtTickSystem
```

---

## 注意事项

1. **包引用**：避免循环引用，context 和 node 包相互独立
2. **编译验证**：每个任务完成后执行 `make build APPS='scene_server'`
3. **日志规范**：使用 `common/log` 包，遵循项目日志规范
4. **错误处理**：Run 返回 error，Stop 静默处理
5. **向后兼容**：确保无行为树的 Plan 仍使用原有 Task 逻辑
6. **关键步骤**：必须在 scene_impl.go 中调用 `RegisterExampleTrees` 和 `RegisterTreesFromConfig`，否则 `BtRunner.trees` 为空，行为树永远不会执行！

## 历史教训

Part 6 首次实现时遗漏了行为树注册步骤，导致系统虽然编译通过但无法工作。详见反思文档：`.claude/reflections/behavior-tree-design-reflection.md`
