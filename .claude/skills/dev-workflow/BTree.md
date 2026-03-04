# 行为树系统设计全景

> 所有代码路径均相对于 `P1GoServer/` 目录。
> 行为树代码位于 `servers/scene_server/internal/common/ai/bt/`。

---

## 一、系统定位

### 1.1 行为树在 AI 系统中的位置

```
┌─────────────────────────────────────────────────────────────┐
│                    GSS Brain (高层决策)                       │
│              负责：状态切换、条件判断、Plan 选择                │
│                                                              │
│  patrol ──(发现坏人)──> pursuit ──(丢失目标)──> investigate   │
│    ↑                                              │          │
│    └──────────────(调查无果)──────────────────────┘          │
└────────────────────────────┬────────────────────────────────┘
                             │ 产生 Plan + Tasks
                             ▼
┌─────────────────────────────────────────────────────────────┐
│               Executor (Plan 调度器)                          │
│          负责：接收 Plan，分发 Task 到行为树                   │
│          两层调度（详见第八节）                                │
└────────────────────────────┬────────────────────────────────┘
                             │ Run(treeName, entityID)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              BtRunner (行为树运行器)                           │
│         负责：管理树实例、驱动 Tick、处理 Abort                 │
└────────────────────────────┬────────────────────────────────┘
                             │ Tick → OnEnter/OnTick/OnExit
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              节点树 (Sequence/Selector/Leaf...)               │
│              负责：执行具体行为逻辑                             │
└─────────────────────────────────────────────────────────────┘
```

**职责边界**：

| 层级 | 负责 | 决策类型 | 更新频率 |
|------|------|----------|---------|
| GSS Brain | 战略决策："要追人"还是"要巡逻" | What to do | 1 秒/次 |
| Executor | 调度：把 Plan 的 Task 路由到对应行为树 | Where to route | 事件驱动 |
| BtRunner | 执行：驱动行为树 Tick，管理树的生命周期 | How to run | 每帧 |
| 节点 | 原子动作：移动、等待、设置状态 | Action | 每帧 |

### 1.2 与 UE5 行为树的关系

**骨架是 UE5，皮肤是自己的。**

UE5 行为树的核心特性全部对齐：

| UE5 特性 | 当前实现 | 说明 |
|----------|---------|------|
| Blackboard | `BtContext.Blackboard` | 共享数据存储 + 脏 key 追踪 |
| Conditional Decorator | `BlackboardCheck` / `FeatureCheck` | 条件守卫 + 运行时中断 |
| Decorator Abort | `abort_type`: none/self/lower_priority/both | 事件驱动分支切换 |
| Service | `SyncFeatureToBlackboard` / `UpdateSchedule` / `Log` | 后台周期任务 |
| SimpleParallel | `finish_mode`: immediate/delayed | 主任务 + 后台任务并行 |
| SubTree | `tree_name` 引用，最大递归 10 层 | 树复用 |
| Task 三态 | Success / Failed / Running | 异步节点支持 |

自定义扩展部分：

| 扩展 | 说明 |
|------|------|
| 长运行行为节点 | OnEnter(初始化→Running) → OnTick(保持Running) → OnExit(清理)，替代旧 entry/exit 分离 |
| 复合树模式 | Selector + Service + Decorator(abort=both)，Brain 管行为类别切换，BT 管类别内分支 |
| 两层调度 | resolveTreeName(BT层) → 硬编码回退 |
| 行为节点两层 | 策划用（NPC 语义）+ 程序员用（原子操作） |

---

## 二、执行模型：从轮询到事件驱动

这是理解整个系统最关键的一节。

### 2.1 传统行为树 vs UE5 行为树

**传统行为树**（如 libGDX AI）是轮询式的：

```
每帧：
  从根节点开始 → 遍历整棵树 → 找到应该执行的叶子 → 执行

问题：
  - 每帧都要从头跑一遍，O(n) 开销
  - 无法在子节点运行时被打断
  - 条件节点是叶子，只有轮到它才检查
```

**UE5 行为树**是事件驱动式的：

```
正常状态：
  树停在某个 Running 节点上 → 只 Tick 这个节点 → 等待完成

条件变化时：
  Blackboard 值变了 → 脏 key 通知 → Decorator 重评估 → 满足 abort 条件 → 打断当前分支 → 跳转到正确分支

优势：
  - 不需要每帧从头遍历
  - 正在运行的节点可以被主动打断
  - 响应速度 = 下一帧（不是下次遍历到这个分支）
```

### 2.2 事件驱动的完整循环

以 `pursuit.json` 为例，理解四个角色如何配合：

```
┌──────────────────────────────────────────────────────────────────┐
│ ① Service（数据生产者）                                           │
│    SyncFeatureToBlackboard 每 200ms 执行：                        │
│    Feature[feature_pursuit_entity_id] → Blackboard[target_entity_id]
│                                                                   │
│    当目标丢失时，Feature 值变为 0                                   │
│    → Blackboard["target_entity_id"] = 0                           │
│    → 标记 "target_entity_id" 为脏 key                             │
└──────────────────────────┬───────────────────────────────────────┘
                           │ 脏 key
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│ ② Runner Tick（调度者）                                           │
│    ConsumeDirtyKeys() → 拿到 {"target_entity_id"}                 │
│    SetFrameDirtyKeys() → 供本帧 Abort 评估使用                    │
│    tickNode(root) → 开始执行树                                    │
└──────────────────────────┬───────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│ ③ Decorator（条件守卫 + 打断触发器）                               │
│    BlackboardCheck(key="target_entity_id", op="!=", value=0)      │
│    abort_type = "both"                                            │
│                                                                   │
│    Selector.OnTick() 时检查：                                     │
│    - "target_entity_id" 是脏 key → 需要重评估                     │
│    - Evaluate() → target_entity_id == 0 → 条件不满足              │
│    - abort_type 包含 self → 触发 Self Abort                       │
│    - 打断当前正在运行的追逐循环子树                                 │
└──────────────────────────┬───────────────────────────────────────┘
                           │ 中断 + 分支切换
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│ ④ Composite（执行调度者）                                         │
│    Selector 发现第一个子节点（追逐分支）被 abort                    │
│    → 尝试第二个子节点（目标丢失分支）                               │
│    → Log "target lost" → 返回 Success                             │
│    → 树结束 → Runner 通知 Executor → 触发 Brain 重新决策           │
└──────────────────────────────────────────────────────────────────┘
```

