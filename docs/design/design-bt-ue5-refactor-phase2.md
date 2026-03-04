# 设计文档：基于 UE5 设计思想的行为树重构（第二期）

## 1. 概述

### 1.1 背景

第一期已完成：
- 节点实例隔离（深拷贝，每次 Run 从 config 重建）
- 基础 Decorator（Inverter / Repeater / Timeout / Cooldown）
- 行为节点拆解为原子 JSON 组合
- 36 个 JSON 树全部重写

第二期目标：引入 UE5 行为树的**核心运行时机制**，使行为树从"一次性执行序列"升级为"响应式持续运行系统"。

### 1.2 范围（第二期）

| PR | 特性 | 说明 |
|----|------|------|
| PR 1 | 基础设施扩展 | JSON 格式扩展、接口定义、Blackboard Observer |
| PR 2 | Decorator Abort | BlackboardDecorator + 条件中断机制 |
| PR 3 | Service 节点 | 附加在 Composite 上的周期性后台任务 |
| PR 4 | Simple Parallel + SubTree | 并行执行 + 子树引用 |
| PR 5 | 事件驱动评估 + JSON 全量重写 | 黑板变更触发重评估，所有树利用新特性 |

### 1.3 UE5 行为树核心概念映射

```
UE5 概念                    当前系统                    第二期目标
─────────────────────────────────────────────────────────────────
Composite (Sequence/        SequenceNode/               保留，增强 abort 支持
  Selector)                 SelectorNode

Decorator (条件+中断)       Inverter/Repeater/          新增 BlackboardDecorator
                            Timeout/Cooldown            + AbortType 中断机制

Service (周期后台)          不存在                      新增 IService 接口
                                                        + 附加到 Composite

Task (多帧叶子)             叶子节点（支持 Running）    保留（第一期已解决）

Simple Parallel             不存在                      新增 SimpleParallelNode

SubTree                     不存在                      新增 SubTreeNode

Event-Driven                每帧 Tick 轮询              Blackboard Observer
                                                        + 脏标记重评估
```

---

## 2. JSON 格式扩展

### 2.1 新增字段

在 `NodeConfig` 中新增 `decorators` 和 `services` 两个可选数组字段：

```json
{
  "type": "Selector",
  "decorators": [
    {
      "type": "BlackboardCheck",
      "params": {"key": "has_target", "operator": "==", "value": true},
      "abort_type": "lower_priority"
    }
  ],
  "services": [
    {
      "type": "UpdateTargetDistance",
      "params": {"interval_ms": 500, "output_key": "target_dist"}
    }
  ],
  "children": [...]
}
```

### 2.2 向后兼容

- `decorators` 和 `services` 均为可选字段（`omitempty`）
- 不含这两个字段的旧 JSON 树行为完全不变
- 第一期的所有 JSON 树无需立即修改

### 2.3 NodeConfig 变更

```go
// config/types.go

type NodeConfig struct {
    Type       string            `json:"type"`
    Params     map[string]any    `json:"params,omitempty"`
    Children   []NodeConfig      `json:"children,omitempty"`
    Child      *NodeConfig       `json:"child,omitempty"`
    Decorators []DecoratorConfig `json:"decorators,omitempty"` // NEW
    Services   []ServiceConfig   `json:"services,omitempty"`   // NEW
}

// DecoratorConfig 装饰器配置
type DecoratorConfig struct {
    Type      string         `json:"type"`                // 装饰器类型名
    Params    map[string]any `json:"params,omitempty"`    // 参数
    AbortType string         `json:"abort_type,omitempty"` // none/self/lower_priority/both
}

// ServiceConfig 服务配置
type ServiceConfig struct {
    Type   string         `json:"type"`             // 服务类型名
    Params map[string]any `json:"params,omitempty"` // 参数（含 interval_ms）
}
```

### 2.4 完整 JSON 示例（利用所有新特性）

