# Agent B: 行为树节点与系统

## 概述

负责实现行为树的叶子节点和 BtTickSystem。

**计划文件**：`.claude/plans/behavior-tree-integration-plan.md`
**协调文件**：`.claude/agents/bt-integration-orchestrator.md`

---

## 任务列表

| 序号 | 任务 | 文件 | 依赖 | 输出 |
|------|------|------|------|------|
| 1.3 | 评估现有代码 | - | 无 | 复用清单 |
| 2.1 | MoveToNode | `bt/nodes/move_to.go` | Sync 1 | 移动节点 |
| 2.2 | WaitNode | `bt/nodes/wait.go` | Sync 1 | 等待节点 |
| 2.3 | StopMoveNode | `bt/nodes/stop_move.go` | Sync 1 | 停止移动节点 |
| 2.4 | SetFeatureNode | `bt/nodes/set_feature.go` | Sync 1 | 设置特征节点 |
| 2.5 | CheckConditionNode | `bt/nodes/check_condition.go` | Sync 1 | 条件检查节点 |
| 2.6 | LogNode | `bt/nodes/log.go` | Sync 1 | 日志节点 |
| 2.7 | LookAtNode | `bt/nodes/look_at.go` | Sync 1 | 面向目标节点 |
| 2.8 | SetBlackboardNode | `bt/nodes/set_blackboard.go` | Sync 1 | 黑板设置节点 |
| 3.2 | BtTickSystem | `decision/bt_tick_system.go` | Sync 2 | Tick 系统 |

---

## 任务 1.3：评估现有 bt/ 代码

### 目标
评估现有 `bt/` 目录代码的复用程度。

### 检查文件
- `bt/tree/node/bt_node.go` - 节点接口和基类
- `bt/tree/node/context.go` - 上下文
- `bt/tree/node/node_control.go` - 控制节点
- `bt/tree/node/node_decorator.go` - 装饰节点
- `bt/tree/node/node_leaf.go` - 叶子节点
- `bt/config/config.go` - 配置结构

### 预期结论

根据计划文档 8.3 的决策：

| 复用 | 不复用 |
|------|--------|
| `BtNodeStatus` 枚举值 | `IBtNode` 接口（重新设计） |
| `BtNodeType` 枚举值 | `BTXContext`（重新设计） |
| 状态管理逻辑思路 | `ControlTick/ActionTick` 方法 |

### 输出
确认复用清单，无需创建文件。

---

## 任务 2.x：叶子节点实现

### 前置条件
**等待 Sync 1**：Agent A 完成 BtContext 和 IBtNode 接口定义。

### 基类定义

首先创建 `bt/nodes/base.go`：

```go
package nodes

import (
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// BaseLeafNode 叶子节点基类
type BaseLeafNode struct {
    status node.BtNodeStatus
}

func (n *BaseLeafNode) Status() node.BtNodeStatus {
    return n.status
}

func (n *BaseLeafNode) Reset() {
    n.status = node.BtNodeStatusInit
}

func (n *BaseLeafNode) Children() []node.IBtNode {
    return nil
}

func (n *BaseLeafNode) NodeType() node.BtNodeType {
    return node.BtNodeTypeLeaf
}

// 子类需要实现：
// OnEnter(ctx *context.BtContext) node.BtNodeStatus
// OnTick(ctx *context.BtContext) node.BtNodeStatus
// OnExit(ctx *context.BtContext)
```

---

### 任务 2.1：MoveToNode

**文件**：`bt/nodes/move_to.go`

