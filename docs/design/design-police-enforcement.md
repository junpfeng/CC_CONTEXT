# 设计文档：警察执法行为统一到行为树（police_enforcement 复合树）

## 1. 需求回顾

将警察 NPC（Blackman）的追捕（pursuit）和调查（investigate）两个独立 Plan 合并为单棵 `police_enforcement` 复合树，同时引入异步节点模式，让树能自然流动（Sequence 驱动步骤推进），而不是永远停在 Running 等外部打断。

**核心原则**：
- Brain 管战略（进入/退出执法模式），BT 管战术（追捕↔调查↔返回）
- BT 叶子节点是意图层（发命令 + 看结果），ECS System 是机制层（执行规则）
- 叶子节点的 OnTick 负责"目标达成检测"，不执行业务逻辑

---

## 2. 架构设计

### 2.1 改造前后对比

**改造前**（Brain 管理所有状态切换 + 永恒 Running 节点）：

```
Brain: 8 plans, ~30 transitions
  ├─ idle/move/home_idle/dialog/meeting_idle/meeting_move (日常)
  ├─ pursuit (追捕) ← Brain transition 驱动，PursuitBehavior 永恒 Running
  └─ investigate (调查) ← Brain transition 驱动，InvestigateBehavior 永恒 Running

状态流转全在 Brain：
  idle → pursuit (feature_state_pursuit=true)
  pursuit → investigate (feature_pursuit_miss=true)
  investigate → pursuit (feature_state_pursuit=true)
  pursuit → idle (feature_arrested=true)
  investigate → idle (feature_release_wanted=true)
```

**改造后**（BT 管理执法内部切换 + 异步节点自然完成）：

```
Brain: 7 plans, ~20 transitions (简化)
  ├─ idle/move/home_idle/dialog/meeting_idle/meeting_move (日常)
  └─ police_enforcement (执法) ← BT 内部 Sequence 编排异步步骤

BT 内部流动（树结构驱动）：
  police_enforcement.json:
    Selector
    ├─ Sequence [pursuit] (guard: state_pursuit==true)
    │  ├─ ChaseTarget → Running...Running...Success（追到）/ Failed（丢了）
    │  └─ PerformArrest → Success（执行逮捕）
    ├─ Sequence [investigate] (guard: pursuit_miss==true)
    │  ├─ SetupNavMeshPath → Success（设路径）
    │  ├─ StartMove → Success（开始走）
    │  ├─ WaitForNavMeshArrival → Running...Running...Success（到了）
    │  ├─ Wait(5s) → Running...Running...Success（等完了）
    │  └─ ClearInvestigation → Success（清状态）
    └─ ReturnToSchedule (fallback)
```

### 2.2 叶子节点分层

```
┌──────────────────────────────────────────────────┐
│  BT 叶子节点（意图层）                             │
│  职责：发命令 → 看结果 → 报完成                     │
│                                                    │
│  OnEnter: 写 Component（设移动目标、开始跑步）       │
│  OnTick:  读 Component（到了吗？还看得见吗？）       │
│  OnExit:  写 Component（被打断时停止移动、清状态）    │
└─────────────────────┬────────────────────────────┘
                      │ 读/写 ECS Component
                      ▼
┌──────────────────────────────────────────────────┐
│  ECS System（机制层）                              │
│  职责：执行游戏世界规则                             │
│                                                    │
│  MoveSystem:        驱动 NPC 位移                  │
│  PoliceSystem:      suspicion 累积/衰减/逮捕执行    │
│  VisionSystem:      视野检测                       │
│  BeingWantedSystem: 通缉状态聚合                    │
└──────────────────────────────────────────────────┘
```

### 2.3 数据流

```
PoliceComp (状态机) ──500ms──▶ MiscSensor ──▶ Feature
                                                │
                                   ┌────────────┘
                                   ▼
                        SyncFeatureToBlackboard (Service)
                                   │ OnActivate: 立即同步
                                   │ OnTick: 500ms 间隔
                                   ▼
                             Blackboard (脏 key)
                                   │
                                   ▼
                        BlackboardCheck (Decorator)
                             abort_type=both
                                   │ 条件变化 → Abort
                                   ▼
                        Selector 重新评估分支
```

---

## 3. 基础设施改造