```json
{
  "name": "pursuit_main_v2",
  "description": "NPC 追捕 - 使用 UE5 风格的 Decorator Abort + Service",
  "root": {
    "type": "Selector",
    "services": [
      {
        "type": "SyncFeatureToBlackboardService",
        "params": {
          "interval_ms": 200,
          "mappings": {"feature_pursuit_entity_id": "target_entity_id"}
        }
      }
    ],
    "children": [
      {
        "type": "Sequence",
        "decorators": [
          {
            "type": "BlackboardCheck",
            "params": {"key": "target_entity_id", "operator": "!=", "value": 0},
            "abort_type": "both"
          }
        ],
        "children": [
          {"type": "SetTargetEntity", "params": {"entity_id_key": "target_entity_id"}},
          {"type": "MoveTo", "params": {"target_key": "target_pos"}}
        ]
      },
      {
        "type": "Sequence",
        "children": [
          {"type": "Log", "params": {"message": "target lost, returning", "level": "info"}},
          {"type": "SubTree", "params": {"tree_name": "return_to_schedule"}}
        ]
      }
    ]
  }
}
```

---

## 3. 核心接口设计

### 3.1 FlowAbortMode（中断模式）

```go
// node/abort.go (新文件)

// FlowAbortMode UE5 风格的中断模式
type FlowAbortMode int

const (
    // FlowAbortNone 无中断（默认，兼容现有行为）
    FlowAbortNone FlowAbortMode = iota

    // FlowAbortSelf 自中断
    // 当装饰器条件变为 false 时，中断自身所在的子树
    // 用途：正在执行的行为的前置条件不再满足时中止
    FlowAbortSelf

    // FlowAbortLowerPriority 低优先级中断
    // 当装饰器条件变为 true 时，中断 Selector 中更低优先级的正在执行的子树
    // 用途：更高优先级行为的条件满足时，抢占当前低优先级行为
    FlowAbortLowerPriority

    // FlowAbortBoth 双向中断（Self + LowerPriority）
    FlowAbortBoth
)

func ParseFlowAbortMode(s string) FlowAbortMode {
    switch s {
    case "self":
        return FlowAbortSelf
    case "lower_priority":
        return FlowAbortLowerPriority
    case "both":
        return FlowAbortBoth
    default:
        return FlowAbortNone
    }
}
```

### 3.2 IConditionalDecorator（条件装饰器接口）

```go
// node/decorator.go (新文件)

// IConditionalDecorator 条件装饰器接口
// 附加在节点上，由父 Composite 在 Tick 前评估
type IConditionalDecorator interface {
    // Evaluate 评估条件是否满足
    Evaluate(ctx *context.BtContext) bool

    // AbortType 获取中断模式
    AbortType() FlowAbortMode

    // ObservedKeys 返回观察的 Blackboard key 列表（事件驱动用）
    ObservedKeys() []string
}
```

### 3.3 IService（服务接口）

```go
// node/service.go (新文件)

// IService 服务接口
// 附加在 Composite 节点上，当 Composite 处于活跃状态时周期性执行
// UE5 中用于更新 Blackboard 值（感知、目标选择等）
type IService interface {
    // OnActivate 服务激活时调用（Composite 开始执行时）
    OnActivate(ctx *context.BtContext)

    // OnTick 周期性调用（按 IntervalMs 间隔）
    OnTick(ctx *context.BtContext)

    // OnDeactivate 服务停用时调用（Composite 退出时）
    OnDeactivate(ctx *context.BtContext)

    // IntervalMs 获取调用间隔（毫秒）
    IntervalMs() int64
}
```

### 3.4 IBtNode 接口扩展

```go
// node/interface.go — 扩展 IBtNode

type IBtNode interface {
    // --- 现有方法（不变）---
    OnEnter(ctx *context.BtContext) BtNodeStatus
    OnTick(ctx *context.BtContext) BtNodeStatus
    OnExit(ctx *context.BtContext)
    Status() BtNodeStatus
    Reset()
    Children() []IBtNode
    NodeType() BtNodeType

    // --- 新增方法 ---

    // Decorators 获取附加的条件装饰器列表
    Decorators() []IConditionalDecorator

    // Services 获取附加的服务列表（仅 Composite 有意义）
    Services() []IService
}
```

`BaseNode` 提供默认空实现（返回 nil slice），不影响现有节点。

### 3.5 TreeInstance 扩展

