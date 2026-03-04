# 设计方案：行为树长运行行为节点重构

## 1. 需求回顾

### 1.1 背景

当前行为树系统采用"on_exit 子树"模式管理行为生命周期：
- `BTreeConfig.OnExit` 字段：JSON 配置中与 `root` 平级的 `on_exit` 子树
- `Runner.executeOnExitTree()`：在 Stop() 和 Tick() 完成时同步执行 on_exit 子树
- 10 对 entry/exit 行为节点：entry 节点在 root 的 Sequence 中执行初始化，exit 逻辑由 on_exit 子树承载

### 1.2 问题

1. **on_exit 与 root 平级不自然**：行为树不应在 config 层面携带生命周期钩子，这属于状态机模式
2. **双重执行风险**：Tick 完成和 Stop 都会触发 on_exit，已修复但增加了复杂度
3. **节点对不成对**：entry 节点在树内，exit 节点在 on_exit 里，结构不对称

### 1.3 新设计方向

**长运行行为节点**：每个行为节点自身管理完整生命周期

- `OnEnter`：初始化行为（返回 Running）
- `OnTick`：保持运行（返回 Running）
- `OnExit`：清理行为（Runner.Stop() 时自动递归调用）

本质：将状态机的 enter/exit 语义下沉到节点的代码级生命周期，不暴露给 JSON 配置。

## 2. 架构变更

### 2.1 BTreeConfig — 移除 OnExit 字段

**Before:**
```go
type BTreeConfig struct {
    Name        string      `json:"name"`
    Description string      `json:"description,omitempty"`
    Root        NodeConfig  `json:"root"`
    OnExit      *NodeConfig `json:"on_exit,omitempty"` // 移除
}
```

**After:**
```go
type BTreeConfig struct {
    Name        string     `json:"name"`
    Description string     `json:"description,omitempty"`
    Root        NodeConfig `json:"root"`
}
```

### 2.2 Runner — 移除 executeOnExitTree

**移除方法：** `executeOnExitTree(instance *TreeInstance)`

**修改 Stop()：**
```go
func (r *BtRunner) Stop(entityID uint64) {
    instance, ok := r.runningTrees[entityID]
    if !ok {
        return
    }
    // 递归调用所有运行中节点的 OnExit（已有逻辑，保留）
    r.stopNode(instance.Root, instance.Context)
    // 移除：r.executeOnExitTree(instance)
    // 清理 Observer 和实例
    instance.Context.RemoveObservers()
    instance.Context.ClearFrameDirtyKeys()
    delete(r.runningTrees, entityID)
}
```

**修改 Tick() 完成路径：**
```go
if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
    // 移除：r.executeOnExitTree(instance)
    instance.Context.RemoveObservers()
    delete(r.runningTrees, entityID)
}
```

### 2.3 清理保证

清理逻辑通过 **节点级 OnExit** 保证：

| 场景 | 触发路径 | 清理方式 |
|------|---------|---------|
| Plan 切换（Stop → Run） | `Stop()` → `stopNode()` 递归 | 运行中节点的 `OnExit()` 被调用 |
| 树正常完成 | `Tick()` → `tickNode()` | 节点完成时 `OnExit()` 被调用 |

Runner.stopNode() 已有递归逻辑：遍历所有子节点，对 Running 状态的节点调用 OnExit。长运行行为节点在 Sequence 中保持 Running，Stop 时必然被清理。

## 3. 行为节点合并设计

### 3.1 合并原则

- 每对 entry + exit 节点合并为一个长运行行为节点
- `OnEnter`：执行原 entry 节点的全部初始化逻辑，返回 **Running**
- `OnTick`：返回 **Running**（保持运行，等待外部中断）
- `OnExit`：执行原 exit 节点的全部清理逻辑

### 3.2 合并映射表

