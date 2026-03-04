# Agent B: BtRunner-Executor 接口与系统

## 概述

负责实现 Part 6 的接口定义和系统集成：SystemType、IBtNode、BtTickSystem、场景初始化、**行为树模板注册**。

> **重要**：任务 6.9（行为树模板注册）是整个系统能否工作的关键步骤。之前的实现遗漏了这一步，导致行为树从未被实际使用。详见 `.claude/reflections/behavior-tree-design-reflection.md`

**计划文件**：`.claude/plans/behavior-tree-integration-plan.md` (Part 6)
**协调文件**：`.claude/agents/bt-executor-integration-orchestrator.md`

---

## 任务列表

| 序号 | 任务 | 文件 | 依赖 | 输出 |
|------|------|------|------|------|
| 6.1 | SystemType_AiBt | `common/system_type.go` | 无 | 系统类型常量 |
| 6.3 | IBtNode 接口 | `bt/node/interface.go` | 无 | 节点接口 |
| 6.6 | BtTickSystem | `decision/bt_tick_system.go` | 6.1, 6.4(Agent A) | Tick 系统 |
| 6.7 | 场景初始化 | 场景初始化代码 | 6.5(Agent A), 6.6 | 系统注册 |
| **6.9** | **行为树注册（关键！）** | `scene_impl.go` | 6.7 | **行为树可用** |

---

## 任务 6.1：新增 SystemType_AiBt

### 目标
在系统类型枚举中添加行为树系统类型。

### 文件位置
`servers/scene_server/internal/common/system_type.go`（或类似位置）

### 修改内容

查找 `SystemType` 枚举定义，添加新类型：

```go
const (
    // ... 现有类型
    SystemType_AiBt  SystemType = ...  // 新增：行为树 Tick 系统
)
```

### 验收标准

- [ ] SystemType_AiBt 常量已定义
- [ ] 编译通过：`make build APPS='scene_server'`

---

## 任务 6.3：实现 IBtNode 接口

### 目标
定义统一的行为树节点接口，供所有节点实现。

### 文件位置
`servers/scene_server/internal/common/ai/bt/node/interface.go`

### 完整实现