```go
// runner/runner.go — TreeInstance 扩展

type TreeInstance struct {
    // --- 现有字段 ---
    TreeName  string
    Root      node.IBtNode
    Context   *context.BtContext
    Status    node.BtNodeStatus
    StartTime int64

    // --- 新增字段 ---

    // ActiveServices 当前活跃的 Service 实例（含上次 Tick 时间）
    ActiveServices []activeService

    // DirtyKeys 自上次 Tick 以来发生变化的 Blackboard key（事件驱动用）
    DirtyKeys map[string]struct{}
}

type activeService struct {
    Service    node.IService
    LastTickMs int64 // 上次调用时间戳
}
```

---

## 4. PR 1：基础设施扩展

### 4.1 变更清单

| 文件 | 变更 |
|------|------|
| `node/abort.go` | **新增** FlowAbortMode 类型和解析函数 |
| `node/decorator.go` | **新增** IConditionalDecorator 接口 |
| `node/service.go` | **新增** IService 接口 |
| `node/interface.go` | 扩展 IBtNode（新增 Decorators/Services 方法） |
| `config/types.go` | 新增 DecoratorConfig / ServiceConfig |
| `config/loader.go` | 解析 decorators / services 字段 |
| `context/context.go` | 新增 Blackboard Observer 机制 |

### 4.2 Blackboard Observer（BtContext 扩展）

```go
// context/context.go 新增

// BlackboardObserver 黑板观察者
type BlackboardObserver struct {
    Key      string
    Callback func(key string, oldVal, newVal any)
}

type BtContext struct {
    // ... 现有字段

    // 观察者列表
    observers []BlackboardObserver

    // 脏标记（事件驱动用，PR 5 完善）
    dirtyKeys map[string]struct{}
}

// SetBlackboard 设置黑板数据（增强版：触发观察者通知）
func (c *BtContext) SetBlackboard(key string, value any) {
    oldVal, _ := c.Blackboard[key]
    c.Blackboard[key] = value

    // 标记脏 key
    if c.dirtyKeys == nil {
        c.dirtyKeys = make(map[string]struct{})
    }
    c.dirtyKeys[key] = struct{}{}

    // 通知观察者
    for _, obs := range c.observers {
        if obs.Key == key {
            obs.Callback(key, oldVal, value)
        }
    }
}

// AddObserver 注册 Blackboard 观察者
func (c *BtContext) AddObserver(key string, cb func(string, any, any)) {
    c.observers = append(c.observers, BlackboardObserver{Key: key, Callback: cb})
}

// RemoveObservers 移除所有观察者（树停止时调用）
func (c *BtContext) RemoveObservers() {
    c.observers = c.observers[:0]
}

// ConsumeDirtyKeys 获取并清空脏 key（BtRunner.Tick 开始时调用）
func (c *BtContext) ConsumeDirtyKeys() map[string]struct{} {
    dirty := c.dirtyKeys
    c.dirtyKeys = nil
    return dirty
}
```

### 4.3 BTreeLoader 扩展

```go
// config/loader.go — BuildNode 扩展

func (l *BTreeLoader) BuildNode(cfg *NodeConfig) (node.IBtNode, error) {
    // 1. 创建节点（现有逻辑不变）
    n, err := l.factory.Create(cfg)
    // ... 处理 children / child

    // 2. 解析并附加 Decorators（NEW）
    for _, decCfg := range cfg.Decorators {
        decorator, err := l.factory.CreateDecorator(&decCfg)
        if err != nil {
            return nil, fmt.Errorf("create decorator '%s' failed: %w", decCfg.Type, err)
        }
        n.AddDecorator(decorator)
    }

    // 3. 解析并附加 Services（NEW）
    for _, svcCfg := range cfg.Services {
        service, err := l.factory.CreateService(&svcCfg)
        if err != nil {
            return nil, fmt.Errorf("create service '%s' failed: %w", svcCfg.Type, err)
        }
        n.AddService(service)
    }

    return n, nil
}
```

### 4.4 NodeFactory 扩展

```go
// config/loader.go — NodeFactory 接口扩展

type NodeFactory interface {
    Create(cfg *NodeConfig) (node.IBtNode, error)
    HasCreator(nodeType string) bool

    // NEW
    CreateDecorator(cfg *DecoratorConfig) (node.IConditionalDecorator, error)
    CreateService(cfg *ServiceConfig) (node.IService, error)
}
```

---

## 5. PR 2：Decorator Abort 系统

### 5.1 核心机制

UE5 的 Decorator Abort 工作原理：

