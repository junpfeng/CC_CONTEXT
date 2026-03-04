# Agent A: 行为树核心框架

## 概述

负责实现行为树的核心基础设施：BtContext、BtRunner、Executor 集成。

**计划文件**：`.claude/plans/behavior-tree-integration-plan.md`
**协调文件**：`.claude/agents/bt-integration-orchestrator.md`

---

## 任务列表

| 序号 | 任务 | 文件 | 依赖 | 输出 |
|------|------|------|------|------|
| 1.1 | BtContext | `bt/context/context.go` | 无 | 接口定义（通知 Agent B） |
| 1.2 | BtRunner | `bt/runner/runner.go` | 1.1 | 树运行器 |
| 3.1 | 修改 Executor | `decision/executor.go` | 1.2 | 集成行为树 |

---

## 任务 1.1：实现 BtContext

### 目标
创建行为树执行上下文，提供 Entity 组件访问和黑板数据管理。

### 文件位置
`servers/scene_server/internal/common/ai/bt/context/context.go`

### 接口定义

```go
package context

import (
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/ecs/com/cnpc"
    "mp/servers/scene_server/internal/ecs/com/caidecision"
    "mp/servers/scene_server/internal/ecs/com/ctrans"
)

// BtContext 行为树执行上下文
type BtContext struct {
    Scene      common.Scene
    EntityID   uint64
    Blackboard map[string]any
    DeltaTime  float32

    // 组件缓存（懒加载）
    moveComp      *cnpc.NpcMoveComp
    decisionComp  *caidecision.DecisionComp
    transformComp *ctrans.Transform
}

// NewBtContext 创建新的上下文
func NewBtContext(scene common.Scene, entityID uint64) *BtContext

// Reset 重置上下文（复用时调用）
func (c *BtContext) Reset(entityID uint64, deltaTime float32)

// --- 组件访问 ---

// GetMoveComp 获取移动组件（懒加载）
func (c *BtContext) GetMoveComp() *cnpc.NpcMoveComp

// GetDecisionComp 获取决策组件（懒加载）
func (c *BtContext) GetDecisionComp() *caidecision.DecisionComp

// GetTransformComp 获取变换组件（懒加载）
func (c *BtContext) GetTransformComp() *ctrans.Transform

// GetEntity 获取 Entity
func (c *BtContext) GetEntity() common.Entity

// --- 黑板操作 ---

// SetBlackboard 设置黑板数据
func (c *BtContext) SetBlackboard(key string, value any)

// GetBlackboard 获取黑板数据
func (c *BtContext) GetBlackboard(key string) (any, bool)

// GetBlackboardInt64 获取 int64 类型黑板数据
func (c *BtContext) GetBlackboardInt64(key string) (int64, bool)

// GetBlackboardFloat32 获取 float32 类型黑板数据
func (c *BtContext) GetBlackboardFloat32(key string) (float32, bool)

// GetBlackboardString 获取 string 类型黑板数据
func (c *BtContext) GetBlackboardString(key string) (string, bool)

// ClearBlackboard 清空黑板
func (c *BtContext) ClearBlackboard()
```

### 实现要点

1. **懒加载组件**：首次访问时从 Scene 获取，缓存到字段
2. **类型安全的黑板访问**：提供泛型或类型特化的 Get 方法
3. **复用支持**：Reset 方法清理缓存，支持对象池复用

### 验收标准

- [ ] 能通过 EntityID 获取各类组件
- [ ] 黑板读写正常
- [ ] 编译通过：`make build APPS='scene_server'`

### 完成后动作

**通知 Agent B**：接口定义完成，可以开始叶子节点实现。

---

## 任务 1.2：实现 BtRunner

### 目标
创建行为树运行器，管理行为树的注册、实例化、执行和生命周期。

### 文件位置
`servers/scene_server/internal/common/ai/bt/runner/runner.go`

### 依赖
- 任务 1.1 BtContext
- 节点接口（同时定义在 `bt/node/interface.go`）

### 接口定义

```go
package runner

import (
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// BtRunner 行为树运行器
type BtRunner struct {
    scene        common.Scene
    trees        map[string]node.IBtNode       // planName -> 行为树根节点
    runningTrees map[uint64]*TreeInstance      // entityID -> 运行中的树实例
}

// TreeInstance 行为树实例
type TreeInstance struct {
    PlanName  string
    Root      node.IBtNode
    Context   *context.BtContext
    Status    node.BtNodeStatus
    StartTime int64
}

// NewBtRunner 创建运行器
func NewBtRunner(scene common.Scene) *BtRunner

// --- 树管理 ---

// RegisterTree 注册行为树
func (r *BtRunner) RegisterTree(planName string, root node.IBtNode)

// HasTree 检查是否有对应的行为树
func (r *BtRunner) HasTree(planName string) bool

// --- 执行控制 ---

// Run 启动行为树
func (r *BtRunner) Run(planName string, entityID uint64) error

// Stop 停止行为树
func (r *BtRunner) Stop(entityID uint64)

// Tick 执行一帧
func (r *BtRunner) Tick(entityID uint64, deltaTime float32) node.BtNodeStatus

// --- 状态查询 ---

// IsRunning 检查是否正在运行
func (r *BtRunner) IsRunning(entityID uint64) bool

// GetRunningTrees 获取所有运行中的树（供 BtTickSystem 遍历）
func (r *BtRunner) GetRunningTrees() map[uint64]*TreeInstance

// GetInstance 获取指定实体的树实例
func (r *BtRunner) GetInstance(entityID uint64) *TreeInstance
```