```go
package nodes

import (
    "common/transform"
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// MoveToNode 移动到指定点
type MoveToNode struct {
    BaseLeafNode
    TargetPointKey string          // 从黑板读取目标点的 key
    TargetPoint    *transform.Vec3 // 或直接指定目标点
    Speed          float32         // 移动速度，0 表示使用默认速度
    pathKey        string          // 内部使用的路径 key
}

func NewMoveToNode(targetKey string) *MoveToNode {
    return &MoveToNode{
        TargetPointKey: targetKey,
    }
}

func NewMoveToNodeWithPoint(target *transform.Vec3) *MoveToNode {
    return &MoveToNode{
        TargetPoint: target,
    }
}

func (n *MoveToNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    target := n.getTarget(ctx)
    if target == nil {
        return node.BtNodeStatusFailed
    }

    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }

    // 生成唯一路径 key
    n.pathKey = fmt.Sprintf("bt_move_%d_%d", ctx.EntityID, time.Now().UnixNano())

    // 计算路径并设置（需要根据实际寻路系统调整）
    pointList := []*transform.Vec3{target}
    moveComp.SetPointList(n.pathKey, pointList, nil)

    if n.Speed > 0 {
        moveComp.SetSpeed(n.Speed)
    }
    moveComp.StartMove()

    n.status = node.BtNodeStatusRunning
    return node.BtNodeStatusRunning
}

func (n *MoveToNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }

    if moveComp.IsFinish {
        n.status = node.BtNodeStatusSuccess
        return node.BtNodeStatusSuccess
    }

    return node.BtNodeStatusRunning
}

func (n *MoveToNode) OnExit(ctx *context.BtContext) {
    moveComp := ctx.GetMoveComp()
    if moveComp != nil {
        moveComp.StopMove()
    }
}

func (n *MoveToNode) getTarget(ctx *context.BtContext) *transform.Vec3 {
    if n.TargetPoint != nil {
        return n.TargetPoint
    }
    if n.TargetPointKey != "" {
        if val, ok := ctx.GetBlackboard(n.TargetPointKey); ok {
            if target, ok := val.(*transform.Vec3); ok {
                return target
            }
        }
    }
    return nil
}
```

---

### 任务 2.2：WaitNode

**文件**：`bt/nodes/wait.go`

```go
package nodes

import (
    "common/mtime"
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// WaitNode 等待指定时间
type WaitNode struct {
    BaseLeafNode
    DurationMs    int64  // 等待时间（毫秒）
    DurationKey   string // 从黑板读取等待时间的 key
    startTime     int64  // 开始等待的时间
}

func NewWaitNode(durationMs int64) *WaitNode {
    return &WaitNode{
        DurationMs: durationMs,
    }
}

func NewWaitNodeWithKey(durationKey string) *WaitNode {
    return &WaitNode{
        DurationKey: durationKey,
    }
}

func (n *WaitNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    n.startTime = mtime.NowMilliTickWithOffset()
    n.status = node.BtNodeStatusRunning
    return node.BtNodeStatusRunning
}

func (n *WaitNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    duration := n.getDuration(ctx)
    elapsed := mtime.NowMilliTickWithOffset() - n.startTime

    if elapsed >= duration {
        n.status = node.BtNodeStatusSuccess
        return node.BtNodeStatusSuccess
    }

    return node.BtNodeStatusRunning
}

func (n *WaitNode) OnExit(ctx *context.BtContext) {
    // 无需清理
}

func (n *WaitNode) getDuration(ctx *context.BtContext) int64 {
    if n.DurationKey != "" {
        if val, ok := ctx.GetBlackboardInt64(n.DurationKey); ok {
            return val
        }
    }
    return n.DurationMs
}
```

---

### 任务 2.3：StopMoveNode

**文件**：`bt/nodes/stop_move.go`

```go
package nodes

import (
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// StopMoveNode 停止移动（立即完成）
type StopMoveNode struct {
    BaseLeafNode
}

func NewStopMoveNode() *StopMoveNode {
    return &StopMoveNode{}
}

func (n *StopMoveNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp != nil {
        moveComp.StopMove()
    }
    n.status = node.BtNodeStatusSuccess
    return node.BtNodeStatusSuccess
}

func (n *StopMoveNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    return node.BtNodeStatusSuccess
}

func (n *StopMoveNode) OnExit(ctx *context.BtContext) {
    // 无需清理
}
```

---

### 任务 2.4：SetFeatureNode

**文件**：`bt/nodes/set_feature.go`

```go
package nodes

import (
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
    "mp/servers/scene_server/internal/common/ai/decision"
)

// SetFeatureNode 设置决策特征（立即完成）
type SetFeatureNode struct {
    BaseLeafNode
    FeatureKey   string
    FeatureValue any
    TTLMs        int64 // 特征过期时间，0 表示不过期
}

func NewSetFeatureNode(key string, value any, ttlMs int64) *SetFeatureNode {
    return &SetFeatureNode{
        FeatureKey:   key,
        FeatureValue: value,
        TTLMs:        ttlMs,
    }
}

func (n *SetFeatureNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    decisionComp := ctx.GetDecisionComp()
    if decisionComp == nil {
        n.status = node.BtNodeStatusFailed
        return node.BtNodeStatusFailed
    }

    err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     ctx.EntityID,
        FeatureKey:   n.FeatureKey,
        FeatureValue: n.FeatureValue,
        TTLMs:        n.TTLMs,
    })

    if err != nil {
        n.status = node.BtNodeStatusFailed
        return node.BtNodeStatusFailed
    }

    n.status = node.BtNodeStatusSuccess
    return node.BtNodeStatusSuccess
}

func (n *SetFeatureNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    return node.BtNodeStatusSuccess
}

func (n *SetFeatureNode) OnExit(ctx *context.BtContext) {
    // 无需清理
}
```