```
Selector
├── [0] Sequence (优先级高)
│   ├── decorators: [BlackboardCheck(key="has_target", abort=lower_priority)]
│   └── children: [ChaseTarget, ...]
│
├── [1] Sequence (优先级低，当前正在执行)
│   └── children: [Patrol, ...]

执行流程：
1. NPC 正在巡逻（Selector child[1] running）
2. Blackboard "has_target" 变为 true
3. Selector 重新评估 child[0] 的 decorator
4. child[0] decorator 返回 true → abort_type=lower_priority
5. 中断 child[1]（调用 OnExit 清理）
6. 启动 child[0]（调用 OnEnter）
```

### 5.2 BlackboardCheckDecorator

```go
// nodes/blackboard_decorator.go (新文件)

// BlackboardCheckDecorator 黑板条件检查装饰器
// UE5 中最常用的 Decorator，检查 Blackboard key 的值
type BlackboardCheckDecorator struct {
    key       string        // 观察的 Blackboard key
    operator  Operator      // 比较运算符
    value     any           // 比较值
    abortType node.FlowAbortMode
}

func (d *BlackboardCheckDecorator) Evaluate(ctx *context.BtContext) bool {
    val, ok := ctx.GetBlackboard(d.key)
    if !ok {
        // key 不存在：IsSet 类检查返回 false，NotSet 类返回 true
        return d.operator == "not_set"
    }
    return compareValues(val, d.operator, d.value)
}

func (d *BlackboardCheckDecorator) AbortType() node.FlowAbortMode {
    return d.abortType
}

func (d *BlackboardCheckDecorator) ObservedKeys() []string {
    return []string{d.key}
}
```

**JSON 格式**：
```json
{
  "type": "BlackboardCheck",
  "params": {
    "key": "has_target",
    "operator": "==",
    "value": true
  },
  "abort_type": "lower_priority"
}
```

**支持的 operator**：
- `==`, `!=`, `>`, `<`, `>=`, `<=`
- `is_set`（key 存在）
- `not_set`（key 不存在）

### 5.3 FeatureCheckDecorator

```go
// nodes/feature_decorator.go (新文件)

// FeatureCheckDecorator Feature 值条件检查装饰器
// 与 BlackboardCheck 类似，但检查 Feature 值而非 Blackboard
type FeatureCheckDecorator struct {
    featureKey string
    operator   Operator
    value      any
    abortType  node.FlowAbortMode
}

func (d *FeatureCheckDecorator) Evaluate(ctx *context.BtContext) bool {
    val, ok := ctx.GetFeatureValue(d.featureKey)
    if !ok {
        return d.operator == "not_set"
    }
    return compareValues(val, d.operator, d.value)
}
```

**JSON 格式**：
```json
{
  "type": "FeatureCheck",
  "params": {
    "feature_key": "feature_pursuit_entity_id",
    "operator": "!=",
    "value": 0
  },
  "abort_type": "self"
}
```

### 5.4 Selector 增强（支持 LowerPriority Abort）

```go
// nodes/selector.go — 增强版

func (n *SelectorNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    children := n.Children()

    // ===== NEW: Abort 评估 =====
    // 检查比当前活跃子节点优先级更高的子节点的 decorator
    if n.currentIndex > 0 {
        for i := 0; i < n.currentIndex; i++ {
            child := children[i]
            if n.shouldAbortForChild(child, ctx) {
                // 中断当前活跃子树
                n.abortCurrentChild(ctx)
                // 重置到更高优先级子节点
                n.currentIndex = i
                break
            }
        }
    }
    // ===== END NEW =====

    // ... 现有 Tick 逻辑（不变）
}

// shouldAbortForChild 检查子节点的 decorator 是否触发 LowerPriority abort
func (n *SelectorNode) shouldAbortForChild(child node.IBtNode, ctx *context.BtContext) bool {
    for _, dec := range child.Decorators() {
        abortType := dec.AbortType()
        if abortType == node.FlowAbortLowerPriority || abortType == node.FlowAbortBoth {
            if dec.Evaluate(ctx) {
                return true
            }
        }
    }
    return false
}

// abortCurrentChild 中断当前活跃子节点
func (n *SelectorNode) abortCurrentChild(ctx *context.BtContext) {
    children := n.Children()
    if n.currentIndex < len(children) {
        child := children[n.currentIndex]
        if child.Status() == node.BtNodeStatusRunning {
            child.OnExit(ctx)
            child.Reset()
        }
    }
}
```

