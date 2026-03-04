# 行为树系统设计文档

## 一、设计思想

### 1.1 什么是行为树

行为树（Behavior Tree）是一种用于控制 AI 决策和行为的树形结构。它将复杂的行为分解为简单的、可组合的节点，通过树形结构组织这些节点来实现复杂的行为逻辑。

**核心特点**：
- **模块化**：每个节点是独立的行为单元，可复用
- **可视化**：树形结构直观，易于理解和调试
- **可配置**：支持数据驱动，无需改代码即可调整行为
- **可扩展**：易于添加新的节点类型

### 1.2 为什么选择行为树

在本项目中，原有的 AI 决策系统采用 GSS Brain 模型：
- **决策层**：基于特征(Feature)、条件(Condition)、转移(Transition)生成 Plan
- **执行层**：Executor 通过硬编码的 `handleXxxTask()` 函数执行具体行为

**原有问题**：
1. 每个 Plan 的执行逻辑都是硬编码的 Go 函数
2. 复杂行为序列需要写大量代码
3. 行为调整需要改代码、重新编译

**行为树解决方案**：
- 行为树作为 Plan 的**可选执行器**
- 复杂行为通过**节点组合**实现
- 支持**配置驱动**，减少硬编码

### 1.3 架构定位

```
┌─────────────────────────────────────────────────────────┐
│                     决策层 (GSS Brain)                    │
│  Feature → Condition → Transition → Plan                │
└─────────────────────────┬───────────────────────────────┘
                          │ OnPlanCreated(Plan)
                          ▼
┌─────────────────────────────────────────────────────────┐
│                     执行层 (Executor)                     │
│                                                          │
│  if hasBehaviorTree(plan.Name):                         │
│      btRunner.Run(plan.Name, entityID)  ← 行为树执行     │
│  else:                                                   │
│      executeTask(task)  ← 原有硬编码逻辑                  │
└─────────────────────────────────────────────────────────┘
```

**关键设计决策**：
- **一个 Plan = 一棵行为树**：简化管理，Entry/Exit 通过节点生命周期处理
- **渐进式迁移**：新 Plan 用行为树，旧 Plan 保持原逻辑
- **行为树完成后自动触发决策重评估**：避免 NPC "发呆"

### 1.4 场景中的行为树架构

#### 1.4.1 整体结构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Scene (场景)                                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Systems (系统层)                             │   │
│  │                                                                      │   │
│  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────┐  │   │
│  │  │  DecisionSystem  │    │  BtTickSystem    │    │ OtherSystems │  │   │
│  │  │  (决策系统)       │    │  (行为树Tick)    │    │              │  │   │
│  │  └────────┬─────────┘    └────────┬─────────┘    └──────────────┘  │   │
│  │           │                       │                                 │   │
│  └───────────┼───────────────────────┼─────────────────────────────────┘   │
│              │                       │                                      │
│              │  OnPlanCreated        │  Update (每帧)                       │
│              ▼                       ▼                                      │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                           Executor (执行器)                            │ │
│  │                                                                        │ │
│  │   ┌─────────────────────────────────────────────────────────────┐    │ │
│  │   │                    BtRunner (行为树运行器)                    │    │ │
│  │   │                                                              │    │ │
│  │   │  trees: map[string]IBtNode      # 注册的行为树模板           │    │ │
│  │   │    ├─ "patrol" → SequenceNode                               │    │ │
│  │   │    ├─ "idle"   → SequenceNode                               │    │ │
│  │   │    └─ "dialog" → SelectorNode                               │    │ │
│  │   │                                                              │    │ │
│  │   │  runningTrees: map[uint64]*TreeInstance  # 运行中的实例      │    │ │
│  │   │    ├─ Entity_101 → TreeInstance{patrol, Running}            │    │ │
│  │   │    ├─ Entity_102 → TreeInstance{idle, Running}              │    │ │
│  │   │    └─ Entity_103 → TreeInstance{dialog, Running}            │    │ │
│  │   └─────────────────────────────────────────────────────────────┘    │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                      │                                      │
│                                      │ 组件访问                              │
│                                      ▼                                      │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                         Entities (实体层)                              │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │ │
│  │  │  NPC Entity (EntityID: 101)                                     │ │ │
│  │  │                                                                  │ │ │
│  │  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────┐│ │ │
│  │  │  │ Transform    │ │ NpcMoveComp  │ │ DecisionComp             ││ │ │
│  │  │  │ (位置/旋转)   │ │ (移动控制)   │ │ (决策数据/特征)          ││ │ │
│  │  │  └──────────────┘ └──────────────┘ └──────────────────────────┘│ │ │
│  │  └─────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │ │
│  │  │  NPC Entity (EntityID: 102)  ...                                │ │ │
│  │  └─────────────────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.4.2 核心组件关系

```
┌─────────────┐         ┌─────────────┐         ┌─────────────────┐
│   Scene     │────────▶│  Executor   │────────▶│    BtRunner     │
│  (场景)     │         │  (执行器)    │         │  (行为树运行器)  │
└─────────────┘         └─────────────┘         └────────┬────────┘
      │                                                   │
      │                                                   │ 管理
      │                                                   ▼
      │                                         ┌─────────────────┐
      │                                         │  TreeInstance   │
      │                                         │  (树实例)        │
      │                                         │                 │
      │                                         │  - PlanName     │
      │                                         │  - Root (根节点) │
      │                                         │  - Context      │
      │                                         │  - Status       │
      │                                         └────────┬────────┘
      │                                                  │
      │                                                  │ 包含
      │                                                  ▼
      │                                         ┌─────────────────┐
      │                                         │   BtContext     │
      │                                         │   (执行上下文)   │
      │         组件访问                         │                 │
      │◀────────────────────────────────────────│  - Scene        │
      │                                         │  - EntityID     │
      │                                         │  - Blackboard   │
      │                                         │  - DeltaTime    │
      │                                         │  - 组件缓存     │
      │                                         └─────────────────┘
      │
      ▼
┌─────────────┐
│   Entity    │
│  (实体)     │
│             │
│ Components: │
│ - Transform │
│ - MoveComp  │
│ - Decision  │
└─────────────┘
```

#### 1.4.3 TreeInstance 数据结构

```go
// TreeInstance 行为树实例
type TreeInstance struct {
    PlanName  string              // 关联的 Plan 名称
    Root      node.IBtNode        // 行为树根节点（共享模板）
    Context   *context.BtContext  // 执行上下文（每实例独立）
    Status    node.BtNodeStatus   // 当前状态
    StartTime int64               // 开始时间（毫秒）
}
```

**关键设计**：
- **模板共享**：多个 Entity 运行同一 Plan 时，共享同一个行为树模板（Root）
- **上下文独立**：每个 TreeInstance 有独立的 BtContext，存储各自的黑板数据
- **状态追踪**：每个实例独立跟踪执行状态

#### 1.4.4 为什么 Executor 是 Resource

在 ECS 架构中，Executor/BtRunner 作为 **Resource** 而非 System 存在，原因如下：

**System vs Resource 的职责区别**：

| 概念 | 职责 | 特点 |
|------|------|------|
| **System** | 执行逻辑（动词） | 有 Update()，每帧执行，无/临时状态 |
| **Resource** | 持有数据（名词） | 无 Update()，持久状态，被多方访问 |

**为什么不能是 System**：

```go
// ❌ 如果 Executor 是 System
type ExecutorSystem struct {
    btRunner *runner.BtRunner  // 持有状态
}

func (s *ExecutorSystem) Update() {
    // ??? Executor 响应事件，不需要每帧执行
}

// 问题：DecisionSystem 如何访问 ExecutorSystem 的 btRunner？
```

**Resource 的优势**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  多个 System/模块需要访问同一个 Executor                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  DecisionSystem ──────┐                                                     │
│     (OnPlanCreated)   │                                                     │
│                       │                                                     │
│  BtTickSystem ────────┼───► ExecutorResource ───► Executor ───► BtRunner   │
│     (每帧 Tick)       │                                                     │
│                       │                                                     │
│  NPC 初始化代码 ──────┘                                                     │
│     (注册行为树)                                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**共享 vs 独立的对比**：

