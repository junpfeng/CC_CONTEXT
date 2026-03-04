# 行为树接入 AI 决策执行层方案

## 一、背景

现有 AI 决策系统采用 GSS Brain（Game State Space）模型：
- **决策层**：基于特征(Feature)、条件(Condition)、转移(Transition)生成 Plan
- **执行层**：Executor 接收 Plan，通过硬编码的 `handleXxxTask()` 函数执行具体行为

**现有问题**：
1. 每个 Plan 的执行逻辑都是硬编码的 Go 函数
2. 复杂行为序列（走到A点 → 等待 → 播放动画 → 走到B点）需要写大量代码
3. 行为调整需要改代码、重新编译
4. 已有 `bt/` 目录下的行为树基础实现未被使用

## 二、目标

将行为树接入 AI 决策的执行层，使用行为树来控制 AINPC 的执行：
- 复杂行为序列可通过行为树组合实现
- 支持配置驱动，减少硬编码
- 渐进式迁移，不破坏现有逻辑

## 三、方案选择

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **方案A** | 行为树作为 Plan 执行器 | 渐进式迁移，不破坏现有逻辑 | 需要维护两套执行方式 |
| **方案B** | 行为树替代所有 handle 函数 | 统一执行方式 | 改动大，风险高 |
| **方案C** | 行为树作为独立 Brain 类型 | 完全独立 | 与现有 GSS 决策割裂 |

**选择方案A**：行为树作为 Plan 的可选执行器

## 四、架构设计

### 4.1 整体架构

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
│      btRunner.Run(plan.Name, entityID)  ──────────────┐ │
│  else:                                                 │ │
│      executeTask(task)  // 原有逻辑                     │ │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                 行为树执行器 (BtRunner)                    │
│                                                          │
│  BehaviorTree "patrol":                                 │
│  ├─ Sequence                                            │
│  │   ├─ MoveTo(pointA)      // 叶子节点                  │
│  │   ├─ Wait(3s)                                        │
│  │   ├─ PlayAnimation("look_around")                    │
│  │   └─ MoveTo(pointB)                                  │
│  │                                                       │
│  叶子节点调用:                                            │
│  ├─ NpcMoveComp.StartMove()                             │
│  ├─ NpcMoveComp.SetPointList()                          │
│  └─ DialogComp.SetState()                               │
└─────────────────────────────────────────────────────────┘
```

### 4.2 核心组件

#### 4.2.1 BtRunner（行为树运行器）

**文件位置**: `/servers/scene_server/internal/common/ai/bt/runner/runner.go`

```go
type BtRunner struct {
    scene        common.Scene
    trees        map[string]*BehaviorTree   // plan名称 -> 行为树定义
    runningTrees map[uint64]*TreeInstance   // entityID -> 运行中的树实例
}

type TreeInstance struct {
    Tree      *BehaviorTree
    Context   *BtContext
    Status    BtNodeStatus
    StartTime int64
}

// 核心方法
func (r *BtRunner) RegisterTree(planName string, tree *BehaviorTree)
func (r *BtRunner) HasTree(planName string) bool
func (r *BtRunner) Run(planName string, entityID uint64) error
func (r *BtRunner) Tick(entityID uint64) BtNodeStatus
func (r *BtRunner) Stop(entityID uint64)
func (r *BtRunner) IsRunning(entityID uint64) bool
```

#### 4.2.2 BtContext（行为树上下文）

**文件位置**: `/servers/scene_server/internal/common/ai/bt/context/context.go`

```go
type BtContext struct {
    Scene      common.Scene
    EntityID   uint64
    Blackboard map[string]any  // 黑板数据，节点间共享
    StartTime  int64           // 行为树启动时间

    // 组件缓存（懒加载）
    moveComp      *cnpc.NpcMoveComp
    dialogComp    *cdialog.DialogComp
    transformComp *ctrans.Transform
    decisionComp  *caidecision.DecisionComp
}

// 组件访问方法
func (c *BtContext) GetMoveComp() *cnpc.NpcMoveComp
func (c *BtContext) GetDialogComp() *cdialog.DialogComp
func (c *BtContext) GetTransformComp() *ctrans.Transform
func (c *BtContext) GetDecisionComp() *caidecision.DecisionComp

// 黑板操作
func (c *BtContext) SetBlackboard(key string, value any)
func (c *BtContext) GetBlackboard(key string) (any, bool)
func (c *BtContext) GetBlackboardAs[T any](key string) (T, bool)
```

#### 4.2.3 节点接口（复用现有 bt/tree/node/）

```go
// 已有接口，位于 /bt/tree/node/bt_node.go
type IBtNode interface {
    Begin(ctx *BtContext) BtNodeStatus
    End(ctx *BtContext) BtNodeStatus
    Tick(ctx *BtContext) BtNodeStatus
    Execute(ctx *BtContext) BtNodeStatus
    NowStatus() BtNodeStatus
    SetStatus(status BtNodeStatus)
    IsRunning() bool
    IsCompleted() bool
    Children() []IBtNode
    Type() BTNodeType
}

type BtNodeStatus int
const (
    BtNodeStatusInit    BtNodeStatus = iota
    BtNodeStatusRunning
    BtNodeStatusSuccess
    BtNodeStatusFailed
)
```

### 4.3 叶子节点设计

**文件位置**: `/servers/scene_server/internal/common/ai/bt/nodes/`

#### 4.3.1 移动节点

```go
// nodes/move_to.go
type MoveToNode struct {
    BtNodeBase
    TargetPointKey string        // 从黑板读取目标点的 key
    TargetPoint    *transform.Vec3  // 或直接指定目标点
    Speed          float32       // 移动速度，0 表示使用默认速度
}

func (n *MoveToNode) Begin(ctx *BtContext) BtNodeStatus {
    target := n.getTarget(ctx)
    if target == nil {
        return BtNodeStatusFailed
    }

    moveComp := ctx.GetMoveComp()
    // 计算路径并开始移动
    moveComp.SetPointList(...)
    moveComp.StartMove()
    return BtNodeStatusRunning
}

func (n *MoveToNode) Tick(ctx *BtContext) BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp.IsFinish {
        return BtNodeStatusSuccess
    }
    return BtNodeStatusRunning
}
```

#### 4.3.2 等待节点

```go
// nodes/wait.go
type WaitNode struct {
    BtNodeBase
    DurationMs int64  // 等待时间（毫秒）
    startTime  int64  // 开始等待的时间
}

func (n *WaitNode) Begin(ctx *BtContext) BtNodeStatus {
    n.startTime = mtime.NowMilliTickWithOffset()
    return BtNodeStatusRunning
}

func (n *WaitNode) Tick(ctx *BtContext) BtNodeStatus {
    elapsed := mtime.NowMilliTickWithOffset() - n.startTime
    if elapsed >= n.DurationMs {
        return BtNodeStatusSuccess
    }
    return BtNodeStatusRunning
}
```

#### 4.3.3 设置特征节点

```go
// nodes/set_feature.go
type SetFeatureNode struct {
    BtNodeBase
    FeatureKey   string
    FeatureValue any
    TTLMs        int64
}

func (n *SetFeatureNode) Execute(ctx *BtContext) BtNodeStatus {
    decisionComp := ctx.GetDecisionComp()
    if decisionComp == nil {
        return BtNodeStatusFailed
    }

    err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     ctx.EntityID,
        FeatureKey:   n.FeatureKey,
        FeatureValue: n.FeatureValue,
        TTLMs:        n.TTLMs,
    })

    if err != nil {
        return BtNodeStatusFailed
    }
    return BtNodeStatusSuccess
}
```

#### 4.3.4 条件检查节点

```go
// nodes/check_condition.go
type CheckConditionNode struct {
    BtNodeBase
    FeatureKey string
    Operator   string  // "==", "!=", ">", "<", ">=", "<="
    Value      any
}