### 5.5 Sequence 增强（支持 Self Abort）

```go
// nodes/sequence.go — 增强版

func (n *SequenceNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    children := n.Children()

    // ===== NEW: Self Abort 评估 =====
    // 检查自身的 decorator 条件是否仍然满足
    for _, dec := range n.Decorators() {
        abortType := dec.AbortType()
        if abortType == node.FlowAbortSelf || abortType == node.FlowAbortBoth {
            if !dec.Evaluate(ctx) {
                // 条件不再满足，中断自身
                n.abortSelf(ctx)
                return node.BtNodeStatusFailed
            }
        }
    }
    // ===== END NEW =====

    // ... 现有 Tick 逻辑（不变）
}
```

### 5.6 Decorator 评估时序

每帧 Tick 的完整执行顺序：

```
BtRunner.Tick(entityID, dt)
    │
    ├── 1. 更新 DeltaTime
    │
    ├── 2. Tick Services（周期性后台任务，PR 3）
    │
    ├── 3. Tick Root Node
    │       │
    │       ├── Selector.OnTick()
    │       │   ├── 检查高优先级子节点的 LowerPriority decorator
    │       │   │   └── 条件满足 → abort 当前子树 → 切换到高优先级
    │       │   │
    │       │   └── 正常 Tick 当前子节点
    │       │       ├── Sequence.OnTick()
    │       │       │   ├── 检查自身的 Self decorator
    │       │       │   │   └── 条件不满足 → abort 自身 → 返回 Failed
    │       │       │   │
    │       │       │   └── 正常 Tick 子节点序列
    │       │       │
    │       │       └── LeafNode.OnTick()
    │       │
    │       └── 返回状态
    │
    └── 4. 处理完成状态
```

---

## 6. PR 3：Service 节点

### 6.1 设计思路

UE5 Service 是附加在 Composite 节点上的后台任务，在 Composite 活跃期间按固定间隔执行。典型用途：
- 更新 Blackboard 中的感知数据（目标距离、视线检查等）
- 周期性同步 Feature 到 Blackboard
- 定时执行清理或刷新操作

### 6.2 Service 生命周期

```
Composite.OnEnter()
    → 激活所有附加 Service（调用 Service.OnActivate）

Composite 每帧 Tick
    → 检查每个 Service 的 interval
    → 到期则调用 Service.OnTick()

Composite.OnExit()
    → 停用所有 Service（调用 Service.OnDeactivate）
```

### 6.3 内置 Service 实现

#### SyncFeatureToBlackboardService

周期性将 Feature 值同步到 Blackboard，替代在树开头手动调用 `SyncFeatureToBlackboard` 节点：

```go
// nodes/service_sync_feature.go

type SyncFeatureToBlackboardService struct {
    intervalMs int64
    mappings   map[string]string // featureKey -> blackboardKey
}

func (s *SyncFeatureToBlackboardService) OnActivate(ctx *context.BtContext) {
    s.OnTick(ctx) // 立即执行一次
}

func (s *SyncFeatureToBlackboardService) OnTick(ctx *context.BtContext) {
    for featureKey, bbKey := range s.mappings {
        if val, ok := ctx.GetFeatureValue(featureKey); ok {
            ctx.SetBlackboard(bbKey, val)
        }
    }
}

func (s *SyncFeatureToBlackboardService) OnDeactivate(ctx *context.BtContext) {}
func (s *SyncFeatureToBlackboardService) IntervalMs() int64 { return s.intervalMs }
```

**JSON**：
```json
{
  "type": "SyncFeatureToBlackboardService",
  "params": {
    "interval_ms": 200,
    "mappings": {"feature_pursuit_entity_id": "target_entity_id"}
  }
}
```

#### UpdateScheduleService

周期性更新日程数据到 Blackboard：

```json
{
  "type": "UpdateScheduleService",
  "params": {
    "interval_ms": 1000,
    "output_keys": {"server_timeout": "timeout", "location": "schedule_loc"}
  }
}
```

#### LogService（调试用）

```json
{
  "type": "LogService",
  "params": {
    "interval_ms": 5000,
    "message": "pursuit active",
    "level": "debug"
  }
}
```

