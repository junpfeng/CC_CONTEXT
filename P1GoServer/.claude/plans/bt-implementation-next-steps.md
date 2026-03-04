# 行为树系统下一步实施计划

## 概述

本文档描述让行为树系统真正工作所需的具体实施步骤。

### 当前状态

| 类别 | 状态 | 说明 |
|------|------|------|
| 核心框架 | ✅ 完成 | BtRunner, BtContext, NodeFactory |
| 基础节点 | ✅ 完成 | Sequence, Selector, Log, Wait, SetFeature 等 |
| 配置文件 | ✅ 完成 | 9个Plan的JSON配置 |
| 系统注册 | ❌ 缺失 | 行为树未被注册到Executor |
| 业务节点 | ❌ 缺失 | 18个新节点需要实现 |

### 关键问题

```
当前代码路径:
Scene 创建 → ExecutorResource 创建 → BtTickSystem 创建
                    ↓
            btRunner.trees = {} (空)
                    ↓
            HasTree() 永远返回 false
                    ↓
            永远回退到原有 Task 逻辑
```

---

## 第一阶段：系统集成修复（优先级 P0）

### 任务 1.1：注册行为树到 Executor

**目标**：在场景初始化时调用 `RegisterTreesFromConfig`

**修改文件**：`servers/scene_server/internal/ecs/scene/scene_impl.go`

**修改位置**：`initNpcAISystemsFromConfig` 函数

```go
// 在 ExecutorResource 创建后，BtTickSystem 创建前添加
func (s *scene) initNpcAISystemsFromConfig() error {
    // ...existing code...

    if cfg.EnableDecision {
        executorRes := decision.NewExecutorResource(s)
        s.AddResource(executorRes)

        // === 新增：注册行为树 ===
        executor := executorRes.GetExecutor()
        count, err := trees.RegisterTreesFromConfig(executor.RegisterBehaviorTree)
        if err != nil {
            s.Warningf("[Scene] failed to register behavior trees: %v", err)
        } else {
            s.Infof("[Scene] registered %d behavior trees", count)
        }
        // === 新增结束 ===

        btTickSystem := decision.NewBtTickSystem(s, executor.GetBtRunner())
        s.AddSystem(btTickSystem)
        // ...rest of code...
    }
}
```

**验收标准**：
- [ ] 启动日志出现 `"[Scene] registered N behavior trees"`
- [ ] N > 0

### 任务 1.2：添加可观测性日志

**目标**：在关键路径添加日志，便于调试

**修改文件**：
- `bt/runner/runner.go`
- `ecs/system/decision/executor.go`

```go
// runner.go - HasTree 方法
func (r *BtRunner) HasTree(name string) bool {
    _, ok := r.trees[name]
    r.scene.Debugf("[BtRunner] HasTree check, name=%s, found=%v, total_trees=%d",
        name, ok, len(r.trees))
    return ok
}

// executor.go - OnPlanCreated 方法
func (e *Executor) OnPlanCreated(entityID uint32, plan *Plan) {
    planName := plan.GetName()
    hasBT := e.btRunner != nil && e.btRunner.HasTree(planName)
    e.scene.Debugf("[Executor] OnPlanCreated, entity=%d, plan=%s, has_bt=%v",
        entityID, planName, hasBT)
    // ...rest of code...
}
```

**验收标准**：
- [ ] Plan 触发时日志显示 `has_bt=true`

---

## 第二阶段：实现业务节点（优先级 P0-P1）

### 需要实现的节点清单

根据9个JSON配置文件的使用情况，需要实现以下节点：

#### P0 节点（阻塞所有Plan）

| 节点名称 | 使用的配置 | 功能 |
|----------|------------|------|
| `SyncFeatureToBlackboard` | 全部 | Feature值同步到黑板 |
| `SetPathFindType` | move, pursuit, investigate | 设置寻路类型 |
| `SetTargetType` | move, pursuit, investigate | 设置目标类型 |
| `StopMove` | move, pursuit, investigate | 停止移动 |
| `ClearPath` | pursuit | 清除路径 |
| `StartRun` | pursuit | 开始奔跑 |

#### P1 节点（阻塞特定Plan）

| 节点名称 | 使用的配置 | 功能 |
|----------|------------|------|
| `GetScheduleData` | idle | 获取日程数据 |
| `SetDialogOutFinishStamp` | idle | 设置外出结束时间戳 |
| `SetTownNpcOutDuration` | idle | 设置外出时长（同步客户端） |
| `SetTransformFromFeature` | idle, home_idle | 从Feature设置位置 |
| `QueryRoadNetworkPath` | move, meeting_move | 路网寻路 |
| `StartMove` | move | 开始移动 |
| `SetPointList` | move | 设置路径点列表 |
| `GetScheduleKey` | move | 获取日程key |
| `SetTargetEntity` | pursuit | 设置目标实体 |
| `PausePath` | dialog | 暂停路径 |
| `ResumePath` | dialog | 恢复路径 |
| `PushDialogTask` | dialog | 推送对话任务 |