### 3.1 Runner: OnTick 后同步 SetStatus

**问题**：当前 `tickNode` 调用 `n.OnTick(ctx)` 后不更新节点内部状态，导致 OnExit 中 `n.Status()` 始终是 Running，无法区分"自然完成"和"被打断"。

**改动**：`runner/runner.go` 的 `tickNode` 方法

```go
// 现在（runner.go:308-314）：
status := n.OnTick(ctx)
if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
    n.OnExit(ctx)
}

// 改为：
status := n.OnTick(ctx)
n.SetStatus(status)  // ← 新增：同步内部状态
if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
    n.OnExit(ctx)
}
```

同样，OnEnter 的非 Running 路径也需要同步：

```go
// 现在（runner.go:299-305）：
if n.Status() == node.BtNodeStatusInit {
    status := n.OnEnter(ctx)
    if status != node.BtNodeStatusRunning {
        n.OnExit(ctx)
        return status
    }
}

// 改为：
if n.Status() == node.BtNodeStatusInit {
    status := n.OnEnter(ctx)
    n.SetStatus(status)  // ← 新增
    if status != node.BtNodeStatusRunning {
        n.OnExit(ctx)
        return status
    }
}
```

**效果**：OnExit 中通过 `n.Status()` 区分退出原因：
- `Status() == Running` → 被打断（Abort/Stop）→ 需要清理
- `Status() == Success/Failed` → 自然完成 → 按需清理

**向后兼容性**：现有行为节点的 OnExit 不检查 Status()，全部无条件清理，因此这个改动不影响现有行为。新节点可以利用这个能力做差异化清理。

### 3.2 BtContext: 缓存 PoliceComp 和 VisionComp

按已有 GetMoveComp/GetDecisionComp 的缓存模式，新增：

```go
// context/context.go
func (c *BtContext) GetPoliceComp() *cpolice.NpcPoliceComp { ... }
func (c *BtContext) GetVisionComp() *cvision.VisionComp { ... }
```

同步更新 `Reset()` 和 `context_test.go` 的 TestReset 断言。

---

## 4. 新增节点

### 4.1 异步节点（OnTick 监控完成）

#### WaitForNavMeshArrival — 等待 NavMesh 移动到达

文件：`nodes/wait_for_arrival.go`

```go
type WaitForNavMeshArrivalNode struct {
    BaseLeafNode
}

func (n *WaitForNavMeshArrivalNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }
    // 验证 NavMesh 路径已设置
    if moveComp.IsNavPathComplete() {
        return node.BtNodeStatusSuccess  // 已经到了（路径为空 = 已到达）
    }
    return node.BtNodeStatusRunning
}

func (n *WaitForNavMeshArrivalNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }
    if moveComp.IsNavPathComplete() {
        return node.BtNodeStatusSuccess  // 到了
    }
    if !moveComp.NavMesh.IsMoving && !moveComp.IsNavPathComplete() {
        return node.BtNodeStatusFailed   // 异常停止（路径未完成但停了）
    }
    return node.BtNodeStatusRunning
}

func (n *WaitForNavMeshArrivalNode) OnExit(ctx *context.BtContext) {
    if n.Status() == node.BtNodeStatusRunning {
        // 被打断 → 停止移动
        if moveComp := ctx.GetMoveComp(); moveComp != nil {
            moveComp.StopNavMove()
        }
    }
    // 自然完成 → 不干预
}
```

#### WaitForRoadNetworkArrival — 等待路网移动到达

```go
type WaitForRoadNetworkArrivalNode struct {
    BaseLeafNode
}

func (n *WaitForRoadNetworkArrivalNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }
    if moveComp.IsFinish {
        return node.BtNodeStatusSuccess
    }
    return node.BtNodeStatusRunning
}

func (n *WaitForRoadNetworkArrivalNode) OnExit(ctx *context.BtContext) {
    if n.Status() == node.BtNodeStatusRunning {
        if moveComp := ctx.GetMoveComp(); moveComp != nil {
            moveComp.StopMove()
        }
    }
}
```

#### ChaseTarget — 追逐目标直到接近或丢失

文件：`nodes/chase_target.go`