func (n *CheckConditionNode) Execute(ctx *BtContext) BtNodeStatus {
    decisionComp := ctx.GetDecisionComp()
    value, ok := decisionComp.GetFeatureValue(n.FeatureKey)
    if !ok {
        return BtNodeStatusFailed
    }

    if n.evaluate(value, n.Operator, n.Value) {
        return BtNodeStatusSuccess
    }
    return BtNodeStatusFailed
}
```

#### 4.3.5 其他常用节点

| 节点 | 文件 | 功能 |
|------|------|------|
| `PlayAnimationNode` | `nodes/play_animation.go` | 播放动画 |
| `StopMoveNode` | `nodes/stop_move.go` | 停止移动 |
| `LookAtNode` | `nodes/look_at.go` | 面向目标 |
| `LogNode` | `nodes/log.go` | 输出日志（调试用） |
| `SetBlackboardNode` | `nodes/set_blackboard.go` | 设置黑板数据 |
| `RandomSelectNode` | `nodes/random_select.go` | 随机选择子节点 |

### 4.4 控制节点（复用现有实现）

已有实现位于 `/bt/tree/node/node_control.go`：
- `SequenceNode` - 顺序执行，全部成功才成功
- `SelectorNode` - 选择执行，一个成功就成功
- `ParallelNode` - 并行执行

### 4.5 装饰节点（复用现有实现）

已有实现位于 `/bt/tree/node/node_decorator.go`：
- `InverterNode` - 反转结果
- `RepeatNode` - 重复执行
- `RetryNode` - 失败重试

## 五、与现有系统集成

### 5.1 修改 Executor

**文件**: `/servers/scene_server/internal/ecs/system/decision/executor.go`

```go
type Executor struct {
    Scene    common.Scene
    btRunner *bt.BtRunner  // 新增
}

func NewExecutor(scene common.Scene) *Executor {
    return &Executor{
        Scene:    scene,
        btRunner: bt.NewBtRunner(scene),
    }
}

func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    // 检查是否有对应的行为树
    if e.btRunner.HasTree(req.Plan.Name) {
        // 停止之前运行的行为树（如果有）
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

// 新增：注册行为树
func (e *Executor) RegisterBehaviorTree(planName string, tree *bt.BehaviorTree) {
    e.btRunner.RegisterTree(planName, tree)
}
```

### 5.2 新增行为树 Tick 系统

**文件**: `/servers/scene_server/internal/ecs/system/decision/bt_tick_system.go`

```go
type BtTickSystem struct {
    *system.SystemBase
    executor *Executor
}

func NewBtTickSystem(scene common.Scene, executor *Executor) *BtTickSystem {
    return &BtTickSystem{
        SystemBase: system.New(scene),
        executor:   executor,
    }
}

func (s *BtTickSystem) Type() common.SystemType {
    return common.SystemType_BtTick
}

func (s *BtTickSystem) Update() {
    // 遍历所有运行中的行为树
    for entityID, instance := range s.executor.btRunner.GetRunningTrees() {
        status := s.executor.btRunner.Tick(entityID)

        if status == bt.BtNodeStatusSuccess || status == bt.BtNodeStatusFailed {
            // 行为树执行完成，可以通知决策层生成下一个 Plan
            s.onTreeCompleted(entityID, status)
        }
    }
}

func (s *BtTickSystem) onTreeCompleted(entityID uint64, status bt.BtNodeStatus) {
    // 可选：通知决策层行为树执行完成
    // 让 GSS Brain 知道当前 Plan 已完成，可以进行下一次转移判断
}
```

### 5.3 行为树注册（初始化时）

```go
// 在场景初始化时注册行为树
func initBehaviorTrees(executor *Executor) {
    // 示例：巡逻行为树
    patrolTree := bt.NewBehaviorTree("patrol",
        bt.Sequence(
            nodes.NewMoveToNode("patrol_point_a"),
            nodes.NewWaitNode(3000),
            nodes.NewMoveToNode("patrol_point_b"),
            nodes.NewWaitNode(3000),
        ),
    )
    executor.RegisterBehaviorTree("patrol", patrolTree)

    // 示例：对话行为树
    dialogTree := bt.NewBehaviorTree("dialog",
        bt.Sequence(
            nodes.NewStopMoveNode(),
            nodes.NewLookAtNode("dialog_target"),
            nodes.NewSetFeatureNode("feature_dialog_state", "dialog", 0),
            // 等待对话结束...
        ),
    )
    executor.RegisterBehaviorTree("dialog", dialogTree)
}
```

## 六、配置驱动详细设计（Part 5 实现）

### 6.1 配置格式选择

**选择 JSON**，理由：
- 现有 `bt/config/config.go` 已使用 JSON tag
- JSON 比 TOML 更适合表达树形结构
- Go 标准库支持，无需额外依赖

### 6.2 配置文件结构

```json
{
  "name": "patrol",
  "description": "NPC 巡逻行为",
  "blackboard": {
    "patrol_point_a": { "type": "vec3", "value": [100, 0, 200] },
    "patrol_point_b": { "type": "vec3", "value": [150, 0, 250] },
    "wait_time": { "type": "int64", "value": 3000 }
  },
  "root": {
    "type": "Sequence",
    "children": [
      {
        "type": "MoveTo",
        "params": {
          "target_key": "patrol_point_a",
          "speed": 0
        }
      },
      {
        "type": "Wait",
        "params": {
          "duration_key": "wait_time"
        }
      },
      {
        "type": "MoveTo",
        "params": {
          "target_key": "patrol_point_b"
        }
      },
      {
        "type": "Wait",
        "params": {
          "duration_ms": 3000
        }
      }
    ]
  }
}
```

### 6.3 Go 配置类型定义

**文件**: `bt/config/types.go`

```go
// BTreeConfig 行为树配置根结构
type BTreeConfig struct {
    Name        string                     `json:"name"`
    Description string                     `json:"description,omitempty"`
    Blackboard  map[string]BlackboardValue `json:"blackboard,omitempty"`
    Root        NodeConfig                 `json:"root"`
}

// BlackboardValue 黑板初始值
type BlackboardValue struct {
    Type  string `json:"type"`  // "int32", "int64", "float32", "string", "bool", "vec3"
    Value any    `json:"value"` // 根据 type 解析
}

// NodeConfig 节点配置（递归结构）
type NodeConfig struct {
    Type     string            `json:"type"`               // 节点类型名
    Params   map[string]any    `json:"params,omitempty"`   // 节点参数
    Children []NodeConfig      `json:"children,omitempty"` // 子节点（控制节点）
    Child    *NodeConfig       `json:"child,omitempty"`    // 单子节点（装饰节点）
}
```

### 6.4 节点工厂设计

**文件**: `bt/nodes/factory.go`

```go
// NodeFactory 节点工厂
type NodeFactory struct {
    creators map[string]NodeCreator
}

// NodeCreator 节点创建函数
type NodeCreator func(params map[string]any) (IBtNode, error)

// NewNodeFactory 创建节点工厂（注册所有内置节点）
func NewNodeFactory() *NodeFactory {
    f := &NodeFactory{
        creators: make(map[string]NodeCreator),
    }

    // 控制节点
    f.Register("Sequence", createSequenceNode)
    f.Register("Selector", createSelectorNode)
    f.Register("Parallel", createParallelNode)

    // 装饰节点
    f.Register("Inverter", createInverterNode)
    f.Register("Repeat", createRepeatNode)
    f.Register("Retry", createRetryNode)

    // 叶子节点
    f.Register("MoveTo", createMoveToNode)
    f.Register("Wait", createWaitNode)
    f.Register("StopMove", createStopMoveNode)
    f.Register("SetFeature", createSetFeatureNode)
    f.Register("CheckCondition", createCheckConditionNode)
    f.Register("Log", createLogNode)
    f.Register("LookAt", createLookAtNode)
    f.Register("SetBlackboard", createSetBlackboardNode)

    return f
}

// Register 注册自定义节点
func (f *NodeFactory) Register(nodeType string, creator NodeCreator) {
    f.creators[nodeType] = creator
}

// Create 根据配置创建节点
func (f *NodeFactory) Create(config NodeConfig) (IBtNode, error) {
    creator, ok := f.creators[config.Type]
    if !ok {
        return nil, fmt.Errorf("unknown node type: %s", config.Type)
    }
    return creator(config.Params)
}
```

### 6.5 配置加载器设计

**文件**: `bt/config/loader.go`

```go
type BTreeLoader struct {
    factory *NodeFactory
}

func NewBTreeLoader() *BTreeLoader {
    return &BTreeLoader{
        factory: NewNodeFactory(),
    }
}

// LoadFromFile 从文件加载行为树
func (l *BTreeLoader) LoadFromFile(path string) (*BehaviorTree, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("read file failed: %w", err)
    }
    return l.LoadFromJSON(data)
}