### 任务 2.1：实现 P0 节点

**新建文件**：`servers/scene_server/internal/common/ai/bt/nodes/`

#### 2.1.1 sync_feature_to_blackboard.go

```go
package nodes

import (
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

// SyncFeatureToBlackboardNode 将Feature值同步到黑板
type SyncFeatureToBlackboardNode struct {
    BaseLeafNode
    Mappings map[string]string // feature_key -> blackboard_key
}

func NewSyncFeatureToBlackboardNode(mappings map[string]string) *SyncFeatureToBlackboardNode {
    n := &SyncFeatureToBlackboardNode{Mappings: mappings}
    n.BaseLeafNode = *NewBaseLeafNode("SyncFeatureToBlackboard")
    return n
}

func (n *SyncFeatureToBlackboardNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    decisionComp := ctx.GetDecisionComp()
    if decisionComp == nil {
        return node.BtNodeStatusFailed
    }

    for featureKey, bbKey := range n.Mappings {
        if val, ok := decisionComp.GetFeatureValue(featureKey); ok {
            ctx.SetBlackboard(bbKey, val)
        }
    }
    return node.BtNodeStatusSuccess
}
```

#### 2.1.2 path_control.go

```go
package nodes

// SetPathFindTypeNode 设置寻路类型
type SetPathFindTypeNode struct {
    BaseLeafNode
    PathFindType string // "None", "RoadNetwork", "NavMesh"
}

// SetTargetTypeNode 设置目标类型
type SetTargetTypeNode struct {
    BaseLeafNode
    TargetType string // "None", "WayPoint", "Player"
    EntityID   int64  // 可选
}

// ClearPathNode 清除路径
type ClearPathNode struct {
    BaseLeafNode
}

// StartRunNode 开始奔跑
type StartRunNode struct {
    BaseLeafNode
}
```

### 任务 2.2：在 NodeFactory 中注册新节点

**修改文件**：`servers/scene_server/internal/common/ai/bt/nodes/factory.go`

```go
func (f *NodeFactory) init() {
    // ...existing registrations...

    // P0 节点
    f.Register("SyncFeatureToBlackboard", f.createSyncFeatureToBlackboard)
    f.Register("SetPathFindType", f.createSetPathFindType)
    f.Register("SetTargetType", f.createSetTargetType)
    f.Register("ClearPath", f.createClearPath)
    f.Register("StartRun", f.createStartRun)

    // P1 节点
    f.Register("GetScheduleData", f.createGetScheduleData)
    f.Register("SetDialogOutFinishStamp", f.createSetDialogOutFinishStamp)
    f.Register("SetTransformFromFeature", f.createSetTransformFromFeature)
    // ... 其他节点 ...
}
```

---

## 第三阶段：端到端验证（优先级 P0）

### 任务 3.1：最小可验证测试

**目标**：验证一个最简单的行为树能够被执行

**步骤**：

1. 选择最简单的Plan：`home_idle`
2. 确保其所需的所有节点都已实现
3. 启动服务器，创建NPC
4. 触发 home_idle Plan
5. 观察日志

**预期日志**：
```
[Scene] registered 9 behavior trees
[Executor] OnPlanCreated, entity=123, plan=home_idle, has_bt=true
[BtRunner] Run, entity=123, tree=home_idle
[BtTickSystem] tick, running_trees=1
[HomeIdleEntry] start
[HomeIdleEntry] completed
```

### 任务 3.2：创建集成测试

**新建文件**：`servers/scene_server/internal/common/ai/bt/integration_test.go`

```go
func TestE2E_HomeIdlePlan(t *testing.T) {
    // 1. 创建测试场景
    scene := createTestScene()

    // 2. 初始化 ExecutorResource 和注册行为树
    executorRes := decision.NewExecutorResource(scene)
    count, err := trees.RegisterTreesFromConfig(
        executorRes.GetExecutor().RegisterBehaviorTree)
    require.NoError(t, err)
    require.Greater(t, count, 0)

    // 3. 创建测试NPC实体
    entity := createTestNPCEntity(scene)

    // 4. 模拟 Plan 创建
    plan := &gss.Plan{Name: "home_idle"}
    executorRes.GetExecutor().OnPlanCreated(entity.ID(), plan)

    // 5. 验证行为树启动
    btRunner := executorRes.GetExecutor().GetBtRunner()
    assert.True(t, btRunner.IsRunning(entity.ID()))

    // 6. 执行若干次 Tick
    for i := 0; i < 10; i++ {
        btRunner.Tick(entity.ID(), 0.1)
    }

    // 7. 验证行为树完成
    assert.False(t, btRunner.IsRunning(entity.ID()))
}
```