```go
type ChaseTargetNode struct {
    BaseLeafNode
    targetFeatureKey  string  // 目标 entityID 的 feature key
    arriveDistance     float32 // 抓捕距离阈值（距离平方）
    visionTimeoutMs   int64   // 视野丢失超时（毫秒）
    lastSeenTime      int64   // 上次看见目标的时间（节点实例级，每次 Run 重建）
}

func (n *ChaseTargetNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 1. 获取追捕目标
    targetID, ok := ctx.GetFeatureUint64(n.targetFeatureKey)
    if !ok || targetID == 0 {
        return node.BtNodeStatusFailed
    }

    // 2. 设置 NavMesh 追逐
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }
    moveComp.Clear()
    moveComp.StartRun()
    moveComp.SetPathFindType(int32(cnpc.EPathFindType_NavMesh))
    moveComp.SetTargetEntity(targetID)
    moveComp.SetTargetType(cnpc.ETargetType_Player)

    // 3. 初始化视野超时计时器
    n.lastSeenTime = mtime.NowMilliTickWithOffset()

    return node.BtNodeStatusRunning
}

func (n *ChaseTargetNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    targetID, ok := ctx.GetFeatureUint64(n.targetFeatureKey)
    if !ok || targetID == 0 {
        return node.BtNodeStatusFailed  // 目标消失
    }

    // 1. 检查距离 → 够近了就 Success
    policeTransform := ctx.GetTransformComp()
    if policeTransform != nil {
        if playerTransform := n.getPlayerTransform(ctx, targetID); playerTransform != nil {
            distSq := calculateDistanceSquared(policeTransform.Position(), playerTransform.Position())
            policeComp := ctx.GetPoliceComp()
            if policeComp != nil && distSq < policeComp.GetConfig().ArrestingDistance {
                return node.BtNodeStatusSuccess  // 追到了！
            }
        }
    }

    // 2. 检查视野
    visionComp := ctx.GetVisionComp()
    if visionComp != nil {
        now := mtime.NowMilliTickWithOffset()
        if visionComp.IsEntityInVision(targetID) {
            n.lastSeenTime = now  // 还能看见，刷新计时
        } else if now-n.lastSeenTime > n.visionTimeoutMs {
            // 视野丢失超时 → 设置调查状态
            if policeComp := ctx.GetPoliceComp(); policeComp != nil {
                policeComp.AddArrestingPlayerToSuspicion()
                policeComp.SetArrestingPlayer(0)
                policeComp.SetInvestigatePlayer(targetID)
            }
            return node.BtNodeStatusFailed  // 丢了
        }
    }

    return node.BtNodeStatusRunning
}

func (n *ChaseTargetNode) OnExit(ctx *context.BtContext) {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return
    }
    // 无论完成还是被打断，都清理移动状态
    moveComp.StopMove()
    moveComp.SetPathFindType(int32(cnpc.EPathFindType_None))
    moveComp.SetTargetEntity(0)
    moveComp.SetTargetType(cnpc.ETargetType_None)
}
```

**关键设计**：
- `arriveDistance` 和 `visionTimeoutMs` 从 JSON params 读取，默认值从 PoliceComp 配置获取
- `lastSeenTime` 是节点实例级字段（每次 Run() 从 config 重建，不跨实例共享）
- OnTick 只**读** ECS 组件状态，不做业务计算（距离用现有 transform，视野用现有 VisionComp）
- 视野丢失时设置 `policeComp.SetInvestigatePlayer` → MiscSensor 更新 Feature → Service 更新 BB → Decorator Abort 切到调查分支

### 4.2 同步节点（OnEnter 即完成）

#### StartMove — 开始移动

```go
type StartMoveNode struct {
    BaseLeafNode
    runMode bool // true=跑步 false=走路
}

func (n *StartMoveNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }
    if n.runMode {
        moveComp.StartRun()
    } else {
        moveComp.StartMove()
    }
    return node.BtNodeStatusSuccess
}
```

#### PerformArrest — 执行逮捕

```go
type PerformArrestNode struct {
    BaseLeafNode
    targetFeatureKey string
}

func (n *PerformArrestNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    targetID, ok := ctx.GetFeatureUint64(n.targetFeatureKey)
    if !ok || targetID == 0 {
        return node.BtNodeStatusFailed
    }

    // 通过 PoliceSystem 执行逮捕（跨实体操作由 System 负责）
    policeSystem, ok := ctx.Scene.GetSystem(common.SystemType_NpcPolice)
    if !ok {
        return node.BtNodeStatusFailed
    }
    ps := policeSystem.(*police.NpcPoliceSystem)
    ps.CheckCloseRangeArrest(ctx.EntityID, targetID)

    return node.BtNodeStatusSuccess
}
```