### 6.4 Composite 节点集成

Sequence 和 Selector 需要管理 Service 生命周期：

```go
// nodes/sequence.go — Service 支持

func (n *SequenceNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // ... 现有逻辑

    // NEW: 激活 Services
    for _, svc := range n.Services() {
        svc.OnActivate(ctx)
    }

    return node.BtNodeStatusRunning
}

func (n *SequenceNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    // NEW: Tick Services
    now := time.Now().UnixMilli()
    for i, svc := range n.activeServices {
        if now - n.serviceLastTick[i] >= svc.IntervalMs() {
            svc.OnTick(ctx)
            n.serviceLastTick[i] = now
        }
    }

    // ... 现有 Tick 逻辑
}

func (n *SequenceNode) OnExit(ctx *context.BtContext) {
    // NEW: 停用 Services
    for _, svc := range n.Services() {
        svc.OnDeactivate(ctx)
    }

    // ... 现有 OnExit 逻辑
}
```

---

## 7. PR 4：Simple Parallel + SubTree

### 7.1 SimpleParallelNode

UE5 的 Simple Parallel 同时执行两个分支：
- **主任务**（Main Task）：第一个子节点，决定整体完成时机
- **后台任务**（Background Task）：第二个子节点，在主任务期间持续运行

```go
// nodes/simple_parallel.go (新文件)

type FinishMode int
const (
    // FinishImmediately 主任务完成后立即中断后台任务
    FinishImmediately FinishMode = iota
    // FinishDelayed 主任务完成后等待后台任务也完成
    FinishDelayed
)

type SimpleParallelNode struct {
    node.BaseNode
    finishMode     FinishMode
    mainCompleted  bool
    mainStatus     node.BtNodeStatus
}

func (n *SimpleParallelNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    children := n.Children()
    main := children[0]
    bg := children[1]

    // Tick 主任务
    if !n.mainCompleted {
        mainStatus := tickChild(main, ctx)
        if mainStatus != node.BtNodeStatusRunning {
            n.mainCompleted = true
            n.mainStatus = mainStatus
        }
    }

    // Tick 后台任务
    bgStatus := tickChild(bg, ctx)

    // 完成判定
    if n.mainCompleted {
        switch n.finishMode {
        case FinishImmediately:
            // 立即中断后台
            if bgStatus == node.BtNodeStatusRunning {
                bg.OnExit(ctx)
            }
            return n.mainStatus
        case FinishDelayed:
            // 等后台也完成
            if bgStatus != node.BtNodeStatusRunning {
                return n.mainStatus
            }
        }
    }

    return node.BtNodeStatusRunning
}
```

**JSON**：
```json
{
  "type": "SimpleParallel",
  "params": {"finish_mode": "immediate"},
  "children": [
    {"type": "MoveTo", "params": {"target_key": "dest"}},
    {"type": "Repeater", "params": {"count": 0}, "child":
      {"type": "Log", "params": {"message": "still moving...", "level": "debug"}}
    }
  ]
}
```

### 7.2 SubTreeNode

引用另一棵已注册的行为树，支持复用：

```go
// nodes/subtree.go (新文件)

type SubTreeNode struct {
    node.BaseNode
    treeName string
    subRoot  node.IBtNode // Run 时从 BtRunner 获取
}

func (n *SubTreeNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 从 runner 获取子树配置并构建
    runner := ctx.GetBtRunner()
    if runner == nil {
        return node.BtNodeStatusFailed
    }

    cfg, ok := runner.GetTreeConfig(n.treeName)
    if !ok {
        return node.BtNodeStatusFailed
    }

    root, err := runner.GetLoader().BuildNode(&cfg.Root)
    if err != nil {
        return node.BtNodeStatusFailed
    }

    n.subRoot = root
    return root.OnEnter(ctx)
}

func (n *SubTreeNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    if n.subRoot == nil {
        return node.BtNodeStatusFailed
    }
    return n.subRoot.OnTick(ctx)
}

func (n *SubTreeNode) OnExit(ctx *context.BtContext) {
    if n.subRoot != nil {
        n.subRoot.OnExit(ctx)
    }
}
```

**JSON**：
```json
{"type": "SubTree", "params": {"tree_name": "return_to_schedule"}}
```