---

### 任务 2.5：CheckConditionNode

**文件**：`bt/nodes/check_condition.go`

```go
package nodes

import (
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// CheckConditionNode 条件检查（立即完成）
type CheckConditionNode struct {
    BaseLeafNode
    BlackboardKey string // 从黑板读取的 key
    Operator      string // "==", "!=", ">", "<", ">=", "<="
    Value         any    // 比较值
}

func NewCheckConditionNode(key string, operator string, value any) *CheckConditionNode {
    return &CheckConditionNode{
        BlackboardKey: key,
        Operator:      operator,
        Value:         value,
    }
}

func (n *CheckConditionNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    val, ok := ctx.GetBlackboard(n.BlackboardKey)
    if !ok {
        n.status = node.BtNodeStatusFailed
        return node.BtNodeStatusFailed
    }

    if n.evaluate(val) {
        n.status = node.BtNodeStatusSuccess
        return node.BtNodeStatusSuccess
    }

    n.status = node.BtNodeStatusFailed
    return node.BtNodeStatusFailed
}

func (n *CheckConditionNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    return n.status
}

func (n *CheckConditionNode) OnExit(ctx *context.BtContext) {
    // 无需清理
}

func (n *CheckConditionNode) evaluate(val any) bool {
    // 根据 Operator 和 Value 类型进行比较
    // 支持 int64, float64, string, bool 等类型
    switch n.Operator {
    case "==":
        return val == n.Value
    case "!=":
        return val != n.Value
    // 数值比较需要类型转换...
    default:
        return false
    }
}
```

---

### 任务 2.6：LogNode

**文件**：`bt/nodes/log.go`

```go
package nodes

import (
    "common/log"
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// LogNode 输出日志（立即完成，调试用）
type LogNode struct {
    BaseLeafNode
    Message string
    Level   string // "debug", "info", "warn", "error"
}

func NewLogNode(message string) *LogNode {
    return &LogNode{
        Message: message,
        Level:   "debug",
    }
}

func NewLogNodeWithLevel(message string, level string) *LogNode {
    return &LogNode{
        Message: message,
        Level:   level,
    }
}

func (n *LogNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    msg := fmt.Sprintf("[BT][Entity:%d] %s", ctx.EntityID, n.Message)

    switch n.Level {
    case "info":
        log.Info(msg)
    case "warn":
        log.Warn(msg)
    case "error":
        log.Error(msg)
    default:
        log.Debug(msg)
    }

    n.status = node.BtNodeStatusSuccess
    return node.BtNodeStatusSuccess
}

func (n *LogNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    return node.BtNodeStatusSuccess
}

func (n *LogNode) OnExit(ctx *context.BtContext) {
    // 无需清理
}
```

---

### 任务 2.7：LookAtNode

**文件**：`bt/nodes/look_at.go`

```go
package nodes

import (
    "common/transform"
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// LookAtNode 面向目标点（立即完成）
type LookAtNode struct {
    BaseLeafNode
    TargetKey   string          // 从黑板读取目标点
    TargetPoint *transform.Vec3 // 或直接指定
}

func NewLookAtNode(targetKey string) *LookAtNode {
    return &LookAtNode{
        TargetKey: targetKey,
    }
}

func NewLookAtNodeWithPoint(target *transform.Vec3) *LookAtNode {
    return &LookAtNode{
        TargetPoint: target,
    }
}

func (n *LookAtNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    target := n.getTarget(ctx)
    if target == nil {
        n.status = node.BtNodeStatusFailed
        return node.BtNodeStatusFailed
    }

    transComp := ctx.GetTransformComp()
    if transComp == nil {
        n.status = node.BtNodeStatusFailed
        return node.BtNodeStatusFailed
    }

    // 计算朝向并设置
    // direction := target.Sub(transComp.Position).Normalize()
    // transComp.SetRotation(direction.ToRotation())

    n.status = node.BtNodeStatusSuccess
    return node.BtNodeStatusSuccess
}

func (n *LookAtNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    return node.BtNodeStatusSuccess
}

func (n *LookAtNode) OnExit(ctx *context.BtContext) {
    // 无需清理
}

func (n *LookAtNode) getTarget(ctx *context.BtContext) *transform.Vec3 {
    if n.TargetPoint != nil {
        return n.TargetPoint
    }
    if n.TargetKey != "" {
        if val, ok := ctx.GetBlackboard(n.TargetKey); ok {
            if target, ok := val.(*transform.Vec3); ok {
                return target
            }
        }
    }
    return nil
}
```

