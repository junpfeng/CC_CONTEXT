# V2 行为树框架设计

## 需求回顾

V2 正交管线中，简单 Plan 用 PlanHandler 直写 NpcState，复杂 Plan 需要行为树驱动（战斗中并行子行为、寻路多步流程等）。

**约束**：V2 行为树引擎完全独立于 V1（`ai/bt/` 包），不复用 V1 的 BtRunner/BtContext/BtNode。

**本次目标**：搭好框架骨架（引擎 + 节点接口 + 基础节点 + BtPlanHandler 适配器），升级 CombatHandler 和 NavigateHandler 为 BT 驱动版本的骨架。具体行为树内容后续填充。

## 架构设计

### 系统边界

仅涉及 P1GoServer，在 `execution` 包内新建 `btree` 子包：

```
servers/scene_server/internal/common/ai/execution/
├── plan_handler.go          # PlanHandler 接口 + PlanContext（不变）
├── plan_executor.go         # PlanExecutor（不变）
├── btree/                   # 【新建】V2 轻量行为树引擎
│   ├── node.go             # 节点接口 + 状态枚举
│   ├── composite.go        # Sequence / Selector / Parallel
│   ├── decorator.go        # Condition / Repeater / Inverter / UntilSuccess / UntilFailure
│   ├── leaf.go             # Action / Wait
│   └── tree.go             # BehaviorTree（根 + Tick + Reset）
├── bt_handler.go            # 【新建】BtPlanHandler 适配器
└── handlers/
    ├── engagement_handlers.go  # CombatHandler 升级为 BT 驱动
    ├── navigation_handlers.go  # NavigateHandler 升级为 BT 驱动
    └── ...                     # 其他 Handler 不变
```

### V1 vs V2 行为树对比

| | V1 (`ai/bt/`) | V2 (`execution/btree/`) |
|---|---|---|
| 运行上下文 | BtContext（Blackboard + Scene） | PlanContext（NpcState + Snapshot） |
| 状态存储 | Blackboard key-value | NpcState 直接字段 |
| 节点实例 | per-entity 从 config 重建 | per-entity，存储在 NpcState.BtreeInstances 中 |
| 驱动方式 | BtRunner.Tick() | BtPlanHandler.OnTick() → tree.Tick() |
| 事件机制 | Blackboard 脏标记 + Observer | 无（KISS，后续按需加） |
| 配置加载 | JSON BTreeConfig + BTreeLoader | Go 代码构建（后续可加 JSON） |
| 依赖 | common.Scene, BtRunner, 60+ 文件 | 仅 PlanContext，<10 文件 |

### 核心设计决策

1. **节点直接使用 PlanContext**：btree 是 execution 的子包，Go 允许子包 import 父包，无循环依赖。节点 Tick 直接接收 `*PlanContext`，无需重复定义 TickContext。
2. **Go 代码构建树**：初期用代码组装节点树，不做 JSON 配置加载（YAGNI）
3. **per-entity 树实例存 NpcState**：树实例存储在 `NpcState.BtreeInstances map[string]*BehaviorTree` 中，Handler 保持无状态共享单例，与现有 Handler 约定一致。NPC 销毁时 NpcState 回收，树实例自动清理，无泄漏风险。
4. **BtPlanHandler 无状态适配器**：OnEnter 创建树存入 NpcState，OnTick 从 NpcState 取树 Tick，OnExit 从 NpcState 删除树。

## 详细设计

### 1. 节点接口 (`btree/node.go`)

```go
package btree

import "mp/servers/scene_server/internal/common/ai/execution"

// Status 节点执行状态
type Status int

const (
    Running Status = iota
    Success
    Failure
)

// Node 行为树节点接口
type Node interface {
    Tick(ctx *execution.PlanContext) Status
    Reset()
}
```

直接复用 `*execution.PlanContext`，无需额外的上下文类型。

### 2. 基础节点

**Composite 节点** (`btree/composite.go`)：

| 节点 | 行为 |
|------|------|
| `Sequence` | 依次执行子节点，全部 Success 返回 Success，任一 Failure 返回 Failure |
| `Selector` | 依次尝试子节点，任一 Success 返回 Success，全部 Failure 返回 Failure |
| `Parallel` | 同时执行所有子节点，策略可配（AllSuccess / AnySuccess） |

**Decorator 节点** (`btree/decorator.go`)：

| 节点 | 行为 |
|------|------|
| `Condition` | 执行判断函数，true→Success，false→Failure |
| `Repeater` | 重复执行子节点 N 次或无限次 |
| `Inverter` | 反转子节点结果 |
| `UntilSuccess` | 重复子节点直到 Success，支持超时（maxDuration） |
| `UntilFailure` | 重复子节点直到 Failure（如战斗循环，目标丢失→退出） |
| `AlwaysSucceed` | 执行子节点但始终返回 Success |

**Leaf 节点** (`btree/leaf.go`)：

| 节点 | 行为 |
|------|------|
| `Action` | 执行用户自定义函数 `func(*PlanContext) Status`，返回 Status |
| `Wait` | 等待指定时间（基于 DeltaTime 累加），内部状态 elapsed |

> **Wait 节点状态注意**：Wait 有内部 elapsed 字段，这是 btree 中唯一有 per-tick 状态的 leaf。树实例是 per-entity 的，所以无共享问题。Reset() 时清零。

### 3. BehaviorTree (`btree/tree.go`)

```go
// BehaviorTree 行为树实例
type BehaviorTree struct {
    root Node
}

func NewTree(root Node) *BehaviorTree {
    return &BehaviorTree{root: root}
}

func (t *BehaviorTree) Tick(ctx *execution.PlanContext) Status {
    return t.root.Tick(ctx)
}

func (t *BehaviorTree) Reset() {
    t.root.Reset()
}
```