```
❌ 方案A：每个 NPC 独立 Executor（内存浪费、无法统一调度）

   NPC_1 ──► Executor_1 ──► BtRunner_1 ──► trees: {"patrol": ...}
   NPC_2 ──► Executor_2 ──► BtRunner_2 ──► trees: {"patrol": ...}  ← 重复!
   NPC_3 ──► Executor_3 ──► BtRunner_3 ──► trees: {"patrol": ...}  ← 重复!

✅ 方案B：场景级共享 ExecutorResource

   Scene ──► ExecutorResource ──► Executor ──► BtRunner
                                                   │
                                                   ├─ trees (模板共享)
                                                   │   └─ "patrol": 只有一份
                                                   │
                                                   └─ runningTrees (实例独立)
                                                       ├─ NPC_1: TreeInstance
                                                       ├─ NPC_2: TreeInstance
                                                       └─ NPC_3: TreeInstance
```

### 1.5 完整生命周期

#### 1.5.1 生命周期概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          行为树系统完整生命周期                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Phase 1: 场景初始化                                                         │
│  ─────────────────                                                          │
│  ① 创建 ExecutorResource（含 Executor、BtRunner）                           │
│  ② 注册行为树模板到 BtRunner                                                 │
│  ③ 创建 BtTickSystem，关联 BtRunner                                         │
│  ④ 注册系统到场景                                                           │
│                                                                             │
│  Phase 2: NPC 创建                                                          │
│  ────────────────                                                           │
│  ① 获取共享的 ExecutorResource                                              │
│  ② 创建 DecisionComp，传入 Executor                                         │
│  ③ NPC 加入场景                                                             │
│                                                                             │
│  Phase 3: 运行时执行                                                         │
│  ────────────────                                                           │
│  ① GSS Brain 产生 Plan                                                      │
│  ② Executor.OnPlanCreated() 检查并启动行为树                                 │
│  ③ BtTickSystem.Update() 每帧 Tick 所有运行中的树                           │
│                                                                             │
│  Phase 4: 完成与重评估                                                       │
│  ──────────────────                                                         │
│  ① 行为树返回 Success/Failed                                                │
│  ② 触发 DecisionComp.TriggerCommand()                                       │
│  ③ GSS Brain 重新评估 → 产生新 Plan → 回到 Phase 3                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.5.2 Phase 1: 场景初始化详解

```go
// scene_impl.go - 场景初始化代码

func (s *SceneImpl) initSystems() error {
    if cfg.EnableDecision {
        // ① 创建共享执行器资源（包含 Executor 和 BtRunner）
        executorRes := decision.NewExecutorResource(s)
        s.AddResource(executorRes)

        // ② 注册行为树模板（只需注册一次，所有 NPC 共享）
        executor := executorRes.GetExecutor()
        trees.RegisterExampleTrees(executor.RegisterBehaviorTree)
        // 或从 JSON 配置加载
        trees.RegisterTreesFromConfig(executor.RegisterBehaviorTree)

        // ③ 创建决策系统
        decisionSystem := decision.NewDecisionSystem(s)
        s.AddSystem(decisionSystem)

        // ④ 创建并注册行为树 Tick 系统
        btTickSystem := decision.NewBtTickSystem(s, executorRes.GetBtRunner())
        s.AddSystem(btTickSystem)
    }
    return nil
}
```

**初始化流程图**：

```
场景创建
    │
    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 1: 创建 ExecutorResource                                               │
│                                                                             │
│   executorRes := NewExecutorResource(scene)                                 │
│       │                                                                     │
│       └──► 内部创建:                                                        │
│            ├─ Executor (决策执行器)                                         │
│            └─ BtRunner (行为树运行器)                                        │
│                 ├─ trees: map[string]IBtNode{}      // 空的模板表           │
│                 └─ runningTrees: map[uint64]*TreeInstance{}  // 空          │
│                                                                             │
│   scene.AddResource(executorRes)                                            │
└─────────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 2: 注册行为树模板                                                       │
│                                                                             │
│   executor.RegisterBehaviorTree("patrol", patrolTree)                       │
│   executor.RegisterBehaviorTree("idle", idleTree)                           │
│   executor.RegisterBehaviorTree("dialog", dialogTree)                       │
│       │                                                                     │
│       └──► BtRunner.trees 变为:                                             │
│            {                                                                │
│                "patrol": SequenceNode{...},                                │
│                "idle":   SequenceNode{...},                                │
│                "dialog": SelectorNode{...},                                │
│            }                                                                │
└─────────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 3: 创建 BtTickSystem                                                   │
│                                                                             │
│   btTickSystem := NewBtTickSystem(scene, executorRes.GetBtRunner())         │
│       │                                                                     │
│       └──► BtTickSystem 持有 BtRunner 的引用                                │
│            用于每帧遍历 runningTrees 执行 Tick                               │
│                                                                             │
│   scene.AddSystem(btTickSystem)                                             │
└─────────────────────────────────────────────────────────────────────────────┘
    │
    ▼
场景准备就绪，等待 NPC 创建
```

#### 1.5.3 Phase 2: NPC 创建详解

```go
// npc/common.go - NPC 初始化

func InitNpcAIComponentsWithParam(param *InitNpcAIComponentsParam) bool {
    scene := param.Scene
    entity := param.Entity

    // ① 获取共享的 ExecutorResource
    executorRes, ok := common.GetResourceAs[*decision.ExecutorResource](
        scene, common.ResourceType_Executor)
    if !ok {
        // 降级：创建临时 Executor（不推荐，日志警告）
        executor = &decision.Executor{Scene: scene}
    } else {
        executor = executorRes.GetExecutor()
    }

    // ② 创建 DecisionComp，传入共享的 Executor
    decisionComp, err := caidecision.CreateAIDecisionComp(
        executor,      // 共享的执行器
        scene,
        entity.ID(),
        param.GSSTempID,
    )

    // ③ 添加组件到 Entity
    entity.AddComponent(decisionComp)
    return true
}
```

**NPC 创建流程图**：

```
创建 NPC Entity
    │
    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 1: 获取共享 ExecutorResource                                           │
│                                                                             │
│   executorRes := GetResourceAs[*ExecutorResource](scene, ResourceType_Executor)│
│       │                                                                     │
│       └──► 获取场景级共享的执行器资源                                        │
│            所有 NPC 共用同一个 BtRunner                                      │
└─────────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 2: 创建 DecisionComp                                                   │
│                                                                             │
│   decisionComp := CreateAIDecisionComp(executor, scene, entityID, gssTempID)│
│       │                                                                     │
│       ├──► 创建 AI Agent (GSS Brain)                                       │
│       └──► Agent 内部持有 Executor 引用                                     │
│            当产生 Plan 时会调用 executor.OnPlanCreated()                     │
└─────────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 3: 添加组件到 Entity                                                   │
│                                                                             │
│   entity.AddComponent(decisionComp)                                        │
│   entity.AddComponent(moveComp)                                            │
│   entity.AddComponent(transformComp)                                       │
│   ...                                                                       │
└─────────────────────────────────────────────────────────────────────────────┘
    │
    ▼
NPC 准备就绪，等待决策系统 Tick
```

#### 1.5.4 Phase 3: 运行时执行详解

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Scene.Update() 每帧调用                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         ▼                             ▼                             ▼
┌─────────────────┐          ┌─────────────────┐          ┌─────────────────┐
│ DecisionSystem  │          │  BtTickSystem   │          │   MoveSystem    │
│    .Update()    │          │    .Update()    │          │    .Update()    │
└────────┬────────┘          └────────┬────────┘          └─────────────────┘
         │                            │
         │                            │
         ▼                            ▼