**设计决策**：PerformArrest 不自己执行逮捕逻辑，而是调用 `PoliceSystem.CheckCloseRangeArrest`。因为逮捕是跨实体操作（传送玩家 + 清理所有追击同一玩家的警察），应由 System 层协调。BT 节点只负责触发时机。

#### ClearInvestigation — 清除调查状态

```go
type ClearInvestigationNode struct {
    BaseLeafNode
}

func (n *ClearInvestigationNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    policeComp := ctx.GetPoliceComp()
    if policeComp != nil {
        policeComp.SetInvestigatePlayer(0)
    }
    // 清除相关 Feature
    setFeature(ctx, "feature_release_wanted", false)
    setFeature(ctx, "feature_pursuit_miss", false)
    return node.BtNodeStatusSuccess
}
```

---

## 5. 复合树 JSON

### 5.1 police_enforcement.json

```json
{
  "name": "police_enforcement",
  "description": "警察执法 — 追捕/调查/返回日程，Sequence 编排异步步骤",
  "root": {
    "type": "Selector",
    "services": [
      {
        "type": "SyncFeatureToBlackboard",
        "interval_ms": 500,
        "params": {
          "mappings": {
            "feature_state_pursuit": "state_pursuit",
            "feature_pursuit_entity_id": "pursuit_target_id",
            "feature_pursuit_miss": "pursuit_miss"
          }
        }
      }
    ],
    "children": [
      {
        "type": "Sequence",
        "description": "追捕分支：追到目标 → 执行逮捕",
        "decorators": [
          {
            "type": "BlackboardCheck",
            "abort_type": "both",
            "params": { "key": "state_pursuit", "operator": "==", "value": true }
          }
        ],
        "children": [
          {
            "type": "ChaseTarget",
            "description": "NavMesh 追逐，到达抓捕距离 → Success，视野丢失 10s → Failed",
            "params": {
              "target_feature": "feature_pursuit_entity_id",
              "vision_timeout_ms": 10000
            }
          },
          {
            "type": "PerformArrest",
            "description": "调用 PoliceSystem 执行逮捕",
            "params": {
              "target_feature": "feature_pursuit_entity_id"
            }
          }
        ]
      },
      {
        "type": "Sequence",
        "description": "调查分支：走到最后看见位置 → 等待 → 清状态",
        "decorators": [
          {
            "type": "BlackboardCheck",
            "abort_type": "both",
            "params": { "key": "pursuit_miss", "operator": "==", "value": true }
          }
        ],
        "children": [
          {
            "type": "SetupNavMeshPathToFeature",
            "description": "从 Feature 获取最后看见位置，NavMesh 寻路",
            "params": {
              "pos_keys": ["feature_posx", "feature_posy", "feature_posz"]
            }
          },
          {
            "type": "StartMove",
            "description": "开始走路移动",
            "params": { "run_mode": false }
          },
          {
            "type": "WaitForNavMeshArrival",
            "description": "等待到达调查地点"
          },
          {
            "type": "Wait",
            "description": "到达后原地等待 5 秒",
            "params": { "duration_ms": 5000 }
          },
          {
            "type": "ClearInvestigation",
            "description": "清除调查状态和 Feature"
          }
        ]
      },
      {
        "type": "SubTree",
        "description": "执法结束，NavMesh 返回日程位置",
        "params": { "tree_name": "return_to_schedule" }
      }
    ]
  }
}
```

### 5.2 设计要点

1. **Service interval_ms=500**：匹配 MiscSensor 的 500ms 更新周期
2. **OnActivate 立即同步**：`SyncFeatureToBlackboard.OnActivate` 确保首帧 BB 值正确
3. **abort_type=both**：
   - **self**: 当前分支 guard 变 false → 中断（如追捕中抓到了 → state_pursuit=false）
   - **lower_priority**: 高优先级分支 guard 变 true → 中断低优先级（如调查中重新发现 → 切回追捕）
