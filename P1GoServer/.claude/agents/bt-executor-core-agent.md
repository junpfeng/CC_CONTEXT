# Agent A: BtRunner-Executor 核心框架

## 概述

负责实现 Part 6 的核心基础设施：BtContext、BtRunner、Executor 集成。

**计划文件**：`.claude/plans/behavior-tree-integration-plan.md` (Part 6)
**协调文件**：`.claude/agents/bt-executor-integration-orchestrator.md`

---

## 任务列表

| 序号 | 任务 | 文件 | 依赖 | 输出 |
|------|------|------|------|------|
| 6.2 | BtContext | `bt/context/context.go` | 无 | 执行上下文 |
| 6.4 | BtRunner | `bt/runner/runner.go` | 6.2, 6.3(Agent B) | 运行器（通知 Agent B） |
| 6.5 | 修改 Executor | `decision/executor.go` | 6.4 | 集成行为树 |

---

## 任务 6.2：实现 BtContext

### 目标
创建行为树执行上下文，提供 Entity 组件访问和黑板数据管理。

### 文件位置
`servers/scene_server/internal/common/ai/bt/context/context.go`

### 完整实现

```go
package context

import (
    "common/log"
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/ecs/com/caidecision"
    "mp/servers/scene_server/internal/ecs/com/cnpc"
    "mp/servers/scene_server/internal/ecs/com/ctrans"
)

// BtContext 行为树执行上下文
// 提供 Entity 组件访问和黑板数据管理
type BtContext struct {
    Scene      common.Scene   // 所属场景
    EntityID   uint64         // 实体ID
    Blackboard map[string]any // 黑板数据存储
    DeltaTime  float32        // 帧间隔时间（秒）

    // 组件缓存（懒加载）
    moveComp      *cnpc.NpcMoveComp
    decisionComp  *caidecision.DecisionComp
    transformComp *ctrans.Transform
}

// NewBtContext 创建新的行为树上下文
func NewBtContext(scene common.Scene, entityID uint64) *BtContext {
    return &BtContext{
        Scene:      scene,
        EntityID:   entityID,
        Blackboard: make(map[string]any),
        DeltaTime:  0,
    }
}

// Reset 重置上下文（复用时调用）
func (c *BtContext) Reset(entityID uint64, deltaTime float32) {
    c.EntityID = entityID
    c.DeltaTime = deltaTime
    c.moveComp = nil
    c.decisionComp = nil
    c.transformComp = nil
    c.Blackboard = make(map[string]any)
}

// --- 组件访问（懒加载） ---

// GetMoveComp 获取移动组件
func (c *BtContext) GetMoveComp() *cnpc.NpcMoveComp {
    if c.moveComp != nil {
        return c.moveComp
    }
    comp, ok := common.GetComponentAs[*cnpc.NpcMoveComp](c.Scene, c.EntityID, common.ComponentType_NpcMove)
    if !ok {
        log.Debugf("[BtContext] move component not found, entity_id=%d", c.EntityID)
        return nil
    }
    c.moveComp = comp
    return c.moveComp
}

// GetDecisionComp 获取决策组件
func (c *BtContext) GetDecisionComp() *caidecision.DecisionComp {
    if c.decisionComp != nil {
        return c.decisionComp
    }
    comp, ok := common.GetComponentAs[*caidecision.DecisionComp](c.Scene, c.EntityID, common.ComponentType_AIDecision)
    if !ok {
        log.Debugf("[BtContext] decision component not found, entity_id=%d", c.EntityID)
        return nil
    }
    c.decisionComp = comp
    return c.decisionComp
}

// GetTransformComp 获取变换组件
func (c *BtContext) GetTransformComp() *ctrans.Transform {
    if c.transformComp != nil {
        return c.transformComp
    }
    comp, ok := common.GetComponentAs[*ctrans.Transform](c.Scene, c.EntityID, common.ComponentType_Transform)
    if !ok {
        log.Debugf("[BtContext] transform component not found, entity_id=%d", c.EntityID)
        return nil
    }
    c.transformComp = comp
    return c.transformComp
}

// GetEntity 获取 Entity
func (c *BtContext) GetEntity() common.Entity {
    entity, ok := c.Scene.GetEntity(c.EntityID)
    if !ok {
        log.Debugf("[BtContext] entity not found, entity_id=%d", c.EntityID)
        return nil
    }
    return entity
}

// --- 黑板操作 ---

// SetBlackboard 设置黑板数据
func (c *BtContext) SetBlackboard(key string, value any) {
    if c.Blackboard == nil {
        c.Blackboard = make(map[string]any)
    }
    c.Blackboard[key] = value
}

// GetBlackboard 获取黑板数据
func (c *BtContext) GetBlackboard(key string) (any, bool) {
    if c.Blackboard == nil {
        return nil, false
    }
    val, ok := c.Blackboard[key]
    return val, ok
}

// GetBlackboardInt64 获取 int64 类型黑板数据
func (c *BtContext) GetBlackboardInt64(key string) (int64, bool) {
    val, ok := c.GetBlackboard(key)
    if !ok {
        return 0, false
    }
    switch v := val.(type) {
    case int64:
        return v, true
    case int:
        return int64(v), true
    case int32:
        return int64(v), true
    default:
        return 0, false
    }
}

// GetBlackboardFloat32 获取 float32 类型黑板数据
func (c *BtContext) GetBlackboardFloat32(key string) (float32, bool) {
    val, ok := c.GetBlackboard(key)
    if !ok {
        return 0, false
    }
    switch v := val.(type) {
    case float32:
        return v, true
    case float64:
        return float32(v), true
    default:
        return 0, false
    }
}

// GetBlackboardString 获取 string 类型黑板数据
func (c *BtContext) GetBlackboardString(key string) (string, bool) {
    val, ok := c.GetBlackboard(key)
    if !ok {
        return "", false
    }
    if str, ok := val.(string); ok {
        return str, true
    }
    return "", false
}

// ClearBlackboard 清空黑板
func (c *BtContext) ClearBlackboard() {
    c.Blackboard = make(map[string]any)
}
```