**BtContext 扩展**：需要新增 `GetBtRunner()` 方法（或将 runner 注入到 context）。

### 7.3 额外 Decorator

| 节点 | 说明 | JSON |
|------|------|------|
| ForceSuccess | 子节点无论结果都返回 Success | `{"type": "ForceSuccess", "child": {...}}` |
| ForceFailure | 子节点无论结果都返回 Failed | `{"type": "ForceFailure", "child": {...}}` |

---

## 8. PR 5：事件驱动评估 + JSON 全量重写

### 8.1 事件驱动评估

**当前问题**：每帧从 root 开始 Tick，即使没有任何状态变化也重新评估所有节点。

**UE5 方案**：只在 Blackboard key 发生变化时重新评估相关 Decorator。

**实现方案**：

```go
// runner/runner.go — Tick 增强

func (r *BtRunner) Tick(entityID uint64, deltaTime float32) node.BtNodeStatus {
    instance := r.runningTrees[entityID]
    instance.Context.DeltaTime = deltaTime

    // 1. 消费脏 key
    dirtyKeys := instance.Context.ConsumeDirtyKeys()

    // 2. 如果有脏 key，检查是否需要重新评估
    if len(dirtyKeys) > 0 {
        r.evaluateAbortConditions(instance, dirtyKeys)
    }

    // 3. Tick Services
    r.tickServices(instance)

    // 4. Tick 树
    return r.tickNode(instance.Root, instance.Context)
}

// evaluateAbortConditions 基于脏 key 评估 abort 条件
func (r *BtRunner) evaluateAbortConditions(inst *TreeInstance, dirtyKeys map[string]struct{}) {
    // 遍历树中所有 decorator
    // 只检查与 dirtyKeys 相关的 decorator
    // 如果 abort 条件满足，执行中断
    r.walkAndEvaluate(inst.Root, inst.Context, dirtyKeys)
}
```

### 8.2 优化效果

| 场景 | 当前（每帧轮询） | 优化后（事件驱动） |
|------|-----------------|-------------------|
| NPC 空闲（无状态变化） | 每帧评估整棵树 | 跳过评估，仅 Tick 活跃叶子 |
| Blackboard 变化 | 每帧评估整棵树 | 只评估关联 decorator |
| 100 NPC 场景 | 100 × 全树评估 | 只评估有变化的 NPC |

### 8.3 JSON 全量重写策略

利用第二期所有新特性，重写 36 个 JSON 树。重写原则：

1. **entry 树**：大部分保持现有 Sequence 结构（一次性初始化操作）
2. **main 树**：从空壳升级为响应式持续运行树
   - 使用 `Selector` + `BlackboardCheck decorator` 实现优先级行为
   - 使用 `Service` 持续更新 Blackboard
   - 使用 `SimpleParallel` 实现并行行为
3. **exit 树**：保持现有结构（一次性清理操作）
4. **提取公共 SubTree**：如 `return_to_schedule` 可被多个 transition 复用

#### 重写示例：pursuit_main.json

**当前**（空壳，立即完成）：
```json
{
  "name": "pursuit_main",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "Log", "params": {"message": "[PursuitMain] pursuing target", "level": "debug"}}
    ]
  }
}
```

**重写后**（响应式持续运行）：
```json
{
  "name": "pursuit_main",
  "description": "NPC 追捕 - 持续追逐目标，目标丢失时返回",
  "root": {
    "type": "Selector",
    "services": [
      {
        "type": "SyncFeatureToBlackboardService",
        "params": {
          "interval_ms": 200,
          "mappings": {
            "feature_pursuit_entity_id": "target_entity_id",
            "feature_pursuit_target_pos_x": "target_x",
            "feature_pursuit_target_pos_y": "target_y",
            "feature_pursuit_target_pos_z": "target_z"
          }
        }
      }
    ],
    "children": [
      {
        "type": "Sequence",
        "decorators": [
          {
            "type": "BlackboardCheck",
            "params": {"key": "target_entity_id", "operator": "!=", "value": 0},
            "abort_type": "both"
          }
        ],
        "children": [
          {"type": "SetTargetEntity", "params": {"entity_id_key": "target_entity_id"}},
          {"type": "MoveTo", "params": {"target_key": "target_pos"}}
        ]
      },
      {
        "type": "Sequence",
        "children": [
          {"type": "Log", "params": {"message": "[PursuitMain] target lost", "level": "info"}}
        ]
      }
    ]
  }
}
```

