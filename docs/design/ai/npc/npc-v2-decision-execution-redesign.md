# V2 决策-执行架构重设计

> **目标**：对标 GTA5 正交维度并行架构，重新设计 P1 的 NPC 决策与执行系统。
>
> 基于 V2 配置驱动重构（已归档）的讨论演进，修正"单状态机"方案的不足。
>
> 生成日期：2026-03-12

---

## 目录

1. [设计原则](#1-设计原则)
2. [架构总览](#2-架构总览)
3. [NPC State 共享状态](#3-npc-state-共享状态)
4. [全局守卫](#4-全局守卫)
5. [决策维度划分](#5-决策维度划分)
6. [执行层：PlanHandler](#6-执行层planhandler)
7. [每帧执行流程](#7-每帧执行流程)
8. [State 写入仲裁](#8-state-写入仲裁)
9. [InteractionLock 生命周期](#9-interactionlock-生命周期)
10. [全局守卫恢复协议](#10-全局守卫恢复协议)
11. [任务/脚本系统接入](#11-任务脚本系统接入)
12. [JSON 配置格式](#12-json-配置格式)
13. [与原设计对比](#13-与原设计对比)
14. [扩展路径](#14-扩展路径)

---

## 1. 设计原则

### 1.1 从 GTA5 架构中提取的核心原则

| 原则 | 说明 | GTA5 对应 |
|------|------|-----------|
| **正交维度并行** | 独立维度并行输出，维度内互斥 | 5 个决策系统并行，系统内优先级互斥 |
| **决策与执行分离** | 决策选"做什么"（Plan），执行管"怎么做" | 决策系统 → 行为树 |
| **NPC State 单一数据源** | 所有维度从同一个 State 读取，不直接通信 | 隐式协调模式 |
| **全局守卫优先** | 死亡/失能等状态接管一切，跳过所有决策 | BT_Damage |
| **写入仲裁** | 多维度写同一字段时按优先级仲裁 | WriteBuffer + StateArbiter |
| **恢复协议** | 全局守卫退出后从零评估，不续接旧状态 | 第 11 节恢复协议 |

### 1.2 P1 与 GTA5 的差异适配

| GTA5 | P1 | 差异原因 |
|------|----|---------|
| C++ 单机引擎，帧级 Tick | Go 服务端，毫秒级 Tick | 服务端无动画/物理层 |
| 5 个决策维度 | 3+1 个决策维度 | P1 业务较简单，交战+武器合并 |
| 14 棵行为树 | ~8 棵行为树 | 按需配置，不提前膨胀 |
| 动画映射层 | 无（客户端负责） | 服务端只输出行为状态 |
| WriteBuffer 帧末仲裁 | 写入时优先级覆盖 | P1 实际冲突极少，简化实现 |

### 1.3 决策 vs 执行的分界线

**策划需要调转换条件的 → 决策层（V2Brain JSON 配置）**

**程序控制的执行细节 → 执行层（PlanHandler / 行为树）**

决策层输出 Plan 名（秒级切换），执行层负责 Plan 的多帧执行流程（帧级控制）。
同一 Plan 内可以有并行子行为（如战斗中边移动边攻击），由行为树处理。

---

## 2. 架构总览

```
┌─ 感知层 ───────────────────────────────────────────────────────────┐
│                                                                     │
│  SensorPlugin（插件化采集）→ NPC State                              │
│  ├── StateSensorPlugin      （Movement.IsMoving 等）               │
│  ├── PursuitSensorPlugin    （Combat.PursuitEntity 等）            │
│  ├── ScheduleSensorPlugin   （Schedule.CurrentNode 等）            │
│  └── EventSensorPlugin      （Social.InDialog 等）                 │
│                                                                     │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼
┌─ NPC State ──────────────────────────────────────────────────────────┐
│  Snapshot（只读副本，所有决策系统的唯一输入）                          │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
┌─ 全局守卫 ───────────────────┼───────────────────────────────────────┐
│  IsDead / IsStunned / ...    │                                       │
│  → 触发时接管输出，跳过所有决策系统                                    │
└──────────────────────────────┼───────────────────────────────────────┘
                               │ 未触发时继续
┌─ 决策层（3+1 个 V2Brain 并行）┼───────────────────────────────────────┐
│                              │                                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │ 运动载体  │  │   导航   │  │   交战   │  │   表现   │            │
│  │ 怎么动？  │  │  去哪？  │  │ 与谁对抗？│  │ 姿态叠加 │            │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘            │
│       │Plan          │Plan         │Plan          │Plan              │
└───────┼──────────────┼─────────────┼──────────────┼──────────────────┘
        │              │             │              │
┌─ 仲裁层 ─────────────┼─────────────┼──────────────┼──────────────────┐
│       │              │             │              │                   │
│       │         State 写入仲裁（moveTarget 等共享字段）               │
│       │              │             │              │                   │
└───────┼──────────────┼─────────────┼──────────────┼──────────────────┘
        │              │             │              │
┌─ 执行层（PlanHandler）┼─────────────┼──────────────┼──────────────────┐
│       ▼              ▼             ▼              ▼                   │
│   PlanHandler    PlanHandler   PlanHandler    PlanHandler             │
│   (简单/行为树)  (简单/行为树)  (简单/行为树)  (简单/直写)             │
│       │              │             │              │                   │
└───────┼──────────────┼─────────────┼──────────────┼──────────────────┘
        │              │             │              │
        ▼              ▼             ▼              ▼
┌─ ECS 组件 ───────────────────────────────────────────────────────────┐
│  NpcMoveComp / DialogComp / CombatComp / AnimComp / ...              │
└──────────────────────────────────────────────────────────────────────┘
```

**与 GTA5 对比**：

| 层 | GTA5 | P1 |
|----|------|----|
| 感知层 | CPedPerception + EntityScanner | SensorPlugin 插件化 |
| 状态层 | NPC State（内存结构） | NpcState + Snapshot（sync.Pool） |
| 全局守卫 | BT_Damage（22 个物理接管节点） | GlobalGuard（死亡/眩晕/被控） |
| 决策层 | 5 个硬编码 Evaluate() | 3+1 个 V2Brain（JSON 配置） |
| 仲裁层 | WriteBuffer + StateArbiter | 写入时优先级覆盖 |
| 执行层 | 行为树（14 棵） | PlanHandler（简单直写 + 复杂挂行为树） |
| 输出层 | 动画映射层 | 直写 ECS（服务端无动画） |

---

## 3. NPC State 共享状态

所有决策系统的唯一输入。由感知插件每 Tick 更新，决策系统通过只读 Snapshot 访问。

### 3.1 状态字段

| 分类 | 字段 | 类型 | 说明 | GTA5 对应 |
|------|------|------|------|-----------|
| **感知** | `Perception.DialogRequests` | []uint64 | 待处理的对话请求 | — |
| | `Perception.TradeRequests` | []uint64 | 待处理的交易请求 | — |
| | `Perception.ThreatEntities` | []uint64 | 威胁实体列表 | nearestEnemy |
| **自身** | `Self.IsDead` | bool | 是否死亡 | isDead |
| | `Self.IsStunned` | bool | 是否眩晕/被控 | isRagdoll |
| | `Self.EntityID` | uint64 | 自身实体 ID | — |
| **运动** | `Movement.IsMoving` | bool | 是否移动中 | — |
| | `Movement.MotionMode` | enum | ON_FOOT / IN_VEHICLE / MOUNTED | currentMotionMode |
| | `Movement.MoveTarget` | Vec3 | 移动目标点（可由多方写入） | moveTarget |
| | `Movement.MoveSource` | enum | 写入来源（仲裁用） | moveSource |
| **日程** | `Schedule.CurrentNode` | int | 当前日程节点 | — |
| | `Schedule.HasTarget` | bool | 是否有日程目标 | — |
| | `Schedule.MeetingState` | int | 会议状态 | — |
| **战斗** | `Combat.PursuitEntity` | uint64 | 追击目标 | nearestEnemy |
| | `Combat.ThreatLevel` | enum | NONE / SUSPICIOUS / COMBAT | threatLevel |
| | `Combat.InFight` | bool | 是否交战中 | — |
| **社交** | `Social.InDialog` | bool | 是否对话中 | — |
| | `Social.InTrade` | bool | 是否交易中 | — |
| | `Social.HasInteraction` | bool | 是否有待处理交互 | — |
| **锁定** | `Lock.InteractionLock` | enum | NONE / MELEE（仅交战维度写入） | interactionLock |
| | `Lock.LockTimer` | int64 | 锁定计时器（超时保护） | interactionLockTimer |
| **脚本** | `Script.Override` | bool | 任务脚本强制模式 | scriptOverride |
| | `Script.MoveTarget` | Vec3 | 脚本指定移动目标 | — |

### 3.2 更新时机

```
每 Tick 执行顺序：
1. SensorPlugin 更新 NpcState             ← 先更新状态
2. 生成 Snapshot（只读副本）               ← 冻结当前帧数据
3. 全局守卫检查                            ← 在决策之前判断（触发则清理+跳过）
4. InteractionLock 检查                    ← 锁定期间抑制运动载体/导航
5. 重置可写字段 + 日程写入 MoveTarget       ← 准备本帧写入
6. 各维度 决策→执行 交替进行                ← 写入方先于读取方（详见第 7 节）
7. Tick 结束，ECS 组件已由 PlanHandler 直写
```

---

## 4. 全局守卫

不属于任何决策维度，在决策层之前执行。对标 GTA5 的 BT_Damage。

### 4.1 触发条件

| 条件 | 说明 | GTA5 对应 |
|------|------|-----------|
| `Self.IsDead` | NPC 死亡 | isDead → TaskDamageDeath |
| `Self.IsStunned` | 眩晕/被控制 | isRagdoll → TaskRageRagdoll |
| 未来扩展：击飞、倒地等 | — | TaskNMShot, TaskNMExplosion 等 |

### 4.2 触发效果

```
全局守卫触发时：
1. 接管输出，跳过所有决策系统
2. 对所有活跃 PlanHandler 调用 OnExit() 进行清理
   （如：对话中被击晕 → interact PlanHandler.OnExit() 清理对话状态，通知对方 NPC）
3. 清理可能导致矛盾的 State 字段：
   - Lock.InteractionLock → NONE（防止残留锁定）
   - Movement.MoveSource → NONE（清除移动来源）
   - Movement.MoveTarget → 零值（清除移动目标）
4. 所有 PlanExecutor 重置（current → ""，下次执行时从 OnEnter 开始）
5. 所有决策系统暂停（不执行 Tick）
6. 感知插件持续运行（保持 State 感知字段最新）
```

> **不清除感知字段**（ThreatLevel、DialogRequests 等），因为感知系统持续更新，恢复后仍需这些数据做决策。

### 4.3 P1 当前需要的全局守卫

P1 当前 NPC 系统较简单，全局守卫主要处理死亡和眩晕。但架构上预留扩展，未来可增加更多物理接管状态（如 GTA5 的 22 种）。

```go
func (g *GlobalGuard) Check(snapshot *NpcStateSnapshot) bool {
    return snapshot.Self.IsDead || snapshot.Self.IsStunned
}
```

---

## 5. 决策维度划分

### 5.1 维度总览

对标 GTA5 的 5 维度，P1 采用 3+1 维度（交战+武器合并，暂不拆分）：

```
GTA5 (5维度)                    P1 (3+1维度)
───────────────                 ──────────────────
全局守卫 (BT_Damage)             全局守卫 (死亡/眩晕)
运动载体 (怎么动？)              运动载体 (walk，未来 ride/drive)
导航     (去哪里？)              导航     (idle/navigate/interact/scenario)
交战     (与谁对抗？)        ┐   交战     (合并，P1 暂不需要拆)
武器     (用什么打？)        ┘
表现     (姿态叠加)              表现     (表情/社交叠加)
```

### 5.2 运动载体决策（Locomotion）

管辖 NPC **怎么动**——用什么载体移动。同一时刻只有一种运动载体。

| Plan | 进入条件 | 说明 |
|------|---------|------|
| on_foot | 默认兜底 | 步行/奔跑 |
| in_vehicle | MotionMode == IN_VEHICLE | 驾驶中（未来） |
| mounted | MotionMode == MOUNTED | 骑乘中（未来） |

**与 GTA5 对应**：BT_OnFoot / BT_Vehicle / BT_Mount / BT_Aquatic / BT_Aerial

**当前实现**：只有 on_foot，决策系统仅返回 "walk"。未来扩展载具时增加 Plan。

### 5.3 导航决策（Navigation）

管辖 NPC **去哪里**以及**就地交互**——移动目标、路径、停留交互。与运动载体正交并行。

| Plan | 进入条件 | 退出条件 | 说明 |
|------|---------|---------|------|
| navigate | MoveTarget 有值 | 到达目标 | 寻路移动 |
| interact | HasInteraction == true | 交互结束 | 对话/交易（停下来与人交互） |
| scenario | 附近有场景点且无其他任务 | 场景结束 | 场景交互（未来） |
| idle | 默认兜底 | — | 原地闲置/徘徊 |

**与 GTA5 对应**：BT_Navigate / BT_Scenario / BT_Idle

> **对话/交易归入导航维度**：对话和交易的本质是"停下来，在原地做一件事"——和 navigate（移动到目标）、idle（原地闲置）互斥。NPC 不能同时走路和对话，也不能同时对话和交易，它们天然是导航维度内的互斥 Plan。
>
> 对话/交易不需要 InteractionLock。导航维度的 Plan 互斥天然保证了"对话时不移动"——因为 interact 和 navigate 不会同时被选中。只有近战等需要**跨维度锁定**的行为才用 InteractionLock（见[第 9 节](#9-interactionlock-生命周期)）。

**关键设计**：导航系统不关心 MoveTarget 是谁写的——可能是交战系统写的追击目标、表现系统写的逃跑方向、日程系统写的行程目的地，或脚本写的任务目标。**导航只管"走过去"**。

这就是正交的意义：怎么动（运动载体）× 去哪里（导航）× 为什么（交战/日程/逃跑），自由组合。

### 5.4 交战决策（Engagement）

管辖 NPC 的对抗行为。独立于运动和导航。

| Plan | 进入条件 | 退出条件 | 说明 |
|------|---------|---------|------|
| combat | ThreatLevel == COMBAT | 敌人消失 | 战斗（攻击+战术移动） |
| pursuit | PursuitEntity != 0 | 目标消失 | 追击 |
| investigate | ThreatLevel == SUSPICIOUS | 确认/排除 | 调查可疑 |
| none | 默认兜底 | — | 无交战 |

**与 GTA5 对应**：BT_Combat / BT_LawCrime / BT_Investigation

**关键设计**（对标 GTA5）：
- 交战系统**不自己处理移动**，而是写入 `MoveTarget`（战术位置/追击目标位置），导航系统读取后执行
- 近战等需要双方站位锁定的行为，交战系统写入 `InteractionLock=MELEE`，锁定运动载体和导航维度
- 追击**不需要** InteractionLock——追击通过写 MoveTarget 间接驱动导航，导航正常执行寻路
- 移动逻辑只有一套（导航维度），战斗/日常复用

### 5.5 表现决策（Expression）

管辖姿态叠加——不涉及主行为控制权，与其他维度并行。

| Plan | 进入条件 | 退出条件 | 说明 |
|------|---------|---------|------|
| threat_react | ThreatEntities 不为空 | 威胁消失 | 威胁反应 |
| social_react | 附近有熟人 | 熟人离开 | 社交互动 |
| none | 默认兜底 | — | 无表现 |

**与 GTA5 对应**：BT_ThreatResponse / BT_Social

**关键设计**：
- 表现系统可写入 `MoveTarget`（逃跑方向），但优先级低于交战
- `InteractionLock` 期间，表现系统仍可叠加姿态/表情，但跳过涉及移动的行为

### 5.6 正交组合示例

对标 GTA5 第 8 节的协调场景：

#### 场景 A：NPC 日常行走

```
NpcState: Schedule.HasTarget=true, Combat.ThreatLevel=NONE

运动载体 → on_foot（步行）
导航     → navigate（寻路到日程目标）    ← 读 Schedule 写的 MoveTarget
交战     → none
表现     → none

输出：步行寻路到日程点
```

#### 场景 B：NPC 被追击

```
NpcState: Combat.PursuitEntity=敌人A, Combat.ThreatLevel=COMBAT

运动载体 → on_foot（步行）
导航     → navigate（寻路到敌人位置）    ← 读 交战系统 写的 MoveTarget
交战     → pursuit（追击敌人A）          → 写入 MoveTarget=敌人A位置
表现     → threat_react（威胁姿态）

输出：追击敌人 + 威胁姿态叠加
```

#### 场景 C：NPC 对话中

```
NpcState: Social.HasInteraction=true, Social.InDialog=true

运动载体 → on_foot（步行，但无移动目标）
导航     → interact（对话中）           ← 导航维度内 interact 优先于 navigate/idle
交战     → none
表现     → social_react（对话姿态）

输出：停下来对话（不需要 InteractionLock，导航维度 Plan 互斥天然保证）
```

#### 场景 D：NPC 对话中突遇敌人

```
NpcState: Social.HasInteraction=true, Combat.PursuitEntity=敌人B

执行顺序（步骤 5）：
1. 交战 Brain 评估 → pursuit
2. pursuit PlanHandler 写入 MoveTarget=敌人B位置（source=ENGAGEMENT）
3. 导航 Brain 评估 → MoveTarget 有值 → navigate（优先级高于 interact）
4. 导航从 interact 切到 navigate → interact PlanHandler.OnExit() 清理对话状态

运动载体 → on_foot
导航     → navigate（追向敌人B）        ← MoveTarget 由交战写入
交战     → pursuit（追击）
表现     → threat_react（威胁姿态）

输出：中断对话 → 追击敌人
```

> 对话中断的关键：交战写入 MoveTarget 后，导航决策本帧就能读到（交战先于导航评估）。导航 Brain 的 transition `* → navigate` 条件满足（MoveTarget 有值），自然从 interact 切换到 navigate。对话的 PlanHandler.OnExit() 正常执行清理。不需要任何特殊的"中断对话"逻辑。

---

## 6. 执行层：PlanHandler

### 6.1 接口设计

```go
// PlanHandler 统一执行接口
// 简单 Plan 直接实现，复杂 Plan 内部包装行为树
type PlanHandler interface {
    OnEnter(ctx *PlanContext)   // Plan 切入时初始化
    OnTick(ctx *PlanContext)    // 每 Tick 执行
    OnExit(ctx *PlanContext)    // Plan 切出时清理
}

// PlanExecutor 管理一个维度的 Plan 执行
type PlanExecutor struct {
    handlers map[string]PlanHandler  // Plan 名 → Handler
    current  string                  // 当前 Plan
    handler  PlanHandler
}

func (e *PlanExecutor) Execute(plan string, ctx *PlanContext) {
    if plan != e.current {
        if e.handler != nil {
            e.handler.OnExit(ctx)    // 旧 Plan 清理
        }
        e.current = plan
        e.handler = e.handlers[plan]
        if e.handler != nil {
            e.handler.OnEnter(ctx)   // 新 Plan 初始化
        }
    }
    if e.handler != nil {
        e.handler.OnTick(ctx)        // 每 Tick 执行
    }
}
```

### 6.2 Plan 分类

| 维度 | Plan | 执行方式 | 说明 |
|------|------|---------|------|
| 运动载体 | on_foot | 简单：设移动模式字段 | 当前只有步行 |
| 导航 | idle | 简单：播闲置/徘徊 | — |
| 导航 | navigate | 行为树：取目标→寻路→移动→到达判断 | 多帧流程 |
| 导航 | interact | 简单：停下→面朝对方→等交互结束 | 对话/交易共用 |
| 导航 | scenario | 行为树：走到场景点→执行场景行为 | 未来实现 |
| 交战 | none | 无行为 | 默认 |
| 交战 | pursuit | 简单：每 Tick 更新目标位置→写 MoveTarget | — |
| 交战 | combat | 行为树：战术决策+掩体+攻击（并行子行为） | 未来实现 |
| 交战 | investigate | 中等：写 MoveTarget=可疑点→等待确认 | 未来实现 |
| 表现 | threat_react | 简单：设威胁反应字段+可能写 MoveTarget（逃跑） | — |
| 表现 | social_react | 简单：设社交反应字段 | — |

### 6.3 复杂 Plan 内挂行为树

对标 GTA5 的行为树：Plan 内部可有并行/互斥子行为，由行为树处理。

```go
// 复杂 Plan 示例：未来的 combat
type CombatPlanHandler struct {
    tree *BehaviorTree
}

func (h *CombatPlanHandler) OnEnter(ctx *PlanContext) {
    h.tree.Reset()
}

func (h *CombatPlanHandler) OnTick(ctx *PlanContext) {
    // 行为树内部可以有并行节点：
    // Parallel
    //   ├── 战术移动（写 MoveTarget 到掩体）
    //   └── 攻击控制（选目标、攻击）
    h.tree.Tick(ctx)
}

func (h *CombatPlanHandler) OnExit(ctx *PlanContext) {
    h.tree.Reset()
}
```

### 6.4 与 GTA5 的对应关系

| GTA5 行为树 | P1 PlanHandler | 类型 |
|------------|---------------|------|
| BT_OnFoot | on_foot_handler | 简单 |
| BT_Vehicle | in_vehicle_handler | 行为树（未来） |
| BT_Navigate | navigate_handler | 行为树 |
| BT_Idle | idle_handler | 简单 |
| BT_Combat | combat_handler | 行为树（未来） |
| BT_Investigation | investigate_handler | 中等（未来） |
| BT_ThreatResponse | threat_react_handler | 简单 |
| BT_Social | social_react_handler | 简单 |

---

## 7. 每帧执行流程

对标 GTA5 第 7 节，适配 P1 的 Go 服务端架构。

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 感知系统更新                                               │
│    SensorPlugin.CollectAll()                                 │
│    → 更新 NpcState（各 Plugin 分别采集）                       │
├─────────────────────────────────────────────────────────────┤
│ 2. 生成 Snapshot（只读副本）                                   │
│    snapshot := npcState.CreateSnapshot()  // sync.Pool 复用  │
├─────────────────────────────────────────────────────────────┤
│ 3. 全局守卫检查                                               │
│    if IsDead/IsStunned:                                      │
│      → 清理矛盾字段（InteractionLock, MoveSource 等）         │
│      → 跳过所有决策和执行，直接写死亡/眩晕 ECS 组件            │
│      → return                                                │
├─────────────────────────────────────────────────────────────┤
│ 4. InteractionLock 检查                                      │
│    if InteractionLock != NONE:                               │
│      → 运动载体决策返回无行为                                  │
│      → 导航决策返回无行为                                      │
│      → 交战/表现正常评估                                       │
├─────────────────────────────────────────────────────────────┤
│ 5. 重置可写字段                                                 │
│    MoveSource → NONE, MoveTarget → 零值                       │
│    日程系统写入 MoveTarget（如有日程目标，source=SCHEDULE）      │
├─────────────────────────────────────────────────────────────┤
│ 6. 各维度 决策→执行 交替进行（写入方先于读取方）                  │
│                                                               │
│    a. 交战维度（写入方）                                        │
│       engagementBrain.Tick(snapshot) → engagementPlan         │
│       engagementExecutor.Execute(engagementPlan, ctx)         │
│       → pursuit PlanHandler 写入 MoveTarget=敌人位置           │
│                                                               │
│    b. 表现维度（写入方）                                        │
│       expressionBrain.Tick(snapshot) → expressionPlan         │
│       expressionExecutor.Execute(expressionPlan, ctx)         │
│       → threat_react PlanHandler 可能写 MoveTarget=逃跑方向    │
│                                                               │
│    c. 运动载体维度（不涉及 MoveTarget）                         │
│       locomotionBrain.Tick(snapshot) → locomotionPlan         │
│       locomotionExecutor.Execute(locomotionPlan, ctx)         │
│                                                               │
│    d. 导航维度（读取方，最后执行）                               │
│       navigationBrain.Tick(snapshot) → navigationPlan         │
│       → 此时 MoveTarget 已由高优先级方写入，导航直接读取        │
│       navigationExecutor.Execute(navigationPlan, ctx)         │
│                                                               │
│    MoveTarget 通过 SetMoveTarget() 优先级覆盖，结果与顺序无关  │
├─────────────────────────────────────────────────────────────┤
│ 7. ECS 组件已由各 PlanHandler 直写，Tick 结束                   │
└─────────────────────────────────────────────────────────────┘
```

**与 GTA5 的差异**：

| 步骤 | GTA5 | P1 |
|------|------|----|
| 感知更新 | CExpensiveProcessDistributer | SensorPlugin 插件化 |
| 决策+执行 | 分离：5 个决策全部评估完 → 5 棵行为树全部执行 | 交替：每维度 Brain.Tick → PlanHandler.Execute，写入方先于读取方 |
| 仲裁 | WriteBuffer + 帧末 StateArbiter | 写入时优先级覆盖（简化，结果与顺序无关） |
| 输出 | 动画映射层 | 直写 ECS（服务端无动画） |

---

## 8. State 写入仲裁

对标 GTA5 第 9 节。P1 采用简化版：写入时优先级覆盖，不用 WriteBuffer。

### 8.1 为什么不用 WriteBuffer

GTA5 用 WriteBuffer 是因为"解耦写入顺序依赖"。但 P1 的实际冲突极少：

| 场景 | 交战写 MoveTarget | 表现写 MoveTarget | 冲突？ |
|------|-------------------|-------------------|--------|
| NPC 日常行走 | 无 | 无 | 无冲突 |
| NPC 被追击 | 追击目标位置 | 可能写逃跑方向 | 有冲突，交战优先 |
| NPC 对话中 | 无 | 无 | 无冲突 |

冲突只在交战+表现同时活跃时发生（极少）。写入时优先级覆盖足够处理。

### 8.2 写入时优先级覆盖

```go
type MoveSource int

const (
    MoveSourceNone       MoveSource = 0
    MoveSourceScript     MoveSource = 1  // 普通脚本/任务
    MoveSourceExpression MoveSource = 2  // 表现决策（逃跑方向）
    MoveSourceSchedule   MoveSource = 3  // 日程系统（行程目标）
    MoveSourceEngagement MoveSource = 4  // 交战决策（追击/掩体）—— 高于日程，战斗打断日程
    MoveSourceOverride   MoveSource = 5  // 强制模式（GM 命令/任务关键）
)

func (s *NpcState) SetMoveTarget(target Vec3, source MoveSource) {
    if source >= s.Movement.MoveSource {
        s.Movement.MoveTarget = target
        s.Movement.MoveSource = source
    }
}

// 每 Tick 开始时重置
func (s *NpcState) ResetWritableFields() {
    s.Movement.MoveSource = MoveSourceNone
    s.Movement.MoveTarget = Vec3Zero
}
```

### 8.3 可写字段仲裁规则

| 字段 | 可能的写入方 | 仲裁方式 |
|------|------------|---------|
| `Movement.MoveTarget` | 交战/日程/表现/脚本 | 按 MoveSource 优先级：OVERRIDE > ENGAGEMENT > SCHEDULE > EXPRESSION > SCRIPT > NONE |
| `Movement.MoveSource` | 跟随 MoveTarget | 胜出方的 source |
| `Lock.InteractionLock` | 仅交战维度（近战时） | 无冲突，直接写入。对话/交易不使用 InteractionLock |

> 与 GTA5 一致：MoveTarget 的附属字段（紧迫度、姿态等）跟随写入方，保证一致性。

---

## 9. InteractionLock 生命周期

对标 GTA5 第 10 节。InteractionLock 仅用于需要**跨维度锁定双方站位**的行为，仅由**交战维度**写入。

### 9.1 哪些行为需要 InteractionLock，哪些不需要

| 行为 | 需要 InteractionLock？ | 原因 |
|------|----------------------|------|
| 对话 | **不需要** | 导航维度内 Plan 互斥天然保证"对话时不移动"（interact 和 navigate 不会同时选中） |
| 交易 | **不需要** | 同上，交易也是导航维度的 interact Plan |
| 追击 | **不需要** | 追击通过写 MoveTarget 间接驱动导航，导航正常执行寻路 |
| 近战 | **需要** | 近战需要锁定双方站位，运动载体和导航必须让位给近战控制 |

> 与 GTA5 一致：InteractionLock 只用于近战(MELEE)/逮捕(ARREST)/偷车(STEAL_VEHICLE)——都是需要**物理接触、双方站位锁定**的行为。追击/对话/交易都不用。

### 9.2 锁定类型

| 锁定值 | 写入者 | 说明 |
|--------|--------|------|
| NONE | — | 无锁定 |
| MELEE | 交战维度的 combat PlanHandler | 近战时锁定双方站位（未来实现） |

> P1 当前只需要 MELEE 一种锁定。未来如果新增逮捕/偷车等业务，按 GTA5 模式在交战维度内扩展。

### 9.3 锁定期间的效果

| 被影响维度 | 效果 | GTA5 对应 |
|-----------|------|-----------|
| 运动载体 | 返回无行为（运动控制权交给近战） | Tree 0 被抑制 |
| 导航 | 返回无行为（移动由近战行为直接控制） | Tree 1 被抑制 |
| 交战（自身） | 不受影响，近战行为正常执行 | Tree 2 不受影响 |
| 表现 | 不受影响（可叠加姿态，如近战时的怒吼） | Tree 4 不受影响 |

### 9.4 释放条件

| 场景 | 释放方式 | GTA5 对应 |
|------|---------|-----------|
| 正常完成 | combat PlanHandler 内近战结束，写回 NONE | TaskCombatMelee.OnExit() |
| 全局守卫打断 | GlobalGuard 强制清除 | StateArbiter.OnDamageOverride() |
| 目标消失 | 交战决策降级为 none 时，PlanHandler.OnExit() 清除 | Evaluate() 返回无行为 |
| 超时保护 | LockTimer 超时（10 秒）强制清除 | interactionLockTimer |

### 9.5 状态转移

```
NONE ──→ MELEE ──→ NONE（近战结束）
              └──→ NONE（全局守卫清除）
              └──→ NONE（超时保护清除）

注：当前只有 MELEE 一种锁定。未来扩展时，多种锁定在交战维度内互斥（同一棵树内），
不存在多方竞争——与 GTA5 设计一致。
```

---

## 10. 全局守卫恢复协议

对标 GTA5 第 11 节。NPC 从死亡/眩晕恢复后的状态处理。

### 10.1 进入时清理

```
全局守卫触发时：
1. 对所有活跃 PlanHandler 调用 OnExit()（清理业务状态，如中断对话通知对方）
2. 清理矛盾字段：
   - InteractionLock → NONE
   - MoveSource → NONE
   - MoveTarget → 零值
3. 重置所有 PlanExecutor（current → ""）
4. 不清除感知字段（ThreatLevel 等由感知系统持续更新）
```

### 10.2 退出时从零评估

```
全局守卫退出时（如 IsStunned 变为 false）：
1. 感知字段已是最新（全局守卫期间持续更新）
2. 所有决策系统从零重新评估（不续接旧状态）
3. PlanHandler 从 OnEnter() 开始（不续接旧执行）
```

> **不续接旧状态**：与 GTA5 一致。被击晕前在对话中，恢复后环境可能已变（对话对象已离开），从零评估才安全。

### 10.3 恢复后首 Tick

| 步骤 | 说明 |
|------|------|
| 1 | 感知更新（已是最新） |
| 2 | 全局守卫检查（不触发，继续） |
| 3 | 决策评估（4 个系统基于当前 State 全部重评估） |
| 4 | PlanHandler 执行（选中的 Handler 从 OnEnter 开始） |

---

## 11. 任务/脚本系统接入

对标 GTA5 第 12 节。P1 的任务系统（日程、会议等）作为 NPC State 的外部写入者参与决策。

### 11.1 接入方式

任务系统通过写入 NpcState 字段影响决策，不直接操作决策系统或 PlanHandler：

```
任务/日程系统              NpcState                    决策层

日程到点出发 ──→ Schedule.HasTarget = true   ──→ 导航决策读取
                 Movement.MoveTarget = 目的地
                 Movement.MoveSource = SCHEDULE

会议开始   ──→ Schedule.MeetingState = 1    ──→ 导航决策读取
               Movement.MoveTarget = 会议点

GM 命令    ──→ Script.Override = true       ──→ 强制模式
               Movement.MoveTarget = 指定点
               Movement.MoveSource = OVERRIDE
```

### 11.2 优先级总览

```
优先级（高→低）：

全局守卫（死亡/眩晕）       ← 不可被覆盖
  │
OVERRIDE                    ← GM 命令/任务强制
  │
ENGAGEMENT                  ← 交战决策（追击/掩体）—— 战斗打断一切日常行为
  │
SCHEDULE                    ← 日程系统（行程目标）
  │
EXPRESSION                  ← 表现决策（逃跑方向）
  │
SCRIPT                      ← 普通脚本命令
  │
NONE                        ← 无写入
```

> 与 GTA5 一致：ENGAGEMENT > EXPRESSION > SCRIPT。P1 在 ENGAGEMENT 和 EXPRESSION 之间插入 SCHEDULE（日程是 P1 核心业务）。战斗打断日程，日程打断逃跑——符合直觉。

---

## 12. JSON 配置格式

沿用 V2Brain 表达式驱动，每个维度一个 JSON 文件。

### 12.1 导航维度配置示例

```json
{
  "system": "navigation",
  "init_plan": "idle",
  "plans": [
    { "name": "idle",     "desc": "闲置/徘徊" },
    { "name": "navigate", "desc": "寻路移动" },
    { "name": "interact", "desc": "就地交互（对话/交易）" },
    { "name": "scenario", "desc": "场景交互" }
  ],
  "transitions": [
    {
      "from": "*",     "to": "navigate", "priority": 1,
      "condition": "Movement.MoveTarget != Vec3Zero",
      "_comment": "有移动目标时最高优先级（交战追击/日程行程/逃跑都通过 MoveTarget 驱动）"
    },
    {
      "from": "*",     "to": "interact", "priority": 2,
      "condition": "Social.HasInteraction == true",
      "_comment": "有待处理交互（对话/交易）时，停下来交互"
    },
    {
      "from": "navigate", "to": "idle", "priority": 1,
      "condition": "Movement.IsMoving == false && Movement.MoveTarget == Vec3Zero"
    },
    {
      "from": "interact", "to": "idle", "priority": 1,
      "condition": "Social.HasInteraction == false"
    },
    {
      "from": "idle", "to": "scenario", "priority": 3,
      "condition": "Schedule.NearScenarioPoint == true"
    },
    {
      "from": "scenario", "to": "idle", "priority": 1,
      "condition": "Schedule.NearScenarioPoint == false"
    }
  ]
}
```

> **navigate 与 interact 的优先级关系**：
>
> navigate（`from: "*"`, priority=1）高于 interact（`from: "*"`, priority=2）。当 MoveTarget 有值时，navigate 总是优先匹配。这意味着：
>
> - **对话不能打断移动**？不，对话请求发起时，交互系统主动清除 MoveTarget（挂起日程目标）。MoveTarget 变零值后，navigate 条件不满足，interact 自然匹配。对话结束后恢复日程目标。
> - **追击能打断对话**？是，交战维度每 Tick 重写 MoveTarget（source=ENGAGEMENT），对话中 MoveTarget 变非零，navigate 优先匹配，interact 被打断。不需要特殊中断逻辑。
> - **日程移动中来对话请求**？交互系统清除 MoveTarget，NPC 停下对话。对话结束后日程系统下一 Tick 重写 MoveTarget，NPC 继续走。

### 12.2 交战维度配置示例

```json
{
  "system": "engagement",
  "init_plan": "none",
  "plans": [
    { "name": "none",        "desc": "无交战" },
    { "name": "combat",      "desc": "战斗" },
    { "name": "pursuit",     "desc": "追击" },
    { "name": "investigate", "desc": "调查" }
  ],
  "transitions": [
    {
      "from": "*",       "to": "combat",      "priority": 1,
      "condition": "Combat.ThreatLevel == COMBAT"
    },
    {
      "from": "*",       "to": "pursuit",     "priority": 2,
      "condition": "Combat.PursuitEntity != 0"
    },
    {
      "from": "*",       "to": "investigate", "priority": 3,
      "condition": "Combat.ThreatLevel == SUSPICIOUS"
    },
    {
      "from": "combat",  "to": "none", "priority": 1,
      "condition": "Combat.ThreatLevel != COMBAT"
    },
    {
      "from": "pursuit", "to": "none", "priority": 1,
      "condition": "Combat.PursuitEntity == 0"
    },
    {
      "from": "investigate", "to": "none", "priority": 1,
      "condition": "Combat.ThreatLevel == NONE"
    }
  ]
}
```

### 12.3 配置文件清单

| 文件 | 维度 | Plan 数 |
|------|------|--------|
| `locomotion.json` | 运动载体 | 1（当前），未来 3-5 |
| `navigation.json` | 导航 | 4（idle/navigate/interact/scenario） |
| `engagement.json` | 交战 | 4 |
| `expression.json` | 表现 | 3 |

存放路径：`bin/config/ai_decision_v2/`（沿用原设计）

---

## 13. 与原设计对比

### 13.1 与 V2 配置驱动重构原方案对比

| 维度 | 原方案 | 本方案 | 变更原因 |
|------|--------|--------|---------|
| **决策维度** | 4 个独立 V2Brain | 3+1 个正交并行维度 | 对标 GTA5，运动载体×导航×交战正交组合 |
| **主行为合并** | 日程+对话+追击全在一个状态机 | 拆为导航+交战两个正交维度 | 追击中也要移动，移动逻辑应复用 |
| **全局守卫** | 无 | 有（死亡/眩晕接管一切） | 对标 GTA5 BT_Damage |
| **InteractionLock** | 简化版 | 完整生命周期+超时保护 | 对标 GTA5 第 10 节 |
| **State 写入** | 无仲裁 | 写入时优先级覆盖 | 交战+表现可能写同一字段 |
| **恢复协议** | 无 | 进入清理+退出从零评估 | 对标 GTA5 第 11 节 |
| **执行层** | 全部行为树 | PlanHandler（简单直写+复杂挂树） | 大部分 Plan 太简单不需要行为树 |
| **脚本接入** | 无 | 通过 State 写入+优先级 | 对标 GTA5 第 12 节 |

### 13.2 核心架构变化

**从"维度隔离"到"正交并行"**：

原方案的 4 个维度是隔离的，各管各的。本方案的维度是正交的——交战维度写 MoveTarget，导航维度读取后执行移动。这意味着：

1. 移动逻辑只有一套（导航维度），所有场景复用
2. 交战不需要自己处理寻路，只需要说"去哪"
3. 新增行为（如逃跑）只需要表现维度写 MoveTarget，导航自动执行

**从"全部行为树"到"PlanHandler + 按需挂树"**：

原方案每个 Plan 都套行为树。本方案简单 Plan 直接实现 PlanHandler（几行代码），复杂 Plan 才挂行为树。减少不必要的抽象层。

---

## 14. 扩展路径

### 14.1 维度扩展（对标 GTA5）

当 P1 业务复杂度增长时，可按 GTA5 的方式拆分维度：

| 阶段 | 维度 | 触发条件 |
|------|------|---------|
| 当前 | 运动载体 + 导航 + 交战 + 表现 | — |
| 载具系统上线 | 运动载体拆分：on_foot / in_vehicle / mounted | 新增载具行为 |
| 武器系统上线 | 交战拆出武器维度：engagement + weapon | 战斗中需要独立控制武器 |
| 群组系统上线 | 新增群组维度：群组阵型/跟随 | 多 NPC 协调 |

拆分规则：**当一个维度内出现两组需要并行的行为时，拆为两个正交维度**。

### 14.2 Plan 扩展

每个维度的 Plan 可通过 JSON 配置新增，不改代码：

```
新增交战 Plan "flee"：
1. engagement.json 加 Plan 定义 + transition 条件
2. 实现 FleePlanHandler（写 MoveTarget=远离方向）
3. 注册到 engagementExecutor.handlers["flee"]
```

### 14.3 PlanHandler 升级路径

| 阶段 | 执行方式 | 说明 |
|------|---------|------|
| 初始 | 简单 PlanHandler | 几行代码直写 ECS |
| 业务变复杂 | 升级为行为树 | 内部逻辑不变，外部接口不变 |
| 高度复杂 | 行为树 + 并行子节点 | 如战斗中边移动边攻击 |

升级过程对外透明——PlanHandler 接口不变，只是内部实现从直写代码换成行为树。

### 14.4 与 V1 的关系

- V1/V2 切换标志 `UseSceneNpcArch` 仍然有效
- 本方案完全替代 V2 配置驱动重构原方案
- 第一部分（删除间接层）的任务清单仍然适用
- 第二部分（V2Brain 引擎）的核心实现不变，但集成方式从"4 个独立系统"改为"3+1 正交维度"