```go
package node

import (
    "mp/servers/scene_server/internal/common/ai/bt/context"
)

// BtNodeStatus 节点状态
type BtNodeStatus int

const (
    BtNodeStatusInit    BtNodeStatus = iota // 初始状态
    BtNodeStatusRunning                     // 运行中
    BtNodeStatusSuccess                     // 成功
    BtNodeStatusFailed                      // 失败
)

// String 返回状态的字符串表示
func (s BtNodeStatus) String() string {
    switch s {
    case BtNodeStatusInit:
        return "Init"
    case BtNodeStatusRunning:
        return "Running"
    case BtNodeStatusSuccess:
        return "Success"
    case BtNodeStatusFailed:
        return "Failed"
    default:
        return "Unknown"
    }
}

// BtNodeType 节点类型
type BtNodeType int

const (
    BtNodeTypeControl   BtNodeType = iota // 控制节点（Sequence、Selector 等）
    BtNodeTypeDecorator                   // 装饰节点（Inverter、Repeater 等）
    BtNodeTypeLeaf                        // 叶子节点（Action、Condition 等）
)

// String 返回节点类型的字符串表示
func (t BtNodeType) String() string {
    switch t {
    case BtNodeTypeControl:
        return "Control"
    case BtNodeTypeDecorator:
        return "Decorator"
    case BtNodeTypeLeaf:
        return "Leaf"
    default:
        return "Unknown"
    }
}

// IBtNode 行为树节点接口
type IBtNode interface {
    // --- 生命周期方法 ---

    // OnEnter 节点进入时调用（首次 Tick 或 Reset 后首次 Tick）
    OnEnter(ctx *context.BtContext) BtNodeStatus

    // OnTick 节点执行时调用（每帧调用）
    OnTick(ctx *context.BtContext) BtNodeStatus

    // OnExit 节点退出时调用（状态变为 Success/Failed 或被打断时）
    OnExit(ctx *context.BtContext)

    // --- 状态方法 ---

    // Status 获取当前节点状态
    Status() BtNodeStatus

    // Reset 重置节点状态（包括所有子节点）
    Reset()

    // --- 结构方法 ---

    // Children 获取子节点列表
    Children() []IBtNode

    // NodeType 获取节点类型
    NodeType() BtNodeType
}

// BaseNode 节点基类，提供默认实现
type BaseNode struct {
    status   BtNodeStatus
    nodeType BtNodeType
    children []IBtNode
}

// NewBaseNode 创建基础节点
func NewBaseNode(nodeType BtNodeType) BaseNode {
    return BaseNode{
        status:   BtNodeStatusInit,
        nodeType: nodeType,
        children: make([]IBtNode, 0),
    }
}

// OnEnter 默认实现：返回 Running
func (b *BaseNode) OnEnter(ctx *context.BtContext) BtNodeStatus {
    return BtNodeStatusRunning
}

// OnTick 默认实现：返回 Success
func (b *BaseNode) OnTick(ctx *context.BtContext) BtNodeStatus {
    return BtNodeStatusSuccess
}

// OnExit 默认实现：空操作
func (b *BaseNode) OnExit(ctx *context.BtContext) {
    // 默认不做任何事
}

// Status 获取当前状态
func (b *BaseNode) Status() BtNodeStatus {
    return b.status
}

// SetStatus 设置当前状态
func (b *BaseNode) SetStatus(status BtNodeStatus) {
    b.status = status
}

// Reset 重置节点状态
func (b *BaseNode) Reset() {
    b.status = BtNodeStatusInit
    for _, child := range b.children {
        child.Reset()
    }
}

// Children 获取子节点列表
func (b *BaseNode) Children() []IBtNode {
    return b.children
}

// AddChild 添加子节点
func (b *BaseNode) AddChild(child IBtNode) {
    b.children = append(b.children, child)
}

// NodeType 获取节点类型
func (b *BaseNode) NodeType() BtNodeType {
    return b.nodeType
}

// IsRunning 检查节点是否正在运行
func (b *BaseNode) IsRunning() bool {
    return b.status == BtNodeStatusRunning
}

// IsCompleted 检查节点是否已完成
func (b *BaseNode) IsCompleted() bool {
    return b.status == BtNodeStatusSuccess || b.status == BtNodeStatusFailed
}
```

### 验收标准

- [ ] IBtNode 接口定义完整
- [ ] BaseNode 提供默认实现
- [ ] BtNodeStatus 和 BtNodeType 枚举定义
- [ ] 编译通过：`make build APPS='scene_server'`

---

## 任务 6.6：实现 BtTickSystem

### 目标
创建行为树 Tick 系统，每帧驱动所有运行中的行为树。

### 依赖
- 任务 6.1 SystemType_AiBt（本 Agent）
- 任务 6.4 BtRunner（Agent A）— **等待 Sync 1**

### 文件位置
`servers/scene_server/internal/ecs/system/decision/bt_tick_system.go`

### 完整实现