// LoadFromJSON 从 JSON 数据加载行为树
func (l *BTreeLoader) LoadFromJSON(data []byte) (*BehaviorTree, error) {
    var config BTreeConfig
    if err := json.Unmarshal(data, &config); err != nil {
        return nil, fmt.Errorf("parse json failed: %w", err)
    }
    return l.buildTree(&config)
}

// buildTree 递归构建行为树
func (l *BTreeLoader) buildTree(config *BTreeConfig) (*BehaviorTree, error) {
    root, err := l.buildNode(config.Root)
    if err != nil {
        return nil, fmt.Errorf("build root node failed: %w", err)
    }

    tree := &BehaviorTree{
        Name:       config.Name,
        Root:       root,
        Blackboard: l.parseBlackboard(config.Blackboard),
    }
    return tree, nil
}

// buildNode 递归构建节点
func (l *BTreeLoader) buildNode(config NodeConfig) (IBtNode, error) {
    node, err := l.factory.Create(config)
    if err != nil {
        return nil, err
    }

    // 处理子节点（控制节点）
    if controlNode, ok := node.(IControlNode); ok {
        for _, childConfig := range config.Children {
            child, err := l.buildNode(childConfig)
            if err != nil {
                return nil, err
            }
            controlNode.AddChild(child)
        }
    }

    // 处理单子节点（装饰节点）
    if decoratorNode, ok := node.(IDecoratorNode); ok && config.Child != nil {
        child, err := l.buildNode(*config.Child)
        if err != nil {
            return nil, err
        }
        decoratorNode.SetChild(child)
    }

    return node, nil
}
```

### 6.6 参数绑定约定

为了让配置更灵活，参数支持两种绑定方式：

| 后缀 | 含义 | 示例 |
|------|------|------|
| `_key` | 从黑板读取 | `"target_key": "patrol_point_a"` |
| 无后缀 | 直接值 | `"duration_ms": 3000` |

```json
// 直接指定值
{
  "type": "Wait",
  "params": { "duration_ms": 3000 }
}

// 从黑板读取
{
  "type": "Wait",
  "params": { "duration_key": "wait_time" }
}
```

### 6.7 目录结构

```
bt/
├── config/
│   ├── types.go       # 配置类型定义
│   └── loader.go      # 配置加载器
├── nodes/
│   ├── factory.go     # 节点工厂
│   ├── move_to.go     # MoveTo 节点
│   ├── wait.go        # Wait 节点
│   └── ...
├── context/
│   └── context.go     # BtContext
├── runner/
│   └── runner.go      # BtRunner
└── trees/             # 配置文件目录（可选）
    ├── patrol.json
    ├── dialog.json
    └── ...
```

### 6.8 使用方式

```go
// 初始化时加载
loader := config.NewBTreeLoader()

// 从文件加载
patrolTree, err := loader.LoadFromFile("bt/trees/patrol.json")
executor.RegisterBehaviorTree("patrol", patrolTree)