| Plan | 原 Entry 节点 | 原 Exit 节点 | 新节点名 | 说明 |
|------|-------------|------------|---------|------|
| idle | StandAtSchedulePos | ClearIdleState | IdleBehavior | 站在日程位置 + 清除对话超时 |
| home_idle | StandAtHomePos | ClearHomeIdleState | HomeIdleBehavior | 站在家门口 + 清除敲门请求 |
| move | GoToSchedulePoint | StopMoving | MoveBehavior | 路网寻路+开始移动 + 停止移动 |
| dialog | StartDialog | EndDialog | DialogBehavior | 开始对话 + 结束对话 |
| pursuit | ChaseTarget | ClearPursuitState | PursuitBehavior | 追逐目标 + 清除追逐状态 |
| investigate | GoToInvestigatePos | ClearInvestigateState | InvestigateBehavior | NavMesh寻路 + 清除调查状态 |
| meeting_idle | StandAtMeetingPos | (Log only) | MeetingIdleBehavior | 站在聚会位置（无清理） |
| meeting_move | GoToMeetingPoint | StopMoving | MeetingMoveBehavior | 前往聚会 + 停止移动 |
| sakura_npc_control | EnterPlayerControl | ExitPlayerControl | PlayerControlBehavior | 进入控制 + 退出控制+NavMesh寻路 |
| proxy_trade | StartProxyTrade | EndProxyTrade | ProxyTradeBehavior | 开始交易 + 结束交易 |

**保留不变：** `ReturnToScheduleNode`（transition 节点，一次性执行，不需要长运行）

### 3.3 详细节点设计

#### 3.3.1 IdleBehavior

```go
type IdleBehaviorNode struct {
    BaseLeafNode
}

func (n *IdleBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // === 原 StandAtSchedulePos.OnEnter 逻辑 ===
    // 1. 获取日程数据（scheduleComp, nowState）
    // 2. 设置 Transform（setTransformFromFeature）
    // 3. 设置对话超时（dialogComp.SetOutFinishStamp）
    // 4. 设置外出时长（townNpcComp.SetOutDurationTime）
    // 失败则返回 Failed，成功返回 Running
    ...
    n.SetStatus(node.BtNodeStatusRunning)
    return node.BtNodeStatusRunning
}

func (n *IdleBehaviorNode) OnTick(ctx *context.BtContext) node.BtNodeStatus {
    return node.BtNodeStatusRunning // 持续运行，等待 Plan 切换中断
}

func (n *IdleBehaviorNode) OnExit(ctx *context.BtContext) {
    // === 原 ClearIdleState.OnEnter 逻辑 ===
    // dialogComp.SetOutFinishStamp(0)
    ...
}
```

#### 3.3.2 HomeIdleBehavior

```go
func (n *HomeIdleBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 StandAtHomePos: setFeature("feature_out_timeout", true) + setTransformFromFeature
    ...
    return node.BtNodeStatusRunning
}

func (n *HomeIdleBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 ClearHomeIdleState: setFeature("feature_knock_req", false)
    ...
}
```

#### 3.3.3 MoveBehavior

```go
func (n *MoveBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 GoToSchedulePoint: 快速路径检查 → 路网寻路 → 设置移动
    ...
    return node.BtNodeStatusRunning
}

func (n *MoveBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 StopMoving: moveComp.StopMove()
    ...
}
```

#### 3.3.4 DialogBehavior

```go
func (n *DialogBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 StartDialog: 清特征 → 暂停 → 记时间 → 设状态 → 设角色ID
    ...
    return node.BtNodeStatusRunning
}

func (n *DialogBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 EndDialog: 清特征 → 恢复 → 补偿时间 → 设idle状态
    ...
}
```

#### 3.3.5 PursuitBehavior

```go
func (n *PursuitBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 ChaseTarget: 获取目标ID → 清路径 → 跑步 → NavMesh → 设目标
    ...
    return node.BtNodeStatusRunning
}

func (n *PursuitBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 ClearPursuitState: 停止移动 → 清寻路 → 清目标
    ...
}
```

#### 3.3.6 InvestigateBehavior

```go
func (n *InvestigateBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 GoToInvestigatePos: setupNavMeshPathToFeature
    ...
    return node.BtNodeStatusRunning
}

func (n *InvestigateBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 ClearInvestigateState: 清调查目标 → 清Feature
    ...
}
```

#### 3.3.7 MeetingIdleBehavior