**关键认识**：Decorator 和 Service 不是独立的"两种新节点"——它们是事件驱动执行模型的两个齿轮：
- **Service** 是数据泵，把外部变化注入 Blackboard
- **Decorator** 是响应器，监听 Blackboard 变化并触发分支切换
- **脏 key 追踪** 是连接二者的桥梁

### 2.3 服务与装饰器的设计理念

#### 角色定位

控制节点本身只会"调度子节点"。服务和装饰器是控制节点的**附加能力**，三者合起来构成完整的控制节点：

| | 能力 | 类比 |
|---|---|---|
| 控制节点自身 | **调度**：决定子节点的执行顺序和策略 | 调度员 |
| + 服务 | **感知**：定期把外部变化搬进 Blackboard | 搬运工 |
| + 装饰器 | **反应**：检查条件，不满足时触发打断 | 门卫 |

#### 生产者-消费者模式

服务和装饰器之间是**读写分离**的生产者-消费者关系，Blackboard 是中转站：

```
Service（生产者）→ 写入 Blackboard + 产生脏 key → Decorator（消费者）→ 读取 + 判断
```

分开而不合并的原因：可以自由组合。同一个服务搬进来的数据可以被多个装饰器用不同条件检查；同一个装饰器检查的 key，数据可以来自不同服务或行为节点。

#### 两级决策体系

服务和装饰器在树内提供**战术级决策**，与 Brain 的战略级决策形成分层：

| | Brain（1 秒/次） | 装饰器+服务（每帧） |
|---|---|---|
| 决策粒度 | Plan 级别：巡逻 → 追逐 → 调查 | 分支级别：追逐中目标丢了 → 换分支 |
| 决策内容 | "做什么" | "做的过程中条件变了怎么办" |
| 反应速度 | 最慢 1 秒 | 最慢 1 帧（~16ms） |

没有装饰器+服务时，所有决策都要上推到 Brain，Brain 的状态机会更复杂。有了之后，树内分支切换在树内自行处理，Brain 只管 Plan 级别的战略决策。

#### 生命周期

服务和装饰器的生命周期**等于宿主控制节点的生命周期**。宿主 OnEnter 时激活，每帧 OnTick 时执行，宿主 OnExit 时停用。宿主不在 Running 状态，它们就不执行。

#### 为什么只有控制节点能驱动

服务和装饰器解决的都是**分支级别**的问题，只有控制节点管理分支：
- Self Abort 需要有子节点可以打断 → 叶子节点没有子节点
- Lower Priority Abort 需要在兄弟分支间切换 → 只有 Selector 有互斥分支
- 服务需要一个长生命周期的宿主 → 叶子节点通常在 OnEnter 就完成了

### 2.4 Runner 每帧 Tick 流程

```go
// runner.go: Tick(entityID, deltaTime)

1. instance := runningTrees[entityID]        // 获取该实体的运行树
2. dirtyKeys := ctx.ConsumeDirtyKeys()       // 消费累积的脏 key
3. ctx.SetFrameDirtyKeys(dirtyKeys)          // 设置为本帧可用
4. status := tickNode(instance.Root, ctx)    // 递归执行树
5. ctx.ClearFrameDirtyKeys()                 // 清理
6. return status                             // Running / Success / Failed
```

### 2.4 单节点 Tick 流程

```go
// runner.go: tickNode(node, ctx)

IF node.Status() == Init:                    // 首次进入
    status = node.OnEnter(ctx)
    IF status != Running:
        node.OnExit(ctx)                     // 立即完成，立即退出
        return status
    // Running → 下次 Tick 继续

status = node.OnTick(ctx)                    // 持续执行

IF status == Success or Failed:
    node.OnExit(ctx)                         // 完成，清理退出
    return status

return Running                               // 继续下一帧
```

---

## 三、节点体系

### 3.1 节点接口

```go
// node/interface.go
type IBtNode interface {
    OnEnter(ctx *BtContext) BtNodeStatus    // 进入时初始化
    OnTick(ctx *BtContext) BtNodeStatus     // 每帧执行
    OnExit(ctx *BtContext)                  // 退出时清理

    Status() BtNodeStatus                   // 当前状态
    Reset()                                 // 重置为 Init

    Children() []IBtNode                    // 子节点列表
    NodeType() BtNodeType                   // Control / Decorator / Leaf

    // UE5 扩展
    Decorators() []IConditionalDecorator    // 附加的条件装饰器
    AddDecorator(IConditionalDecorator)
    Services() []IService                   // 附加的服务
    AddService(IService)
}
```

### 3.2 节点状态

```
Init ──OnEnter()──> Running ──OnTick()──> Success
                       │                     │
                       │                OnExit() 清理
                       │
                       └──OnTick()──> Failed
                                        │
                                   OnExit() 清理
```

| 状态 | 值 | 含义 |
|------|---|------|
| Init | 0 | 未执行，等待 OnEnter |
| Running | 1 | 执行中，每帧 OnTick |
| Success | 2 | 成功完成 |
| Failed | 3 | 失败 |

### 3.3 节点类型总览

```
节点
├── 控制节点 (Control)
│   ├── Sequence        顺序执行，全部成功才成功
│   ├── Selector        选择执行，一个成功就成功
│   └── SimpleParallel  主任务 + 后台任务并行
│
├── 装饰节点 (Decorator)
│   ├── Inverter        反转结果 Success ↔ Failed
│   ├── Repeater        重复执行 N 次（0=无限）
│   ├── Timeout         超时返回 Failed
│   ├── Cooldown        成功后冷却期内跳过
│   ├── ForceSuccess    强制返回 Success
│   ├── ForceFailure    强制返回 Failed
│   └── SubTree         引用另一棵注册的树
│
├── 条件装饰器 (Conditional Decorator) ← 附加在节点上，不是独立节点
│   ├── BlackboardCheck 检查黑板值（支持 abort）
│   └── FeatureCheck    检查 Feature 值（支持 abort）
│
├── 服务 (Service) ← 附加在控制节点上，不是独立节点
│   ├── SyncFeatureToBlackboard  周期同步 Feature → Blackboard
│   ├── UpdateSchedule           周期更新日程数据
│   └── Log                      周期输出调试日志
│
├── 行为节点 (Behavior) ← 策划用，NPC 自然语义，长运行自包含
│   ├── IdleBehavior, MoveBehavior, PursuitBehavior, DialogBehavior ...
│   └── 详见第六节
│
└── 工具节点 (Primitive) ← 程序员用
    ├── Wait, Log, SetBlackboard, ComputeBlackboard
    └── 详见第七节
```