┌─────────────────────────┐  ┌─────────────────────────────────────────────────┐
│ 遍历所有 DecisionComp   │  │ 遍历所有 runningTrees                           │
│                         │  │                                                 │
│ for each comp:          │  │ for entityID, instance := range runningTrees:  │
│   comp.Update()         │  │     status := btRunner.Tick(entityID, delta)   │
│     │                   │  │     if status == Success || Failed:            │
│     └─► Agent.Tick()    │  │         onTreeCompleted(entityID)              │
│           │             │  │                                                 │
│           └─► 评估条件   │  └─────────────────────────────────────────────────┘
│               产生 Plan │
│               │         │
│               ▼         │
│   executor.OnPlanCreated(plan)
│               │         │
│     ┌─────────┴────────┐│
│     │                  ││
│     ▼                  ▼│
│  [有行为树]      [无行为树]
│     │                  ││
│  btRunner.Run()  executeTask()
└─────────────────────────┘
```

**OnPlanCreated 详细流程**：

```go
func (e *Executor) OnPlanCreated(req *OnPlanCreatedReq) error {
    // 检查是否有对应的行为树
    if e.btRunner != nil && e.btRunner.HasTree(req.Plan.Name) {
        // 停止之前的行为树（如果有）
        e.btRunner.Stop(uint64(req.EntityID))

        // 启动新的行为树
        if err := e.btRunner.Run(req.Plan.Name, uint64(req.EntityID)); err != nil {
            // 回退到原有逻辑
        } else {
            return nil  // 行为树接管
        }
    }

    // 原有逻辑：遍历任务执行
    for _, task := range req.Plan.Tasks {
        e.executeTask(...)
    }
    return nil
}
```

#### 1.5.5 Phase 4: 完成与重评估详解

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ BtTickSystem.Update() 检测到行为树完成                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   status := btRunner.Tick(entityID, deltaTime)                             │
│                                                                             │
│   if status == BtNodeStatusSuccess || status == BtNodeStatusFailed {       │
│       onTreeCompleted(entityID, planName, status)                          │
│   }                                                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ onTreeCompleted() 处理完成                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   // 1. 从运行器中移除已完成的树                                             │
│   btRunner.Stop(entityID)                                                   │
│                                                                             │
│   // 2. 获取 Entity 和 DecisionComp                                         │
│   entity := scene.GetEntity(entityID)                                       │
│   decisionComp := entity.GetComponent(ComponentType_AIDecision)             │
│                                                                             │
│   // 3. 触发决策重新评估                                                     │
│   decisionComp.TriggerCommand()                                             │
│       │                                                                     │
│       └──► GSS Brain 重新评估条件                                           │
│            │                                                                │
│            └──► 产生新 Plan ───► Executor.OnPlanCreated() ───► 回到 Phase 3│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**完成后的循环**：

```
行为树完成
    │
    ▼
TriggerCommand()
    │
    ▼
GSS Brain 重新评估
    │
    ├─► 条件满足 Plan A → 启动行为树 A
    │
    ├─► 条件满足 Plan B → 启动行为树 B
    │
    └─► 无条件满足 → 等待下一帧继续评估
```

#### 1.5.6 核心数据结构关系

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            核心数据结构关系图                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Scene                                                                      │
│    │                                                                        │
│    ├─► Resources                                                           │
│    │     └─► ExecutorResource                                              │
│    │           └─► Executor                                                │
│    │                 └─► BtRunner                                          │
│    │                       │                                               │
│    │                       ├─► trees: map[string]IBtNode                   │
│    │                       │     │                                         │
│    │                       │     ├─ "patrol" ──► SequenceNode (模板)       │
│    │                       │     ├─ "idle"   ──► SequenceNode (模板)       │
│    │                       │     └─ "dialog" ──► SelectorNode (模板)       │
│    │                       │                                               │
│    │                       └─► runningTrees: map[uint64]*TreeInstance      │
│    │                             │                                         │
│    │                             ├─ 101 ──► TreeInstance                   │
│    │                             │           ├─ PlanName: "patrol"         │
│    │                             │           ├─ Root: (指向 trees["patrol"])│
│    │                             │           ├─ Context: BtContext{101}    │
│    │                             │           └─ Status: Running            │
│    │                             │                                         │
│    │                             └─ 102 ──► TreeInstance                   │
│    │                                         ├─ PlanName: "idle"           │
│    │                                         ├─ Root: (指向 trees["idle"]) │
│    │                                         ├─ Context: BtContext{102}    │
│    │                                         └─ Status: Running            │
│    │                                                                        │
│    ├─► Systems                                                             │
│    │     ├─► DecisionSystem                                                │
│    │     │     └─► 遍历 DecisionComp，触发 Executor.OnPlanCreated          │
│    │     │                                                                  │
│    │     └─► BtTickSystem                                                  │
│    │           └─► btRunner (引用)                                         │
│    │                 └─► 遍历 runningTrees，执行 Tick                      │
│    │                                                                        │
│    └─► Entities                                                            │
│          │                                                                  │
│          ├─► Entity 101                                                    │
│          │     ├─► DecisionComp ──► Agent ──► Executor (引用)              │
│          │     ├─► NpcMoveComp                                             │
│          │     └─► Transform                                               │
│          │                                                                  │
│          └─► Entity 102                                                    │
│                ├─► DecisionComp ──► Agent ──► Executor (引用)              │
│                ├─► NpcMoveComp                                             │
│                └─► Transform                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.5.7 关键设计总结

| 设计点 | 决策 | 原因 |
|--------|------|------|
| **Executor 作为 Resource** | 场景级共享 | 多个 System/NPC 需要访问，避免重复创建 |
| **行为树模板共享** | trees 只存一份 | 节省内存，所有 NPC 共用模板 |
| **上下文实例独立** | 每个 TreeInstance 有独立 BtContext | 黑板数据、状态各自独立 |
| **BtTickSystem 独立** | 不在 DecisionSystem 中 Tick | 职责分离，解耦合 |
| **完成后触发重评估** | TriggerCommand | 避免 NPC "发呆"，自动进入下一行为 |
| **向后兼容** | HasTree 检查 | 无行为树的 Plan 使用原有 Task 逻辑 |

---

## 二、核心原理

### 2.0 行为树的树状结构

#### 2.0.1 根节点类型

根节点可以是**任何实现了 IBtNode 接口的节点**，但实践中有合理的选择：

**根节点类型分析**：

| 节点类型 | 可作为根? | 实用性 | 说明 |
|---------|----------|--------|------|
| **Sequence** | ✅ | ⭐⭐⭐ | 最常用，顺序执行任务链 |
| **Selector** | ✅ | ⭐⭐⭐ | 最常用，优先级行为选择 |
| **Repeat** | ✅ | ⭐⭐ | 循环执行子树（如无限巡逻） |
| **Inverter** | ✅ | ⭐ | 少见，反转子树结果 |
| **叶子节点** | ✅ | ❌ | 技术可行但无意义（退化为单动作） |

**为什么这样设计**：

1. **接口一致性**：所有节点实现相同的 `IBtNode` 接口，BtRunner 只需调用统一方法：
```go
// BtRunner 不关心根节点是什么类型
func (r *BtRunner) Run(planName string, entityID uint64) error {
    root := r.trees[planName]  // IBtNode 接口
    root.OnEnter(ctx)          // 统一调用
}
```

2. **灵活性**：不限制根节点类型，让设计者根据需求自由选择

**常见根节点模式**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  模式 1: Sequence 作为根（顺序任务）                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│           ┌───────────────┐                                                 │
│           │   Sequence    │  ← 必须全部成功                                  │
│           └───────┬───────┘                                                 │
│                   │                                                         │
│       ┌───────────┼───────────┐                                            │
│       ▼           ▼           ▼                                            │
│   ┌───────┐   ┌───────┐   ┌───────┐                                       │
│   │Move A │   │ Wait  │   │Move B │                                       │
│   └───────┘   └───────┘   └───────┘                                       │
│                                                                             │
│   用途：完成一系列顺序任务                                                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  模式 2: Selector 作为根（优先级行为）                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│           ┌───────────────┐                                                 │
│           │   Selector    │  ← 一个成功即可                                  │
│           └───────┬───────┘                                                 │
│                   │                                                         │
│       ┌───────────┼───────────┐                                            │
│       ▼           ▼           ▼                                            │
│   ┌───────┐   ┌───────┐   ┌───────┐                                       │
│   │ 攻击  │   │ 追逐  │   │ 巡逻  │                                       │
│   │优先级1│   │优先级2│   │优先级3│                                       │
│   └───────┘   └───────┘   └───────┘                                       │
│                                                                             │
│   用途：多个互斥行为，按优先级选择执行                                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  模式 3: Repeat 作为根（循环行为）                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│           ┌───────────────┐                                                 │
│           │    Repeat     │  ← 永久循环                                     │
│           │  (forever)    │                                                 │
│           └───────┬───────┘                                                 │
│                   │                                                         │
│                   ▼                                                         │
│           ┌───────────────┐                                                 │
│           │   Sequence    │                                                 │
│           └───────┬───────┘                                                 │
│                   │                                                         │
│       ┌───────────┼───────────┐                                            │
│       ▼           ▼           ▼                                            │
│   ┌───────┐   ┌───────┐   ┌───────┐                                       │
│   │Move A │   │ Wait  │   │Move B │                                       │
│   └───────┘   └───────┘   └───────┘                                       │
│                                                                             │
│   用途：永久循环执行的行为（如持续巡逻直到被打断）                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**根节点选择指南**：

| 场景 | 推荐根节点 | 原因 |
|------|-----------|------|
| NPC 需要完成一系列任务 | Sequence | 顺序执行，全部成功才算完成 |
| NPC 有多种互斥行为 | Selector | 按优先级尝试，找到能执行的 |
| NPC 需要永久循环某行为 | Repeat | 子树完成后自动重新开始 |
| 复杂混合行为 | 根据最外层逻辑 | 先分析最顶层的行为模式 |

#### 2.0.2 典型行为树结构图

以一个"智能 NPC 行为"为例（使用 Selector 实现优先级行为）：

```
                                    ┌─────────────┐
                                    │   Root      │
                                    │ (Selector)  │  ← 优先级行为选择 Selector
                                    └──────┬──────┘
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              │                            │                            │
              ▼                            ▼                            ▼
     ┌─────────────────┐          ┌─────────────────┐          ┌─────────────────┐
     │    Sequence     │          │    Sequence     │          │    Sequence     │
     │   (处理对话)     │          │   (处理追逐)    │          │   (默认巡逻)     │
     └────────┬────────┘          └────────┬────────┘          └────────┬────────┘
              │                            │                            │
     ┌────────┼────────┐          ┌────────┼────────┐          ┌────────┼────────┐
     │        │        │          │        │        │          │        │        │
     ▼        ▼        ▼          ▼        ▼        ▼          ▼        ▼        ▼
┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌─────────┐
│ Check   ││ Stop    ││ Set     ││ Check   ││ Run To  ││ Attack  ││ MoveTo  ││ Wait    ││ MoveTo  │
│ Dialog  ││ Move    ││ State   ││ Enemy   ││ Enemy   ││         ││ PointA  ││ 3000ms  ││ PointB  │
│ Request ││         ││ Dialog  ││ Visible ││         ││         ││         ││         ││         │
└─────────┘└─────────┘└─────────┘└─────────┘└─────────┘└─────────┘└─────────┘└─────────┘└─────────┘
  [条件]     [动作]     [动作]     [条件]     [动作]     [动作]     [动作]     [动作]     [动作]
```

**图例说明**：
```
┌─────────────┐
│  Selector   │  ← 控制节点：选择器（尝试每个子节点直到成功）
└─────────────┘

┌─────────────┐
│  Sequence   │  ← 控制节点：顺序器（依次执行所有子节点）
└─────────────┘

┌─────────────┐
│  Check XXX  │  ← 叶子节点：条件检查（立即返回 Success/Failed）
└─────────────┘

┌─────────────┐
│  MoveTo     │  ← 叶子节点：动作（可能返回 Running，需要多帧执行）
└─────────────┘
```

#### 2.0.3 Sequence 作为根节点的示例

以"简单巡逻任务"为例（使用 Sequence 实现顺序任务）：

```
                    ┌───────────────────┐
                    │     Sequence      │  ← 顺序任务选择 Sequence
                    │      (Root)       │
                    └─────────┬─────────┘
                              │
    ┌─────────────────────────┼─────────────────────────┐
    │           │             │             │           │
    ▼           ▼             ▼             ▼           ▼
┌───────┐ ┌─────────┐   ┌─────────┐   ┌─────────┐ ┌───────┐
│  Log  │ │ MoveTo  │   │  Wait   │   │ MoveTo  │ │  Log  │
│"开始" │ │ PointA  │   │  3000   │   │ PointB  │ │"完成" │
└───────┘ └─────────┘   └─────────┘   └─────────┘ └───────┘
 [同步]     [异步]        [异步]        [异步]     [同步]

执行顺序：Log → MoveTo(A) → Wait → MoveTo(B) → Log
必须按顺序全部成功，任一失败则整体失败
```

**根节点选择总结**：
| 场景 | 根节点 | 原因 |
|------|--------|------|
| NPC 有多种互斥行为，按优先级选择 | Selector | 找到一个能执行的就行 |
| NPC 需要完成一系列任务 | Sequence | 必须按顺序全部完成 |
| 复杂行为（混合） | 任意 | 根据最外层逻辑决定 |

#### 2.0.4 带分支的巡逻行为树

```
                    ┌───────────────────┐
                    │     Sequence      │  ← 根节点：顺序执行
                    │      (Root)       │
                    └─────────┬─────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│     Log       │     │   Selector    │     │     Log       │
│ "开始巡逻"    │     │  (选择目标)    │     │  "巡逻完成"   │
└───────────────┘     └───────┬───────┘     └───────────────┘
   [立即完成]                  │                [立即完成]
                    ┌─────────┴─────────┐
                    │                   │
                    ▼                   ▼
            ┌───────────────┐   ┌───────────────┐
            │   Sequence    │   │   Sequence    │
            │   (路线A)     │   │   (路线B)     │
            └───────┬───────┘   └───────┬───────┘
                    │                   │
            ┌───────┼───────┐   ┌───────┼───────┐
            │       │       │   │       │       │
            ▼       ▼       ▼   ▼       ▼       ▼
         ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
         │Move │ │Wait │ │Move │ │Move │ │Wait │ │Move │
         │To A1│ │2000 │ │To A2│ │To B1│ │3000 │ │To B2│
         └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘
          [异步]  [异步]  [异步]  [异步]  [异步]  [异步]
```

#### 2.0.5 节点层级关系

```
层级 0 (Root):       [Sequence/Selector]
                            │
                     ┌──────┼──────┐
                     │      │      │
层级 1 (Branch):    [A]    [B]    [C]     ← 分支节点
                     │      │      │
                    ┌┴┐   ┌─┼─┐   ┌┴┐
层级 2 (Leaf):     [a1][a2][b1][b2][b3][c1]  ← 叶子节点

执行规则：
- 深度优先遍历
- 从左到右执行
- 父节点控制子节点的执行逻辑
```

#### 2.0.6 树结构的遍历执行流程

**Sequence 节点的执行流程**：

```
Sequence 节点执行：依次执行子节点，全部成功才成功

         ┌─────────────┐
         │  Sequence   │ ← 当前执行
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌───────┐   ┌───────┐   ┌───────┐
│ Child1│   │ Child2│   │ Child3│
│  [1]  │   │  [2]  │   │  [3]  │
└───────┘   └───────┘   └───────┘

执行顺序：1 → 2 → 3

Step 1: 执行 Child1
        ├─ Success → 继续执行 Child2
        ├─ Running → Sequence 返回 Running，下一帧继续
        └─ Failed  → Sequence 立即返回 Failed（不执行后续）

Step 2: 执行 Child2
        ├─ Success → 继续执行 Child3
        ├─ Running → Sequence 返回 Running
        └─ Failed  → Sequence 返回 Failed

Step 3: 执行 Child3
        ├─ Success → Sequence 返回 Success（全部完成）
        ├─ Running → Sequence 返回 Running
        └─ Failed  → Sequence 返回 Failed
```

**Selector 节点的执行流程**：

```
Selector 节点执行：尝试子节点，一个成功就成功

         ┌─────────────┐
         │  Selector   │ ← 当前执行
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌───────┐   ┌───────┐   ┌───────┐
│ Child1│   │ Child2│   │ Child3│
│  [1]  │   │  [2]  │   │  [3]  │
└───────┘   └───────┘   └───────┘

执行顺序：1 → (2) → (3)  # 括号表示可能不执行

Step 1: 执行 Child1
        ├─ Success → Selector 立即返回 Success（不执行后续）
        ├─ Running → Selector 返回 Running，下一帧继续
        └─ Failed  → 继续尝试 Child2

Step 2: 执行 Child2（仅当 Child1 失败时）
        ├─ Success → Selector 返回 Success
        ├─ Running → Selector 返回 Running
        └─ Failed  → 继续尝试 Child3