4. **ChaseTarget 视野超时**：10s 视野丢失由节点自己检测（OnTick 读 VisionComp），不依赖 PoliceSystem.handleArrestingPlayer
5. **PerformArrest 委托 System**：跨实体操作由 PoliceSystem 负责，BT 只触发时机
6. **调查等待 5s**：使用现有 Wait 节点，时间可配置
7. **SubTree 引用 return_to_schedule**：复用已有公共子树

---

## 6. 运行时场景分析

### 场景 A：追捕成功（追到并抓获）

```
1. Brain 决策 → police_enforcement plan
2. Selector.OnEnter → Service OnActivate 立即同步 BB
3. BB: state_pursuit=true → Sequence[pursuit] guard 通过
4. ChaseTarget.OnEnter → NavMesh 追逐，开始跑步
5. ChaseTarget.OnTick → Running...Running...
6. 距离 < ArrestingDistance → ChaseTarget 返回 Success
7. Sequence 推进 → PerformArrest.OnEnter → 调用 CheckCloseRangeArrest → Success
8. Sequence[pursuit] 完成 → MiscSensor 更新 → BB: state_pursuit=false
9. Decorator self-abort → Selector 重新评估
10. branch[0] 失败, branch[1] 失败 → SubTree(return_to_schedule)
11. 树完成 → TriggerCommand → Brain → 回到日程
```

### 场景 B：追捕丢失 → 调查 → 调查完成

```
1. ChaseTarget Running (追捕中)
2. 10s 视野丢失 → ChaseTarget.OnTick 设置 policeComp Investigate 状态 → 返回 Failed
3. Sequence[pursuit] 失败 → MiscSensor 更新 → BB: state_pursuit=false, pursuit_miss=true
4. Decorator abort → Selector 重新评估
5. branch[0] 失败 → branch[1] guard 通过 → Sequence[investigate] 开始
6. SetupNavMeshPath → Success → StartMove → Success → WaitForNavMeshArrival → Running...
7. 到达调查地点 → WaitForNavMeshArrival → Success
8. Wait(5s) → Running...Success
9. ClearInvestigation → Success → Sequence[investigate] 完成
10. BB: pursuit_miss=false → SubTree(return_to_schedule)
11. 树完成 → Brain → 回到日程
```

### 场景 C：调查中重新发现目标

```
1. Sequence[investigate] Running, WaitForNavMeshArrival 或 Wait 执行中
2. PoliceSystem.updateSuspicionSystem → 新目标 → SetArrestingPlayer
3. MiscSensor → feature_state_pursuit=true
4. Service → BB: state_pursuit=true (脏 key)
5. Decorator lower_priority abort → Sequence[investigate] 中断
6. WaitForNavMeshArrival.OnExit 或 Wait.OnExit（Status==Running → 被打断 → 清理移动）
7. Selector 从 branch[0] 重新评估 → guard 通过 → Sequence[pursuit] 开始
8. ChaseTarget.OnEnter → NavMesh 追逐新目标
```

### 场景 D：追捕中目标消失（非视野丢失，如玩家下线）

```
1. ChaseTarget.OnTick → targetID == 0 → 返回 Failed
2. Sequence[pursuit] 失败
3. MiscSensor → BB 更新 → Selector 重评估
4. 如果 pursuit_miss=true → 进调查分支
5. 如果 pursuit_miss=false → 进 return_to_schedule
```

---

## 7. Brain 配置变更（Blackman_State.json）

### 7.1 Plan 变更

**删除**：`pursuit`、`investigate`

**新增**：
```json
{
  "name": "police_enforcement",
  "entry_task": "do_entry",
  "exit_task": "do_exit",
  "main_task": "do_main"
}
```

### 7.2 Transition 删除清单（15 条）

| # | 名称 | 方向 |
|---|------|------|
| 1 | idle_to_pursuit | idle → pursuit |
| 2 | move_to_pursuit | move → pursuit |
| 3 | dialog_to_pursuit | dialog → pursuit |
| 4 | meeting_move_to_pursuit | meeting_move → pursuit |
| 5 | meeting_idle_to_pursuit | meeting_idle → pursuit |
| 6 | pursuit_to_home_idle | pursuit → home_idle |
| 7 | pursuit_to_idle | pursuit → idle |
| 8 | pursuit_to_move | pursuit → move |
| 9 | pursuit_to_meeting_idle | pursuit → meeting_idle |
| 10 | pursuit_to_meeting_move | pursuit → meeting_move |
| 11 | pursuit_to_investigate | pursuit → investigate |
| 12 | investigate_to_home_idle | investigate → home_idle |
| 13 | investigate_to_idle | investigate → idle |
| 14 | investigate_to_move | investigate → move |
| 15 | investigate_to_pursuit | investigate → pursuit |