### 验收标准

- [ ] 能通过 EntityID 获取各类组件
- [ ] 黑板读写正常
- [ ] 编译通过：`make build APPS='scene_server'`

---

## 任务 6.4：实现 BtRunner

### 目标
创建行为树运行器，管理行为树的注册、实例化、执行和生命周期。

### 依赖
- 任务 6.2 BtContext（本 Agent）
- 任务 6.3 IBtNode（Agent B）

### 文件位置
`servers/scene_server/internal/common/ai/bt/runner/runner.go`

### 完整实现

```go
package runner

import (
    "errors"
    "time"

    "common/log"
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

var (
    ErrTreeNotFound       = errors.New("behavior tree not found")
    ErrTreeAlreadyRunning = errors.New("behavior tree already running for this entity")
)

// TreeInstance 行为树实例
type TreeInstance struct {
    PlanName  string
    Root      node.IBtNode
    Context   *context.BtContext
    Status    node.BtNodeStatus
    StartTime int64
}

// BtRunner 行为树运行器
type BtRunner struct {
    scene        common.Scene
    trees        map[string]node.IBtNode     // planName -> 行为树根节点
    runningTrees map[uint64]*TreeInstance    // entityID -> 运行中实例
}

// NewBtRunner 创建行为树运行器
func NewBtRunner(scene common.Scene) *BtRunner {
    return &BtRunner{
        scene:        scene,
        trees:        make(map[string]node.IBtNode),
        runningTrees: make(map[uint64]*TreeInstance),
    }
}

// --- 树管理 ---

// RegisterTree 注册行为树
func (r *BtRunner) RegisterTree(planName string, root node.IBtNode) {
    if root == nil {
        log.Warningf("[BtRunner] RegisterTree failed: root is nil, plan_name=%s", planName)
        return
    }
    r.trees[planName] = root
    log.Infof("[BtRunner] RegisterTree success, plan_name=%s", planName)
}

// UnregisterTree 取消注册行为树
func (r *BtRunner) UnregisterTree(planName string) {
    delete(r.trees, planName)
}

// HasTree 检查是否有对应的行为树
func (r *BtRunner) HasTree(planName string) bool {
    _, ok := r.trees[planName]
    return ok
}

// GetTree 获取行为树模板
func (r *BtRunner) GetTree(planName string) (node.IBtNode, bool) {
    tree, ok := r.trees[planName]
    return tree, ok
}

// --- 执行控制 ---

// Run 启动行为树
func (r *BtRunner) Run(planName string, entityID uint64) error {
    root, ok := r.trees[planName]
    if !ok {
        return ErrTreeNotFound
    }

    // 如果已有运行中的树，先停止
    if _, exists := r.runningTrees[entityID]; exists {
        r.Stop(entityID)
    }

    // 创建上下文
    ctx := context.NewBtContext(r.scene, entityID)

    // 重置树状态
    root.Reset()

    // 创建树实例
    instance := &TreeInstance{
        PlanName:  planName,
        Root:      root,
        Context:   ctx,
        Status:    node.BtNodeStatusInit,
        StartTime: time.Now().UnixMilli(),
    }

    r.runningTrees[entityID] = instance

    // 调用根节点 OnEnter
    status := root.OnEnter(ctx)
    instance.Status = status

    log.Infof("[BtRunner] Run started, entity_id=%d, plan_name=%s, status=%s",
        entityID, planName, status.String())

    return nil
}

// Stop 停止行为树
func (r *BtRunner) Stop(entityID uint64) {
    instance, ok := r.runningTrees[entityID]
    if !ok {
        return
    }

    // 递归调用所有运行中节点的 OnExit
    r.stopNode(instance.Root, instance.Context)

    delete(r.runningTrees, entityID)

    log.Infof("[BtRunner] Stop completed, entity_id=%d, plan_name=%s",
        entityID, instance.PlanName)
}

func (r *BtRunner) stopNode(n node.IBtNode, ctx *context.BtContext) {
    if n == nil {
        return
    }
    if n.Status() == node.BtNodeStatusRunning {
        n.OnExit(ctx)
    }
    for _, child := range n.Children() {
        r.stopNode(child, ctx)
    }
}

// Tick 执行一帧
func (r *BtRunner) Tick(entityID uint64, deltaTime float32) node.BtNodeStatus {
    instance, ok := r.runningTrees[entityID]
    if !ok {
        return node.BtNodeStatusFailed
    }

    instance.Context.DeltaTime = deltaTime

    if instance.Status == node.BtNodeStatusSuccess ||
       instance.Status == node.BtNodeStatusFailed {
        return instance.Status
    }

    status := r.tickNode(instance.Root, instance.Context)
    instance.Status = status

    if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
        instance.Root.OnExit(instance.Context)
        log.Infof("[BtRunner] Tick completed, entity_id=%d, plan_name=%s, status=%s",
            entityID, instance.PlanName, status.String())
    }

    return status
}

func (r *BtRunner) tickNode(n node.IBtNode, ctx *context.BtContext) node.BtNodeStatus {
    if n == nil {
        return node.BtNodeStatusFailed
    }

    // 首次进入
    if n.Status() == node.BtNodeStatusInit {
        status := n.OnEnter(ctx)
        if status != node.BtNodeStatusRunning {
            n.OnExit(ctx)
            return status
        }
    }

    // 每帧执行
    status := n.OnTick(ctx)

    // 完成时退出
    if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
        n.OnExit(ctx)
    }

    return status
}

// --- 状态查询 ---

// IsRunning 检查是否正在运行
func (r *BtRunner) IsRunning(entityID uint64) bool {
    instance, ok := r.runningTrees[entityID]
    if !ok {
        return false
    }
    return instance.Status == node.BtNodeStatusRunning ||
           instance.Status == node.BtNodeStatusInit
}

// GetRunningTrees 获取所有运行中的树
func (r *BtRunner) GetRunningTrees() map[uint64]*TreeInstance {
    return r.runningTrees
}

// GetInstance 获取指定实体的树实例
func (r *BtRunner) GetInstance(entityID uint64) *TreeInstance {
    return r.runningTrees[entityID]
}

// GetRunningCount 获取运行中的树数量
func (r *BtRunner) GetRunningCount() int {
    return len(r.runningTrees)
}

// GetRegisteredCount 获取已注册的树数量
func (r *BtRunner) GetRegisteredCount() int {
    return len(r.trees)
}

// GetScene 获取所属场景
func (r *BtRunner) GetScene() common.Scene {
    return r.scene
}
```