```go
func (n *MeetingIdleBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 StandAtMeetingPos: setTransformFromFeature(meetingPosKeys, meetingRotKeys)
    ...
    return node.BtNodeStatusRunning
}

func (n *MeetingIdleBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 on_exit 只是 Log，无实际清理
}
```

#### 3.3.8 MeetingMoveBehavior

```go
func (n *MeetingMoveBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 GoToMeetingPoint: 查最近路点 → 获取聚会点 → 路网寻路 → 设移动
    ...
    return node.BtNodeStatusRunning
}

func (n *MeetingMoveBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 StopMoving: moveComp.StopMove()
    ...
}
```

#### 3.3.9 PlayerControlBehavior

```go
func (n *PlayerControlBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 EnterPlayerControl: 停止移动 → 清事件类型
    ...
    return node.BtNodeStatusRunning
}

func (n *PlayerControlBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 ExitPlayerControl: 清事件类型 → NavMesh寻路回Feature位置
    ...
}
```

#### 3.3.10 ProxyTradeBehavior

```go
func (n *ProxyTradeBehaviorNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 原 StartProxyTrade: proxyTradeComp.SetTradeStatus(InTrade)
    ...
    return node.BtNodeStatusRunning
}

func (n *ProxyTradeBehaviorNode) OnExit(ctx *context.BtContext) {
    // 原 EndProxyTrade: proxyTradeComp.SetTradeStatus(None)
    ...
}
```

## 4. JSON 配置变更

### 4.1 通用模式变化

**Before（entry + on_exit）：**
```json
{
  "name": "idle",
  "on_exit": { "type": "ClearIdleState" },
  "root": {
    "type": "Sequence",
    "services": [...],
    "children": [
      {"type": "StandAtSchedulePos"},
      {"type": "Repeater", "params": {"count": 0}, "child": {
        "type": "Wait", "params": {"duration_ms": 1000}
      }}
    ]
  }
}
```

**After（长运行行为节点）：**
```json
{
  "name": "idle",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "UpdateSchedule", "params": {"interval_ms": 5000}}
    ],
    "children": [
      {"type": "IdleBehavior"}
    ]
  }
}
```

核心变化：
1. 移除 `on_exit` 字段
2. 用 `IdleBehavior` 替代 `StandAtSchedulePos` + `Repeater(Wait)`
3. IdleBehavior 自身在 OnEnter 中初始化、OnTick 中保持 Running、OnExit 中清理
4. Service 保留在 Sequence（或直接放在行为节点的父节点上）

### 4.2 10 棵树的新 JSON

#### idle.json
```json
{
  "name": "idle",
  "description": "NPC 空闲状态 - 站在日程位置，持续等待",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "UpdateSchedule", "params": {"interval_ms": 5000}}
    ],
    "children": [
      {"type": "IdleBehavior"}
    ]
  }
}
```

#### home_idle.json
```json
{
  "name": "home_idle",
  "description": "NPC 家中空闲状态 - 站在家门口，持续等待",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "Log", "params": {"message": "[HomeIdle] at home", "interval_ms": 5000, "level": "debug"}}
    ],
    "children": [
      {"type": "HomeIdleBehavior"}
    ]
  }
}
```

#### move.json
```json
{
  "name": "move",
  "description": "NPC 移动状态 - 前往日程地点，持续移动中",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "Log", "params": {"message": "[Move] moving", "interval_ms": 3000, "level": "debug"}}
    ],
    "children": [
      {"type": "MoveBehavior"}
    ]
  }
}
```

#### dialog.json
```json
{
  "name": "dialog",
  "description": "NPC 对话状态 - 开始对话，持续对话中",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "Log", "params": {"message": "[Dialog] in dialog", "interval_ms": 5000, "level": "debug"}}
    ],
    "children": [
      {"type": "DialogBehavior"}
    ]
  }
}
```

#### pursuit.json
```json
{
  "name": "pursuit",
  "description": "NPC 追捕 - 追逐目标，目标丢失时结束",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "PursuitBehavior"},
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
              {"type": "Log", "params": {"message": "[Pursuit] has target, pursuing", "level": "debug"}},
              {"type": "Repeater", "params": {"count": 0}, "child": {
                "type": "Wait", "params": {"duration_ms": 500}
              }}
            ]
          },
          {
            "type": "Sequence",
            "children": [
              {"type": "Log", "params": {"message": "[Pursuit] target lost", "level": "info"}}
            ]
          }
        ]
      }
    ]
  }
}
```