### 7.3 Transition 新增清单（10 条）

**入口 transition（5 条，priority=3 最高优先级）**：

| # | 名称 | 条件 |
|---|------|------|
| 1 | idle_to_police_enforcement | feature_state_pursuit=true |
| 2 | move_to_police_enforcement | feature_state_pursuit=true |
| 3 | dialog_to_police_enforcement | feature_state_pursuit=true |
| 4 | meeting_move_to_police_enforcement | feature_state_pursuit=true |
| 5 | meeting_idle_to_police_enforcement | feature_state_pursuit=true |

> **注意**：`home_idle` 无入口（沿用现有设计：警察在家时不追捕）

**出口 transition（5 条）**：

| # | 名称 | 条件 | priority |
|---|------|------|----------|
| 1 | police_enforcement_to_home_idle | pursuit=false AND miss=false AND schedule=StayInBuilding | 1 |
| 2 | police_enforcement_to_idle | pursuit=false AND miss=false AND schedule=LocationBasedAction | 1 |
| 3 | police_enforcement_to_move | pursuit=false AND miss=false AND schedule=MoveToBPointFormAPoint | 1 |
| 4 | police_enforcement_to_meeting_idle | pursuit=false AND miss=false AND meeting_state=2 | 2 |
| 5 | police_enforcement_to_meeting_move | pursuit=false AND miss=false AND meeting_state=1 | 2 |

### 7.4 不再需要的 Brain 级 Feature

以下 Feature 从 Brain transition 条件中移除（但 EventSensor 仍产生）：
- `feature_arrested`：BT 内部通过 state_pursuit=false 自动处理
- `feature_release_wanted`：BT 内部通过 pursuit_miss=false 自动处理

---

## 8. PoliceSystem 改动

### 8.1 handleArrestingPlayer 移除（视野超时移入 ChaseTarget）

`handleArrestingPlayer` 中的 10s 视野丢失超时逻辑已由 `ChaseTarget.OnTick` 接管：
- ChaseTarget.OnTick 每帧检查 VisionComp，维护 lastSeenTime
- 超时后设置 policeComp.SetInvestigatePlayer → 返回 Failed

需要在 `updatePoliceLogic` 中跳过行为树管理的 NPC 的 handleArrestingPlayer 调用，或者用条件判断：如果 BT 正在运行 police_enforcement 树，则跳过 handleArrestingPlayer。

**推荐方案**：保留 handleArrestingPlayer 但让 ChaseTarget 先执行。由于 ChaseTarget.OnTick 在 BtTickSystem（每帧）中执行，而 handleArrestingPlayer 在 PoliceSystem（每 3 帧）中执行，ChaseTarget 会先检测到超时并设置 InvestigatePlayer 状态。handleArrestingPlayer 检查 `!policeComp.IsArresting()` 时会直接 return，不会重复操作。因此**无需修改 PoliceSystem**。

### 8.2 其他 System 不变

| System | 原因 |
|--------|------|
| updateSuspicionSystem | 在所有状态运行，是进入执法的前提 |
| DecaySuspicion | 在所有状态运行 |
| performArrest | 跨实体操作，由 PerformArrest 节点触发 |
| clearAllArrestData | 跨实体协调 |
| BeingWantedSystem | 玩家视角，跨警察聚合 |

---

## 9. 文件变更汇总

### 9.1 新增文件

| 文件 | 说明 |
|------|------|
| `bt/trees/police_enforcement.json` | 复合树 JSON |
| `bt/nodes/chase_target.go` | ChaseTarget 异步节点 |
| `bt/nodes/wait_for_arrival.go` | WaitForNavMeshArrival + WaitForRoadNetworkArrival |
| `bt/nodes/police_actions.go` | PerformArrest + ClearInvestigation + StartMove 同步节点 |

### 9.2 修改文件