### 3.4 节点结构规律

**规律 1：分支数决定节点类型**

```
控制节点    →  N 个子节点（调度员：把任务分给多个孩子）
装饰节点    →  1 个子节点（包装纸：包裹一个孩子并拦截结果）
叶子节点    →  0 个子节点（干活的：自己执行，不委托）
```

从树形图上一眼识别：分叉=控制、单线=装饰、末端=叶子。

```
        Selector ─────────────────── 分叉 → 控制节点
       /        \
  Sequence    Repeater ──────────── 单线 → 装饰节点
  /    \         |
Log   Wait    ForceSuccess ──────── 单线 → 装饰节点
 ↑      ↑       |
末端   末端    ChaseTarget ──────── 末端 → 叶子节点
```

**规律 2：树中可见 vs 不可见**

```
                    ┌─────────────────────────────────────────────┐
树中可见（占层级）    │ 控制节点、装饰节点、叶子节点                  │
                    │ → parent.children[] 中，是 IBtNode           │
                    ├─────────────────────────────────────────────┤
树中不可见（附加属性） │ 条件装饰器（node.decorators[]）              │
                    │ 服务（node.services[]）                      │
                    │ → 不参与树层级，是节点的内部属性               │
                    └─────────────────────────────────────────────┘
```

同一个 BaseNode 上并列三个列表：`children[]`（树骨架）、`decorators[]`（门卫）、`services[]`（后台工人）。
在 JSON 中对应 `children`/`child`、`decorators`、`services` 三个字段。

**规律 3：Service 和 Conditional Decorator 只有 Sequence/Selector 能驱动**

所有节点的 BaseNode 都有 `decorators[]` 和 `services[]` 字段，语法上任何节点都能携带。但：
- 只有 **Sequence 和 Selector** 内嵌了 `ServiceRunner`，才能实际驱动 Service 执行
- 只有 **Sequence 和 Selector** 的 `OnTick` 中实现了 Abort 评估逻辑，才能触发条件装饰器的中断
- 叶子节点和装饰节点即使配置了 services/decorators，也不会被执行

**规律 4：控制节点 vs 装饰节点的本质差异**

| | 控制节点（调度员） | 装饰节点（包装纸） |
|---|---|---|
| 子节点数 | N（≥2 才有意义） | 恰好 1 |
| 核心能力 | 决定**执行顺序和策略** | 决定**条件拦截和结果变换** |
| 自身产出 | 无，汇总子节点结果 | 无，修改子节点结果 |
| 共同点 | 都需要子节点才有意义，都不直接产生行为 |

**规律 5：命名混淆速查**

| 名称 | 是什么 | 在哪里 | JSON 字段 |
|------|--------|--------|-----------|
| 装饰节点 (Decorator Node) | 树中的真实节点 | `parent.children[0]` | `"child": {...}` |
| 条件装饰器 (Conditional Decorator) | 节点的附加属性 | `node.decorators[]` | `"decorators": [...]` |
| 服务 (Service) | 节点的附加属性 | `node.services[]` | `"services": [...]` |

---

## 四、UE5 特性详解

### 4.1 Conditional Decorator（条件装饰器）

**核心区别**：它不是树中的一个节点，而是**附加在节点上的条件守卫**。

**结构位置**：存储在 `BaseNode.decorators[]` 字段中，与 `children[]` 和 `services[]` 并列，不参与树的层级结构。

```
BaseNode
├── children   []IBtNode               ← 树的子节点（构成层级）
├── decorators []IConditionalDecorator  ← 条件装饰器（附加属性，不构成层级）
└── services   []IService              ← 服务（附加属性，不构成层级）
```

**配置位置 vs 评估位置**：decorator 配置在被守卫的节点上，但由该节点的**父节点**（Selector/Sequence）在选择子节点时评估。

```json
{
  "type": "Sequence",
  "decorators": [
    {
      "type": "BlackboardCheck",
      "params": {"key": "has_target", "operator": "==", "value": true},
      "abort_type": "both"
    }
  ],
  "children": [...]
}
```

**两个作用**：

1. **进入守卫**：父节点执行子节点前先评估子节点的 Decorator，条件不满足则跳过该分支
2. **运行时中断**：节点已在运行中，条件变化时主动打断（Self Abort 由自己评估，Lower Priority Abort 由父节点评估）

**`abort_type` 四种模式**：

| 模式 | 含义 | 触发时机 |
|------|------|---------|
| `none` | 只做进入守卫 | 仅进入时检查 |
| `self` | 条件变 false → 打断自己 | 运行中条件失败 |
| `lower_priority` | 条件变 true → 打断低优先级兄弟 | 高优先级条件恢复 |
| `both` | self + lower_priority | 两者都监听 |

**Self Abort 工作原理**（在 Sequence 中）：

```
Sequence.OnTick():
  FOR each decorator with SelfAbort:
    IF observedKeys 中有脏 key:          ← 事件驱动：只在值变化时检查
      IF !decorator.Evaluate():          ← 条件不再满足
        中断当前子节点 → 调用子节点 OnExit() → 返回 Failed
```

**Lower Priority Abort 工作原理**（在 Selector 中）：

```
Selector.OnTick():
  当前正在执行 child[2]（低优先级）

  FOR i = 0 to currentIndex-1:           ← 检查所有更高优先级的兄弟
    FOR each decorator on child[i]:
      IF decorator has LowerPriorityAbort:
        IF observedKeys 中有脏 key:
          IF decorator.Evaluate() == true: ← 高优先级条件恢复了
            中断 child[2] → OnExit() → Reset()
            currentIndex = i              ← 跳回高优先级分支
            重新开始执行 child[i]
```