### 4. NpcState 存储树实例

在 `NpcState` 中新增字段：

```go
// NpcState 新增
BtreeInstances map[string]*btree.BehaviorTree  // dimension→树实例
```

key 为维度名（如 "engagement"、"navigation"），BtPlanHandler 用维度名存取。NPC 销毁时 NpcState 回收到 sync.Pool，Reset() 时清理 map。

### 5. BtPlanHandler 适配器 (`execution/bt_handler.go`)

```go
// TreeBuilder 行为树构建函数
// 每次调用返回一个新的独立树实例（per-entity 隔离）
type TreeBuilder func() *btree.BehaviorTree

// BtPlanHandler 将行为树包装为 PlanHandler
// 无状态共享单例（与其他 Handler 一致），per-entity 树实例存储在 NpcState 中
type BtPlanHandler struct {
    dimension string       // 维度名（作为 NpcState.BtreeInstances 的 key）
    builder   TreeBuilder  // 树构建函数
}

func NewBtPlanHandler(dimension string, builder TreeBuilder) *BtPlanHandler

func (h *BtPlanHandler) OnEnter(ctx *PlanContext) {
    tree := h.builder()
    ctx.NpcState.SetBtree(h.dimension, tree)
}

func (h *BtPlanHandler) OnTick(ctx *PlanContext) {
    tree := ctx.NpcState.GetBtree(h.dimension)
    if tree == nil { return }
    status := tree.Tick(ctx)
    if status != btree.Running {
        // 树执行完毕，清理
        ctx.NpcState.RemoveBtree(h.dimension)
    }
}

func (h *BtPlanHandler) OnExit(ctx *PlanContext) {
    tree := ctx.NpcState.GetBtree(h.dimension)
    if tree != nil {
        tree.Reset()
        ctx.NpcState.RemoveBtree(h.dimension)
    }
}
```

**BtPlanHandler 没有任何 per-entity 状态**，完全符合 Handler 无状态单例约定。

### 6. CombatHandler 升级

```go
func combatTreeBuilder() *btree.BehaviorTree {
    return btree.NewTree(
        btree.NewUntilFailure(              // 目标丢失→Failure→退出树
            btree.NewSequence(
                btree.NewCondition("has_target", hasTarget),  // 前置条件：有目标
                btree.NewAction("pursue", pursueTarget),      // 追近目标
                btree.NewAction("select_skill", selectSkill), // 选技能
                btree.NewAction("cast", castSkill),           // 施法
                btree.NewWait("recover", 300*time.Millisecond), // 恢复
            ),
        ),
    )
}

// 注册
NewBtPlanHandler("engagement", combatTreeBuilder)
```

**目标丢失处理**：`hasTarget` 返回 false → Condition 返回 Failure → Sequence 短路 → UntilFailure 退出。树返回 Success，BtPlanHandler.OnTick 检测到非 Running，清理树实例。决策层下一 Tick 重新评估 Plan。

### 7. NavigateHandler 升级

```go
func navigateTreeBuilder() *btree.BehaviorTree {
    return btree.NewTree(
        btree.NewSequence(
            btree.NewAction("update_target", updateMoveTarget),
            btree.NewAction("start_move", startMove),
            btree.NewUntilSuccess(                              // 等待到达
                btree.NewAction("check_arrival", checkArrival),
                btree.WithTimeout(15*time.Second),              // 超时保护
            ),
        ),
    )
}
```

**超时保护**：UntilSuccess 支持 `maxDuration` 参数，超时返回 Failure，避免卡地形死循环。

### 8. 接口契约

BtPlanHandler 实现 PlanHandler 接口，对 PlanExecutor 完全透明：

```
PlanExecutor.Execute(plan, ctx)
  → BtPlanHandler.OnEnter/OnTick/OnExit(ctx)
    → tree := ctx.NpcState.GetBtree(dimension)
    → tree.Tick(ctx)
      → Node.Tick(ctx)  // 读写 NpcState
```

无跨工程契约变更，无 proto/客户端修改。

## 审查修正记录

| ID | 级别 | 问题 | 修正 |
|----|------|------|------|
| C1 | Critical | BtPlanHandler map 打破 Handler 无状态约定 | 树实例存入 NpcState.BtreeInstances，Handler 保持无状态 |
| C2 | Critical | Combat 树缺少目标丢失处理 | 外层改为 UntilFailure + Condition("has_target") |
| I1 | Important | TickContext 与 PlanContext 重复 | 删除 TickContext，btree 直接 import execution 用 PlanContext |
| I2 | Important | Navigate UntilSuccess 可能死循环 | UntilSuccess 支持 maxDuration 超时参数 |
| I3 | Important | 缺 UntilFailure 节点 | 新增 UntilFailure，用于 Combat 循环 |
| S1 | Suggestion | 缺 AlwaysSucceed | 新增 AlwaysSucceed 装饰器 |

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| per-entity 树实例泄漏 | 存入 NpcState，NPC 销毁时 NpcState 回收自动清理；OnExit 主动删除 |
| Action 函数闭包捕获外部状态 | Action 函数签名统一为 `func(*PlanContext) Status`，无闭包 |
| Wait 节点内部 elapsed 状态 | per-entity 树实例隔离，Reset() 清零，不影响其他 NPC |
| btree ↔ execution 循环依赖 | btree 是 execution 子包，Go 允许子包 import 父包，无循环 |
| 后续需要 JSON 配置加载 | 预留 Node 接口，后续可加 NodeFactory + JSON parser |

---

**文档版本**: v1.1（审查修正后）
**最后更新**: 2026-03-12