```go
package decision

import (
    "common/log"

    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/common/ai/bt/node"
    "mp/servers/scene_server/internal/common/ai/bt/runner"
    "mp/servers/scene_server/internal/ecs/com/caidecision"
    "mp/servers/scene_server/internal/ecs/system"
)

// BtTickSystem 行为树帧更新系统
type BtTickSystem struct {
    *system.SystemBase
    btRunner *runner.BtRunner
}

// NewBtTickSystem 创建行为树帧更新系统
func NewBtTickSystem(scene common.Scene, btRunner *runner.BtRunner) *BtTickSystem {
    return &BtTickSystem{
        SystemBase: system.New(scene),
        btRunner:   btRunner,
    }
}

// Type 返回系统类型
func (s *BtTickSystem) Type() common.SystemType {
    return common.SystemType_AiBt
}

// Update 每帧更新
func (s *BtTickSystem) Update() {
    if s.btRunner == nil {
        return
    }

    runningTrees := s.btRunner.GetRunningTrees()
    if len(runningTrees) == 0 {
        return
    }

    // 帧间隔时间（~60 FPS）
    deltaTime := float32(0.0167)

    // 收集完成的树
    type completedInfo struct {
        entityID uint64
        planName string
        status   node.BtNodeStatus
    }
    completedTrees := make([]completedInfo, 0)

    // 遍历执行 Tick
    for entityID, instance := range runningTrees {
        // 跳过已完成的树
        if instance.Status == node.BtNodeStatusSuccess ||
           instance.Status == node.BtNodeStatusFailed {
            continue
        }

        // 执行 Tick
        status := s.btRunner.Tick(entityID, deltaTime)

        // 检查是否完成
        if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
            completedTrees = append(completedTrees, completedInfo{
                entityID: entityID,
                planName: instance.PlanName,
                status:   status,
            })
        }
    }

    // 处理完成的行为树
    for _, completed := range completedTrees {
        s.onTreeCompleted(completed.entityID, completed.planName, completed.status)
    }
}

// onTreeCompleted 行为树完成时的回调
func (s *BtTickSystem) onTreeCompleted(entityID uint64, planName string, status node.BtNodeStatus) {
    log.Infof("[BtTickSystem] tree completed, entity_id=%d, plan_name=%s, status=%s",
        entityID, planName, status.String())

    // 从运行器中移除已完成的树
    s.btRunner.Stop(entityID)

    // 获取实体
    entity, ok := s.Scene().GetEntity(entityID)
    if !ok {
        log.Debugf("[BtTickSystem] entity not found, entity_id=%d", entityID)
        return
    }

    // 获取决策组件
    decisionComp, ok := common.GetEntityComponentAs[*caidecision.DecisionComp](
        entity, common.ComponentType_AIDecision)
    if !ok {
        log.Debugf("[BtTickSystem] decision component not found, entity_id=%d", entityID)
        return
    }

    // 触发决策重新评估
    if err := decisionComp.TriggerCommand(); err != nil {
        log.Warningf("[BtTickSystem] trigger command failed, entity_id=%d, err=%v", entityID, err)
    }

    log.Infof("[BtTickSystem] triggered re-evaluation, entity_id=%d, plan_name=%s",
        entityID, planName)
}

// GetBtRunner 获取行为树运行器
func (s *BtTickSystem) GetBtRunner() *runner.BtRunner {
    return s.btRunner
}

// GetRunningTreeCount 获取运行中的行为树数量
func (s *BtTickSystem) GetRunningTreeCount() int {
    if s.btRunner == nil {
        return 0
    }
    return s.btRunner.GetRunningCount()
}
```

### 验收标准

- [ ] 正确遍历运行中的行为树
- [ ] 完成后触发决策重评估
- [ ] 编译通过：`make build APPS='scene_server'`

---

## 任务 6.7：场景初始化注册

### 目标
在场景初始化时注册 BtTickSystem。

### 依赖
- 任务 6.5 Executor（Agent A）— **等待 Sync 2**
- 任务 6.6 BtTickSystem（本 Agent）

### 查找位置
搜索场景初始化代码，通常在以下位置：
- `scene.go` 或 `scene_init.go`
- `SystemManager` 初始化代码
- 查找 `AddSystem` 或类似方法调用

### 修改内容

在场景系统初始化处添加：

```go
// 创建 Executor（如果还没有）
executor := decision.NewExecutor(scene)

// 创建并注册 BtTickSystem
btTickSystem := decision.NewBtTickSystem(scene, executor.GetBtRunner())
scene.AddSystem(btTickSystem)

// 或者通过 SystemManager
systemMgr.Register(decision.NewBtTickSystem(scene, executor.GetBtRunner()))
```

### 注意事项