Step 3: 执行 Child3（仅当 Child1、Child2 都失败时）
        ├─ Success → Selector 返回 Success
        ├─ Running → Selector 返回 Running
        └─ Failed  → Selector 返回 Failed（全部失败）
```

#### 2.0.7 完整执行示例（多帧）

以下展示一个简单行为树的逐帧执行过程：

```
行为树结构：
         ┌─────────────┐
         │  Sequence   │
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌───────┐   ┌───────┐   ┌───────┐
│ Check │   │ MoveTo│   │  Log  │
│ Cond  │   │ Point │   │ "Done"│
└───────┘   └───────┘   └───────┘
  [同步]      [异步]      [同步]

═══════════════════════════════════════════════════════════════════
Frame 1: 第一帧
═══════════════════════════════════════════════════════════════════

         ┌─────────────┐
         │  Sequence   │ ← OnEnter() 返回 Running
         │  [Running]  │
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌───────┐   ┌───────┐   ┌───────┐
│ Check │   │ MoveTo│   │  Log  │
│►[Exec]│   │ [Init]│   │ [Init]│  ← ► 表示当前执行
└───────┘   └───────┘   └───────┘
    │
    └─► OnEnter() → Success (条件满足)
        OnExit()

结果: Check 成功，继续 MoveTo

═══════════════════════════════════════════════════════════════════
Frame 1 (继续): 同一帧内
═══════════════════════════════════════════════════════════════════

         ┌─────────────┐
         │  Sequence   │
         │  [Running]  │
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌───────┐   ┌───────┐   ┌───────┐
│ Check │   │ MoveTo│   │  Log  │
│[Done] │   │►[Exec]│   │ [Init]│
└───────┘   └───────┘   └───────┘
                │
                └─► OnEnter() → Running (开始移动)

结果: Sequence 返回 Running，等待下一帧

═══════════════════════════════════════════════════════════════════
Frame 2~N: 移动中
═══════════════════════════════════════════════════════════════════

         ┌─────────────┐
         │  Sequence   │
         │  [Running]  │ ← OnTick()
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌───────┐   ┌───────┐   ┌───────┐
│ Check │   │ MoveTo│   │  Log  │
│[Done] │   │►[Run] │   │ [Init]│
└───────┘   └───────┘   └───────┘
                │
                └─► OnTick() → Running (仍在移动...)

结果: 继续 Running

═══════════════════════════════════════════════════════════════════
Frame N+1: 移动完成
═══════════════════════════════════════════════════════════════════

         ┌─────────────┐
         │  Sequence   │
         │  [Running]  │
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌───────┐   ┌───────┐   ┌───────┐
│ Check │   │ MoveTo│   │  Log  │
│[Done] │   │►[Exec]│   │ [Init]│
└───────┘   └───────┘   └───────┘
                │
                └─► OnTick() → Success (到达目的地)
                    OnExit()

结果: MoveTo 成功，继续 Log

═══════════════════════════════════════════════════════════════════
Frame N+1 (继续): 同一帧内
═══════════════════════════════════════════════════════════════════

         ┌─────────────┐
         │  Sequence   │
         │  [Success]  │ ← 所有子节点成功
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌───────┐   ┌───────┐   ┌───────┐
│ Check │   │ MoveTo│   │  Log  │
│[Done] │   │[Done] │   │►[Exec]│
└───────┘   └───────┘   └───────┘
                            │
                            └─► OnEnter() → Success (输出日志)
                                OnExit()

结果: Sequence 返回 Success，行为树执行完毕

═══════════════════════════════════════════════════════════════════
Frame N+2: 完成处理
═══════════════════════════════════════════════════════════════════

BtTickSystem 检测到 Status == Success
    │
    └─► onTreeCompleted()
        └─► DecisionComp.TriggerCommand() # 触发决策重评估
```

#### 2.0.8 嵌套结构执行

复杂行为树中的嵌套 Sequence/Selector 执行：

```
         ┌─────────────┐
         │  Selector   │  ← 根节点
         │    [S0]     │
         └──────┬──────┘
                │
    ┌───────────┴───────────┐
    │                       │
    ▼                       ▼
┌─────────────┐       ┌─────────────┐
│  Sequence   │       │  Sequence   │
│    [S1]     │       │    [S2]     │
└──────┬──────┘       └──────┬──────┘
       │                     │
  ┌────┼────┐           ┌────┼────┐
  │    │    │           │    │    │
  ▼    ▼    ▼           ▼    ▼    ▼
┌───┐┌───┐┌───┐       ┌───┐┌───┐┌───┐
│ A ││ B ││ C │       │ D ││ E ││ F │
└───┘└───┘└───┘       └───┘└───┘└───┘

执行流程（假设 A 成功，B 失败）：

1. S0 (Selector) OnEnter
2. S1 (Sequence) OnEnter
3. A OnEnter → Success → OnExit
4. B OnEnter → Failed → OnExit
5. S1 返回 Failed（B 失败导致 Sequence 失败）
6. S1 OnExit
7. S0 继续尝试下一个子节点 S2
8. S2 (Sequence) OnEnter
9. D OnEnter → Success → OnExit
10. E OnEnter → Running
11. S2 返回 Running
12. S0 返回 Running
... (后续帧继续 Tick E)
```

#### 2.0.9 节点执行函数详解

每个行为树节点在执行时，会依次调用以下函数。这些函数定义在 `IBtNode` 接口中：

**IBtNode 接口核心函数**：

| 函数名 | 签名 | 调用时机 | 返回值 | 作用 |
|--------|------|----------|--------|------|
| `OnEnter` | `OnEnter(ctx *BtContext) BtNodeStatus` | 节点首次进入 | 状态 | 初始化节点，分配资源 |
| `OnTick` | `OnTick(ctx *BtContext) BtNodeStatus` | 每帧执行 | 状态 | 执行节点核心逻辑 |
| `OnExit` | `OnExit(ctx *BtContext)` | 节点退出时 | 无 | 清理资源，收尾工作 |
| `Status` | `Status() BtNodeStatus` | 任意时刻 | 状态 | 查询当前状态 |
| `Reset` | `Reset()` | 重置时 | 无 | 重置为初始状态 |

**BtRunner.tickNode 执行流程**：

```go
// runner/runner.go 中的 tickNode 函数
func (r *BtRunner) tickNode(n node.IBtNode, ctx *context.BtContext) node.BtNodeStatus {
    // 1. 检查节点状态
    if n.Status() == node.BtNodeStatusInit {
        // 2. 首次进入，调用 OnEnter
        status := n.OnEnter(ctx)
        if status != node.BtNodeStatusRunning {
            // OnEnter 直接返回结果，调用 OnExit
            n.OnExit(ctx)
            return status
        }
    }

    // 3. 调用 OnTick（每帧执行）
    status := n.OnTick(ctx)

    // 4. 如果完成，调用 OnExit
    if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
        n.OnExit(ctx)
    }

    return status
}
```

**执行流程图**：

```
tickNode(node, ctx)
        │
        ├── node.Status() == Init?
        │       │
        │       ├── Yes ───► node.OnEnter(ctx)
        │       │                  │
        │       │                  ├── 返回 Running ───► 继续执行 OnTick
        │       │                  │
        │       │                  └── 返回 Success/Failed ───► node.OnExit(ctx) ───► 返回
        │       │
        │       └── No ───► 直接执行 OnTick
        │
        ├── node.OnTick(ctx)
        │       │
        │       └── 返回 status
        │
        └── status == Success/Failed?
                │
                ├── Yes ───► node.OnExit(ctx) ───► 返回 status
                │
                └── No (Running) ───► 返回 status