> pursuit 比较特殊：PursuitBehavior 作为 Sequence 第一个子节点（长运行），但实际 pursuit 树还有后续的目标丢失检测逻辑。当 PursuitBehavior 返回 Running 时，Sequence 会等待它完成后才执行下一个子节点。这意味着目标丢失检测不会被执行。
>
> **解决方案**：pursuit 树不使用长运行模式，PursuitBehavior 的 OnEnter 初始化后返回 Success（与现有 ChaseTarget 一致），OnExit 做清理。后续的 Selector 仍用 Repeater+Wait 保持运行。Stop 时 Runner.stopNode 会递归清理所有 Running 节点，PursuitBehavior 的 OnExit 在此时被调用。
>
> 但注意：如果 PursuitBehavior.OnEnter 返回 Success，tickNode 会立即调用 OnExit。这意味着清理会在初始化后立刻执行，不符合预期。
>
> **最终方案**：保持 pursuit 现有结构不变（ChaseTarget 返回 Success），但将 ClearPursuitState 的逻辑挂到树被 Stop 时触发。具体做法：让 PursuitBehavior 用长运行模式包裹整个 pursuit 逻辑——即 PursuitBehavior 是树的**唯一根行为节点**，OnEnter 做初始化返回 Running，OnExit 做清理。pursuit 的条件判断逻辑移到树的其他位置（Service 或 Decorator）。
>
> **实际上更简洁的做法**：对于 pursuit 这种需要后续条件逻辑的行为，拆分为初始化节点 + 清理行为节点。但这又回到了 entry/exit 分离的模式。
>
> **决策**：Pursuit 采用与其他行为一致的长运行模式。将整棵树简化为 PursuitBehavior 单节点（长运行），目标丢失检测通过 Service 或 Decorator 在树层面处理。目标丢失时通过 Blackboard 变化触发 abort，Runner.Stop 执行清理。

#### investigate.json
```json
{
  "name": "investigate",
  "description": "NPC 调查状态 - 前往调查位置，持续调查中",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "Log", "params": {"message": "[Investigate] investigating", "interval_ms": 3000, "level": "debug"}}
    ],
    "children": [
      {"type": "InvestigateBehavior"}
    ]
  }
}
```

#### meeting_idle.json
```json
{
  "name": "meeting_idle",
  "description": "NPC 会议空闲状态 - 站在聚会位置，持续等待",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "Log", "params": {"message": "[MeetingIdle] in meeting", "interval_ms": 5000, "level": "debug"}}
    ],
    "children": [
      {"type": "MeetingIdleBehavior"}
    ]
  }
}
```

#### meeting_move.json
```json
{
  "name": "meeting_move",
  "description": "NPC 前往会议状态 - 前往聚会地点，持续移动中",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "Log", "params": {"message": "[MeetingMove] moving to meeting", "interval_ms": 3000, "level": "debug"}}
    ],
    "children": [
      {"type": "MeetingMoveBehavior"}
    ]
  }
}
```

#### sakura_npc_control.json
```json
{
  "name": "sakura_npc_control",
  "description": "樱校 NPC 控制状态 - 进入玩家控制，持续等待释放",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "Log", "params": {"message": "[SakuraNpcControl] under control", "interval_ms": 5000, "level": "debug"}}
    ],
    "children": [
      {"type": "PlayerControlBehavior"}
    ]
  }
}
```

#### proxy_trade.json
```json
{
  "name": "proxy_trade",
  "description": "NPC 代理交易状态 - 开始交易，持续等待",
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "Log", "params": {"message": "[ProxyTrade] trading", "interval_ms": 5000, "level": "debug"}}
    ],
    "children": [
      {"type": "ProxyTradeBehavior"}
    ]
  }
}
```

## 5. Pursuit 特殊处理