1. **执行顺序**：BtTickSystem 应在 DecisionSystem 之后执行
2. **Executor 共享**：确保 Executor 实例被正确共享
3. **系统类型注册**：确保 SystemType_AiBt 已在类型枚举中注册

### 验收标准

- [ ] BtTickSystem 在场景初始化时被创建
- [ ] 系统 Update 被正确调用
- [ ] 编译通过：`make build APPS='scene_server'`

---

## 任务 6.9：行为树模板注册（关键任务！）

### 目标
在场景初始化时注册行为树模板到 BtRunner，**这是整个系统能否工作的关键步骤**。

### 背景
之前的实现遗漏了这一步，导致 `BtRunner.trees` 为空，行为树从未被实际执行。

### 修改位置
`servers/scene_server/internal/ecs/scene/scene_impl.go` 的 `initNpcAISystemsFromConfig` 函数

### 修改内容

```go
import (
    "mp/servers/scene_server/internal/common/ai/bt/trees"
    // ... 其他 import
)

func (s *scene) initNpcAISystemsFromConfig() error {
    // ... 现有代码 ...

    if cfg.EnableDecision {
        // 创建共享执行器资源
        executorRes := decision.NewExecutorResource(s)
        s.AddResource(executorRes)

        // ★★★ 关键步骤：注册行为树模板 ★★★
        executor := executorRes.GetExecutor()
        trees.RegisterExampleTrees(executor.RegisterBehaviorTree)
        if count, err := trees.RegisterTreesFromConfig(executor.RegisterBehaviorTree); err != nil {
            log.Warningf("[Scene] register behavior trees from config failed: %v", err)
        } else if count > 0 {
            log.Infof("[Scene] registered %d behavior trees from config", count)
        }

        // 创建决策系统
        decisionSystem := decision.NewDecisionSystem(s)
        s.AddSystem(decisionSystem)

        // 创建行为树 Tick 系统
        btTickSystem := decision.NewBtTickSystem(s, executorRes.GetBtRunner())
        s.AddSystem(btTickSystem)
    }
    // ...
}
```

### 验收标准

- [ ] 导入 `trees` 包
- [ ] 调用 `RegisterExampleTrees()` 注册硬编码示例树
- [ ] 调用 `RegisterTreesFromConfig()` 加载 JSON 配置树
- [ ] 启动日志显示 `[Scene] registered X behavior trees from config`
- [ ] 编译通过：`make build APPS='scene_server'`
- [ ] **端到端验证**：运行时，当 Plan 名称与行为树名称匹配时，走行为树执行逻辑

### 历史教训

详见 `.claude/reflections/behavior-tree-design-reflection.md`

---

## 文件结构

完成后的目录结构：

```
servers/scene_server/internal/
├── common/
│   ├── system_type.go          # 6.1 新增 SystemType_AiBt
│   └── ai/bt/
│       └── node/
│           └── interface.go    # 6.3 IBtNode 接口
│
└── ecs/system/decision/
    └── bt_tick_system.go       # 6.6 BtTickSystem
```

---

## 同步点说明

### Sync 1（等待 Agent A 完成 6.4）

在开始任务 6.6 之前，需要等待 Agent A 完成：
- 6.2 BtContext
- 6.4 BtRunner

**检查方式**：确认以下文件存在且编译通过：
- `bt/context/context.go`
- `bt/runner/runner.go`

### Sync 2（等待 Agent A 完成 6.5）

在开始任务 6.7 之前，需要等待 Agent A 完成：
- 6.5 Executor 修改

**检查方式**：确认 `executor.go` 包含 `btRunner` 字段和 `GetBtRunner()` 方法。

---

## 注意事项

1. **包引用**：node 包需要引用 context 包（单向依赖）
2. **系统类型**：确保 SystemType_AiBt 值不与现有类型冲突
3. **日志**：使用 `common/log` 包
4. **决策重评估**：使用 `decisionComp.TriggerCommand()` 或类似方法