```

**完整执行时序示例（MoveTo 节点）**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  MoveTo 节点执行时序（移动到目标点）                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Frame 1:                                                                   │
│    tickNode(moveTo, ctx)                                                    │
│      ├── moveTo.Status()     → Init                                        │
│      ├── moveTo.OnEnter(ctx) → 设置目标点，启动移动 → 返回 Running          │
│      ├── moveTo.OnTick(ctx)  → 检查是否到达 → 返回 Running                  │
│      └── 返回 Running                                                       │
│                                                                             │
│  Frame 2:                                                                   │
│    tickNode(moveTo, ctx)                                                    │
│      ├── moveTo.Status()     → Running                                     │
│      ├── moveTo.OnTick(ctx)  → 检查是否到达 → 返回 Running                  │
│      └── 返回 Running                                                       │
│                                                                             │
│  ...（多帧持续移动）...                                                       │
│                                                                             │
│  Frame N:                                                                   │
│    tickNode(moveTo, ctx)                                                    │
│      ├── moveTo.Status()     → Running                                     │
│      ├── moveTo.OnTick(ctx)  → 检查是否到达 → 已到达 → 返回 Success         │
│      ├── moveTo.OnExit(ctx)  → 清理状态                                    │
│      └── 返回 Success                                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**不同节点类型的函数实现差异**：

| 节点类型 | OnEnter | OnTick | OnExit |
|---------|---------|--------|--------|
| **Sequence** | 初始化子节点索引=0 | 遍历执行子节点，全成功则成功 | 停止运行中的子节点 |
| **Selector** | 初始化子节点索引=0 | 遍历执行子节点，一成功则成功 | 停止运行中的子节点 |
| **Repeat** | 初始化循环计数=0 | 执行子节点，完成后重置重试 | 停止子节点 |
| **MoveTo** | 设置目标点，启动移动 | 检查是否到达目标 | 停止移动 |
| **Wait** | 记录开始时间 | 检查是否超时 | 无操作 |
| **Log** | 输出日志，返回 Success | 返回 Success | 无操作 |

**关键函数调用链**：

```
BtTickSystem.Update()
    │
    └── btRunner.Tick(entityID, deltaTime)
            │
            └── tickNode(root, ctx)
                    │
                    ├── Status()          // 查询状态
                    ├── OnEnter(ctx)      // 首次进入
                    ├── OnTick(ctx)       // 每帧执行
                    │       │
                    │       └── (控制节点) tickNode(child, ctx)  // 递归执行子节点
                    │
                    └── OnExit(ctx)       // 完成时退出
```

### 2.1 节点类型

行为树由三类节点组成：

| 类型 | 说明 | 示例 |
|------|------|------|
| **控制节点** | 控制子节点的执行流程 | Sequence, Selector |
| **装饰节点** | 修改单个子节点的行为 | Inverter, Repeat |
| **叶子节点** | 执行具体的行为或条件检查 | MoveTo, Wait, CheckCondition |

### 2.2 节点状态

每个节点在执行时返回以下状态之一：

```go
const (
    BtNodeStatusInit    // 初始状态，尚未执行
    BtNodeStatusRunning // 运行中，需要继续 Tick
    BtNodeStatusSuccess // 执行成功
    BtNodeStatusFailed  // 执行失败
)
```

### 2.3 节点生命周期

```
┌─────────┐     首次Tick      ┌─────────┐
│  Init   │ ───────────────→ │ OnEnter │
└─────────┘                   └────┬────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
               [Success]      [Running]      [Failed]
                    │              │              │
                    │              ▼              │
                    │         ┌────────┐         │
                    │         │ OnTick │←────┐   │
                    │         └────┬───┘     │   │
                    │              │         │   │
                    │    ┌────────┬┴────────┐│   │
                    │    ▼        ▼         ▼│   │
                    │ [Success][Running][Failed] │
                    │    │        │         │    │
                    │    │        └─────────┘    │
                    ▼    ▼                       ▼
               ┌─────────────────────────────────────┐
               │              OnExit                 │
               └─────────────────────────────────────┘
```

**生命周期方法**：
- `OnEnter(ctx)`: 节点进入时调用，执行初始化
- `OnTick(ctx)`: 每帧调用，执行主逻辑
- `OnExit(ctx)`: 节点退出时调用，执行清理

### 2.4 控制节点工作原理

#### Sequence（顺序节点）
按顺序执行所有子节点，**全部成功才成功，任一失败则失败**。

```
Sequence
├─ [子节点1] → Success → 继续
├─ [子节点2] → Success → 继续
├─ [子节点3] → Failed  → 整体 Failed
└─ [子节点4] → 不执行
```

#### Selector（选择节点）
按顺序尝试执行子节点，**一个成功就成功，全部失败则失败**。

```
Selector
├─ [子节点1] → Failed  → 尝试下一个
├─ [子节点2] → Success → 整体 Success
├─ [子节点3] → 不执行
└─ [子节点4] → 不执行
```

### 2.5 黑板（Blackboard）

黑板是节点间共享数据的机制，存储在 BtContext 中：

```go
// 设置数据
ctx.SetBlackboard("target_point", &transform.Vec3{X: 100, Y: 0, Z: 200})

// 读取数据
if target, ok := ctx.GetBlackboard("target_point"); ok {
    // 使用 target
}
```

**常用场景**：
- 存储目标位置
- 传递中间计算结果
- 存储状态标志

---

## 三、代码结构

### 3.1 目录结构

```
servers/scene_server/internal/common/ai/bt/
├── context/
│   └── context.go       # BtContext - 执行上下文
├── node/
│   └── interface.go     # IBtNode 接口 + BaseNode 基类
├── runner/
│   └── runner.go        # BtRunner - 行为树运行器
├── nodes/               # 节点实现
│   ├── base.go          # BaseLeafNode 叶子节点基类
│   ├── sequence.go      # SequenceNode 顺序节点
│   ├── selector.go      # SelectorNode 选择节点
│   ├── move_to.go       # MoveToNode 移动节点
│   ├── wait.go          # WaitNode 等待节点
│   ├── stop_move.go     # StopMoveNode 停止移动
│   ├── set_feature.go   # SetFeatureNode 设置特征
│   ├── check_condition.go # CheckConditionNode 条件检查
│   ├── log.go           # LogNode 日志输出
│   ├── look_at.go       # LookAtNode 面向目标
│   ├── set_blackboard.go # SetBlackboardNode 设置黑板
│   └── factory.go       # NodeFactory 节点工厂
├── config/              # 配置加载
│   ├── types.go         # 配置类型定义
│   └── loader.go        # 配置加载器
└── trees/               # 行为树定义
    ├── example_trees.go # 代码定义的示例
    ├── patrol.json      # JSON 配置示例
    └── conditional.json # JSON 配置示例

servers/scene_server/internal/ecs/system/decision/
├── executor.go          # Executor - 集成行为树
└── bt_tick_system.go    # BtTickSystem - 帧更新系统
```

### 3.2 核心接口

```go
// IBtNode 行为树节点接口
type IBtNode interface {
    OnEnter(ctx *BtContext) BtNodeStatus  // 进入节点
    OnTick(ctx *BtContext) BtNodeStatus   // 每帧执行
    OnExit(ctx *BtContext)                // 退出节点
    Status() BtNodeStatus                 // 获取状态
    Reset()                               // 重置状态
    Children() []IBtNode                  // 获取子节点
    NodeType() BtNodeType                 // 获取类型
}
```

```go
// BtContext 执行上下文
type BtContext struct {
    Scene      common.Scene      // 场景引用
    EntityID   uint64            // 实体ID
    Blackboard map[string]any    // 黑板数据
    DeltaTime  float32           // 帧间隔

    // 组件缓存（懒加载）
    moveComp      *cnpc.NpcMoveComp
    decisionComp  *caidecision.DecisionComp
    transformComp *ctrans.Transform
}
```

---

## 四、使用教程

### 4.1 代码方式定义行为树

```go
import (
    "mp/servers/scene_server/internal/common/ai/bt/nodes"
)

// 创建一个简单的巡逻行为树
func createPatrolTree() node.IBtNode {
    return nodes.NewSequenceNode(
        // 记录日志
        nodes.NewLogNode("开始巡逻"),
        // 移动到点A（从黑板读取）
        nodes.NewMoveToNode("patrol_point_a"),
        // 等待2秒
        nodes.NewWaitNode(2000),
        // 移动到点B
        nodes.NewMoveToNode("patrol_point_b"),
        // 等待2秒
        nodes.NewWaitNode(2000),
        // 记录日志
        nodes.NewLogNode("巡逻完成"),
    )
}