Pursuit 是唯一有复杂条件逻辑的行为树。当前结构：
```
Sequence
├── ChaseTarget (Success → 初始化追逐)
└── Selector (条件分支，target 丢失检测)
    ├── Sequence [BlackboardCheck: target!=0, abort=both]
    │   ├── Log("has target")
    │   └── Repeater(0) → Wait(500)
    └── Sequence
        └── Log("target lost")
```

on_exit: ClearPursuitState

**问题**：PursuitBehavior 用长运行模式（OnEnter→Running），Sequence 会卡在第一个子节点，后续 Selector 不执行。

**解决方案**：Pursuit 保持特殊结构，使用 SimpleParallel：

```json
{
  "name": "pursuit",
  "root": {
    "type": "SimpleParallel",
    "params": {"finish_mode": "immediate"},
    "children": [
      {"type": "PursuitBehavior"},
      {
        "type": "Selector",
        "services": [
          {"type": "SyncFeatureToBlackboard", "params": {"interval_ms": 200, "mappings": {"feature_pursuit_entity_id": "target_entity_id"}}}
        ],
        "children": [
          {
            "type": "Sequence",
            "decorators": [
              {"type": "BlackboardCheck", "params": {"key": "target_entity_id", "operator": "!=", "value": 0}, "abort_type": "both"}
            ],
            "children": [
              {"type": "Log", "params": {"message": "[Pursuit] has target", "level": "debug"}},
              {"type": "Repeater", "params": {"count": 0}, "child": {"type": "Wait", "params": {"duration_ms": 500}}}
            ]
          },
          {"type": "Log", "params": {"message": "[Pursuit] target lost", "level": "info"}}
        ]
      }
    ]
  }
}
```

- `SimpleParallel` 的主任务是 `PursuitBehavior`（长运行），后台任务是条件检测 Selector
- 主任务完成（被 abort 或失败）→ SimpleParallel 结束 → 触发子节点 OnExit
- Stop 时 → `stopNode` 递归 → PursuitBehavior.OnExit 清理追逐状态

## 6. Factory 注册变更

### 6.1 移除的节点注册

```
StandAtSchedulePos, ClearIdleState
StandAtHomePos, ClearHomeIdleState
GoToSchedulePoint, StopMoving
StartDialog, EndDialog
ChaseTarget, ClearPursuitState
GoToInvestigatePos, ClearInvestigateState
StandAtMeetingPos
GoToMeetingPoint
EnterPlayerControl, ExitPlayerControl
StartProxyTrade, EndProxyTrade
```

共 19 个节点注册（10 entry + 9 exit，StopMoving 被 move 和 meeting_move 共用）。

### 6.2 新增的节点注册

```go
f.RegisterWithMeta(&NodeMeta{
    Type:        "IdleBehavior",
    Category:    CategoryAction,
    Description: "空闲行为 - 站在日程位置，等待中断",
}, createIdleBehaviorNode)

f.RegisterWithMeta(&NodeMeta{
    Type:        "HomeIdleBehavior",
    Category:    CategoryAction,
    Description: "家中空闲行为 - 站在家门口，等待中断",
}, createHomeIdleBehaviorNode)

// ... 类似注册其余 8 个
```

共 10 个新节点注册。

### 6.3 保留不变

- `ReturnToSchedule`：transition 节点，一次性执行，不需要改造
- 所有控制节点、装饰器、工具节点、条件装饰器、服务均保持不变

## 7. Executor 影响

### 7.1 Channel 1/1.5 路径

不受影响。行为树名称不变（idle, move, dialog 等），Channel 1.5 仍用 planName 查找。

### 7.2 Channel 2 硬编码回退

executor.go 中大量 Deprecated 的 handleXxxEntryTask / handleXxxExitTask 方法。
这些方法作为 Channel 2 回退已长期存在，本次不做删除（渐进式迁移，Channel 2 作为安全网）。

### 7.3 Exit 任务处理

当前 OnPlanCreated 中 exit task 类型会调用 `btRunner.Stop()`，这已经是正确行为：
- Stop → stopNode 递归 → 行为节点 OnExit 执行清理
- 不再需要 executeOnExitTree

## 8. 测试变更

### 8.1 Runner 测试