**支持的运算符**：

| 运算符 | 说明 |
|--------|------|
| `==` | 等于 |
| `!=` | 不等于 |
| `>` `<` `>=` `<=` | 数值比较 |
| `is_set` | key 存在于 Blackboard |
| `not_set` | key 不存在 |

### 4.2 Service（后台服务）

附加在**控制节点**上，节点活跃期间按固定间隔执行后台任务。

**结构位置**：存储在 `BaseNode.services[]` 字段中，与 decorators 相同，不参与树的层级结构。Service 由宿主控制节点自身的 `ServiceRunner` 管理，在 OnEnter 激活、OnTick 定期执行、OnExit 停用。

**帧内执行顺序**（以 Sequence 为例）：

```
Sequence.OnTick():
  ① Self Abort 检查（评估 decorators）
  ② Tick Services（调用 serviceRunner.TickServices）
  ③ 执行 children
```

```json
{
  "type": "Selector",
  "services": [
    {
      "type": "SyncFeatureToBlackboard",
      "params": {
        "interval_ms": 200,
        "mappings": {"feature_pursuit_entity_id": "target_entity_id"}
      }
    }
  ],
  "children": [...]
}
```

**生命周期**：

```
控制节点 OnEnter()
  → ActivateServices()
    → service.OnActivate(ctx)          ← 首次激活，立即执行一次

控制节点 OnTick() 每帧
  → TickServices(deltaTime)
    → elapsed += dt
    → IF elapsed >= intervalMs:
        service.OnTick(ctx)            ← 到达间隔，执行
        elapsed = 0                    ← 重置计时

控制节点 OnExit()
  → DeactivateServices()
    → service.OnDeactivate(ctx)        ← 清理
```

**已有服务类型**：

| 服务 | 间隔默认值 | 作用 |
|------|-----------|------|
| `SyncFeatureToBlackboard` | 200ms | 将 Feature 值同步到 Blackboard（数据泵） |
| `UpdateSchedule` | 1000ms | 将日程数据写入 Blackboard |
| `Log` | 5000ms | 周期性输出调试日志 |

### 4.3 SimpleParallel（并行执行）

同时执行主任务（第一个子节点）和后台任务（第二个子节点）。

```json
{
  "type": "SimpleParallel",
  "params": {"finish_mode": "immediate"},
  "children": [
    {"type": "MoveTo", "params": {"target_key": "dest"}},
    {"type": "Sequence", "children": [
      {"type": "Wait", "params": {"duration_ms": 1000}},
      {"type": "Log", "params": {"message": "still moving..."}}
    ]}
  ]
}
```

| finish_mode | 行为 |
|-------------|------|
| `immediate` | 主任务完成 → 立即中断后台 → 返回主任务状态 |
| `delayed` | 主任务完成 → 等后台也完成 → 返回主任务状态 |

### 4.4 SubTree（子树引用）

引用另一棵已注册的行为树，实现树复用。

```json
{"type": "SubTree", "params": {"tree_name": "return_to_schedule"}}
```

- 运行时动态构建：调用 `runner.BuildNodeFromConfig(treeName)` 创建新实例
- 最大递归深度 10 层，防止无限嵌套
- 每次 OnEnter 构建新实例，OnExit 时释放

---

## 五、Blackboard 与脏 Key 机制

### 5.1 BtContext 结构

```go
// context/context.go
type BtContext struct {
    Scene    common.Scene            // ECS 场景引用
    EntityID uint64                  // NPC 实体 ID

    Blackboard map[string]any        // 共享数据存储
    DeltaTime  float32               // 帧间隔

    // 组件缓存（延迟加载）
    moveComp      *cnpc.NpcMoveComp
    decisionComp  *caidecision.DecisionComp
    transformComp *ctrans.Transform

    // 脏 key 追踪（事件驱动核心）
    dirtyKeys      map[string]struct{}    // 累积的脏 key
    frameDirtyKeys map[string]struct{}    // 当前帧的脏 key

    runner BtRunnerAccess                 // Runner 反向引用（SubTree 用）
}
```

**关键特性**：
- **跨树共享**：同一个 BtContext 在 Plan 切换时保留，Blackboard 数据在不同树之间共享
- **组件延迟加载**：`GetMoveComp()` 首次调用时从 Scene 获取，之后缓存
- **Feature vs Blackboard**：Feature 从 DecisionComp 只读，Blackboard 可读写

### 5.2 脏 Key 三阶段生命周期

```
阶段 1：累积
─────────────────────────────────────────
SetBlackboard("target_id", 42)
  → Blackboard["target_id"] = 42
  → dirtyKeys["target_id"] = {}          ← 标记为脏

（可能来自 Service、行为节点、或任何修改 Blackboard 的操作）

阶段 2：消费（Runner.Tick 开始时）
─────────────────────────────────────────
keys := ctx.ConsumeDirtyKeys()           ← 取出所有脏 key，清空累积
ctx.SetFrameDirtyKeys(keys)              ← 设置为本帧可用

阶段 3：使用 + 清理
─────────────────────────────────────────
Sequence/Selector.OnTick():
  ctx.HasRelevantFrameDirtyKeys(observedKeys)  ← Decorator 检查是否需要重评估

Runner.Tick 结束:
  ctx.ClearFrameDirtyKeys()              ← 清理，下一帧重新开始
```

**优化效果**：不需要每帧评估所有 Decorator，只在 Blackboard 值变化时才重评估关联的 Decorator。

---

## 六、行为节点（策划用）

从 NPC 自然行为视角命名，一个节点 = NPC 的一个完整行为生命周期。

### 6.0 设计理念：长运行自包含节点

每个行为节点管理自身的完整生命周期：**OnEnter（初始化 → Running）→ OnTick（保持 Running）→ OnExit（清理）**。

与旧设计的对比：
- **旧**：19 个 entry/exit 分离节点（如 ChaseTarget + ClearPursuitState），需要三阶段树调度
- **新**：10 个长运行节点（如 PursuitBehavior），OnEnter 做 ChaseTarget 的事，OnExit 做 ClearPursuitState 的事

