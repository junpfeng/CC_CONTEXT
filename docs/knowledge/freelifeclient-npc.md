# Freelife Client NPC 系统

> 客户端 NPC 操作的完整知识图谱，涵盖三套 NPC 系统（TownNpc / SakuraNpc / BigWorldNpc）的生命周期、状态机、组件、日程、交互、网络同步。

## 目录

- [1. 架构总览](#1-架构总览)
- [2. TownNpc 系统](#2-townnpc-系统)
- [3. SakuraNpc 系统](#3-sakuranpc-系统)
- [4. 共享模式与差异对比](#4-共享模式与差异对比)
- [5. 网络同步](#5-网络同步)
- [6. 关键文件索引](#6-关键文件索引)
- [7. [0.0.1新增] BigWorldNpc 系统](#7-00-1新增-bigworldnpc-系统)

---

## 1. 架构总览

客户端 NPC 采用 **Controller + Component + FSM** 三层架构，服务器权威驱动状态。

```
┌──────────────────────────────────────────────────────┐
│                   NPC Manager                         │
│          (生命周期管理、Spawn/Despawn)                  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │              NPC Controller                     │  │
│  │         (实体容器、组件协调)                      │  │
│  │                                                │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────┐   │  │
│  │  │ FSM Comp │ │Animation │ │ Transform    │   │  │
│  │  │(状态机)   │ │ Comp     │ │ Comp(位置同步)│   │  │
│  │  └────┬─────┘ └──────────┘ └──────────────┘   │  │
│  │       │                                        │  │
│  │  ┌────▼──────────────────────────────────┐     │  │
│  │  │ States: Idle│Move│Run│Turn│InDoor│... │     │  │
│  │  └───────────────────────────────────────┘     │  │
│  │                                                │  │
│  │  ┌──────────────┐ ┌────────────┐               │  │
│  │  │ Interactable │ │ 特殊组件    │               │  │
│  │  │ Comp(交互)    │ │(Police/    │               │  │
│  │  │              │ │ Weapon/...)│               │  │
│  │  └──────────────┘ └────────────┘               │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │           Data Layer                            │  │
│  │  ClientData ← NetData ← Server Protobuf        │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

**数据流**: Server Protobuf → NetData → ClientData → StateData → FSM → 表现层

---

## 2. TownNpc 系统

小镇玩法中的 NPC，以**日程驱动**为核心，支持警察、交易等特殊行为。

### 2.1 生命周期

```
DataManager.TownNpcs 变化
  → TownNpcManager.OnUpdate() 检测新增/移除
  → 新增: 加入 _waitingAddList → SpawnTownNpc() (每帧最多 1 个)
      → 对象池加载预制体 (按性别) → TownNpcController.Init() → 初始化全部组件
      → 添加到 _townNpcList → 触发 EventId.TownNpcSpawned
  → 移除: TownNpcController.Dispose() → 归还对象池
```

**更新循环**:
- `OnUpdate`: 检测 Spawn/Despawn，调用 `Controller.Tick(deltaTime)`
- `OnLateUpdate`: 距离 LOD 分级（近 900m²、中 360m²、远 10%采样），警察逮捕检测（0.2s 节流）
- `OnFixedUpdate/OnLateFixedUpdate`: 物理 FSM 更新

### 2.2 组件组成

| 组件 | 职责 |
|------|------|
| `TownFsmComp` | 状态机驱动，foot IK 检测 |
| `TownNpcAnimationComp` | 动画播放 + foot IK |
| `TownNpcTransformComp` | 位置/旋转网络同步 |
| `TownNpcInteractableComp` | 碰撞体触发交互，显示交互提示 |
| `TownNpcPoliceComp` | 警察专属：视锥检测、嫌疑追踪、逮捕逻辑、夜巡手电 |
| `TownNpcWeaponComp` | 警察专属：手枪模型显示/隐藏 |
| `TownNpcHoldComp` | 物品持有，同步 PersonStatus.HoldItem |
| `TownNpcTradeEffectComp` | 交易成功后的变形/粒子/动画效果 |

### 2.3 状态机 (FSM)

基于 `GuardedFsm<TownNpcController>` 框架，6 个状态：

| ID | 状态 | 驱动源 | 说明 |
|----|------|--------|------|
| 0 | Idle | 服务器 | 停止移动，动画速度重置 1.0 |
| 1 | Move | 服务器 | 前进移动，速度参数 0.3 |
| 2 | Run | 服务器 | 警察追击，显示武器 |
| 3 | Turn | 客户端 | 本地旋转，完成后回退前一状态 |
| 4 | InDoor | 客户端 | 转身 180° + 开门动画 → 发送 PushInNpc |
| 5 | TradeEffect | 客户端 | 交易效果播放 |

**状态切换**:
- 服务器驱动: `StateIdUpdate` 信号 → `TownFsmComp.OnUpdateStateId()` → `ChangeStateById()`
- 客户端驱动: `FsmComp.ChangeState<T>()`
- 超时逻辑: `OutdoorTime` 倒计时归零 → 强制进入 `InDoorState`

### 2.4 日程系统

```
TownNpcScheduleSetConfig (ScriptableObject 资产)
  └── List<TownNpcScheduleEntry>
       ├── Key: 唯一标识
       ├── Type: 日程类型枚举
       └── ActionData: 类型专属数据
```

**5 种日程类型**:
1. `WaitForDelivery` - 等待配送
2. `UseVendingMachine` - 使用贩卖机
3. `LocationBasedAction` - 位置行为
4. `StayInBuilding` - 停留在建筑内
5. `MoveToBPointFromAPoint` - A→B 点移动

每种类型包含: Priority（优先级）、StartTime（开始时间）、Duration（持续时间）、位置/建筑引用。

### 2.5 交互与对话

**交互流程**:
```
玩家进入碰撞区 → InteractableComp.Enter()
  → 显示交互提示 (MuiUtil.AddInteractTip)
  → 玩家点击 → OnInteractClick()
  → 检查守卫条件 (NPC 未在对话、玩家未被逮捕)
  → 警察: 显示气泡对话
  → 普通NPC: 切换相机模式 → 打开 DiaTownPanel
```

**对话系统** (`TownDialogueManager`):
- 数据结构: 树状对话，头节点 + `choiceIDs` 分支
- 运行时映射: `NpcDialoguesByNpcId` (NPC→根节点)、`NpcDialogues` (全节点)、`NpcChoices` (选项)
- 客户端状态: `DialogInfo.Estate` (0=空闲, 1=对话中)
- 断线保护: 5 秒超时检测，自动发送 `TownNpcDialogFinish`

### 2.6 警察特殊行为

- **视锥检测**: 60° 半角 + 射线遮挡检查，1s 轮询
- **动态视距**: 基础值 + 手电加成 - 蹲下减免
- **逮捕机制**: 触发区 + 红色光环视觉效果 + 嫌疑状态追踪
- **夜巡模式**: 20:00-05:00 显示手电模型

---

## 3. SakuraNpc 系统

樱花校园模式中的 NPC，以**玩家交互驱动**为核心，支持跟随、头部追踪、关系系统。

### 3.1 生命周期

与 TownNpc 类似的 Manager → Controller 模式，但**不使用对象池**（直接实例化/销毁）。

### 3.2 组件组成

| 组件 | 职责 |
|------|------|
| `SakuraNpcFsmComp` | 状态机，6 个核心状态 |
| `SakuraNpcAnimationComp` | 动画控制 |
| `SakuraNpcTransformComp` | 位置同步 |
| `SakuraNpcInteractableComp` | 交互检测 |
| `SakuraNpcHeadLookComp` | **独有**: FinalIK 头部追踪，10m 范围，±60°水平/±30°垂直 |

### 3.3 状态机

| 状态 | 说明 |
|------|------|
| Idle | 待机 |
| Walk | 行走 |
| Run | 奔跑 |
| Turn | 转向 |
| Wait | 等待（跟随时暂停） |
| Interact | 交互中（含 Dialog 子状态） |

### 3.4 跟随策略系统

可插拔策略接口 `ISakuraNpcFollowStrategy`：

- `SakuraNpcDefaultFollowStrategy`: 默认跟随
  - IdleRadius: 2m（进入待机范围）
  - ArriveThreshold: 2m（到达判定）
  - RunThreshold: 7m（切换奔跑距离）

### 3.5 交互管理

`SakuraNpcInteractManager` 管理 3 种交互类型：
1. **Follow** - 跟随玩家
2. **Wait** - 原地等待
3. **Dialog** - 对话

通过 `OnInteractStart/End` 事件回调通知状态变化。

### 3.6 独有系统

- **头部追踪**: 自动检测 10m 内玩家，LookAtIK 旋转控制
- **关系系统**: `SakuraNpcRelationshipData`、`SakuraNpcAttributeData`、`PlayerRelationshipEntry`
- **背包数据**: `SakuraNpcBackpackData`

---

## 4. 共享模式与差异对比

### 4.1 共享架构模式

| 模式 | 说明 |
|------|------|
| Controller 基类 | 均继承 `Controller` (NetEntity) |
| Comp 组合 | FSM + Animation + Transform + Interactable |
| 服务器权威 | 状态由服务器推送，客户端仅表现 |
| DataSignalType | 数据变更通过信号通知组件 |
| 性别预制体 | Male/Female 变体加载 |

### 4.2 核心差异

| 维度 | TownNpc | SakuraNpc |
|------|---------|-----------|
| 设计定位 | 日程驱动（静态日常） | 玩家交互驱动（动态响应） |
| 对象池 | ✅ 使用 | ❌ 直接实例化 |
| 特殊组件 | Police/Weapon/Hold/TradeEffect | HeadLook/Follow策略 |
| 日程系统 | 5 种日程类型 | 简化版日程 |
| 关系系统 | ❌ | ✅ 关系+属性 |
| 头部追踪 | ❌ | ✅ FinalIK |
| 交易系统 | ✅ TradeEffect | ❌ |
| 执法系统 | ✅ Police | ❌ |

---

## 5. 网络同步

### 5.1 数据更新协议

服务器通过 **NpcDataUpdate** Protobuf 推送以下数据：

| 字段 | 说明 |
|------|------|
| BaseInfo | 基础信息（性别、外观、Avatar部件） |
| Status | 在线状态 |
| PersonStatus | 人物状态（持有物品等） |
| MoveStateInfo | 移动状态 (EMoveState 枚举) |
| TownNpcInfo | 小镇 NPC 特有数据 |
| MoveInfo | 移动信息（位置、方向） |
| DialogInfo | 对话状态 (Estate: 0=空闲, 1=对话中) |
| Transform | 位置旋转 |
| SuspicionInfo | 嫌疑信息（警察相关） |

### 5.2 数据层级

```
Server Protobuf
  → TownNpcNetData (CfgId, OutDurationTime, OrderStatus, IsDealerTrade)
  → TownNpcClientData (聚合全部数据 → 通知监听器)
  → TownNpcStateData (当前 StateId → 触发 FSM 切换)
```

### 5.3 移动同步

- 使用 **TransformQueue** 时间戳快照队列
- 客户端插值平滑移动表现
- TransformComp 负责每帧从队列取值应用

---

## 6. 关键文件索引

### TownNpc

| 类别 | 文件路径 |
|------|----------|
| Manager | `Gameplay/Managers/Npc/TownNpcManager.cs` |
| Controller | `Gameplay/Modules/S1Town/Entity/NPC/TownNpcController.cs` |
| FSM 组件 | `Gameplay/Modules/S1Town/Entity/NPC/Comp/TownFsmComp.cs` |
| 状态基类 | `Gameplay/Modules/S1Town/Entity/NPC/State/TownNpcStateBase.cs` |
| 各状态 | `Gameplay/Modules/S1Town/Entity/NPC/State/TownNpc{Idle\|Move\|Run\|Turn\|InDoor}State.cs` |
| 交互组件 | `Gameplay/Modules/S1Town/Entity/NPC/Comp/TownNpcInteractableComp.cs` |
| 警察组件 | `Gameplay/Modules/S1Town/Entity/NPC/Comp/TownNpcPoliceComp.cs` |
| 武器组件 | `Gameplay/Modules/S1Town/Entity/NPC/Comp/TownNpcWeaponComp.cs` |
| 持有组件 | `Gameplay/Modules/S1Town/Entity/NPC/Comp/TownNpcHoldComp.cs` |
| 交易效果 | `Gameplay/Modules/S1Town/Entity/NPC/Comp/TownNpcTradeEffectComp.cs` |
| 动画组件 | `Gameplay/Modules/S1Town/Entity/NPC/Comp/TownNpcAnimationComp.cs` |
| 位置同步 | `Gameplay/Modules/S1Town/Entity/NPC/Comp/TownNpcTransformComp.cs` |
| 客户端数据 | `Gameplay/Modules/S1Town/Entity/NPC/Data/TownNpcClientData.cs` |
| 网络数据 | `Gameplay/Modules/S1Town/Entity/NPC/Data/TownNpcNetData.cs` |
| 状态数据 | `Gameplay/Modules/S1Town/Entity/NPC/Data/TownNpcStateData.cs` |
| 日程配置 | `Gameplay/Modules/S1Town/Entity/NPC/Schedule/TownNpcScheduleSetConfig.cs` |
| 对话管理 | `Gameplay/Modules/S1Town/Managers/NpcDialogue/TownDialogueManager.cs` |

### SakuraNpc

| 类别 | 文件路径 |
|------|----------|
| Manager | `Gameplay/Managers/Npc/SakuraNpcManager.cs` |
| Controller | `Gameplay/Modules/Sakura/Entity/NPC/SakuraNpcController.cs` |
| FSM 组件 | `Gameplay/Modules/Sakura/Entity/NPC/Comp/SakuraNpcFsmComp.cs` |
| 各状态 | `Gameplay/Modules/Sakura/Entity/NPC/State/SakuraNpc{Idle\|Walk\|Run\|Turn\|Wait\|Interact}State.cs` |
| 头部追踪 | `Gameplay/Modules/Sakura/Entity/NPC/Comp/SakuraNpcHeadLookComp.cs` |
| 交互管理 | `Gameplay/Modules/Sakura/Managers/SakuraNpcInteractManager.cs` |
| 跟随策略 | `Gameplay/Modules/Sakura/Entity/NPC/Follow/ISakuraNpcFollowStrategy.cs` |

### 配置表 (自动生成，不要手动编辑)

| 配置 | 说明 |
|------|------|
| `CfgNpc.cs` | NPC 基础配置 |
| `CfgTownNpc.cs` | 小镇 NPC 配置 |
| `CfgSakuraNpc.cs` | 樱花 NPC 配置 |
| `CfgNpcAction.cs` | NPC 行为配置 |
| `CfgNpcBehaviorArgs.cs` | 行为参数 |
| `CfgNPCBehaviorTree.cs` | 行为树配置 |
| `CfgNpcTalk.cs` | NPC 对话配置 |
| `CfgNpcTownDialogue.cs` | 小镇对话配置 |
| `CfgNpcRelation.cs` | NPC 关系配置 |

### 服务器端对应

详见 [`p1goserver-npc-framework.md`](p1goserver-npc-framework.md) — 涵盖 NPC AI 感知、GSS 决策、行为树、日程、移动寻路等服务器端逻辑（含 V2 BigWorld NPC 章节）。

---

## 7. [0.0.1新增] BigWorldNpc 系统

大世界 NPC 采用独立的 Controller + Component + FSM 架构，与 TownNpc/SakuraNpc **代码完全隔离**（放在 BigWorld 模块目录下，不引用 S1Town/Sakura 类型）。行为状态完全由服务器 V2 Pipeline 驱动，客户端仅负责表现。

### 7.1 架构特点

```
┌──────────────────────────────────────────────────────────┐
│             BigWorldNpcManager                            │
│    (生命周期 + 对象池 + LOD + 断线重连)                     │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │           BigWorldNpcController                     │  │
│  │                                                    │  │
│  │  ┌──────────┐ ┌──────────────┐ ┌───────────────┐  │  │
│  │  │ FsmComp  │ │AnimationComp │ │TransformComp  │  │  │
│  │  │(FSM状态机)│ │(Animancer)   │ │(SnapshotQueue)│  │  │
│  │  └────┬─────┘ └──────────────┘ └───────────────┘  │  │
│  │       │                                            │  │
│  │  ┌────▼─────────────────┐  ┌────────────────────┐  │  │
│  │  │ States: Idle│Move│Turn│ │ MoveComp           │  │  │
│  │  └──────────────────────┘  │ AppearanceComp     │  │  │
│  │                            │ EmotionComp (P1)   │  │  │
│  │                            └────────────────────┘  │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  数据流: NpcDataUpdate → NpcData → DataSignal → Comp     │
└──────────────────────────────────────────────────────────┘
```

### 7.2 生命周期

```
NpcDataUpdate 全量同步到达
  → BigWorldNpcManager.OnSpawn()
  → 对象池获取/创建 NPC 实体
  → BigWorldNpcController.OnInit() → AddComp 注册全部组件
  → 各 Comp 监听 DataSignal

回收:
  → Controller.OnClear()（Cancel Token、解除事件、停止动画、释放 SnapshotQueue）
  → 归还对象池
  → ResetForPool()（FSM ForceState Idle、清零速度、重建 CancellationTokenSource）
```

**对象池双阶段策略**：
- **OnClear（回收阶段）**：释放资源防泄漏（Token 取消、事件解绑、动画停止、大对象 Clear）
- **ResetForPool（取出阶段）**：初始化状态防残留（FSM 重置、速度清零、Token 重建）
- 两者职责不重叠，调用顺序：回收时 OnClear→入池，取出时 ResetForPool→OnInit

### 7.3 组件组成

| 组件 | 文件 | 职责 |
|------|------|------|
| `BigWorldNpcFsmComp` | `Comp/BigWorldNpcFsmComp.cs` | 轻量 FSM，由服务器 AnimState 驱动状态切换 |
| `BigWorldNpcAnimationComp` | `Comp/BigWorldNpcAnimationComp.cs` | Animancer 多层动画（UpperBody/Arms/AdditiveBody/Face） |
| `BigWorldNpcTransformComp` | `Comp/BigWorldNpcTransformComp.cs` | TransformSnapshotQueue 位置插值同步，LOD 感知外推窗口 |
| `BigWorldNpcMoveComp` | `Comp/BigWorldNpcMoveComp.cs` | 服务器移动数据驱动，写入 SnapshotQueue |
| `BigWorldNpcAppearanceComp` | `Comp/BigWorldNpcAppearanceComp.cs` | 异步 BodyParts 加载，三级 fallback |
| `BigWorldNpcEmotionComp` | `Comp/BigWorldNpcEmotionComp.cs` | 情绪表现（P1 扩展） |

### 7.4 状态机（FSM）

基于 `GuardedFsm<BigWorldNpcController>`，[0.0.3新增] 扩展到 5 个状态：

| 状态 | 驱动源 | 说明 |
|------|--------|------|
| Idle | 服务器 | 停止移动，播放 idle 动画 |
| Move | 服务器 | Walk/Run 移动，速度与动画归一化匹配 |
| Turn | 服务器 | 原地转向，角度差 >30° 触发，2s 超时自动退出 |
| ScenarioState | 服务器 | [0.0.3新增] 场景点行为（坐下/驻足），播放场景点动画后 Idle |
| ScheduleIdleState | 服务器 | [0.0.3新增] 日程驻留状态，目标点到位后原地等待 |

**TurnState 细节** [0.0.3完善]：
- `_prevStateType` 记录进入 TurnState 前的状态，完成后恢复
- `_pendingTurnDeltaAngleDeg` 存储待转向角（Deg 后缀，度数）
- 角度阈值 `TurnThresholdDeg = 30f`，低于阈值不触发转身
- 超时 2 秒强制退出，防止 NPC 持续卡在 TurnState

**关键约束**：
- 状态切换由 `NpcData.AnimState` DataSignal 驱动，客户端**不做自主决策**
- 每个 State 的 OnExit **必须 Stop 所有使用过的动画层**
- 动画 clip 播放前**必须检查 isLooping**（FBX 可能未勾选 Loop）
- 速度归一化 refSpeed 必须匹配实际移速，否则视觉冻结/过快

### 7.5 LOD 管理（客户端）

| LOD 级别 | 距离 | 动画更新 | 渲染 | 插值策略 |
|----------|------|----------|------|----------|
| FULL | 0-50m | 每帧 | 完整模型+阴影 | 默认外推 300ms |
| REDUCED | 50-150m | 每 3 帧 | 简化模型+无阴影 | 外推 500ms + EaseOut |
| MINIMAL | 150m+ | 暂停 | HiZCulling 裁剪 | 外推 800ms + 线性 |

> 客户端 LOD 比服务端更激进（50m 就降级），因渲染/动画开销远大于服务端 Tick 开销。

### 7.6 对象池与预热

- OnInit 时启动 async UniTask 预热：await YooAsset 异步加载 prefab → 同步 Instantiate pool_size=20 入池
- `_isReady` 标记：false 期间生成消息排入 `_pendingSpawnQueue`，就绪后统一处理
- 预热在 loading 界面完成（预算 <500ms），避免 gameplay 阶段首次 Spawn 卡顿

### 7.7 断线重连

1. 标记所有现存 NPC 为 `pendingValidation`
2. 服务端发送全量 `NpcDataUpdate(is_all=true)` 原子消息（绕过节流）
3. 客户端统一 diff：存在的更新 / 不存在的销毁 / 新增的创建
4. `pendingValidation` 超时 5s 自动清除（销毁仍标记 pending 的 NPC）
5. 窗口期内收到正常 despawn 消息直接执行销毁，不等超时

### 7.8 外观加载

`AppearanceComp` 根据服务器下发的外观 ID 异步加载 BodyParts 预制件：

- **三级 fallback**：单部件失败→跳过该部件；全部失败→应用第一套外观(body-only)；fallback 也失败→使用 prefab 默认 mesh
- 对象池回收时卸载外观部件，复用时重新加载
- 所有异步操作使用 UniTask + CancellationToken

### 7.9 碰撞与物理

- Kinematic Rigidbody + CapsuleCollider（isTrigger=false）
- 不响应外力推挤（Kinematic 不受物理力影响，符合服务器权威）
- NPC 层与 Grounds 层交互（Raycast 地面检测）
- NPC 层与 Vehicle 层碰撞检测（OnCollisionStay 通知，不产生物理推力）
- NPC 层不与 Player 层物理碰撞
- P0 不显示头顶 UI（NamePlate/血条）

### 7.10 注意事项

- **EntityId 是 ulong**，不是 int
- **日志禁止 `$""` 插值**，必须用 `+` 拼接（GC 压力）
- **using FL.NetModule 时必须加 Vector2/Vector3 alias** 消歧义
- **async UniTaskVoid 必须带 CancellationToken**，OnClear 中 Cancel
- **新 Comp 必须在 Controller.OnInit 中 AddComp 注册**
- **角度变量命名必须带 Deg/Rad 后缀**，禁止混用弧度和度数
- 代码目录：`Gameplay/Modules/BigWorld/Entity/NPC/`，禁止引用 S1Town/Sakura 模块

### 7.11 BigWorldNpc 关键文件索引

| 类别 | 文件路径 |
|------|----------|
| Manager | `Gameplay/Modules/BigWorld/Managers/BigWorldNpcManager.cs` |
| Controller | `Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs` |
| FSM 组件 | `Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs` |
| 动画组件 | `Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs` |
| 位置同步 | `Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcTransformComp.cs` |
| 移动驱动 | `Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcMoveComp.cs` |
| 外观加载 | `Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAppearanceComp.cs` |
| 情绪表现 | `Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcEmotionComp.cs` |
| Idle 状态 | `Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcIdleState.cs` |
| Move 状态 | `Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcMoveState.cs` |
| Turn 状态 | `Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcTurnState.cs` |
| ScenarioState | `Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcScenarioState.cs` | [0.0.3新增] |
| ScheduleIdleState | `Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcScheduleIdleState.cs` | [0.0.3新增] |

> 路径相对于 `freelifeclient/Assets/Scripts/`。

### 7.13 [0.0.3新增] BigWorldNpc V2 表现力扩展

#### 7.13.1 性别 Prefab 选择（REQ-001）

`BigWorldNpcController.SelectPrefabByGender()` 在 Spawn 阶段根据服务器下发的性别字段选择对应 Prefab。
- 默认回退：性别字段缺失时使用 Male Prefab
- `AppearanceComp` 在 Prefab 加载完成后继续加载 BodyParts

#### 7.13.2 Animancer 七层动画架构（REQ-004/005/008 完善）

`BigWorldNpcAnimationComp` 管理 7 个 Animancer 层，按优先级从低到高：

| 层索引 | 名称 | 类型 | 用途 |
|--------|------|------|------|
| 0 | Base | 普通层 | 全身基础动画（移动/Idle/场景点） |
| 1 | RightArm | Avatar Mask 层 | 右臂专用动画（武器持握等） |
| 2 | UpperBody | Avatar Mask 层 | 上身叠加（击中反应、战斗状态） |
| 3 | Arms | Avatar Mask 层 | 双臂混合 |
| 4 | AdditiveBodyDefault | Additive 叠加层 | 默认加法叠加动画 |
| 5 | AdditiveBodyExtra | Additive 叠加层 | 额外加法叠加（Scared/Panicked/Flee 姿态） |
| 6 | Face | Avatar Mask 层 | 面部表情动画 |

**层共享冲突规则**（见 `auto-work-lesson-007`）：
- 同一层可能被多个系统同时使用（如 UpperBody 被 HitReaction 和 Flee 共用）
- 激活高优先级效果时记录 `_hasHighPriorityOverride`
- `RestoreUpperBodyAnim()` 执行前必须检查高优先级系统是否仍在激活，否则跳过归零

#### 7.13.3 面部动画与 EmotionComp 联动（REQ-005）

```
服务器 EmotionData → BigWorldNpcEmotionComp.UpdateEmotion()
  → BigWorldNpcAnimationComp.PlayFaceAnim(EmotionType)
  → Face 层 (index=6) 播放对应表情 Clip
```

- `_faceClips` 字典缓存 4 种表情：None/Angry/Happy/Sad
- Face 层 AvatarMask 只影响面部骨骼，不干扰身体动画
- `EmotionComp.ResetEmotion()` 在对象池复用时清空 pending 情绪

#### 7.13.4 Timeline 动画支持（REQ-006）

`BigWorldNpcAnimationComp` 新增 Timeline 替换机制：

```csharp
// 按动画组切换 Timeline（如 ScenarioState 坐椅子动作）
PlayTimeline(string timelineId)
StopTimeline(string timelineId)
```

- `_replaceTimelines` 字典：`animGroup → PlayableDirector 引用`
- `ChangeAnimationsByGroup()` 同步加载 Timeline 替换表
- **降级机制**：Timeline 资源加载失败时回退到普通 Clip 播放

#### 7.13.5 战斗/警惕/逃跑状态动画（REQ-007）

`FsmComp.HandleServerState(NpcState)` 在服务端状态切换时：

1. 调用 `AnimationComp.SetAnimationGroup(NpcState)` 切换基础动画组
   - `NpcState.Combat` → 动画组 `NpcWpn01`（武装状态移动循环）
   - 其他非战斗状态 → 默认动画组
2. 调用 `AnimationComp.SetAdditiveBodyOverlay(NpcState)` 设置叠加层
   - `Scared / Panicked` → AdditiveBodyExtra 播放惊恐姿态
   - `Flee` → UpperBody 叠加逃跑上半身动画
   - 切换前先 `ClearAdditiveBodyOverlay()` 清除旧叠加

**状态切换时序**：
```
服务器推送新 NpcState
  → FsmComp.ChangeStateByServerStateId()
  → HandleServerState() 先 ClearOverlay → 再 SetOverlay
  → 防止新旧叠加同时存在
```

#### 7.13.6 击中反应动画（REQ-008）

`BigWorldNpcAnimationComp.OnHit(HitData)` 触发击中反应：

```
OnHit()
  → 检查 _isDead，死亡状态跳过
  → UpperBody 层播放击中 Clip，权重 1.0，淡入 0.1s
  → 启动 _hitReactionTimer（1 秒倒计时）
  → 1 秒后 RestoreUpperBodyAnim()
      → 检查 _hasHighPriorityOverride，Flee 叠加中则跳过归零
      → 否则 UpperBody 层 StartFade(0)，权重归零
```

**关键字段**：
- `_isInHitReaction`：防止重入，播放中不重叠触发
- `_isDead`：死亡状态（对象池复用时必须 ResetForPool 清零）

### 7.12 与 TownNpc/SakuraNpc 对比

| 维度 | TownNpc | SakuraNpc | BigWorldNpc [0.0.1新增] |
|------|---------|-----------|------------------------|
| 设计定位 | 日程驱动（静态日常） | 玩家交互驱动 | 环境角色（AOI 动态生成） |
| 对象池 | ✅ | ❌ | ✅ 双阶段策略 + 预热 |
| FSM 状态数 | 6（含 InDoor/TradeEffect） | 6（含 Wait/Interact） | 5（+ScenarioState/ScheduleIdle）[0.0.3] |
| 决策来源 | 服务器 GSS Brain | 服务器 GSS Brain | 服务器 V2 Pipeline |
| LOD 管理 | 距离三档采样 | 无 | 三级 LOD + 感知插值 |
| 特殊组件 | Police/Weapon/Hold/Trade | HeadLook/Follow | Appearance/Emotion/Timeline [0.0.3] |
| 交互 | 对话/交易 | 跟随/对话/等待 | P0 无交互（环境角色） |
| 断线重连 | 无特殊处理 | 无特殊处理 | pendingValidation + diff |
| 碰撞 | 标准 | 标准 | Kinematic 不推挤 |