---

### 任务 2.8：SetBlackboardNode

**文件**：`bt/nodes/set_blackboard.go`

```go
package nodes

import (
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// SetBlackboardNode 设置黑板数据（立即完成）
type SetBlackboardNode struct {
    BaseLeafNode
    Key   string
    Value any
}

func NewSetBlackboardNode(key string, value any) *SetBlackboardNode {
    return &SetBlackboardNode{
        Key:   key,
        Value: value,
    }
}

func (n *SetBlackboardNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    ctx.SetBlackboard(n.Key, n.Value)
    n.status = node.BtNodeStatusSuccess
    return node.BtNodeStatusSuccess
}

func (n *SetBlackboardNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    return node.BtNodeStatusSuccess
}

func (n *SetBlackboardNode) OnExit(ctx *context.BtContext) {
    // 无需清理
}
```

---

## 任务 3.2：BtTickSystem

### 前置条件
**等待 Sync 2**：Agent A 完成 BtRunner，本 Agent 完成叶子节点。

### 文件位置
`servers/scene_server/internal/ecs/system/decision/bt_tick_system.go`

### 实现

```go
package decision

import (
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/common/ai/bt/node"
    "mp/servers/scene_server/internal/common/ai/bt/runner"
    "mp/servers/scene_server/internal/ecs/system"
)

// BtTickSystem 行为树帧更新系统
type BtTickSystem struct {
    *system.SystemBase
    btRunner *runner.BtRunner
}

func NewBtTickSystem(scene common.Scene, btRunner *runner.BtRunner) *BtTickSystem {
    return &BtTickSystem{
        SystemBase: system.New(scene),
        btRunner:   btRunner,
    }
}

func (s *BtTickSystem) Type() common.SystemType {
    return common.SystemType_BtTick // 需要在 common 中注册
}

func (s *BtTickSystem) Update(dt float32) {
    // 遍历所有运行中的行为树
    for entityID, instance := range s.btRunner.GetRunningTrees() {
        status := s.btRunner.Tick(entityID, dt)

        // 行为树执行完成
        if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
            s.onTreeCompleted(entityID, instance.PlanName, status)
        }
    }
}

func (s *BtTickSystem) onTreeCompleted(entityID uint64, planName string, status node.BtNodeStatus) {
    // 通知决策层重新评估
    entity := s.Scene().Entity(entityID)
    if entity == nil {
        return
    }

    // 获取 DecisionComp 并触发重新评估
    decisionComp := entity.GetComponent(common.ComponentType_Decision)
    if decisionComp != nil {
        if dc, ok := decisionComp.(*caidecision.DecisionComp); ok {
            dc.RequestEvaluation()
        }
    }
}
```

### 注册系统

需要在场景初始化时注册 BtTickSystem：

```go
// 在场景初始化代码中
btTickSystem := NewBtTickSystem(scene, executor.GetBtRunner())
scene.RegisterSystem(btTickSystem)
```

### 验收标准

- [ ] BtTickSystem 正确遍历运行中的树
- [ ] 每帧调用 Tick
- [ ] 完成后触发决策层重新评估
- [ ] 编译通过

---

## 文件结构

完成后的目录结构：

```
servers/scene_server/internal/common/ai/bt/
├── context/
│   └── context.go          # Agent A
├── node/
│   └── interface.go        # Agent A
├── runner/
│   └── runner.go           # Agent A
└── nodes/
    ├── base.go             # 基类
    ├── move_to.go          # 2.1
    ├── wait.go             # 2.2
    ├── stop_move.go        # 2.3
    ├── set_feature.go      # 2.4
    ├── check_condition.go  # 2.5
    ├── log.go              # 2.6
    ├── look_at.go          # 2.7
    └── set_blackboard.go   # 2.8

servers/scene_server/internal/ecs/system/decision/
├── executor.go             # Agent A 修改
└── bt_tick_system.go       # 3.2
```

---

## 注意事项

1. **等待 Sync 1**：叶子节点实现前，必须等待 Agent A 完成 BtContext 接口
2. **立即完成节点**：OnEnter 直接返回 Success/Failed，OnTick 返回相同状态
3. **异步节点**：OnEnter 返回 Running，OnTick 检查完成条件
4. **OnExit 清理**：释放资源、停止正在进行的操作
5. **编译验证**：每个节点完成后执行 `make build APPS='scene_server'`