**契约**：OnEnter 做了什么，OnExit 必须撤销。OnEnter 成功返回 Running（不是 Success）。

### 6.1 长运行行为节点

| 节点 | 含义 | OnEnter | OnExit |
|------|------|---------|--------|
| `IdleBehavior` | 站在日程位置 | 设 Transform + 对话超时 + 外出时长 | 重置 OutFinishStamp |
| `HomeIdleBehavior` | 站在家门口 | 设 feature_out_timeout + Transform | 清 feature_knock_req |
| `MoveBehavior` | 按日程移动 | 查路网路径 → 设移动组件 | StopMove |
| `DialogBehavior` | 和玩家对话 | 清事件 → 暂停对话 → 记录时间 | 恢复对话 → 补偿时间 |
| `PursuitBehavior` | 追逐目标 | 清路径 → NavMesh → 设目标 | StopMove + 清寻路 + 清目标 + NavMesh回程 |
| `InvestigateBehavior` | 前往调查 | NavMesh 寻路到 Feature 位置 | 清调查玩家 + 清 Feature |
| `MeetingIdleBehavior` | 站在聚会位置 | 从 meeting Feature 设 Transform | 无操作 |
| `MeetingMoveBehavior` | 走到聚会地点 | 找最近路点 → 查路网 → 设移动 | StopMove |
| `PlayerControlBehavior` | 被玩家控制 | 停止移动 + 清事件 | 清事件 + NavMesh 返回位置 |
| `ProxyTradeBehavior` | 代理交易 | SetTradeStatus(InTrade) | SetTradeStatus(None) |

### 6.2 过渡节点（一次性）

| 节点 | 含义 | 说明 |
|------|------|------|
| `ReturnToSchedule` | 从当前位置回归日程路线 | OnEnter 返回 Success（非 Running），不是长运行节点 |

---

## 七、工具节点 + 控制节点

### 7.1 工具节点（程序员用）

| 节点 | 参数 | 说明 |
|------|------|------|
| `Wait` | `duration_ms` 或 `duration_key` | 等待指定时间（Running 状态） |
| `Log` | `message`, `level` | 输出日志 |
| `SetBlackboard` | `key`, `value` | 设置黑板值 |
| `ComputeBlackboard` | `operation`, `left_key`, `right_key`, `output_key` | 黑板值运算 |

### 7.2 控制节点

**Sequence**：顺序执行所有子节点，全部 Success 才 Success，遇到 Failed 立即 Failed。

```
Sequence
├── child[0] → Success ✓ → 继续
├── child[1] → Success ✓ → 继续
├── child[2] → Failed ✗ → Sequence 返回 Failed
└── child[3] → 未执行
```

**Selector**：选择执行，找到第一个 Success 就 Success，全部 Failed 才 Failed。

```
Selector
├── child[0] → Failed ✗ → 跳过，试下一个
├── child[1] → Success ✓ → Selector 返回 Success
└── child[2] → 未执行
```

**重要**：Sequence 和 Selector 都支持 Service 和 Decorator Abort。

### 7.3 装饰节点

**结构位置**：装饰节点是树中的**真实节点**，存在父节点的 `children[]` 中，自身的 `children[0]` 指向被装饰节点。它与条件装饰器（Conditional Decorator）的区别：

| | 装饰节点 (Decorator Node) | 条件装饰器 (Conditional Decorator) |
|---|---|---|
| 存储位置 | `parent.children[]` | `node.decorators[]` |
| 是否参与树层级 | **是**（真实的父子关系） | **否**（附加属性） |
| JSON 配置 | `"child": {...}` | `"decorators": [...]` |
| 接口 | `IBtNode` | `IConditionalDecorator` |
| 谁驱动执行 | 自己的 OnEnter/OnTick/OnExit | 宿主节点或其父节点 |
| 支持 abort | 不支持 | 支持（`abort_type`） |
| 示例 | Inverter, Repeater, Timeout | BlackboardCheck, FeatureCheck |

| 节点 | 参数 | 效果 |
|------|------|------|
| `Inverter` | - | Success ↔ Failed，Running 不变 |
| `Repeater` | `count`(0=无限), `break_on_failure` | 重复执行子节点 |
| `Timeout` | `timeout_ms` / `timeout_ms_key` | 超时强制 Failed |
| `Cooldown` | `cooldown_ms` / `cooldown_ms_key` | 成功后冷却期 |
| `ForceSuccess` | - | 非 Running 结果都变 Success |
| `ForceFailure` | - | 非 Running 结果都变 Failed |
| `SubTree` | `tree_name` | 引用另一棵树 |

#### 装饰器与被装饰节点的关系

**树结构中的位置**：装饰节点是被装饰节点的父节点，恰好只有一个子节点：

```
Selector                    ← 控制节点（N 个子节点）
├── Timeout(5000)           ← 装饰节点（恰好 1 个子节点）
│   └── Sequence            ← 被装饰的可以是任何类型
│       ├── Log
│       └── Wait
├── Repeater(0)             ← 装饰节点可以嵌套
│   └── ForceSuccess        ← 子节点也是装饰节点
│       └── Wait
└── ChaseTarget             ← 叶子节点直接挂控制节点
```

**代码实现**：本质是组合 + 手动委托，没有语法层面的特殊机制。

```go
// 装饰器嵌入 BaseNode，被装饰节点存在 BaseNode.children[0]
type InverterNode struct {
    node.BaseNode                    // children[0] 就是被装饰节点
}

// 装饰器在生命周期方法中手动调用子节点，拦截返回值
func (n *InverterNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    child := n.Children()[0]         // 取被装饰节点
    status := child.OnTick(ctx)      // 手动委托
    return invertStatus(status)      // 拦截并修改返回值
}
```

组装时由 Loader 建立父子关系（JSON 中用 `child` 字段）：

```go
inverter := factory.Create("Inverter")
child := factory.Create("ChaseTarget")
inverter.AddChild(child)            // BaseNode.children = [child]
```

**拦截方式分类**：