### 节点接口定义

同时创建 `bt/node/interface.go`：

```go
package node

// BtNodeStatus 节点状态
type BtNodeStatus int

const (
    BtNodeStatusInit    BtNodeStatus = iota
    BtNodeStatusRunning
    BtNodeStatusSuccess
    BtNodeStatusFailed
)

// BtNodeType 节点类型
type BtNodeType int

const (
    BtNodeTypeControl   BtNodeType = iota // 控制节点
    BtNodeTypeDecorator                   // 装饰节点
    BtNodeTypeLeaf                        // 叶子节点
)

// IBtNode 行为树节点接口
type IBtNode interface {
    // 生命周期
    OnEnter(ctx *context.BtContext) BtNodeStatus
    OnTick(ctx *context.BtContext) BtNodeStatus
    OnExit(ctx *context.BtContext)

    // 状态
    Status() BtNodeStatus
    Reset()

    // 结构
    Children() []IBtNode
    NodeType() BtNodeType
}
```

### 实现要点

1. **Run 逻辑**：
   - 检查 planName 对应的树是否存在
   - 创建 TreeInstance，初始化 BtContext
   - 调用根节点 OnEnter

2. **Stop 逻辑**：
   - 递归调用所有运行中节点的 OnExit
   - 清理 TreeInstance

3. **Tick 逻辑**：
   - 更新 DeltaTime
   - 调用根节点 OnTick
   - 返回状态

### 验收标准

- [ ] 能注册行为树
- [ ] Run/Stop/Tick 正常工作
- [ ] 编译通过

---

## 任务 3.1：修改 Executor

### 目标
将 BtRunner 集成到现有 Executor，支持 Plan 使用行为树执行。

### 文件位置
`servers/scene_server/internal/ecs/system/decision/executor.go`

### 依赖
- 任务 1.2 BtRunner
- Agent B 完成叶子节点（Sync 2）

### 修改内容

```go
type Executor struct {
    Scene    common.Scene
    btRunner *runner.BtRunner  // 新增
}

func NewExecutor(scene common.Scene) *Executor {
    return &Executor{
        Scene:    scene,
        btRunner: runner.NewBtRunner(scene),  // 新增
    }
}

// OnPlanCreated 处理新 Plan
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    // 检查是否有对应的行为树
    if e.btRunner.HasTree(req.Plan.Name) {
        // 停止之前的行为树
        e.btRunner.Stop(uint64(req.EntityID))
        // 启动新的行为树
        return e.btRunner.Run(req.Plan.Name, uint64(req.EntityID))
    }

    // 原有逻辑
    for _, task := range req.Plan.Tasks {
        e.executeTask(req.EntityID, req.Plan.Name, req.Plan.FromPlan, task)
    }
    return nil
}

// RegisterBehaviorTree 注册行为树
func (e *Executor) RegisterBehaviorTree(planName string, root node.IBtNode) {
    e.btRunner.RegisterTree(planName, root)
}

// GetBtRunner 获取 BtRunner（供 BtTickSystem 使用）
func (e *Executor) GetBtRunner() *runner.BtRunner {
    return e.btRunner
}
```

### 验收标准

- [ ] Executor 正确判断是否使用行为树
- [ ] Plan 转移时正确 Stop/Start 行为树
- [ ] 原有 handleXxxTask 逻辑不受影响
- [ ] 编译通过

---

## 文件结构

完成后的目录结构：

```
servers/scene_server/internal/common/ai/bt/
├── context/
│   └── context.go      # BtContext（任务 1.1）
├── node/
│   └── interface.go    # IBtNode 接口（任务 1.2）
├── runner/
│   └── runner.go       # BtRunner（任务 1.2）
└── nodes/              # Agent B 负责
    └── ...
```

---

## 注意事项

1. **包引用**：避免循环引用，context 和 node 包相互独立
2. **线程安全**：BtRunner 的 map 操作考虑并发（如果需要）
3. **日志**：关键操作添加 Debug 日志
4. **错误处理**：Run 返回 error，Stop 静默处理