---

## 第四阶段：渐进式迁移（优先级 P1-P2）

### 迁移顺序

| 批次 | Plan | 依赖节点 | 复杂度 |
|------|------|----------|--------|
| 1 | home_idle | SetTransformFromFeature, SyncFeatureToBlackboard, SetFeature | 低 |
| 2 | idle | GetScheduleData, SetDialogOutFinishStamp, SetTownNpcOutDuration | 低 |
| 3 | move | QueryRoadNetworkPath, SetPathFindType, SetTargetType, SetPointList | 中 |
| 4 | dialog | PausePath, ResumePath, PushDialogTask | 中 |
| 5 | meeting_idle, meeting_move | 复用 move 节点 | 低 |
| 6 | pursuit | ClearPath, StartRun, SetTargetEntity, NavMesh相关 | 高 |
| 7 | investigate | 复用 pursuit 节点 | 高 |
| 8 | sakura_npc_control | 专用节点 | 高 |

### 每个Plan迁移检查清单

- [ ] 所需节点全部实现
- [ ] JSON配置文件语法正确
- [ ] NodeFactory 注册节点
- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] 端到端日志正确
- [ ] 无回归问题

---

## 实施时间线

```
Week 1:
├── Day 1-2: 第一阶段 - 系统集成修复
│   ├── 任务1.1: 注册行为树
│   └── 任务1.2: 添加可观测性日志
│
├── Day 3-5: 第二阶段 - P0节点实现
│   ├── SyncFeatureToBlackboard
│   ├── SetPathFindType
│   ├── SetTargetType
│   ├── ClearPath
│   └── StartRun

Week 2:
├── Day 1-2: 第二阶段 - P1节点实现
│   ├── GetScheduleData
│   ├── SetDialogOutFinishStamp
│   └── SetTransformFromFeature
│
├── Day 3: 第三阶段 - 端到端验证
│   └── home_idle Plan 完整流程
│
├── Day 4-5: 第四阶段 - 迁移第1批
│   ├── home_idle
│   └── idle

Week 3+:
├── 继续迁移其他Plan
└── 清理旧代码
```

---

## 验收标准总结

### 第一阶段验收
- [ ] `[Scene] registered N behavior trees` 日志出现，N > 0
- [ ] `[Executor] OnPlanCreated ... has_bt=true` 日志出现

### 第二阶段验收
- [ ] 所有P0节点编译通过
- [ ] 所有P0节点单元测试通过
- [ ] NodeFactory 能创建所有新节点

### 第三阶段验收
- [ ] home_idle Plan 完整执行流程可观测
- [ ] 集成测试通过

### 第四阶段验收
- [ ] 每批迁移的Plan功能正常
- [ ] 无回归问题
- [ ] 性能无明显下降

---

## 风险与应对

| 风险 | 可能性 | 影响 | 应对措施 |
|------|--------|------|----------|
| 节点实现与原Handler逻辑不一致 | 高 | 高 | 逐行对比，充分测试 |
| 组件访问方式不兼容 | 中 | 中 | 扩展BtContext接口 |
| 性能下降 | 低 | 中 | 性能测试，必要时优化 |
| 迁移过程中出现回归 | 中 | 高 | 保留旧代码，支持快速回滚 |

---

## 附录：文件清单

### 需要修改的文件
```
servers/scene_server/internal/ecs/scene/scene_impl.go      # 注册行为树
servers/scene_server/internal/common/ai/bt/nodes/factory.go # 注册新节点
servers/scene_server/internal/common/ai/bt/runner/runner.go # 添加日志
servers/scene_server/internal/ecs/system/decision/executor.go # 添加日志
```

### 需要新建的文件
```
servers/scene_server/internal/common/ai/bt/nodes/sync_feature_to_blackboard.go
servers/scene_server/internal/common/ai/bt/nodes/path_control.go
servers/scene_server/internal/common/ai/bt/nodes/schedule.go
servers/scene_server/internal/common/ai/bt/nodes/dialog.go
servers/scene_server/internal/common/ai/bt/nodes/transform.go
servers/scene_server/internal/common/ai/bt/integration_test.go
```