| 文件 | 改动 |
|------|------|
| `bt/runner/runner.go` | tickNode 中 OnTick/OnEnter 后 SetStatus |
| `bt/context/context.go` | 新增 GetPoliceComp / GetVisionComp 缓存 |
| `bt/context/context_test.go` | TestReset 新增断言 |
| `bt/nodes/factory.go` | 注册 ChaseTarget / WaitForNavMeshArrival / WaitForRoadNetworkArrival / PerformArrest / ClearInvestigation / StartMove |
| `config/.../Blackman_State.json` | 删 2 plan + 15 transition，加 1 plan + 10 transition |
| `bt/integration_test.go` | 更新 3 处 JSON 文件列表 |
| `bt/integration_phased_test.go` | 更新 plan name 列表 |

### 9.3 删除文件

| 文件 | 原因 |
|------|------|
| `bt/trees/pursuit.json` | 合并到 police_enforcement.json |
| `bt/trees/investigate.json` | 合并到 police_enforcement.json |
| `bt/trees/pursuit_to_move_transition.json` | 不再需要独立 transition 树 |

### 9.4 不需要修改的文件

| 文件 | 原因 |
|------|------|
| `behavior_nodes.go` | PursuitBehavior/InvestigateBehavior 保留（其他 NPC 可能使用） |
| `executor.go` | 两层调度自动处理 |
| `misc_sensor.go` | Feature 同步逻辑不变 |
| `police_system.go` | handleArrestingPlayer 自动跳过（见 8.1） |
| `being_wanted_system.go` | 调查超时逻辑不变 |

---

## 10. 时序安全分析

### 10.1 ChaseTarget vs PoliceSystem.handleArrestingPlayer 竞态

两者都检测视野丢失超时，但不冲突：
- ChaseTarget.OnTick 在 BtTickSystem（每帧 ~33ms）中执行
- handleArrestingPlayer 在 PoliceSystem（每 3 帧 ~100ms）中执行
- ChaseTarget 先检测到超时 → 设置 InvestigatePlayer → 返回 Failed
- handleArrestingPlayer 下次执行时 `!policeComp.IsArresting()` → 直接 return
- 不存在重复操作

### 10.2 调查分支的 Wait(5s) vs BeingWantedSystem(35s)

- BT Wait(5s) 是调查地点原地等待时间（行为层）
- BeingWantedSystem 35s 是从最后有警察追捕到彻底解除通缉（系统层）
- 两者独立：Wait 完成后 ClearInvestigation 清状态 → MiscSensor 更新 → Brain 回日程
- BeingWantedSystem 35s 超时是安全兜底（所有警察都放弃后才释放玩家通缉）

### 10.3 Sequence 中断时的 OnExit 清理

Abort 打断 Sequence 时，Sequence.OnExit 会递归调用 Running 子节点的 OnExit：
- WaitForNavMeshArrival 被打断 → `Status()==Running` → `StopNavMove()` 清理移动
- Wait 被打断 → 无资源需要清理
- ChaseTarget 被打断 → 清理移动状态

### 10.4 Service OnActivate 保证首帧正确性

与之前分析相同：`SyncFeatureToBlackboard.OnActivate` 在树启动时立即同步 Feature → BB，确保首帧 Decorator 正确评估。

---

## 11. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| ChaseTarget 的 lastSeenTime 是节点实例级字段 | 每次树重建会重置 | 符合预期：每次进入追捕分支重新开始计时 |
| PerformArrest 调用 CheckCloseRangeArrest 但距离可能已变 | 可能判定不在抓捕距离内 | CheckCloseRangeArrest 内部有距离校验，不会误逮捕 |
| Runner SetStatus 改动影响现有节点 | 现有节点 OnExit 不检查 Status，全部无条件清理 | 向后兼容，不影响现有行为 |
| NavMesh.IsMoving 在极端情况下不准确 | WaitForNavMeshArrival 可能误判 | 同时检查 IsNavPathComplete + IsMoving 双重判断 |
| 老的 PursuitBehavior/InvestigateBehavior 节点仍注册 | 死代码 | 保留不删除，其他 NPC 可能使用，无副作用 |
| Brain 1s 评估间隔与 BT 完成的时序窗口 | Brain 可能在 BT 完成前触发 GSSExit | btRunner.Stop() 幂等 |