// 注册行为树
func initBehaviorTrees(executor *Executor) {
    executor.RegisterBehaviorTree("patrol", createPatrolTree())
}
```

### 4.2 JSON 配置方式定义行为树

**patrol.json**:
```json
{
  "name": "patrol",
  "description": "NPC 巡逻行为",
  "blackboard": {
    "patrol_point_a": { "type": "vec3", "value": [100, 0, 200] },
    "patrol_point_b": { "type": "vec3", "value": [150, 0, 250] },
    "wait_time": { "type": "int64", "value": 2000 }
  },
  "root": {
    "type": "Sequence",
    "children": [
      { "type": "Log", "params": { "message": "开始巡逻" } },
      { "type": "MoveTo", "params": { "target_key": "patrol_point_a" } },
      { "type": "Wait", "params": { "duration_key": "wait_time" } },
      { "type": "MoveTo", "params": { "target_key": "patrol_point_b" } },
      { "type": "Wait", "params": { "duration_ms": 2000 } },
      { "type": "Log", "params": { "message": "巡逻完成" } }
    ]
  }
}
```

**加载配置**:
```go
import "mp/servers/scene_server/internal/common/ai/bt/trees"

// 方式1: 自动加载嵌入的 JSON 配置
count, err := trees.RegisterTreesFromConfig(executor.RegisterBehaviorTree)

// 方式2: 从文件加载
cfg, root, err := trees.LoadTreeFromFile("path/to/tree.json")
executor.RegisterBehaviorTree(cfg.Name, root)
```

### 4.3 节点参数说明

#### MoveTo - 移动到目标点
```json
{
  "type": "MoveTo",
  "params": {
    "target_key": "blackboard_key",  // 从黑板读取目标点
    // 或
    "target": [100, 0, 200],         // 直接指定坐标
    "speed": 5.0                     // 可选：移动速度
  }
}
```

#### Wait - 等待
```json
{
  "type": "Wait",
  "params": {
    "duration_key": "wait_time",  // 从黑板读取等待时间
    // 或
    "duration_ms": 3000           // 直接指定毫秒数
  }
}
```

#### CheckCondition - 条件检查
```json
{
  "type": "CheckCondition",
  "params": {
    "feature_key": "feature_dialog_req",  // 黑板 key
    "operator": "==",                     // 运算符: ==, !=, >, <, >=, <=
    "value": true                         // 比较值
  }
}
```

#### SetFeature - 设置决策特征
```json
{
  "type": "SetFeature",
  "params": {
    "feature_key": "feature_state",
    "feature_value": "idle",
    "ttl_ms": 0                    // 可选：过期时间
  }
}
```

#### Log - 输出日志
```json
{
  "type": "Log",
  "params": {
    "message": "日志内容",
    "level": "info"               // 可选：debug, info, warn, error
  }
}
```

### 4.4 复杂行为示例

**条件分支（对话检测）**:
```go
tree := nodes.NewSelectorNode(
    // 分支1: 如果有对话请求
    nodes.NewSequenceNode(
        nodes.NewCheckConditionNode("feature_dialog_req", "==", true),
        nodes.NewStopMoveNode(),
        nodes.NewLogNode("开始对话"),
        nodes.NewSetFeatureNode("feature_state", "dialog", 0),
    ),
    // 分支2: 否则继续巡逻
    nodes.NewSequenceNode(
        nodes.NewLogNode("继续巡逻"),
        nodes.NewMoveToNode("next_patrol_point"),
    ),
)
```

### 4.5 添加自定义节点

**1. 创建节点结构**:
```go
// nodes/my_custom_node.go
package nodes

type MyCustomNode struct {
    BaseLeafNode
    // 自定义字段
    MyParam string
}

func NewMyCustomNode(param string) *MyCustomNode {
    return &MyCustomNode{
        BaseLeafNode: NewBaseLeafNode(),
        MyParam:      param,
    }
}
```

**2. 实现生命周期方法**:
```go
func (n *MyCustomNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 初始化逻辑
    // 返回 Running 表示需要继续 Tick
    // 返回 Success/Failed 表示立即完成
    return node.BtNodeStatusRunning
}

func (n *MyCustomNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    // 每帧执行的逻辑
    if /* 完成条件 */ {
        return node.BtNodeStatusSuccess
    }
    return node.BtNodeStatusRunning
}

func (n *MyCustomNode) OnExit(ctx *context.BtContext) {
    // 清理逻辑（被打断或完成时调用）
}
```

**3. 注册到工厂（支持 JSON 配置）**:
```go
// nodes/factory.go
func NewNodeFactory() *NodeFactory {
    f := &NodeFactory{...}
    // 添加注册
    f.Register("MyCustom", createMyCustomNode)
    return f
}

func createMyCustomNode(cfg *config.NodeConfig) (node.IBtNode, error) {
    param, _ := cfg.GetParamString("my_param")
    return NewMyCustomNode(param), nil
}
```

---

## 五、执行流程

### 5.1 整体流程

```
┌─────────────────────────────────────────────────────────────────┐
│                         GSS Brain 决策                          │
│                              │                                  │
│                    产生 Plan "patrol"                           │
│                              ▼                                  │
├─────────────────────────────────────────────────────────────────┤
│                    Executor.OnPlanCreated()                     │
│                              │                                  │
│            ┌─────────────────┴─────────────────┐               │
│            │ btRunner.HasTree("patrol")?       │               │
│            │         YES                       │               │
│            ▼                                   │               │
│    btRunner.Run("patrol", entityID)            │               │
│            │                                   │               │
│            ▼                                   │               │
│    创建 TreeInstance                           │               │
│    初始化 BtContext                            │               │
│    调用 root.OnEnter()                         │               │
├─────────────────────────────────────────────────────────────────┤
│                    BtTickSystem.Update()                        │
│                         每帧调用                                 │
│                              │                                  │
│            遍历 runningTrees                                    │
│                              │                                  │
│            btRunner.Tick(entityID, deltaTime)                   │
│                              │                                  │
│            调用 root.OnTick()                                   │
│                              │                                  │
│            ┌─────────────────┴─────────────────┐               │
│            │                                   │               │
│        [Running]                        [Success/Failed]       │
│            │                                   │               │
│         继续等待                          调用 OnExit()          │
│         下一帧                           触发决策重评估          │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Sequence 节点执行示例

假设有以下行为树：
```
Sequence
├─ MoveTo(A)     # 异步节点
├─ Wait(2000)    # 异步节点
└─ Log("Done")   # 同步节点
```

**执行时间线**：
```
Frame 1:
  Sequence.OnEnter() → Running
  Sequence.OnTick()
    MoveTo.OnEnter() → Running (开始移动)

Frame 2~N:
  Sequence.OnTick()
    MoveTo.OnTick() → Running (移动中...)

Frame N+1:
  Sequence.OnTick()
    MoveTo.OnTick() → Success (到达目的地)
    MoveTo.OnExit()
    Wait.OnEnter() → Running (开始等待)

Frame N+2~M:
  Sequence.OnTick()
    Wait.OnTick() → Running (等待中...)

Frame M+1:
  Sequence.OnTick()
    Wait.OnTick() → Success (等待完成)
    Wait.OnExit()
    Log.OnEnter() → Success (立即完成)
    Log.OnExit()
  Sequence → Success (所有子节点成功)

Frame M+2:
  BtTickSystem 检测到树完成
  触发 DecisionComp.TriggerCommand() 重新评估
```

### 5.3 场景帧循环中的执行流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Scene.Update() 每帧调用                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         ▼                             ▼                             ▼
┌─────────────────┐          ┌─────────────────┐          ┌─────────────────┐
│ DecisionSystem  │          │  BtTickSystem   │          │  MoveSystem     │
│    .Update()    │          │    .Update()    │          │    .Update()    │
└────────┬────────┘          └────────┬────────┘          └────────┬────────┘
         │                            │                            │
         │ 评估条件                    │ 遍历 runningTrees          │ 处理移动
         │ 产生 Plan                   │                            │
         ▼                            ▼                            ▼
┌─────────────────┐          ┌─────────────────────────────────────────────┐
│ 如果产生新 Plan │          │  for entityID, instance := range trees:    │
│ Executor.       │          │      status := btRunner.Tick(entityID)     │
│ OnPlanCreated() │          │      if status == Success/Failed:          │
└────────┬────────┘          │          onTreeCompleted(entityID)         │
         │                   └─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  if btRunner.HasTree(plan.Name):   │
│      btRunner.Stop(entityID)       │  ← 停止旧的行为树
│      btRunner.Run(plan.Name, ...)  │  ← 启动新的行为树
│  else:                             │
│      executeTask(...)              │  ← 原有硬编码逻辑
└─────────────────────────────────────┘
```

### 5.4 多 NPC 并行执行

```
Scene 中有 3 个 NPC，各自运行不同的行为树：