| 类型 | 装饰器 | 拦截时机 |
|------|--------|---------|
| 后置拦截 | Inverter, ForceSuccess, ForceFailure | 子节点正常执行，只修改返回值 |
| 前置拦截 | Timeout, Cooldown | 先检查条件，不满足则拦截子节点不执行 |
| 循环拦截 | Repeater | 子节点完成后不上报，Reset 重新执行 |

**与 GoF 装饰器模式的关系**：

同一个设计思想（组合 + 委托 + 同接口），适配到不同数据结构：
- GoF 装饰器用于**链式**场景（如 Java IO 的 BufferedInputStream 包 GZIPInputStream），被装饰对象存在 `wrapped` 字段
- 行为树装饰器用于**树形**场景，被装饰对象存在 `children[0]`，复用树已有的父子关系，无需额外字段

---

## 八、Plan 调度与两层分发

### 8.1 决策边界：Brain vs BT

**核心原则**：Brain 管行为类别切换（战略），BT 管类别内部分支（战术）。

```
Brain 决策粒度（1秒/次）                BT 决策粒度（每帧）
────────────────────────              ──────────────────────
daily_schedule → dialog               daily_schedule 内部：
daily_schedule → pursuit                IdleBehavior ↔ MoveBehavior ↔ HomeIdleBehavior
pursuit → daily_schedule               （按 feature_schedule 切换）
daily_schedule → meeting
meeting → daily_schedule              meeting 内部：
                                        MeetingMoveBehavior ↔ MeetingIdleBehavior
                                       （按 feature_meeting_state 切换）
```

**判断标准**：如果多个 plan 共享所有 transition 条件和优先级，应合并为一个 plan，内部分支交给 BT。

### 8.2 两种树类型

| 树类型 | 结构 | 适用场景 | 示例 |
|--------|------|---------|------|
| 原子树 | 单个长运行行为节点 | plan 只有一种行为 | `dialog.json`、`pursuit.json` |
| 复合树 | Selector + Service + Decorator | plan 内部有多种行为分支 | `daily_schedule.json`、`meeting.json` |

**复合树模式**：

```json
{
  "name": "daily_schedule",
  "root": {
    "type": "Selector",
    "services": [{
      "type": "SyncFeatureToBlackboard",
      "params": {
        "interval_ms": 500,
        "mappings": {"feature_schedule": "schedule"}
      }
    }],
    "children": [
      {
        "type": "MoveBehavior",
        "decorators": [{
          "type": "BlackboardCheck",
          "abort_type": "both",
          "params": {"key": "schedule", "operator": "==", "value": "MoveToBPointFormAPoint"}
        }]
      },
      {
        "type": "HomeIdleBehavior",
        "decorators": [{
          "type": "BlackboardCheck",
          "abort_type": "both",
          "params": {"key": "schedule", "operator": "==", "value": "StayInBuilding"}
        }]
      },
      {
        "type": "IdleBehavior"
      }
    ]
  }
}
```

**工作原理**：
1. `SyncFeatureToBlackboard` 每 500ms 把 `feature_schedule` 同步到 BB key `"schedule"`
2. 每个分支的 `BlackboardCheck(abort_type=both)` 守卫条件
3. Feature 变化 → 脏 key → Decorator 重评估 → Abort 切换分支
4. 最后一个分支（IdleBehavior）无 Decorator，作为默认回退

### 8.3 两层调度

Executor 的 `OnPlanCreated` 接收 Brain 产生的 Plan：

```go
func (e *Executor) OnPlanCreated(req) error {
    for _, task := range req.Plan.Tasks {
        // GSSExit: 停止行为树（触发节点 OnExit 清理）
        if task.Type == GSSExit { btRunner.Stop(entityID); continue }
        // GSSEnter: 已合并到行为节点 OnEnter 中
        if task.Type == GSSEnter { continue }

        // 第一层：BT 调度
        treeName := resolveTreeName(planName, task)  // GSSMain→planName, Transition→taskName
        if treeName != "" && btRunner.HasTree(treeName) {
            btRunner.Run(treeName, entityID)
            continue
        }

        // 第二层：硬编码回退（遗留代码，逐步清退）
        executeTask(entityID, planName, fromPlan, task)
    }
}
```

**resolveTreeName 规则**：

| TaskType | 返回值 | 说明 |
|----------|--------|------|
| GSSMain | planName（如 "daily_schedule"） | 主任务，对应 JSON 树 |
| Transition | task.Name（如 "pursuit_to_move_transition"） | 过渡任务 |
| 其他 | "" | 不走 BT |

### 8.4 Plan 切换

```
Brain 决定 Plan A → Plan B
    │
    ├── GSSExit task → btRunner.Stop(entityID)
    │   └── stopNode 递归 → 所有 Running 节点调用 OnExit（清理）
    │
    └── GSSMain task → btRunner.Run(planB, entityID)
        └── Run() 内置 Stop(旧) + Run(新)，自动清理
```

行为节点的 OnExit 负责所有清理逻辑（停止移动、重置状态等），Plan 切换对策划完全隐式。

### 8.5 Brain 配置简化

Brain 配置是纯 JSON（`config/RawTables/Json/Server/ai_decision/`），修改不需 Go 代码变更。

**Plan 合并示例**：

| NPC 配置 | 合并前 | 合并后 |
|----------|--------|--------|
| DealerNpc_State | 8 plans / 37 transitions | 5 plans / 13 transitions（+proxy_trade） |
| Blackman_State | 8 plans / 42 transitions | 5 plans / 14 transitions（+investigate） |
| Dan_State | 已是复合模式 | 4 plans / 12 transitions |

**合并规则**：
- `home_idle + idle + move` → `daily_schedule`（BT 内部用 BlackboardCheck + schedule Feature 切换）
- `meeting_idle + meeting_move` → `meeting`（BT 内部用 BlackboardCheck + meeting_state Feature 切换）
- NPC 独有行为保留为独立 plan（如 Blackman 的 `investigate`、Dealer 的 `proxy_trade`）

**transition 条件设计要点**：
- `meeting_state != 0`（`ne` 运算符）进入 meeting
- `meeting_state == 0` 离开 meeting
- pursuit_to_daily_schedule 需互斥条件：`state_pursuit == false AND meeting_state == 0`
- pursuit_to_meeting 需互斥条件：`state_pursuit == false AND meeting_state != 0`
- Blackman 追逐结束需额外检查 `arrested == true`（犯人逮捕逻辑）
- 独有行为的进出条件用独有 Feature（如 `pursuit_miss` → investigate，`release_wanted` → daily_schedule）