// 或从嵌入资源加载
//go:embed trees/*.json
var treeConfigs embed.FS
data, _ := treeConfigs.ReadFile("trees/patrol.json")
patrolTree, _ := loader.LoadFromJSON(data)
```

### 6.9 方案优缺点

| 优点 | 缺点 |
|------|------|
| 行为定义与代码解耦 | 增加一层解析开销 |
| 策划可直接编辑 JSON | 复杂逻辑仍需代码实现新节点 |
| 支持热重载 | 类型安全需运行时检查 |
| 易于版本控制和 diff | 调试时需关联配置和代码 |

### 6.10 实现建议

1. **先代码后配置**：Part 1-4 先用代码定义行为树验证流程，Part 5 再加配置驱动
2. **渐进式支持**：简单行为用配置，复杂行为仍用代码
3. **可选实现**：如果行为树数量不多（<20），可以不做配置驱动

## 七、实现计划（分阶段拆解）

### Part 0: 评估与决策

**目标**: 解决待确认问题，明确实现细节

**依赖**: 无

**任务**:
1. 确认行为树与 Plan 的映射关系（Plan 级别 vs Task 级别）
2. 确认行为树完成后的处理方式
3. 评估现有 `bt/` 代码的复用程度
4. 确认配置驱动的优先级

**输出**: 更新本文档"八、待确认问题"章节

**验收标准**: 4 个待确认问题全部有明确答案

---

### Part 1: 核心基础设施

**目标**: 实现行为树运行的基础框架

**依赖**: Part 0 完成

**任务**:

| 序号 | 任务 | 文件 | 说明 |
|------|------|------|------|
| 1.1 | 实现 BtContext | `bt/context/context.go` | 执行上下文，包含黑板、组件缓存 |
| 1.2 | 实现 BtRunner | `bt/runner/runner.go` | 行为树运行器，管理树实例生命周期 |
| 1.3 | 评估并适配现有节点 | `bt/tree/node/*` | 确认接口兼容性，必要时修改 |

**输出**:
- `bt/context/context.go` - BtContext 实现
- `bt/runner/runner.go` - BtRunner 实现

**验收标准**:
- BtRunner 能够注册、启动、停止行为树
- BtContext 能够正确获取 Entity 的各类组件
- 单元测试通过

---

### Part 2: 叶子节点实现

**目标**: 实现常用的行为节点

**依赖**: Part 1 完成

**任务**:

| 序号 | 任务 | 文件 | 说明 |
|------|------|------|------|
| 2.1 | MoveToNode | `bt/nodes/move_to.go` | 移动到指定点 |
| 2.2 | WaitNode | `bt/nodes/wait.go` | 等待指定时间 |
| 2.3 | StopMoveNode | `bt/nodes/stop_move.go` | 停止移动 |
| 2.4 | SetFeatureNode | `bt/nodes/set_feature.go` | 设置决策特征 |
| 2.5 | CheckConditionNode | `bt/nodes/check_condition.go` | 条件检查 |
| 2.6 | LogNode | `bt/nodes/log.go` | 调试日志输出 |
| 2.7 | LookAtNode | `bt/nodes/look_at.go` | 面向目标 |
| 2.8 | SetBlackboardNode | `bt/nodes/set_blackboard.go` | 设置黑板数据 |

**输出**: `bt/nodes/` 目录下的各叶子节点实现

**验收标准**:
- 每个节点实现 `IBtNode` 接口
- 每个节点有对应的单元测试
- 节点能正确与 BtContext 交互

---

### Part 3: 系统集成

**目标**: 将行为树系统集成到现有 AI 决策流程

**依赖**: Part 1、Part 2 完成

**任务**:

| 序号 | 任务 | 文件 | 说明 |
|------|------|------|------|
| 3.1 | 修改 Executor | `decision/executor.go` | 添加 btRunner 字段，集成行为树执行逻辑 |
| 3.2 | 新增 BtTickSystem | `decision/bt_tick_system.go` | 行为树帧更新系统 |
| 3.3 | 注册系统 | 场景初始化代码 | 在场景中注册 BtTickSystem |

**输出**:
- 修改后的 `executor.go`
- 新增的 `bt_tick_system.go`

**验收标准**:
- Executor 能根据 Plan 名称判断是否使用行为树执行
- BtTickSystem 正确驱动行为树 Tick
- 现有硬编码的 handleXxxTask 逻辑不受影响

---

### Part 4: 示例与验证

**目标**: 用一个具体的 Plan 验证整个流程

**依赖**: Part 3 完成

**任务**:

| 序号 | 任务 | 说明 |
|------|------|------|
| 4.1 | 选择一个适合的 Plan | 建议选择简单的行为序列，如"巡逻" |
| 4.2 | 用代码定义行为树 | 在初始化时注册 |
| 4.3 | 端到端测试 | 验证 NPC 行为符合预期 |
| 4.4 | 性能测试 | 多 NPC 场景下的帧率影响 |

**输出**:
- 一个完整可运行的行为树示例
- 测试报告

**验收标准**:
- NPC 使用行为树执行 Plan，行为正确
- 性能在可接受范围内（帧率无明显下降）

---

### Part 5: 配置驱动（可选）

**目标**: 支持从 JSON 配置文件定义行为树

**依赖**: Part 4 完成

**优先级**: 中等，根据实际需求决定是否实施

**任务**:

| 序号 | 任务 | 文件 | 说明 |
|------|------|------|------|
| 5.1 | 定义配置格式 | `bt/config/types.go` | JSON 结构定义 |
| 5.2 | 实现节点工厂 | `bt/nodes/factory.go` | 根据类型名创建节点实例 |
| 5.3 | 实现配置加载器 | `bt/config/loader.go` | 解析 JSON 并构建行为树 |
| 5.4 | 热重载支持 | `bt/config/watcher.go` | 可选：配置变更时自动重载 |

**输出**:
- 配置文件格式规范
- 配置加载实现

**验收标准**:
- 能从 JSON 文件加载并运行行为树
- 配置格式清晰、易于编辑

---

### 阶段依赖关系

```
Part 0 (评估与决策) ✅ 已完成
    │
    ▼
Part 1 (核心基础设施) ✅ 已完成
    │
    ▼
Part 2 (叶子节点实现) ✅ 已完成
    │
    └────────────────┐
                     │
Part 3 (系统集成) ◄──┘ ✅ 已完成
    │
    ▼
Part 4 (示例与验证) ✅ 已完成
    │
    ▼
Part 5 (配置驱动) ✅ 已完成
    │
    ▼
Part 6 (BtRunner-Executor 集成) ✅ 已完成
```

### Part 4 完成记录

**完成时间**: 2026-01-29

**新增文件**:
- `bt/nodes/sequence.go` - SequenceNode 顺序控制节点
- `bt/nodes/selector.go` - SelectorNode 选择控制节点
- `bt/trees/example_trees.go` - 示例行为树注册

**示例行为树**:
1. `bt_wait` - 简单等待行为树（等待3秒）
2. `bt_patrol` - 巡逻行为树（移动→等待→移动）
3. `bt_conditional` - 条件分支行为树（Selector + Sequence）
4. `bt_idle` - 空闲行为树（停止移动 + 长时间等待）

**编译验证**: `make build APPS='scene_server'` 通过

### Part 5 完成记录

**完成时间**: 2026-01-29

**新增文件**:
- `bt/config/types.go` - 配置类型定义 (BTreeConfig, NodeConfig, BlackboardValue)
- `bt/config/loader.go` - 配置加载器 (BTreeLoader)
- `bt/nodes/factory.go` - 节点工厂 (NodeFactory)
- `bt/trees/patrol.json` - 巡逻行为树配置示例
- `bt/trees/conditional.json` - 条件分支行为树配置示例

**配置格式**:
```json
{
  "name": "plan_name",
  "description": "描述",
  "blackboard": {
    "key": { "type": "vec3", "value": [x, y, z] }
  },
  "root": {
    "type": "Sequence",
    "children": [...]
  }
}
```

**支持的节点类型**:
- 控制节点: Sequence, Selector
- 叶子节点: MoveTo, Wait, StopMove, SetFeature, CheckCondition, Log, LookAt, SetBlackboard

**使用方式**:
```go
// 从嵌入配置加载
trees.RegisterTreesFromConfig(executor.RegisterBehaviorTree)

// 从文件加载
cfg, root, err := trees.LoadTreeFromFile("path/to/tree.json")

// 从 JSON 字符串加载
cfg, root, err := trees.LoadTreeFromJSON(jsonData)
```

**编译验证**: `make build APPS='scene_server'` 通过

---

### Part 6: BtRunner-Executor 集成实现

**目标**: 将 BtRunner 集成到 Executor 中，实现行为树与决策系统的完整对接

**依赖**: Part 1-5 的设计完成

**状态**: ✅ 已完成

**完成时间**: 2026-02-02

**实现记录**:
- 新增 `ResourceType_Executor` 资源类型
- 新增 `ExecutorResource` 封装共享的 Executor 和 BtRunner
- 在 `scene_impl.go` 中注册 ExecutorResource 和 BtTickSystem
- 更新 `npc/common.go` 使用共享的 ExecutorResource
- **2026-02-02 补充**: 添加行为树模板注册调用
  - 导入 `trees` 包
  - 调用 `RegisterExampleTrees()` 注册硬编码示例树
  - 调用 `RegisterTreesFromConfig()` 加载 JSON 配置树

#### 6.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Scene (场景)                                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Systems (系统层)                             │   │
│  │                                                                      │   │
│  │  ┌──────────────────┐         ┌──────────────────┐                  │   │
│  │  │  DecisionSystem  │         │  BtTickSystem    │  ← 新增          │   │
│  │  │  (决策系统)       │         │  (行为树Tick)    │                  │   │
│  │  └────────┬─────────┘         └────────┬─────────┘                  │   │
│  └───────────┼─────────────────────────────┼────────────────────────────┘   │
│              │                             │                                │
│              │ OnPlanCreated               │ Update (每帧)                  │
│              ▼                             ▼                                │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                      Executor (执行器) - 修改                          │ │
│  │                                                                        │ │
│  │   Scene    common.Scene                                               │ │
│  │   btRunner *runner.BtRunner  ← 新增字段                                │ │
│  │                                                                        │ │
│  │   ┌────────────────────────────────────────────────────────────────┐  │ │
│  │   │                    BtRunner (行为树运行器)                       │  │ │
│  │   │                                                                 │  │ │
│  │   │  trees: map[string]IBtNode       # 注册的行为树模板              │  │ │
│  │   │  runningTrees: map[uint64]*TreeInstance  # 运行中的实例          │  │ │
│  │   └────────────────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 6.2 需要修改/新增的文件

| 操作 | 文件路径 | 说明 |
|------|----------|------|
| 新增 | `common/ai/bt/runner/runner.go` | BtRunner 运行器实现 |
| 新增 | `common/ai/bt/context/context.go` | BtContext 执行上下文 |
| 新增 | `common/ai/bt/node/interface.go` | 统一 IBtNode 接口 |
| 修改 | `ecs/system/decision/executor.go` | 添加 btRunner 字段，集成行为树执行 |
| 新增 | `ecs/system/decision/bt_tick_system.go` | 行为树 Tick 系统 |
| 修改 | `common/system_type.go` | 注册新系统类型 SystemType_AiBt |

#### 6.3 Executor 修改详情

**文件**: `servers/scene_server/internal/ecs/system/decision/executor.go`

**修改内容**:

```go
package decision

import (
    "mp/servers/scene_server/internal/common/ai/bt/node"
    "mp/servers/scene_server/internal/common/ai/bt/runner"
    // ... 其他 import
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
        btRunner: runner.NewBtRunner(scene),  // 新增：初始化行为树运行器
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
    e.Scene.Debugf("[Executor][OnPlanCreated] entity_id=%v, plan=%v", req.EntityID, req.Plan.Name)

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
        e.executeTask(req.EntityID, req.Plan.Name, req.Plan.FromPlan, task)
    }
    return nil
}
```

#### 6.4 BtRunner 实现

**文件**: `servers/scene_server/internal/common/ai/bt/runner/runner.go`

```go
package runner

import (
    "errors"
    "time"
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/common/ai/bt/context"
    "mp/servers/scene_server/internal/common/ai/bt/node"
)

var (
    ErrTreeNotFound       = errors.New("behavior tree not found")
    ErrTreeAlreadyRunning = errors.New("behavior tree already running")
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
    trees        map[string]node.IBtNode     // planName -> 行为树模板
    runningTrees map[uint64]*TreeInstance    // entityID -> 运行中实例
}

func NewBtRunner(scene common.Scene) *BtRunner {
    return &BtRunner{
        scene:        scene,
        trees:        make(map[string]node.IBtNode),
        runningTrees: make(map[uint64]*TreeInstance),
    }
}

// RegisterTree 注册行为树模板
func (r *BtRunner) RegisterTree(planName string, root node.IBtNode) {
    r.trees[planName] = root
}

// HasTree 检查是否有对应行为树
func (r *BtRunner) HasTree(planName string) bool {
    _, ok := r.trees[planName]
    return ok
}

// Run 启动行为树
func (r *BtRunner) Run(planName string, entityID uint64) error {
    root, ok := r.trees[planName]
    if !ok {
        return ErrTreeNotFound
    }

    // 停止已有的运行实例
    if _, exists := r.runningTrees[entityID]; exists {
        r.Stop(entityID)
    }

    // 创建上下文
    ctx := context.NewBtContext(r.scene, entityID)

    // 重置树状态
    root.Reset()

    // 创建实例
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

    return nil
}

// Stop 停止行为树
func (r *BtRunner) Stop(entityID uint64) {
    instance, ok := r.runningTrees[entityID]
    if !ok {
        return
    }

    // 递归调用 OnExit
    r.stopNode(instance.Root, instance.Context)
    delete(r.runningTrees, entityID)
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

// GetRunningTrees 获取运行中的树
func (r *BtRunner) GetRunningTrees() map[uint64]*TreeInstance {
    return r.runningTrees
}

// GetRunningCount 获取运行中的树数量
func (r *BtRunner) GetRunningCount() int {
    return len(r.runningTrees)
}
```

#### 6.5 BtTickSystem 实现

**文件**: `servers/scene_server/internal/ecs/system/decision/bt_tick_system.go`

```go
package decision

import (
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/common/ai/bt/node"
    "mp/servers/scene_server/internal/common/ai/bt/runner"
    "mp/servers/scene_server/internal/ecs/com/caidecision"
    "mp/servers/scene_server/internal/ecs/system"
)

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
    return common.SystemType_AiBt
}

func (s *BtTickSystem) Update() {
    if s.btRunner == nil {
        return
    }

    deltaTime := float32(0.0167)  // ~60 FPS

    type completedInfo struct {
        entityID uint64
        planName string
        status   node.BtNodeStatus
    }
    completedTrees := make([]completedInfo, 0)

    // 遍历运行中的行为树
    for entityID, instance := range s.btRunner.GetRunningTrees() {
        if instance.Status == node.BtNodeStatusSuccess ||
           instance.Status == node.BtNodeStatusFailed {
            continue
        }

        status := s.btRunner.Tick(entityID, deltaTime)

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

func (s *BtTickSystem) onTreeCompleted(entityID uint64, planName string, status node.BtNodeStatus) {
    s.btRunner.Stop(entityID)

    // 获取实体
    entity, ok := s.Scene().GetEntity(entityID)
    if !ok {
        return
    }

    // 获取决策组件
    decisionComp, ok := common.GetEntityComponentAs[*caidecision.DecisionComp](
        entity, common.ComponentType_AIDecision)
    if !ok {
        return
    }

    // 触发决策重评估
    decisionComp.TriggerCommand()
}

func (s *BtTickSystem) GetBtRunner() *runner.BtRunner {
    return s.btRunner
}
```

#### 6.6 执行流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 1: 初始化                                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Scene 创建                                                                 │
│      │                                                                      │
│      ├── executor = NewExecutor(scene)                                     │
│      │       └── btRunner = NewBtRunner(scene)                             │
│      │                                                                      │
│      ├── 注册行为树                                                          │
│      │       └── executor.RegisterBehaviorTree("patrol", patrolTree)       │
│      │                                                                      │
│      └── btTickSystem = NewBtTickSystem(scene, executor.GetBtRunner())     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 2: 决策触发                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  GSS Brain 产生 Plan                                                       │
│      │                                                                      │
│      └── executor.OnPlanCreated(plan)                                      │
│              │                                                              │
│              ├── btRunner.HasTree(plan.Name)? ────Yes────┐                 │
│              │                                           │                 │
│              │   btRunner.Run(plan.Name, entityID) ◄─────┘                 │
│              │       │                                                      │
│              │       ├── 创建 TreeInstance                                  │
│              │       ├── 创建 BtContext                                     │
│              │       └── root.OnEnter(ctx)                                 │
│              │                                                              │
│              └── No ──► 执行原有 Task 逻辑                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 3: 每帧 Tick                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  BtTickSystem.Update()                                                      │
│      │                                                                      │
│      └── for entityID, instance := range btRunner.GetRunningTrees()        │
│              │                                                              │
│              └── btRunner.Tick(entityID, deltaTime)                        │
│                      │                                                      │
│                      └── tickNode(root, ctx)                               │
│                              │                                              │
│                              ├── node.Status() == Init?                    │
│                              │       └── node.OnEnter(ctx)                 │
│                              │                                              │
│                              ├── node.OnTick(ctx)                          │
│                              │                                              │
│                              └── status == Success/Failed?                 │
│                                      └── node.OnExit(ctx)                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 4: 完成与重评估                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  行为树返回 Success/Failed                                                  │
│      │                                                                      │
│      └── onTreeCompleted(entityID, planName, status)                       │
│              │                                                              │
│              ├── btRunner.Stop(entityID)                                   │
│              │                                                              │
│              └── decisionComp.TriggerCommand()                             │
│                      │                                                      │
│                      └── GSS Brain 重新评估 ──► 产生新 Plan ──► 回到 Phase 2│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 6.7 实现任务清单

| 序号 | 任务 | 文件 | 状态 |
|------|------|------|------|
| 6.1 | 新增 SystemType_AiBt | `common/system_type.go` | ✅ 已完成（已有） |
| 6.2 | 实现 BtContext | `common/ai/bt/context/context.go` | ✅ 已完成（已有） |
| 6.3 | 统一 IBtNode 接口 | `common/ai/bt/node/interface.go` | ✅ 已完成（已有） |
| 6.4 | 实现 BtRunner | `common/ai/bt/runner/runner.go` | ✅ 已完成（已有） |
| 6.5 | 修改 Executor | `ecs/system/decision/executor.go` | ✅ 已完成（已有） |
| 6.6 | 实现 BtTickSystem | `ecs/system/decision/bt_tick_system.go` | ✅ 已完成 |
| 6.7 | 场景初始化注册 | `ecs/scene/scene_impl.go` | ✅ 已完成 |
| 6.8 | 新增 ExecutorResource | `ecs/system/decision/executor_resource.go` | ✅ 已完成 |
| 6.9 | 行为树模板注册 | `ecs/scene/scene_impl.go` | ✅ 已完成 (2026-02-02 补充) |

#### 6.8 验收标准

- [x] Executor 包含 btRunner 字段，并在 NewExecutor 中初始化
- [x] OnPlanCreated 优先检查行为树，回退到原有 Task 逻辑
- [x] BtTickSystem 正确驱动所有运行中的行为树
- [x] 行为树完成后触发决策重评估
- [x] 现有 Plan（无行为树）的执行逻辑不受影响
- [x] `make build APPS='scene_server'` 编译通过
- [x] ExecutorResource 作为场景级共享资源正确注册
- [x] NPC 初始化使用共享的 ExecutorResource
- [x] 行为树模板在场景初始化时被注册到 BtRunner

---

### 双 Agent 并行执行方案

#### Agent 分工

| Agent | 职责 | 任务列表 |
|-------|------|----------|
| **Agent A** | 核心框架 | 1.1 BtContext → 1.2 BtRunner → 3.1 修改 Executor |
| **Agent B** | 节点与系统 | 1.3 评估现有节点 → 2.1~2.8 叶子节点 → 3.2 BtTickSystem |

#### 执行时间线

```
时间 ─────────────────────────────────────────────────────────────────►

Agent A: [1.1 BtContext]──►[1.2 BtRunner]─────────────►[3.1 Executor]──►┐
              │                                                         │
              │ 接口定义完成                                              │
              ▼                                                         │
Agent B: [1.3 评估]──►[2.1~2.8 叶子节点实现]──────────►[3.2 BtTickSystem]┤
                                                                        │
                                                                        ▼
                                                              [Part 4 验证]
```

#### 同步点

| 同步点 | 触发条件 | 说明 |
|--------|----------|------|
| **Sync 1** | Agent A 完成 1.1 BtContext | Agent B 开始实现叶子节点（需要 BtContext 接口） |
| **Sync 2** | Agent A、B 都完成 Part 1+2 | 两个 Agent 同时进入 Part 3 |
| **Sync 3** | Agent A、B 都完成 Part 3 | 合并代码，进入 Part 4 验证 |

#### Agent A 详细任务

```
Phase 1: 核心基础设施
├─ 1.1 实现 BtContext
│   ├─ 文件: bt/context/context.go
│   ├─ 内容: Scene、EntityID、Blackboard、组件缓存
│   └─ 输出: BtContext 接口定义 ──► 通知 Agent B
│
└─ 1.2 实现 BtRunner
    ├─ 文件: bt/runner/runner.go
    ├─ 内容: 树注册、实例管理、Run/Stop/Tick
    └─ 依赖: BtContext

Phase 2: 系统集成
└─ 3.1 修改 Executor
    ├─ 文件: decision/executor.go
    ├─ 内容: 添加 btRunner、TransitionTo 逻辑
    └─ 依赖: BtRunner
```

#### Agent B 详细任务

```
Phase 1: 评估与准备
└─ 1.3 评估现有 bt/ 代码
    ├─ 确认 BtNodeStatus、BtNodeType 可复用
    └─ 输出: 复用清单

Phase 2: 叶子节点实现（等待 Sync 1）
├─ 2.1 MoveToNode      (bt/nodes/move_to.go)
├─ 2.2 WaitNode        (bt/nodes/wait.go)
├─ 2.3 StopMoveNode    (bt/nodes/stop_move.go)
├─ 2.4 SetFeatureNode  (bt/nodes/set_feature.go)
├─ 2.5 CheckConditionNode (bt/nodes/check_condition.go)
├─ 2.6 LogNode         (bt/nodes/log.go)
├─ 2.7 LookAtNode      (bt/nodes/look_at.go)
└─ 2.8 SetBlackboardNode (bt/nodes/set_blackboard.go)

Phase 3: 系统集成
└─ 3.2 新增 BtTickSystem
    ├─ 文件: decision/bt_tick_system.go
    ├─ 内容: 遍历运行中的树、调用 Tick、处理完成回调
    └─ 依赖: BtRunner、叶子节点
```

#### 接口契约（Agent 间共享）

Agent A 完成 1.1 后需提供的接口定义：

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

type BtNodeStatus int
const (
    BtNodeStatusInit BtNodeStatus = iota
    BtNodeStatusRunning
    BtNodeStatusSuccess
    BtNodeStatusFailed
)
```

### 建议执行顺序

1. **Part 0** ✅ 已完成 - 设计决策已确认
2. **Part 1** - Agent A、B 并行启动
   - Agent A: 1.1 → 1.2
   - Agent B: 1.3（同时进行）
3. **Sync 1** - Agent A 完成 1.1 后，Agent B 开始 Part 2
4. **Part 2 + Part 1.2** - 并行进行
5. **Sync 2** - 等待 Part 1、2 全部完成
6. **Part 3** - Agent A、B 并行进行集成
7. **Sync 3** - 合并代码
8. **Part 4** - 共同验证
9. **Part 5** - 根据需求决定是否实施

## 八、待确认问题

### 8.1 行为树与 Plan 的关系 ✅ 已确认

**选择方案**：一个 Plan = 一棵完整行为树，Entry/Exit 通过节点生命周期处理

**决策理由**：
1. 项目中的 Exit 行为都是简单状态重置（停止移动、清变量），节点的 `OnExit` 足够处理
2. 结构更简单，不需要额外的转移状态机
3. 一棵树管理整个 Plan 生命周期，逻辑更内聚

**Plan 结构映射**：
```
Plan "work"  ──→  BehaviorTree "work"
                  ├─ Sequence
                  │   ├─ [Entry 逻辑]     ← 节点 OnEnter 处理
                  │   │   └─ Log("开始工作")
                  │   │
                  │   └─ [Main 逻辑]      ← 主行为循环
                  │       └─ Repeat
                  │           └─ Sequence
                  │               ├─ MoveTo(workbench)
                  │               └─ PlayAnimation("working")
                  │
                  └─ [Exit 由各节点 OnExit 处理，不需要显式节点]
```

**Plan 转移流程**：
```
Plan A 运行中 ──► 转移触发 ──► Plan B 运行中

执行顺序：
1. Stop 行为树 A
   └─ 各节点的 OnExit 被调用（停止移动、清状态）
2. Start 行为树 B
   └─ 根节点的 OnEnter 开始执行
```

**Executor 转移逻辑示意**：
```go
func (e *Executor) TransitionTo(entityID uint64, fromPlan, toPlan string) {
    // 1. 停止当前行为树（触发各节点 OnExit）
    e.btRunner.Stop(entityID)

    // 2. 启动新 Plan 的行为树
    e.btRunner.Run(toPlan, entityID)
}
```

**节点 OnExit 处理示例**：
```go
func (n *MoveToNode) OnExit(ctx *BtContext) {
    // 简单状态重置，同步完成
    ctx.GetMoveComp().StopMove()
}

func (n *PlayAnimationNode) OnExit(ctx *BtContext) {
    // 停止动画播放
    ctx.GetAnimComp().Stop()
}
```

---

### 8.2 行为树完成后的处理 ✅ 已确认

**选择方案**：自动触发决策层重新评估（作为默认行为）

**决策理由**：
1. 避免 NPC "发呆"：行为树完成说明当前 Plan 已执行完毕，应该立即决定下一步
2. 与 GSS Brain 的设计理念一致：Brain 负责"决定做什么"，行为树负责"如何做"
3. 简化状态管理：不需要额外的 idle 状态处理

**特殊场景处理**：
对于"执行完后应该等待"的场景，通过行为树本身的设计解决：

```go
// 方案1：使用 Repeat 节点，行为树永不结束
BehaviorTree "wait_customer":
  Repeat(forever)
    Sequence
      CheckCondition("has_customer", false)
      Wait(1000)

// 方案2：在行为树末尾加 WaitForever 节点
BehaviorTree "idle":
  Sequence
    PlayAnimation("idle")
    WaitForever()  // 永不返回 Success，直到被打断
```

**实现示意**：
```go
func (s *BtTickSystem) onTreeCompleted(entityID uint64, status BtNodeStatus) {
    // 行为树完成后，通知决策层重新评估
    decisionComp := s.getDecisionComp(entityID)
    if decisionComp != nil {
        decisionComp.RequestEvaluation()  // 触发 GSS Brain 重新评估
    }
}
```

---

### 8.3 现有 bt/ 代码的复用程度 ✅ 已确认

**选择方案**：重新设计接口，复用枚举值和基础概念

**现状分析**：
- `BTXContext` 只有一个 `NowTask int32` 字段，过于简陋
- `node_control.go` 和 `node_decorator.go` 都是空文件
- 现有接口冗余：`Begin/End/Tick/Execute` 和 `ControlTick/ActionTick` 两套方法
- 基本上只是一个骨架，没有实际业务实现

**决策理由**：
1. 现有代码基本是空壳，复用价值有限
2. 重新设计可以避免接口冗余，更清晰
3. 不会有兼容性负担（没有业务代码在用）

**新接口设计**：
```go
// 简化的节点接口
type IBtNode interface {
    // 核心方法
    OnEnter(ctx *BtContext) BtNodeStatus   // 进入节点时调用
    OnTick(ctx *BtContext) BtNodeStatus    // 每帧调用
    OnExit(ctx *BtContext)                 // 退出节点时调用

    // 状态查询
    Status() BtNodeStatus
    Reset()

    // 结构查询
    Children() []IBtNode
    NodeType() BtNodeType
}

// 丰富的上下文
type BtContext struct {
    Scene      common.Scene
    EntityID   uint64
    Blackboard map[string]any
    DeltaTime  float32

    // 组件缓存（懒加载）
    moveComp     *cnpc.NpcMoveComp
    decisionComp *caidecision.DecisionComp
    // ...
}
```

**复用清单**：
| 复用 | 不复用 |
|------|--------|
| `BtNodeStatus` 枚举值 | `IBtNode` 接口（重新设计） |
| `BtNodeType` 枚举值 | `BTXContext`（重新设计） |
| `BaseBtNode` 的状态管理逻辑 | `ControlTick/ActionTick` 方法 |

---

### 8.4 配置驱动的优先级 ✅ 已确认

**选择方案**：先实现代码定义，后续再加配置驱动（Part 5 可选实施）

**决策理由**：
1. 先验证核心流程正确性，再考虑配置化
2. 如果行为树数量不多（<20），可以不做配置驱动
3. 配置驱动的详细设计已在第六章记录，随时可以实施

## 九、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 行为树 Tick 性能开销 | 大量 NPC 时可能影响帧率 | 分帧处理、限制同时运行数量 |
| 与现有系统的兼容性 | 可能影响已有 NPC 行为 | 渐进式迁移、充分测试 |
| 调试困难 | 行为树状态难以追踪 | 添加日志节点、可视化工具 |

## 十、相关文件

| 类型 | 路径 |
|------|------|
| 现有行为树 | `/servers/scene_server/internal/common/ai/bt/` |
| 决策系统 | `/servers/scene_server/internal/common/ai/decision/` |
| Executor | `/servers/scene_server/internal/ecs/system/decision/executor.go` |
| DecisionComp | `/servers/scene_server/internal/ecs/com/caidecision/decision.go` |
| NpcMoveComp | `/servers/scene_server/internal/ecs/com/cnpc/npc_move.go` |
| DialogComp | `/servers/scene_server/internal/ecs/com/cdialog/dialog.go` |

---

## 十一、已知问题与教训

### 11.1 JSON 配置与代码实现不一致问题 [已解决]

**发现时间**: 2026-02-05
**解决时间**: 2026-02-05

**问题描述**:

JSON 配置文件（如 `bt_idle.json`）中使用了三阶段结构：
```json
{
  "name": "idle",
  "blackboard": { ... },
  "on_entry": { ... },   // 曾经未被代码处理
  "root": { ... },
  "on_exit": { ... }      // 曾经未被代码处理
}
```

**解决方案**:
已实现完整的三阶段支持，详见 11.2 节。

**教训**:
1. **配置先行原则**：先定义完整的配置结构，再实现代码
2. **代码-配置一致性**：代码中的结构体字段必须与 JSON 配置字段一一对应
3. **明确标注实现状态**：文档中应明确标注哪些功能已实现、哪些是待实现
4. **添加配置验证**：加载配置时应检查未知字段并警告

### 11.2 三阶段生命周期支持

**当前状态**: ✅ 已实现 (2026-02-05)

**设计意图**:
- `on_entry`: 行为树开始时执行一次（初始化）
- `root`: 主循环逻辑（持续执行）
- `on_exit`: 行为树结束时执行一次（清理）

**已实现的修改**:

1. 修改 `config/types.go`:
```go
type BTreeConfig struct {
    Name        string                     `json:"name"`
    Description string                     `json:"description,omitempty"`
    Blackboard  map[string]BlackboardValue `json:"blackboard,omitempty"`
    OnEntry     *NodeConfig                `json:"on_entry,omitempty"`
    Root        NodeConfig                 `json:"root"`
    OnExit      *NodeConfig                `json:"on_exit,omitempty"`
}
```

2. 修改 `config/loader.go`:
   - `LoadedTree` 结构体新增 `OnEntry` 和 `OnExit` 字段
   - `LoadFromJSON` 构建三棵子树

3. 修改 `runner/runner.go`:
   - 新增 `TreePhase` 枚举：`TreePhase_OnEntry`, `TreePhase_Root`, `TreePhase_OnExit`, `TreePhase_Done`
   - 新增 `TreeTemplate` 结构体存储三阶段模板
   - `RegisterTreeWithPhases` 支持三阶段注册
   - `Tick` 方法按阶段执行

4. 修改 `executor.go`:
   - 新增 `RegisterBehaviorTreeWithPhases` 函数

5. 修改 `trees/example_trees.go`:
   - 新增 `RegisterTreesFromConfigWithPhases` 支持三阶段注册

**执行流程**:
```
OnEntry (成功) → Root (循环) → OnExit (清理) → Done
    ↓ (失败)
   Done (失败状态)
```

### 11.3 配置验证建议

建议在 `BTreeLoader.LoadFromJSON` 中添加未知字段检查：

```go
func (l *BTreeLoader) LoadFromJSON(data []byte) (*BTreeConfig, node.IBtNode, error) {
    // 检查是否有未处理的字段
    var rawMap map[string]json.RawMessage
    json.Unmarshal(data, &rawMap)

    knownFields := map[string]bool{
        "name": true, "description": true, "blackboard": true, "root": true,
    }
    for key := range rawMap {
        if !knownFields[key] {
            log.Warningf("[BTreeLoader] unknown field '%s' in config, will be ignored", key)
        }
    }

    // ... 正常加载逻辑
}
```

### 11.4 Plan 转换时的 on_exit 子树执行问题

**发现时间**: 2026-02-06
**完成时间**: 2026-02-06
**状态**: ✅ 已实现

#### 问题描述

当前实现中，Plan 转换时（从 Plan A 切换到 Plan B）不会执行前一个 Plan 的 `on_exit` 子树：

| 场景 | 节点级 OnExit() | 子树级 on_exit |
|------|----------------|----------------|
| Root 正常完成 | ✅ 调用 | ✅ 执行 |
| Plan 转换（Stop） | ✅ 调用 | ❌ 不执行 |
| on_entry 失败 | ✅ 调用 | ❌ 不执行 |

这意味着如果 `on_exit` 子树中定义了重要的清理动作（如播放动画、发送事件），在 Plan 转换时会被跳过。

#### 当前代码流程

```
Plan A (running) → Plan B 转换触发
    │
    ├── executor.OnPlanCreated(Plan B)
    │     │
    │     └── btRunner.Run(Plan B, entityID)
    │           │
    │           └── if exists r.runningTrees[entityID]:
    │                   r.Stop(entityID)  ← 直接停止，不执行 on_exit 子树
    │
    └── Plan B 启动
```

`Stop()` 方法当前实现（runner.go:210-228）：
```go
func (r *BtRunner) Stop(entityID uint64) {
    instance, ok := r.runningTrees[entityID]
    if !ok {
        return
    }

    // 只调用节点级 OnExit
    if instance.OnEntry != nil {
        r.stopNode(instance.OnEntry, instance.Context)
    }
    r.stopNode(instance.Root, instance.Context)
    // 注意：OnExit 子树不会被执行

    delete(r.runningTrees, entityID)
}
```

#### 设计目标

实现**优雅过渡**：Plan 转换时，先执行当前 Plan 的 `on_exit` 子树，完成后再启动新 Plan。

#### 设计方案

**方案：异步 on_exit + 排队机制**

```
Plan A (running) → Plan B 转换触发
    │
    ├── 中断 Plan A 的 root 阶段
    │     └── 调用节点级 OnExit() 清理状态
    │
    ├── 进入 Plan A 的 on_exit 阶段（异步执行）
    │     └── 设置 pendingPlan = Plan B
    │
    ├── BtTickSystem 继续 tick on_exit 子树
    │
    └── on_exit 完成后
          └── 自动启动 pendingPlan (Plan B)
```

**TreeInstance 结构修改**：

```go
type TreeInstance struct {
    PlanName    string
    OnEntry     node.IBtNode
    Root        node.IBtNode
    OnExit      node.IBtNode
    Context     *context.BtContext
    Status      node.BtNodeStatus
    Phase       TreePhase
    StartTime   int64
    PendingPlan string  // 新增：等待执行的下一个 Plan
}
```

**执行流程变更**：

1. `Run()` 检测到已有运行中的树时：
   - 如果当前树有 `on_exit` 子树且不在 `TreePhase_OnExit` 阶段：
     - 中断 `root` 阶段（调用节点级 OnExit）
     - 切换到 `TreePhase_OnExit` 阶段
     - 设置 `PendingPlan` 为新 Plan 名称
     - **不立即启动新 Plan**
   - 如果当前树没有 `on_exit` 子树或已在退出阶段：
     - 直接 Stop 并启动新 Plan（当前行为）

2. `Tick()` 中 `on_exit` 完成后：
   - 检查 `PendingPlan` 是否有值
   - 如果有，自动启动 PendingPlan
   - 清理当前实例

**新增方法**：

```go
// GracefulTransition 优雅过渡到新 Plan
// 会先执行当前 Plan 的 on_exit 子树，完成后再启动新 Plan
func (r *BtRunner) GracefulTransition(entityID uint64, newPlanName string) error {
    instance, exists := r.runningTrees[entityID]
    if !exists {
        // 没有运行中的树，直接启动新 Plan
        return r.Run(newPlanName, entityID)
    }

    // 检查新 Plan 是否存在
    if _, ok := r.trees[newPlanName]; !ok {
        return ErrTreeNotFound
    }

    // 如果没有 on_exit 子树，直接切换
    if instance.OnExit == nil {
        r.Stop(entityID)
        return r.Run(newPlanName, entityID)
    }

    // 如果已经在 on_exit 阶段，更新 PendingPlan
    if instance.Phase == TreePhase_OnExit {
        instance.PendingPlan = newPlanName
        return nil
    }

    // 中断当前阶段，进入 on_exit
    r.interruptCurrentPhase(instance)
    instance.OnExit.Reset()
    instance.Phase = TreePhase_OnExit
    instance.PendingPlan = newPlanName

    return nil
}

// interruptCurrentPhase 中断当前阶段（调用节点级 OnExit）
func (r *BtRunner) interruptCurrentPhase(instance *TreeInstance) {
    switch instance.Phase {
    case TreePhase_OnEntry:
        r.stopNode(instance.OnEntry, instance.Context)
    case TreePhase_Root:
        r.stopNode(instance.Root, instance.Context)
    }
}
```

**Tick() 修改**：

```go
case TreePhase_OnExit:
    status := r.tickNode(instance.OnExit, instance.Context)
    if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
        instance.Phase = TreePhase_Done

        // 检查是否有待启动的 Plan
        if instance.PendingPlan != "" {
            pendingPlan := instance.PendingPlan
            // 清理当前实例
            delete(r.runningTrees, entityID)
            // 启动新 Plan
            r.Run(pendingPlan, entityID)
            return node.BtNodeStatusRunning  // 继续运行（新树）
        }

        return instance.Status
    }
    return node.BtNodeStatusRunning
```

**Executor 修改**：

```go
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    if e.btRunner != nil && e.btRunner.HasTree(req.Plan.Name) {
        // 使用优雅过渡而非直接 Stop + Run
        if err := e.btRunner.GracefulTransition(uint64(req.EntityID), req.Plan.Name); err != nil {
            e.Scene.Warningf("[Executor] BT transition failed: %v", err)
            // 回退到原有逻辑
        } else {
            return nil
        }
    }
    // ... 原有逻辑
}
```

#### 实现任务清单

| 序号 | 任务 | 文件 | 状态 |
|------|------|------|------|
| 11.4.1 | 修改 TreeInstance 添加 PendingPlan 字段 | `runner/runner.go` | ✅ 已完成 |
| 11.4.2 | 实现 GracefulTransition 方法 | `runner/runner.go` | ✅ 已完成 |
| 11.4.3 | 实现 interruptCurrentPhase 方法 | `runner/runner.go` | ✅ 已完成 |
| 11.4.4 | 修改 Tick() 支持 PendingPlan | `runner/runner.go` | ✅ 已完成 |
| 11.4.5 | 修改 Executor.OnPlanCreated 使用 GracefulTransition | `executor.go` | ✅ 已完成 |
| 11.4.6 | 添加单元测试 | `runner/runner_test.go` | ✅ 已完成 |
| 11.4.7 | 更新 behavior-tree.md 文档 | `.claude/rules/behavior-tree.md` | ✅ 已完成 |

#### 验收标准

- [x] Plan 转换时，on_exit 子树被执行
- [x] on_exit 执行完成后，新 Plan 自动启动
- [x] 如果在 on_exit 执行期间又有新的 Plan 转换，PendingPlan 被更新为最新的 Plan
- [x] 没有 on_exit 子树的 Plan 保持原有快速切换行为
- [x] 所有现有测试通过
- [x] 新增测试覆盖优雅过渡场景

#### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| on_exit 执行期间又触发新的 Plan 转换 | 更新 PendingPlan 为最新 Plan，on_exit 继续执行 |
| on_exit 执行失败 | 仍然启动 PendingPlan（on_exit 失败不阻止转换） |
| PendingPlan 对应的行为树不存在 | 记录错误日志，不启动新树 |
| 实体被销毁时正在执行 on_exit | Stop() 强制清理，不执行 PendingPlan |