┌─────────────────────────────────────────────────────────────────────────────┐
│                              BtTickSystem.Update()                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
                    ▼                  ▼                  ▼
           ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
           │  Entity 101   │  │  Entity 102   │  │  Entity 103   │
           │  Plan: patrol │  │  Plan: idle   │  │  Plan: dialog │
           └───────┬───────┘  └───────┬───────┘  └───────┬───────┘
                   │                  │                  │
                   ▼                  ▼                  ▼
           ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
           │  Tick 巡逻树  │  │  Tick 空闲树   │  │  Tick 对话树  │
           │               │  │               │  │               │
           │  Sequence     │  │  Sequence     │  │  Selector     │
           │  ├─MoveTo(A)  │  │  ├─StopMove   │  │  ├─Sequence   │
           │  ├─Wait       │  │  └─Wait(60s)  │  │  │ ├─Check    │
           │  └─MoveTo(B)  │  │               │  │  │ └─...      │
           └───────────────┘  └───────────────┘  └───────────────┘
                   │                  │                  │
                   ▼                  ▼                  ▼
              [Running]          [Running]          [Success]
                   │                  │                  │
                   │                  │                  ▼
                   │                  │         ┌───────────────┐
                   │                  │         │ onTreeComplete│
                   │                  │         │ TriggerCommand│
                   │                  │         │ → 重新评估     │
                   │                  │         └───────────────┘
                   ▼                  ▼
              继续下一帧         继续下一帧
```

### 5.5 Plan 转移时的行为树切换

```
NPC 正在执行 "patrol" 行为树，此时触发了 "dialog" 条件：

时间线：
────────────────────────────────────────────────────────────────────────────►

Frame N:  patrol 行为树运行中
          ┌─────────────────────────────┐
          │ Sequence (Running)          │
          │ ├─ MoveTo(A) [完成]         │
          │ ├─ Wait [运行中]            │  ← 当前执行到这里
          │ └─ MoveTo(B) [未执行]       │
          └─────────────────────────────┘

Frame N+1: GSS Brain 检测到对话条件满足，产生 Plan "dialog"
           │
           ▼
          Executor.OnPlanCreated("dialog")
           │
           ├─ btRunner.Stop(entityID)
           │   │
           │   └─ 递归调用所有运行中节点的 OnExit()
           │       ├─ Wait.OnExit()     ← 清理等待状态
           │       └─ Sequence.OnExit()
           │
           └─ btRunner.Run("dialog", entityID)
               │
               └─ 创建新的 TreeInstance
                   调用 dialog 树的 root.OnEnter()

Frame N+2: dialog 行为树运行中
          ┌─────────────────────────────┐
          │ Selector (Running)          │
          │ ├─ Sequence [运行中]        │
          │ │   ├─ StopMove [完成]      │
          │ │   └─ SetFeature [运行中]  │
          │ └─ Sequence [未执行]        │
          └─────────────────────────────┘
```

### 5.6 行为树完成后的决策重评估

```
行为树执行完成后，自动触发决策层重新评估：

┌─────────────────────────────────────────────────────────────────────────────┐
│                         BtTickSystem.Update()                               │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ Tick 返回 Success
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     onTreeCompleted(entityID, status)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  1. btRunner.Stop(entityID)            # 从 runningTrees 移除              │
│                                                                             │
│  2. entity := scene.GetEntity(entityID)                                     │
│                                                                             │
│  3. decisionComp := entity.GetComponent(DecisionComp)                       │
│                                                                             │
│  4. decisionComp.TriggerCommand()      # 触发重新评估                       │
│     │                                                                       │
│     └─► GSS Brain 在下一帧重新评估条件                                       │
│         │                                                                   │
│         └─► 可能产生新的 Plan                                                │
│             │                                                               │
│             └─► Executor.OnPlanCreated()                                    │
│                 │                                                           │
│                 └─► 启动下一个行为树（或执行硬编码逻辑）                       │
└─────────────────────────────────────────────────────────────────────────────┘

示例场景：
┌────────────────┐    ┌────────────────┐    ┌────────────────┐
│  patrol 完成   │───►│  决策重评估     │───►│  idle 开始     │
│  (到达终点)    │    │  条件: 无任务   │    │  (等待下一指令) │
└────────────────┘    └────────────────┘    └────────────────┘
```

### 5.7 节点内部与组件交互

```
以 MoveToNode 为例，展示节点如何通过 BtContext 与 ECS 组件交互：

┌─────────────────────────────────────────────────────────────────────────────┐
│                          MoveToNode.OnEnter(ctx)                            │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ 1. 获取目标点
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  target := ctx.GetBlackboard("patrol_point_a")                              │
│           ↓                                                                 │
│  BtContext.Blackboard["patrol_point_a"] → Vec3{100, 0, 200}                │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ 2. 获取移动组件（懒加载）
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  moveComp := ctx.GetMoveComp()                                              │
│           ↓                                                                 │
│  ctx.moveComp == nil?                                                       │
│      ├─ YES: scene.GetComponent(entityID, NpcMoveComp) → 缓存到 ctx        │
│      └─ NO:  返回缓存的 moveComp                                            │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ 3. 设置路径并开始移动
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  moveComp.SetPointList(pathKey, [target], nil)                              │
│  moveComp.StartMove()                                                       │
│           ↓                                                                 │
│  NpcMoveComp 组件状态变更，MoveSystem 在下一帧开始处理实际移动               │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ 4. 返回 Running
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  return BtNodeStatusRunning                                                 │
│           ↓                                                                 │
│  节点状态设为 Running，下一帧继续调用 OnTick 检查移动是否完成                 │
└─────────────────────────────────────────────────────────────────────────────┘

         ║
         ║ 后续帧
         ▼

┌─────────────────────────────────────────────────────────────────────────────┐
│                          MoveToNode.OnTick(ctx)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  moveComp := ctx.GetMoveComp()     # 使用缓存，无需再次查询                  │
│                                                                             │
│  if moveComp.IsFinish:             # 检查移动系统是否完成移动               │
│      return BtNodeStatusSuccess    # 移动完成                               │
│  else:                                                                      │
│      return BtNodeStatusRunning    # 继续等待                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 六、最佳实践

### 6.1 节点设计原则

1. **单一职责**：每个节点只做一件事
2. **无状态偏好**：尽量将状态存储在黑板而非节点内部
3. **快速失败**：条件检查放在 Sequence 开头
4. **合理粒度**：避免节点过于复杂或过于简单

### 6.2 行为树设计原则

1. **扁平化**：避免过深的嵌套
2. **可复用**：相同的子树可以抽取为独立函数
3. **可调试**：关键位置添加 LogNode
4. **优雅退出**：OnExit 中正确清理状态

### 6.3 性能注意事项

1. **避免每帧创建对象**：复用 BtContext
2. **条件检查优先**：失败快速退出
3. **合理的 Tick 间隔**：不需要每帧 Tick 的节点可以自行控制
4. **限制同时运行的树数量**：大量 NPC 时考虑分帧处理

---

## 七、调试技巧

### 7.1 日志输出

```go
// 在关键节点添加日志
nodes.NewSequenceNode(
    nodes.NewLogNode("进入巡逻状态"),
    nodes.NewMoveToNode("point_a"),
    nodes.NewLogNode("到达点A"),
    // ...
)
```

### 7.2 状态检查

```go
// 获取运行中的树实例
instance := executor.GetBtRunner().GetInstance(entityID)
if instance != nil {
    log.Infof("Tree: %s, Status: %s", instance.PlanName, instance.Status)
}
```

### 7.3 常见问题

| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| 节点不执行 | 未注册行为树 | 检查 RegisterBehaviorTree 调用 |
| 节点卡住 | OnTick 始终返回 Running | 检查完成条件逻辑 |
| 黑板数据为空 | key 拼写错误或未设置 | 检查 SetBlackboard 调用 |
| 行为被打断 | Plan 转移触发了 Stop | 检查决策层条件 |

---

## 八、扩展阅读

- **计划文件**：`.claude/plans/behavior-tree-integration-plan.md`
- **Agent 任务**：`.claude/agents/bt-core-framework.md`、`.claude/agents/bt-nodes-system.md`
- **配置示例**：`bt/trees/*.json`