**注意**：合并后 `init_plan` 从原子 plan（如 `home_idle`）改为复合 plan（`daily_schedule`），相关 Feature 默认值（如 `feature_args3`）也需同步更新

---

## 九、配置与加载流程

### 9.1 JSON 格式

```json
{
  "name": "pursuit",
  "description": "NPC 追捕 - 持续追逐目标",
  "root": {
    "type": "Selector",
    "services": [
      {
        "type": "SyncFeatureToBlackboard",
        "params": {"interval_ms": 200, "mappings": {"feature_x": "bb_x"}}
      }
    ],
    "decorators": [
      {
        "type": "BlackboardCheck",
        "params": {"key": "target", "operator": "!=", "value": 0},
        "abort_type": "both"
      }
    ],
    "children": [
      {"type": "PursuitBehavior"},
      {"type": "Log", "params": {"message": "fallback"}}
    ]
  }
}
```

### 9.2 加载管线

```
JSON 文件 (trees/*.json)
    │ go:embed 编译时嵌入
    ▼
RegisterTreesFromConfig()
    │ 遍历所有 *.json → json.Unmarshal → BTreeConfig
    ▼
BtRunner.RegisterTreeConfig(name, cfg)
    │ 存储在 treeConfigs map 中（只存配置，不构建节点）
    ▼
BtRunner.Run(treeName, entityID)
    │ 从 treeConfigs 取出配置
    │ loader.BuildNode(&cfg.Root)  ← 每次 Run 构建新实例（模板隔离）
    ▼
BuildNode(cfg) 递归：
    ├── factory.Create(cfg)              创建节点实例
    ├── 递归 BuildNode(children)         构建子节点
    ├── factory.CreateDecorator(dec)     创建条件装饰器
    │   └── node.AddDecorator(dec)       附加到节点
    ├── factory.CreateService(svc)       创建服务
    │   └── node.AddService(svc)         附加到节点
    └── return node
```

**关键设计**：每次 `Run()` 都从配置构建全新的节点树实例，每个 NPC 的节点互不干扰。

---

## 十、ECS 系统集成

### 10.1 两个 ECS 系统

```
DecisionSystem（决策系统）                BtTickSystem（行为树驱动系统）
├── 更新频率：1 秒 / 次                  ├── 更新频率：每帧（~16.67ms）
├── 职责：驱动 Brain 产生新 Plan          ├── 职责：Tick 所有运行中的行为树
└── 流程：                               └── 流程：
    DecisionComp.Update()                    btRunner.Tick(entityID, dt)
    → Brain 评估条件                          → 执行节点 → 检查 Abort
    → 产生 Plan + Tasks                      → 树完成时：
    → Executor.OnPlanCreated()                  btRunner.Stop()
    → 两层调度：resolveTreeName → 硬编码回退                      decisionComp.TriggerCommand()
    → btRunner.Run(treeName)                    → 触发 Brain 重新评估
```

### 10.2 完整帧循环

```
Frame N:
  ┌─ DecisionSystem.Update() (每秒)
  │   └─ Brain → Plan → Executor → btRunner.Run("daily_schedule", npc1)
  │
  └─ BtTickSystem.Update() (每帧)
      └─ btRunner.Tick(npc1, 0.016)
          ├─ ConsumeDirtyKeys()
          ├─ Service: SyncFeature → Blackboard (if interval reached)
          ├─ Decorator: check abort conditions
          ├─ tickNode(root) → OnTick chain
          └─ ClearFrameDirtyKeys()

Frame N+1:
  └─ BtTickSystem.Update()
      └─ btRunner.Tick(npc1, 0.016) → 树继续 Running...

Frame N+K: 树完成 (Success)
  └─ BtTickSystem.Update()
      └─ btRunner.Tick(npc1, 0.016) → Success
          └─ onTreeCompleted()
              ├─ btRunner.Stop(npc1)          // 清理
              └─ decisionComp.TriggerCommand() // 触发 Brain 重新决策
```

---

## 十一、目录结构

```
bt/
├── config/
│   ├── types.go                # BTreeConfig, NodeConfig, DecoratorConfig, ServiceConfig
│   ├── loader.go               # JSON → 节点树（BuildNode 递归构建）
│   └── plan_config.go          # PlanConfig 加载
│
├── context/
│   └── context.go              # BtContext：Blackboard + 脏 key + 组件缓存
│
├── node/
│   ├── interface.go            # IBtNode, IConditionalDecorator, IService 接口
│   ├── abort.go                # FlowAbortMode: None/Self/LowerPriority/Both
│   └── conditional_decorator.go
│
├── nodes/
│   ├── factory.go              # 节点工厂：注册 + 创建
│   ├── registry.go             # 节点元数据：搜索 + 文档生成
│   │
│   ├── # 控制节点
│   ├── sequence.go             # Sequence + Self Abort 评估
│   ├── selector.go             # Selector + LowerPriority Abort 评估
│   ├── simple_parallel.go      # SimpleParallel (immediate/delayed)
│   ├── service_runner.go       # Service 间隔执行管理
│   │
│   ├── # 装饰节点
│   ├── decorator.go            # Inverter/Repeater/Timeout/Cooldown/Force*
│   ├── subtree.go              # SubTree（动态构建 + 深度限制）
│   │
│   ├── # 条件装饰器
│   ├── blackboard_decorator.go # BlackboardCheck（BB 条件 + 脏 key 追踪）
│   ├── feature_decorator.go    # FeatureCheck（Feature 条件，无脏 key）
│   │
│   ├── # 服务
│   ├── service_sync_feature.go # SyncFeatureToBlackboard
│   ├── service_update_schedule.go # UpdateSchedule
│   ├── service_log.go          # Log
│   │
│   ├── # 行为节点（策划用）
│   ├── behavior_nodes.go       # 10+1 长运行行为节点定义
│   ├── behavior_helpers.go     # 行为节点工具函数
│   │
│   └── # 工具节点
│       ├── wait.go             # Wait（Running 状态示例）
│       ├── log.go              # Log
│       ├── set_blackboard.go   # SetBlackboard
│       └── compute_blackboard.go # ComputeBlackboard
│
├── runner/
│   └── runner.go               # BtRunner：树管理 + Tick 驱动 + 脏 key 消费
│
└── trees/
    ├── register.go             # go:embed + 自动注册
    │
    ├── # 原子树（单个长运行行为节点）
    ├── dialog.json             # DialogBehavior
    ├── pursuit.json            # PursuitBehavior
    ├── investigate.json        # InvestigateBehavior
    ├── sakura_npc_control.json # PlayerControlBehavior
    ├── proxy_trade.json        # ProxyTradeBehavior
    │
    ├── # 复合树（Selector + Service + Decorator）
    ├── daily_schedule.json     # idle ↔ move ↔ home_idle 分支切换
    ├── meeting.json            # meeting_move ↔ meeting_idle 分支切换
    │
    ├── # 过渡树
    ├── pursuit_to_move_transition.json
    ├── sakura_npc_control_to_move_transition.json
    │
    └── # 公共子树
        └── return_to_schedule.json  # SubTree 引用
```