---

## 9. 文件改动汇总

### 新增文件

| 文件 | PR | 说明 |
|------|-----|------|
| `node/abort.go` | 1 | FlowAbortMode 类型 |
| `node/conditional_decorator.go` | 1 | IConditionalDecorator 接口 |
| `node/service_iface.go` | 1 | IService 接口 |
| `nodes/blackboard_decorator.go` | 2 | BlackboardCheckDecorator |
| `nodes/feature_decorator.go` | 2 | FeatureCheckDecorator |
| `nodes/service_sync_feature.go` | 3 | SyncFeatureToBlackboardService |
| `nodes/service_update_schedule.go` | 3 | UpdateScheduleService |
| `nodes/service_log.go` | 3 | LogService（调试） |
| `nodes/simple_parallel.go` | 4 | SimpleParallelNode |
| `nodes/subtree.go` | 4 | SubTreeNode |
| `nodes/force_decorator.go` | 4 | ForceSuccess / ForceFailure |

### 修改文件

| 文件 | PR | 说明 |
|------|-----|------|
| `node/interface.go` | 1 | IBtNode 新增 Decorators() / Services() |
| `config/types.go` | 1 | 新增 DecoratorConfig / ServiceConfig |
| `config/loader.go` | 1 | 解析 decorators / services |
| `context/context.go` | 1 | Blackboard Observer + 脏标记 |
| `nodes/factory.go` | 1-4 | 注册新节点 / 装饰器 / 服务 |
| `nodes/selector.go` | 2 | LowerPriority abort 逻辑 |
| `nodes/sequence.go` | 2,3 | Self abort + Service tick |
| `runner/runner.go` | 2,5 | TreeInstance 扩展 + 事件驱动 |
| `trees/*.json` | 5 | 全部 36 个树重写 |

### 不变的文件

- `nodes/decorator.go`（Inverter/Repeater/Timeout/Cooldown — 无需修改）
- `config/plan_config.go`（Plan 配置结构不变）
- `ecs/system/decision/executor.go`（三通道调度不变）
- `ecs/system/decision/bt_tick_system.go`（帧更新循环不变）

---

## 10. 风险与缓解

| 风险 | 严重度 | 缓解措施 |
|------|--------|----------|
| Abort 逻辑引入竞态 | 高 | 单线程执行（ECS 帧循环保证）；中断时严格调用 OnExit 清理 |
| Service 泄漏 | 中 | Service 生命周期绑定 Composite；OnExit 必须调用 OnDeactivate |
| SubTree 循环引用 | 中 | 构建时检测递归深度（最大 10 层） |
| 性能退化（Decorator 评估） | 低 | 事件驱动优化（仅脏 key 触发）；Decorator 评估是轻量比较操作 |
| JSON 格式变更 | 低 | 新字段均为 optional，旧树无需修改即可运行 |
| IBtNode 接口破坏性变更 | 中 | BaseNode 提供 Decorators()/Services() 默认空实现，现有节点零修改 |

---

## 11. 实施时间线

```
PR 1 (基础设施)
│   接口定义 + JSON 格式扩展 + Blackboard Observer
│   预计改动：~500 行新增，~100 行修改
│
├── PR 2 (Decorator Abort) ──────── 依赖 PR 1
│   BlackboardCheck + Selector/Sequence abort
│   预计改动：~600 行新增，~200 行修改
│
├── PR 3 (Service) ──────────────── 依赖 PR 1
│   Service 接口 + 3 个内置 Service
│   预计改动：~400 行新增，~150 行修改
│   （可与 PR 2 并行开发，最终合并时处理冲突）
│
└── PR 4 (Parallel + SubTree) ──── 依赖 PR 1
    SimpleParallel + SubTree + ForceSuccess/Failure
    预计改动：~500 行新增，~50 行修改
    （可与 PR 2/3 并行开发）

PR 5 (事件驱动 + JSON 重写) ──── 依赖 PR 2 + 3 + 4
    脏标记机制 + 全部 36 个 JSON 树重写
    预计改动：~200 行新增（事件驱动），~1000 行 JSON 重写
```