### 验收标准

- [ ] 能注册行为树
- [ ] Run/Stop/Tick 正常工作
- [ ] 编译通过：`make build APPS='scene_server'`

### 完成后动作

**通知 Agent B**：BtRunner 完成，可以开始 6.6 BtTickSystem。

---

## 任务 6.5：修改 Executor

### 目标
将 BtRunner 集成到现有 Executor，支持 Plan 使用行为树执行。

### 依赖
- 任务 6.4 BtRunner

### 文件位置
`servers/scene_server/internal/ecs/system/decision/executor.go`

### 修改内容

在现有 Executor 基础上添加：

```go
import (
    // 新增 import
    "mp/servers/scene_server/internal/common/ai/bt/node"
    "mp/servers/scene_server/internal/common/ai/bt/runner"
)

// Executor 决策执行器实现
type Executor struct {
    Scene    common.Scene
    btRunner *runner.BtRunner  // 新增：行为树运行器
}

// NewExecutor 创建决策执行器
func NewExecutor(scene common.Scene) *Executor {
    return &Executor{
        Scene:    scene,
        btRunner: runner.NewBtRunner(scene),  // 新增
    }
}

// RegisterBehaviorTree 注册行为树
func (e *Executor) RegisterBehaviorTree(planName string, root node.IBtNode) {
    if e.btRunner == nil {
        e.btRunner = runner.NewBtRunner(e.Scene)
    }
    e.btRunner.RegisterTree(planName, root)
}

// GetBtRunner 获取行为树运行器（供 BtTickSystem 使用）
func (e *Executor) GetBtRunner() *runner.BtRunner {
    return e.btRunner
}

// OnPlanCreated 处理 AI 决策产生的计划（修改）
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    e.Scene.Debugf("[Executor][OnPlanCreated] entity_id=%v, plan=%v, from_plan=%v",
        req.EntityID, req.Plan.Name, req.Plan.FromPlan)

    // 优先检查是否有对应的行为树
    if e.btRunner != nil && e.btRunner.HasTree(req.Plan.Name) {
        // 停止之前的行为树（如果有）
        e.btRunner.Stop(uint64(req.EntityID))

        // 启动新的行为树
        if err := e.btRunner.Run(req.Plan.Name, uint64(req.EntityID)); err != nil {
            e.Scene.Warningf("[Executor] BT run failed, plan=%v, err=%v", req.Plan.Name, err)
            // 回退到原有逻辑
        } else {
            e.Scene.Infof("[Executor] BT started, plan=%v, entity=%v", req.Plan.Name, req.EntityID)
            return nil  // 行为树接管，不执行原有 Task
        }
    }

    // 原有逻辑：遍历任务执行
    for _, task := range req.Plan.Tasks {
        e.Scene.Debugf("[Executor][OnPlanCreated] task:%v", task)
        e.executeTask(req.EntityID, req.Plan.Name, req.Plan.FromPlan, task)
    }

    return nil
}
```

### 验收标准

- [ ] Executor 包含 btRunner 字段
- [ ] NewExecutor 初始化 btRunner
- [ ] OnPlanCreated 优先检查行为树
- [ ] 原有 Task 逻辑不受影响
- [ ] 编译通过：`make build APPS='scene_server'`

---

## 文件结构

完成后的目录结构：

```
servers/scene_server/internal/common/ai/bt/
├── context/
│   └── context.go      # 6.2 BtContext
├── node/
│   └── interface.go    # 6.3 IBtNode (Agent B)
└── runner/
    └── runner.go       # 6.4 BtRunner

servers/scene_server/internal/ecs/system/decision/
└── executor.go         # 6.5 修改
```

---

## 注意事项

1. **包引用**：context 包不应引用 node 包，避免循环引用
2. **日志**：使用 `common/log` 包
3. **错误处理**：Run 返回 error，Stop 静默处理
4. **向后兼容**：确保无行为树的 Plan 仍使用原有 Task 逻辑