---

## 十二、设计检查清单

### 添加新行为节点

- [ ] 从 NPC 视角命名（"NPC 在做什么"），不是从组件操作命名
- [ ] 在 `behavior_nodes.go` 实现，工具函数放 `behavior_helpers.go`
- [ ] 在 `factory.go` 用 `RegisterWithMeta` 注册（含 Category、Description）
- [ ] 通过 `BtContext` 访问组件，不直接依赖 Scene
- [ ] 先验证后执行：先获取所有组件并校验，全部通过后再修改状态

### 添加新 Plan

- [ ] **原子树**（单行为 plan）：创建 1 个 JSON 文件 `{plan}.json`，根节点为长运行行为节点
- [ ] **复合树**（多行为 plan）：创建 1 个 JSON 文件 `{plan}.json`，根节点为 Selector + Service + Decorator(abort=both)
- [ ] 更新 `integration_test.go` 中 3 处硬编码列表：`TestLoadSpecificTrees`、`TestAllJSONFilesValid`、`TestCountNodeTypes`
- [ ] 更新 `integration_phased_test.go` 中的 planNames 列表
- [ ] 如需 Brain 配置变更：修改对应的 `ai_decision/*.json`（纯 JSON，无 Go 代码）

### 使用 Decorator Abort

- [ ] 确认观测的 key 由 Service 或其他节点定期更新
- [ ] `self`：用于"前提条件不满足时中断自己"
- [ ] `lower_priority`：用于"高优先级条件恢复时抢占低优先级"
- [ ] `both`：两者都需要时使用
- [ ] 避免 `abort_type: none` 的 Decorator 观测高频变化的 key（浪费评估）

### 区分三种"装饰"概念

- [ ] **装饰节点**（Inverter/Repeater/Timeout 等）：树中的真实节点，JSON 用 `child` 配置，存在 `parent.children[]` 中
- [ ] **条件装饰器**（BlackboardCheck/FeatureCheck）：附加属性，JSON 用 `decorators` 配置，存在 `node.decorators[]` 中，不构成树层级
- [ ] **服务**（SyncFeatureToBlackboard/UpdateSchedule/Log）：附加属性，JSON 用 `services` 配置，存在 `node.services[]` 中，不构成树层级
- [ ] 三者在 BaseNode 上并列：`children`（树骨架）、`decorators`（门卫）、`services`（后台工人）

### Blackboard 使用

- [ ] Blackboard 是树内节点间数据总线，不是 BT 与业务层的共享通道
- [ ] 外部数据进入 BT：通过 Service（如 SyncFeatureToBlackboard）单向同步 Feature → Blackboard
- [ ] BT 影响外部：行为节点直接操作 ECS 组件（MoveComp、DialogComp 等），不经过 Blackboard
- [ ] Blackboard 全部在堆上，逻辑属 NPC（按 entityID 隔离），物理属 Scene（BtRunner.contexts map）
- [ ] 无持久化：进程重启丢失；NPC Entity 销毁时需显式 RemoveContext

### Brain 配置重构（原子 Plan → 复合 Plan）

**判断是否可合并**：
- [ ] 多个原子 plan 之间的切换只依赖单个 Feature（如 `schedule`、`meeting_state`）→ 可合并为复合树
- [ ] 原子 plan 有独有的进出条件和 Feature（如 `pursuit_miss`、`arrested`）→ 保留为独立 plan
- [ ] 复合树已存在（`daily_schedule.json`、`meeting.json`）→ 直接复用

**重构步骤**：
- [ ] 识别可合并的原子 plan 组：schedule 类（idle/home_idle/move）→ daily_schedule，meeting 类（meeting_idle/meeting_move）→ meeting
- [ ] 修改 `ai_decision/*.json`：替换 plans 列表，`init_plan` 改为复合 plan 名，移除 `entry_task`/`exit_task`
- [ ] 合并 transitions：原子 plan 间互转的 transition 全部删除（BT 内部处理），只保留跨 plan 的 transition
- [ ] 更新 Feature 默认值：`feature_args3` 等引用旧 plan 名的 Feature 改为新 plan 名

**行为等价性验证**：
- [ ] 逐场景追踪：正常日程轮转 → daily_schedule 内部 Decorator 切换（等价）
- [ ] 会议状态变化 → meeting 内部 Decorator 切换（等价）
- [ ] 对话中断/恢复 → daily_schedule_to_dialog / dialog_to_daily_schedule（等价）
- [ ] 追逐→回归 → pursuit_to_daily_schedule，附加条件（如 arrested）保留在 transition 中
- [ ] NPC 独有行为路径完整（如 pursue→investigate→daily_schedule）

**文件清理**：
- [ ] 确认所有 Brain 配置都不再引用旧原子 plan 名（全局搜索 `ai_decision/*.json`）
- [ ] 删除不再被引用的原子树 JSON 文件
- [ ] 更新 `integration_test.go` 中 3 处硬编码文件列表
- [ ] 更新 `behavior-tree.md` rules 中的目录结构