- 移除 `TestOnExit_TickFailureTriggersOnExit`：on_exit 机制不存在了
- 移除 `TestOnExit_NoDuplicateExecution`：同上
- 修改其他涉及 on_exit 的测试用例
- 新增：测试长运行节点 OnExit 在 Stop 时被调用

### 8.2 集成测试

- `TestAllJSONFilesValid`：验证新 JSON 无 on_exit 字段
- `TestLoadSpecificTrees`：验证新节点类型能正确加载
- `TestCountNodeTypes`：移除 on_exit 计数逻辑

### 8.3 新增测试

- 测试长运行行为节点的 OnEnter 返回 Running
- 测试 Stop 时 OnExit 被正确调用
- 测试 Tick 多帧后 OnTick 持续返回 Running

## 9. 文件变更汇总

| 文件 | 变更 |
|------|------|
| `config/types.go` | 移除 `OnExit *NodeConfig` 字段 |
| `runner/runner.go` | 移除 `executeOnExitTree`，简化 Stop/Tick |
| `nodes/behavior_nodes.go` | 重写：19 个 entry/exit 节点 → 10 个长运行行为节点 |
| `nodes/factory.go` | 移除 19 个旧注册，新增 10 个长运行节点注册 |
| `trees/idle.json` | 移除 on_exit，用 IdleBehavior 替代 |
| `trees/home_idle.json` | 移除 on_exit，用 HomeIdleBehavior 替代 |
| `trees/move.json` | 移除 on_exit，用 MoveBehavior 替代 |
| `trees/dialog.json` | 移除 on_exit，用 DialogBehavior 替代 |
| `trees/pursuit.json` | 移除 on_exit，用 SimpleParallel + PursuitBehavior |
| `trees/investigate.json` | 移除 on_exit，用 InvestigateBehavior 替代 |
| `trees/meeting_idle.json` | 移除 on_exit，用 MeetingIdleBehavior 替代 |
| `trees/meeting_move.json` | 移除 on_exit，用 MeetingMoveBehavior 替代 |
| `trees/sakura_npc_control.json` | 移除 on_exit，用 PlayerControlBehavior 替代 |
| `trees/proxy_trade.json` | 移除 on_exit，用 ProxyTradeBehavior 替代 |
| `runner/runner_test.go` | 移除 on_exit 相关测试，新增长运行节点测试 |
| `integration_test.go` | 更新节点计数和验证逻辑 |
| `integration_phased_test.go` | 更新为新架构验证 |

## 10. 行为等价性对照

### 关键对照点

| 对照项 | Before | After |
|--------|--------|-------|
| 初始化时机 | entry 节点在 Sequence 中执行 | OnEnter 在 Runner.tickNode 首次进入时执行 |
| 运行期间 | Repeater(0)+Wait 保持 Running | OnTick 返回 Running |
| 清理时机 (Stop) | executeOnExitTree → on_exit 子树 | stopNode 递归 → OnExit |
| 清理时机 (完成) | Tick 完成 → executeOnExitTree | tickNode 完成 → OnExit |
| 初始化失败 | entry 节点返回 Failed → Sequence 失败 → 树完成 | OnEnter 返回 Failed → tickNode 返回 Failed → 树完成 |

### OnExit 中的错误处理

原 exit 节点在 OnEnter 中执行清理逻辑，获取组件失败时返回 Failed。
新 OnExit 方法无返回值（void），组件获取失败时只记录 Warning 日志，确保不影响其他清理。

## 11. 风险与缓解

| 风险 | 说明 | 缓解 |
|------|------|------|
| OnExit 未被调用 | 节点不在 Running 状态时，stopNode 不会调用 OnExit | 长运行节点 OnEnter 必须返回 Running（测试覆盖） |
| 初始化失败的清理 | OnEnter 返回 Failed 后，tickNode 会调用 OnExit | OnExit 实现幂等，空状态也能安全清理 |
| Pursuit 特殊逻辑 | SimpleParallel 使用带来的额外复杂度 | 完整测试 pursuit 树的生命周期 |
| Channel 2 回退 | 硬编码逻辑仍存在但不被执行 | 保留 Deprecated 标记，后续独立清理 |
