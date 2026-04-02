# P1GoServer NPC 框架

> scene_server 中 NPC 的完整 AI 框架，涵盖初始化、配置、状态、感知、决策、行为树、移动等子系统。

## 目录

- [1. 架构总览](#1-架构总览)
- [2. NPC 配置体系](#2-npc-配置体系)
- [3. NPC 初始化与创建](#3-npc-初始化与创建)
- [4. ECS 组件](#4-ecs-组件)
- [5. 感知系统（Sensor）](#5-感知系统sensor)
- [6. 决策系统（GSS Brain）](#6-决策系统gss-brain)
- [7. 行为树（Behavior Tree）](#7-行为树behavior-tree)
- [8. 日程系统（Schedule）](#8-日程系统schedule)
- [9. 移动与寻路](#9-移动与寻路)
- [10. 关键文件索引](#10-关键文件索引)

---

## 1. 架构总览

NPC AI 采用**分层架构**，数据流方向为：感知 → 决策 → 行为执行。

```
┌─────────────────────────────────────────────────────┐
│                    ECS World                         │
│                                                     │
│  ┌───────────┐    ┌──────────────┐    ┌───────────┐ │
│  │  Sensor   │───▶│  Decision    │───▶│ Behavior  │ │
│  │  System   │    │  (GSS Brain) │    │   Tree    │ │
│  └───────────┘    └──────────────┘    └───────────┘ │
│       │                  │                  │       │
│       ▼                  ▼                  ▼       │
│  ┌─────────┐      ┌──────────┐      ┌───────────┐  │
│  │ Vision  │      │ Feature  │      │ NpcMove   │  │
│  │ Comp    │      │ ValueMgr │      │ Comp      │  │
│  └─────────┘      └──────────┘      └───────────┘  │
└─────────────────────────────────────────────────────┘
```

**核心流程**：
1. **Sensor System**（每 500ms）采集环境信息，写入 `DecisionComp` 的 Feature
2. **GSS Brain** 根据 Feature 变化驱动状态机，生成 Plan（目标行为序列）
3. **Executor** 消费 Plan，驱动**行为树**执行具体行为（移动、空闲、对话等）
4. 行为树节点操作 ECS 组件（NpcMoveComp、DialogComp 等）产生实际效果

---

## 2. NPC 配置体系

NPC 配置分为**自动生成的二进制配置**（从 Excel 导出）和 **JSON 配置**两类。

### 2.1 自动生成配置（`common/config/cfg_*.go`，禁止手动编辑）

| 配置文件 | 结构体 | 说明 |
|----------|--------|------|
| `cfg_npc.go` | `CfgNpc` | NPC 基础定义：外观、性别、行为树类型(`serverBehaivorType`)、移动速度、掉落、交互半径 |
| `cfg_initnpc.go` | `CfgInitNpc` | 静态 NPC 出生点：场景 ID、位置、朝向、强度 |
| `cfg_npccreaterule.go` | `CfgNpcCreateRule` | NPC 生成规则：冷却时间、对象池、密度上限 |
| `cfg_npcaction.go` | `CfgNpcAction` | NPC 动画映射 |
| `cfg_npcbehaviorargs.go` | `CfgNpcBehaviorArgs` | 行为树参数：描述、是否人形、交互半径 |
| `cfg_npctimeline.go` | `CfgNpcTimeline` | 时间线持续时间 |
| `cfg_npcrelation.go` | `CfgNpcRelation` | 好感度/评价区间 |
| `cfg_npcmeetingpoint.go` | `CfgNpcMeetingPoint` | 约会地点 |
| `cfg_npcpoolgroup.go` | `CfgNpcPoolGroup` | NPC 对象池分组 |

### 2.2 JSON 配置（日程）

| 目录 | 加载函数 | 说明 |
|------|----------|------|
| `TonwNpcSchedule/` | `LoadNpcScheduleJsonFile()` | 城镇 NPC 日程 |
| `SakuraNpcSchedule/` | `LoadSakuraNpcScheduleJsonFile()` | 校园活动 NPC 日程 |

日程配置结构（`config_npc_schedule/schedule.go`）：

```go
NpcSchedule {
    nodeList []*CfgNode    // 一天中的行为节点列表
}

CfgNode {
    Key      string        // 节点标识
    NodeType int           // 节点类型枚举
    Action   INodeAction   // 行为接口（含时间、位置、朝向）
}

// NpcScheduleType 枚举
WaitDelivery(0) | UseVending(1) | LocationWait(2) | StayInBuilding(3) | MovePoint(4)
```

### 2.3 GSS Brain 配置

GSS 状态转移配置位于 `common/ai/decision/gss_brain/config/` 目录，基于 XML 定义状态转移规则和行为树绑定。

### 2.4 Excel 原始表（`RawTables/`）

| 目录 | 说明 |
|------|------|
| `npc/` | NPC 基础定义表 |
| `TownNpc/` | 城镇 NPC 表 |
| `SakuraNpc/` | 校园活动 NPC 表 |
| `BTTreeMeta/` | 行为树元数据 |

---

## 3. NPC 初始化与创建

代码位于 `servers/scene_server/internal/net_func/npc/`。

### 3.1 创建参数

```go
// common.go
type CreateSceneNpcParam struct {
    Scene              common.Scene
    NpcCfgId           int32              // cfg_npc 配置 ID
    BaseNpcId          int32              // 基础 NPC ID
    Position, Rotation trans.Vec3
    SceneSpecificComp  common.Component   // TownNpcComp 或 SakuraNpcComp
    ScheduleCfg        *confignpcschedule.NpcSchedule
    GssStateTransCfg   *configNpcGssBrain.Config
    GSSTempID          string             // GSS 模板 ID
    RunSpeed           float32
    IncludePoliceComp  bool
}
```

### 3.2 创建流程

```
CreateSceneNpc(param)
  ├── CreateNpcFromConfig()          // 基础实体 + 核心组件
  │     ├── Transform（位置/旋转）
  │     ├── NpcComp（外观、名称、性别）
  │     ├── MonsterComp
  │     ├── BaseStatus, PersonStatus, PersonInteraction
  │     ├── Equip, Movement, MoveControl
  │     ├── AnimState, Gas
  │     ├── NpcMoveComp（移动速度）
  │     └── [TradeProxyComp]（城镇商贩 NPC 特有）
  │
  ├── 添加场景特定组件（TownNpcComp / SakuraNpcComp）
  ├── 添加 NpcScheduleComp（日程）
  ├── 添加 DialogComp（对话）
  ├── InitNpcAIComponentsWithParam()  // AI 组件
  │     ├── DecisionComp（GSS 决策代理）
  │     ├── VisionComp（视觉感知）
  │     └── [PoliceComp]（警察职业特有）
  └── 设置 RunSpeed
```

### 3.3 创建入口

| 函数 | 文件 | 说明 |
|------|------|------|
| `CreateSceneNpc()` | `common.go` | 统一场景 NPC 创建（推荐） |
| `CreateSimpleNpc()` | `common.go` | 最简 NPC，使用默认值 + `npc_dialog` GSS 模板 |
| `CreateTownNpc()` | `town_npc.go` | 城镇 NPC，包含警察组件支持 |
| `InitMainWorldNpcs()` | `world_npc.go` | 从 `CfgInitNpc` 批量创建世界 NPC |

---

## 4. ECS 组件

NPC 相关组件位于 `servers/scene_server/internal/ecs/com/` 下。

### 4.1 核心组件

| 组件 | ComponentType | 文件 | 关键字段 |
|------|--------------|------|----------|
| `NpcComp` | `ComponentType_NpcBase` | `cnpc/npc_comp.go` | NpcCfgId, Name, Gender, PartList, InteractRand, Killer |
| `NpcScheduleComp` | `ComponentType_NpcSchedule` | `cnpc/schedule_comp.go` | cfg, NowState, MeetingState, MeetingPointID |
| `NpcMoveComp` | `ComponentType_NpcMove` | `cnpc/npc_move.go` | speed, eState, ePathFindType, NavMesh, pointList |
| `DecisionComp` | `ComponentType_AIDecision` | `caidecision/decision.go` | agent, dialogContext |
| `VisionComp` | `ComponentType_Vision` | `cvision/vision_comp.go` | VisionRadius, VisionAngle, visibleEntities, visionRecords |
| `BehaviorComp` | `ComponentType_BehaviorTree` | `csystem/behavior_comp.go` | BtType, Instance, Context, Controller |
| `PoliceComp` | — | `cpolice/police_comp.go` | 追捕、调查状态 |

### 4.2 NPC 状态枚举（Proto 定义）

```protobuf
// common/proto/npc_pb.go
NpcState:       Stand | Ground | Drive | Interact | Death | Shelter | Shiver
NpcSyncState:   None | WeakControl | Override | FastReflex
MonsterDangerState: Idle | Alert | Attack
```

---

## 5. 感知系统（Sensor）

代码位于 `servers/scene_server/internal/ecs/system/sensor/`。

### 5.1 系统入口

`SensorFeatureSystem`（`sensor_feature.go`）每 **500ms** 更新一次，包含两步：
1. **Pull 模式**：主动轮询各传感器采集环境数据
2. **Push 模式**：处理事件驱动的特征更新

### 5.2 子传感器

| 传感器 | 文件 | 职责 |
|--------|------|------|
| `eventSensorFeature` | `event_sensor_feature.go` | 对话事件、控制事件 |
| `eventSensor` | `event_sensor.go` | 逮捕、通缉、击倒等事件（Push 模式） |
| `scheduleSensorFeature` | `schedule_sensor_feature.go` | 日程相关特征 |
| `visionSensor` | `vision_sensor.go` | 视觉半径、角度、可见实体数量 |
| `distanceSensor` | `distance_sensor.go` | 距离计算 |
| `stateSensor` | `state_sensor.go` | NPC 状态感知 |
| `miscSensor` | `misc_sensor.go` | 杂项状态特征 |

### 5.3 Feature 列表

Feature 是传感器写入、决策层读取的键值对，存储在 `DecisionComp` 的 `ValueMgr` 中。

**视觉类**：
- `feature_vision_radius` / `feature_vision_angle` / `feature_vision_enabled`
- `feature_visible_entities_count` / `feature_visible_players_count` / `feature_visible_npcs_count`

**事件类**（带 TTL，过期自动清除）：
- `feature_knock_req`（TTL=1s）— 击倒请求
- `feature_dialog_req`（TTL=1s）— 对话请求
- `feature_arrested` — 被逮捕
- `feature_release_wanted` — 解除通缉

**状态类**：
- `feature_state_pursuit` / `feature_pursuit_entity_id` / `feature_pursuit_miss` — 追捕状态

**日程类**：由 `scheduleSensorFeature` 从 `NpcScheduleComp` 提取当前日程节点信息。

### 5.4 视觉组件详情

`VisionComp`（`cvision/vision_comp.go`）维护 NPC 的视野状态：

- **VisionRadius**：视觉半径（float32）
- **VisionAngle**：视觉角度（360 = 全向感知）
- **visibleEntities**：当前可见实体集合
- **visionRecords**：每个实体的进入时间、距离记录
- 方法：`UpdateVisibleEntities()` 全量刷新，检测进入/离开；`IsEntityInVision()` 单体查询

---

## 6. 决策系统（GSS Brain）

GSS（Goal-driven State Sequencing）是 NPC 的核心决策引擎，代码位于 `servers/scene_server/internal/common/ai/decision/`。

### 6.1 核心概念

- **Agent**：决策代理接口，封装 GSS Brain + ValueMgr
- **ValueMgr**：Feature 键值存储，Sensor 写入，Brain 读取
- **Plan**：决策产物，包含目标行为序列，交由 Executor 消费
- **Executor**：Plan 执行器，驱动行为树执行具体行为（场景级共享资源）

### 6.2 GSS Brain 状态机

```
┌──────┐     ┌──────────────┐     ┌─────────────────────┐
│ Init │────▶│ WaitConsume  │────▶│ WaitCreateNotify    │
└──────┘     └──────────────┘     └─────────────────────┘
                  ▲                        │
                  └────────────────────────┘
```

状态机（`decision/fsm/gss_brain_fsm.go`）：

| 状态 | 说明 |
|------|------|
| `InitState` | 初始化，立即转入 WaitConsume |
| `WaitConsumeState` | 等待当前 Plan 被 Executor 消费完毕 |
| `WaitCreateNotifyState` | 等待外部条件变化触发新 Plan 创建 |

每个状态实现 `GssBrainState` 接口：`Name()`, `Type()`, `Enter()`, `Exit()`, `Update()`。

### 6.3 决策上下文

```go
type GssBrainStateContext struct {
    Brain       interface{}
    EntityID    uint32
    NpcCfgId    int32
    CurrentPlan *decision.Plan
    Config      *configNpcGssBrain.Config   // XML 状态转移配置
    CfgMgr      *config.ConfigMgr
}
```

### 6.4 Agent 创建

```go
// caidecision/decision.go
CreateAIDecisionComp(executor, scene, entityID, gssTempID) (*DecisionComp, error)
  ├── 创建 ValueMgr
  ├── agent.New(executor) 创建 Agent
  ├── Agent.Init(gssTempID) 加载 GSS 模板配置
  └── 封装为 DecisionComp
```

### 6.5 决策类型

| 类型 | 说明 |
|------|------|
| `DecisionTypeGSS` | 主用：目标驱动状态序列，配合行为树 |
| `DecisionTypeNDU` | 实验性：位于 `ndu_brain/` 目录 |

---

## 7. 行为树（Behavior Tree）

代码位于 `servers/scene_server/internal/common/ai/bt/`。

### 7.1 节点工厂

`nodes/factory.go` 中的 `NodeFactory` 注册了所有内置节点类型：

**控制节点**：

| 节点 | 说明 |
|------|------|
| `Sequence` | 顺序执行，全部成功才成功 |
| `Selector` | 选择执行，一个成功即成功 |
| `SimpleParallel` | 并行执行 |
| `Inverter` | 结果取反 |
| `Repeater` | 重复执行 |
| `Timeout` | 超时中断 |
| `Cooldown` | 冷却控制 |
| `ForceSuccess` / `ForceFailure` | 强制返回结果 |
| `SubTree` | 子树引用 |

**长时行为节点**（生命周期：`OnEnter` → `OnTick`(Running) → `OnExit`）：

| 节点 | 说明 |
|------|------|
| `IdleBehavior` | 日程空闲：设置位置，配置对话超时和外出时长 |
| `HomeIdleBehavior` | 在家空闲：设置外出超时 |
| `MoveBehavior` | 路网寻路移动（feature_start_point → feature_end_point） |
| `DialogBehavior` | 对话：暂停计时器，退出时补偿时长 |
| `PursuitBehavior` | NavMesh 追捕（读取 feature_pursuit_entity_id） |
| `InvestigateBehavior` | 三阶段：NavMesh 移动 → 等待 → 清除调查状态 |
| `MeetingIdleBehavior` | 约会空闲 |
| `MeetingMoveBehavior` | 路网寻路前往约会地点 |
| `PlayerControlBehavior` | 玩家控制模式，退出时 NavMesh 返回日程 |
| `ProxyTradeBehavior` | 代理交易状态切换 |
| `ReturnToSchedule` | NavMesh 寻路返回日程位置 |

**异步节点**：

| 节点 | 说明 |
|------|------|
| `ChaseTarget` | 追踪目标 |
| `WaitForNavMeshArrival` | 等待 NavMesh 到达 |
| `WaitForRoadNetworkArrival` | 等待路网到达 |

**同步动作**：

| 节点 | 说明 |
|------|------|
| `SetupNavMeshPathToFeature` | 设置 NavMesh 路径 |
| `StartMove` | 开始移动 |
| `PerformArrest` | 执行逮捕 |
| `ClearInvestigation` | 清除调查 |
| `SetInitialPosition` | 设置初始位置 |
| `SetNpcOutDuration` | 设置外出时长 |

**装饰器**：`BlackboardCheck`（黑板条件）、`FeatureCheck`（Feature 条件）

**服务**：`SyncFeatureToBlackboard`（同步 Feature 到黑板）、`UpdateSchedule`（更新日程）、`Log`

### 7.2 BehaviorComp（旧版怪物行为树）

`csystem/behavior_comp.go` 中的 `BehaviorComp` 是**旧版怪物行为树**组件，由 `aiBtSystem`（`system/ai_bt/ai_bt.go`）每帧 Tick。

注意：NPC AI 的行为树由 **GSS Decision → Executor** 驱动，不经过 `aiBtSystem`。`BehaviorComp` 主要用于非 GSS 的怪物 AI。

---

## 8. 日程系统（Schedule）

### 8.1 日程组件

`NpcScheduleComp`（`cnpc/schedule_comp.go`）管理 NPC 的日常作息：

```go
type NpcScheduleComp struct {
    cfg              *NpcSchedule              // 日程配置
    NowState         *CfgNode                  // 当前日程节点
    gssStateTransCfg *configNpcGssBrain.Config // GSS 状态转移配置
    orderedMeeting   int32                     // 已预约的约会 ID
    MeetingState     int32                     // 约会状态
    MeetingPointID   int32                     // 约会地点 ID
    needFeatureSync  bool                      // 是否需要同步 Feature
}
```

**约会状态机**：

| 常量 | 值 | 说明 |
|------|----|------|
| `MeetingStateNone` | 0 | 无约会 |
| `MeetingStateOrder` | 1 | 已预约 |
| `MeetingStateOn` | 2 | 约会进行中 |

### 8.2 日程查询

```go
// 根据当前时间获取活跃的日程节点，支持跨午夜
NpcSchedule.GetNowSchedule(nowTime) *CfgNode
```

### 8.3 约会流程

1. `SetOrderMeeting(meetingID)` — 预约（进行中时不可预约）
2. NPC 在约会时间前 2 小时（`TmpAdvanceMeetingTime = 7200`）开始移动
3. `updateNpcMeetingSchedule()`（`system/npc/npc_update.go`）动态更新约会进度
4. `ClearMeeting()` — 结束，重置状态并标记 Feature 同步

---

## 9. 移动与寻路

`NpcMoveComp`（`cnpc/npc_move.go`）支持两种寻路模式：

### 9.1 路网寻路（Road Network）

- `ePathFindType = EPathFindType_RoadNetWork (1)`
- 使用预定义路点列表：`SetPointList(key, pointList, targetDirection)`
- 按顺序遍历路点：`GetNextPoint()` / `PassPoint()`
- 用于日常移动（`MoveBehavior`、`MeetingMoveBehavior`）

### 9.2 NavMesh 寻路

- `ePathFindType = EPathFindType_NavMesh (2)`
- 使用 `navmesh.Agent` 进行动态寻路
- 关键数据：`NavMeshData { Agent, TargetPos, Path, PathIndex, Radius, Height, MaxSpeed }`
- 用于追捕（`PursuitBehavior`）、调查（`InvestigateBehavior`）、返回日程（`ReturnToSchedule`）

### 9.3 移动状态

| 状态 | 说明 |
|------|------|
| `EMoveState_Stop` | 静止 |
| `EMoveState_Move` | 行走 |
| `EMoveState_Run` | 奔跑 |

支持 `PauseState()` / `ResumeState()` 暂停恢复模式。

---

## 10. 关键文件索引

### 配置层

| 文件 | 说明 |
|------|------|
| `common/config/cfg_npc.go` | NPC 基础配置（自动生成） |
| `common/config/cfg_initnpc.go` | 静态出生点配置 |
| `common/config/cfg_npccreaterule.go` | 生成规则配置 |
| `common/config/cfg_npcbehaviorargs.go` | 行为树参数配置 |
| `common/config/config_npc_schedule/schedule.go` | 日程 JSON 配置加载 |

### 初始化层

| 文件 | 说明 |
|------|------|
| `scene_server/internal/net_func/npc/common.go` | NPC 创建主逻辑 |
| `scene_server/internal/net_func/npc/town_npc.go` | 城镇 NPC 创建 |
| `scene_server/internal/net_func/npc/world_npc.go` | 世界 NPC 批量初始化 |
| `scene_server/internal/ecs/entity/factory.go` | 实体工厂 |

### ECS 组件层

| 文件 | 说明 |
|------|------|
| `ecs/com/cnpc/npc_comp.go` | NPC 基础组件 |
| `ecs/com/cnpc/schedule_comp.go` | 日程组件 |
| `ecs/com/cnpc/npc_move.go` | 移动组件 |
| `ecs/com/caidecision/decision.go` | 决策组件 |
| `ecs/com/cvision/vision_comp.go` | 视觉组件 |
| `ecs/com/csystem/behavior_comp.go` | 行为树组件（旧版怪物用） |
| `ecs/com/cpolice/police_comp.go` | 警察组件 |

### AI 决策层

| 文件 | 说明 |
|------|------|
| `common/ai/decision/agent/factory.go` | Agent 工厂 |
| `common/ai/decision/fsm/gss_brain_fsm.go` | GSS 状态机 |
| `common/ai/decision/gss_brain/` | GSS Brain 实现 |
| `common/ai/decision/gss_brain/config/` | GSS XML 配置 |
| `common/ai/decision/ndu_brain/` | NDU Brain（实验性） |

### 行为树层

| 文件 | 说明 |
|------|------|
| `common/ai/bt/nodes/factory.go` | 节点工厂（注册所有内置节点） |
| `common/ai/bt/nodes/behavior_nodes.go` | 长时行为节点实现 |
| `common/ai/bt/nodes/behavior_helpers.go` | 行为辅助函数 |
| `common/ai/bt/nodes/wait.go` | 等待节点 |
| `common/ai/bt/nodes/wait_for_arrival.go` | 到达等待节点 |

### 系统层

| 文件 | 说明 |
|------|------|
| `ecs/system/sensor/sensor_feature.go` | 感知系统入口 |
| `ecs/system/sensor/vision_sensor.go` | 视觉传感器 |
| `ecs/system/sensor/event_sensor.go` | 事件传感器 |
| `ecs/system/sensor/distance_sensor.go` | 距离传感器 |
| `ecs/system/sensor/state_sensor.go` | 状态传感器 |
| `ecs/system/sensor/schedule_sensor_feature.go` | 日程传感器 |
| `ecs/system/sensor/misc_sensor.go` | 杂项传感器 |
| `ecs/system/ai_bt/ai_bt.go` | 旧版行为树 Tick 系统 |
| `ecs/system/decision/decision.go` | Plan 执行器 |
| `ecs/system/npc/npc_update.go` | NPC 更新（含约会日程） |
| `ecs/system/npc/move.go` | NPC 移动更新 |
| `ecs/system/vision/vision_system.go` | 视觉系统更新 |

### Proto 定义

| 文件 | 说明 |
|------|------|
| `common/proto/npc_pb.go` | NPC 状态枚举、Avatar 消息、同步状态 |

### V2 正交维度管线（OrthogonalPipeline）

| 文件 | 说明 |
|------|------|
| `common/ai/pipeline/orthogonal_pipeline.go` | 正交维度管线编排器（替代 MultiTreeExecutor） |
| `common/ai/execution/plan_handler.go` | PlanHandler 接口 + PlanContext + SceneAccessor 接口 |
| `common/ai/execution/plan_executor.go` | PlanExecutor：Plan 名 → Handler 三阶段生命周期 |
| `common/ai/execution/handlers/` | 各维度 Handler 实现（locomotion/navigation/engagement/expression） |
| `common/ai/guard/global_guard.go` | 全局守卫（死亡/眩晕时接管，清理所有维度） |
| `ecs/res/npc_mgr/v2_pipeline_factory.go` | OrthogonalPipeline 工厂 + DimensionConfig |
| `ecs/res/npc_mgr/v2_pipeline_defaults.go` | 默认维度配置（engagement→expression→locomotion→navigation） |

> 以上路径均相对于 `P1GoServer/servers/scene_server/internal/`（组件/系统/AI 层）或 `P1GoServer/`（配置/Proto 层）。

---

## 11. [0.0.1新增] 大世界 V2 NPC 系统（BigWorld）

大世界 NPC 基于 V2 正交维度管线（OrthogonalPipeline），与小镇/校园 NPC（GSS Brain + 行为树）架构完全独立。核心差异：决策由四个正交维度 Handler 驱动（engagement→expression→locomotion→navigation），不经过 GSS Brain 和行为树。

### 11.1 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                  BigWorld NPC Pipeline                        │
│                                                             │
│  ┌─────────────┐   ┌──────────────────────────────────────┐ │
│  │ SensorSystem │──▶│  OrthogonalPipeline (V2Brain)        │ │
│  │ (感知采集)    │   │                                      │ │
│  │              │   │  engagement → expression              │ │
│  │  - State     │   │       ↓            ↓                  │ │
│  │  - Distance  │   │  locomotion → navigation              │ │
│  │  - Schedule  │   │                                      │ │
│  │  - Traffic   │   │  每个维度独立 Handler，正交决策        │ │
│  └─────────────┘   └──────────────────────────────────────┘ │
│         │                        │                           │
│         ▼                        ▼                           │
│  ┌─────────────┐   ┌──────────────────────────────────────┐ │
│  │  NpcState    │   │  syncNpcMovement → NpcMoveComp       │ │
│  │  (桥接数据)   │   │  net_update → NpcDataUpdate(客户端)   │ │
│  └─────────────┘   └──────────────────────────────────────┘ │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  BigWorldNpcSpawner (AOI动态生成/回收)                 │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**与 V1 NPC 的关键区别**：

| 维度 | V1（Town/Sakura） | V2（BigWorld） |
|------|-------------------|----------------|
| 决策引擎 | GSS Brain + 行为树 | OrthogonalPipeline 四维度 Handler |
| 生成方式 | 静态场景放置（CfgInitNpc） | AOI 动态生成（BigWorldNpcSpawner） |
| 日程系统 | NpcScheduleComp + CfgNode | ScheduleSensor + ScheduleState（JSON） |
| 移动寻路 | 路网 + NavMesh 双模式 | 大世界路网 A* + Raycast Y修正 |
| 代码隔离 | town_ext_handler / sakura_ext_handler | bigworld_ext_handler（独立，禁止交叉 import） |

### 11.2 四维度 Handler

Handler 执行顺序固定：engagement → expression → locomotion → navigation。前两个是"写入者"（决定意图），后两个是"读取者"（执行意图）。

| 维度 | 文件 | 职责 |
|------|------|------|
| engagement | `handlers/bigworld_engagement_handler.go` | 警戒/战斗状态决策（P0 简化：仅 Idle/Alert 两态） |
| expression | `handlers/bigworld_expression_handler.go` | 情绪驱动表情反应（P0 简化：接入 EmotionState 衰减/恢复） |
| locomotion | `handlers/bigworld_locomotion_handler.go` | 移动模式选择（Walk/Run/Idle），红绿灯等待时切 Idle |
| navigation | `handlers/bigworld_navigation_handler.go` | A* 寻路执行 + Y坐标 Raycast 修正 + 交通集成 |

**NavigationHandler 关键机制**：
- **Y坐标三级降级**：Raycast 失败 → SphereCast(1m) → lastValidY 兜底 → 连续 30 帧无效则 despawn
- **车辆避让**：通过 `SceneImplI.GetTrafficManager()` 检测前方 5m 车辆（TrafficManager==nil 时跳过）
- **红绿灯**：读取 `NpcState.PerceptionState.TrafficLightState`（由 TrafficLightSensor 每 5 帧采集），红灯暂停推进 waypoint_index
- **水面检测**：Y < 50 时传送回最近有效路点，传送失败则 despawn

### 11.3 Spawner 动态生成

`BigWorldNpcSpawner` 根据玩家 AOI 动态管理 NPC 生命周期：

- **配额分配**：每个玩家期望配额 = max_count / onlinePlayerCount，TickSpawn 轮询分配
- **分帧生成**：每帧最多 spawn_batch_size 个，防突刺
- **分帧回收**：每帧最多销毁 5 个（传送导致 AOI 大变时）
- **孤儿转移**：玩家下线后其 NPC 按距离转移给最近在线玩家，超额延迟 5s despawn
- **休眠机制**：所有玩家离开后 Spawner 进入 dormant，停止 TickSpawn 和 Pipeline Tick

**配置参数**（`BigWorldNpcConfig`，JSON 加载）：

| 参数 | 类型 | 说明 |
|------|------|------|
| max_count | int | 最大 NPC 数量（默认 50） |
| spawn_density | float32 | 每 100m² 生成密度 |
| spawn_radius | float32 | 围绕玩家的生成半径 |
| despawn_radius | float32 | 回收半径（> spawn_radius） |
| spawn_batch_size | int | 每帧最大生成数 |

### 11.4 日程系统

大世界日程配置以 `V2_BigWorld` 前缀标识，与小镇日程完全隔离。

- P0 阶段：所有 NPC 使用 `default_behavior(patrol)`，不启用时段切换
- P1 扩展：激活日夜循环，支持 patrol/rest/gather 三种行为按时段轮转
- ScheduleSensor 写入 `NpcState.PerceptionState`，V2Brain 维度读取决策
- 配置加载失败时 fallback 到 patrol 默认行为 + log.Errorf 报警

### 11.5 外观系统

P0 使用 JSON 配置（`bigworld_npc_appearance.json`）存储 5-8 套固定外观组合：

- `BigWorldExtHandler.OnNpcCreated` 按权重随机选取外观 ID
- 外观 ID 随 NpcDataUpdate 下发，客户端按 ID 加载 BodyParts
- 对象池回收时卸载外观部件，复用时重新加载
- 配置热更：已生成 NPC 不重新加载，新 NPC 使用新配置

### 11.6 GM 命令

| 命令 | 用法 | 说明 |
|------|------|------|
| bigworld_npc_spawn | `/ke* gm bigworld_npc_spawn <count>` | 强制生成指定数量 NPC |
| bigworld_npc_clear | `/ke* gm bigworld_npc_clear` | 清除所有大世界 NPC |
| bigworld_npc_info | `/ke* gm bigworld_npc_info <npcId>` | 查看 NPC 状态详情 |
| bigworld_npc_schedule | `/ke* gm bigworld_npc_schedule <npcId> <scheduleId>` | 强制切换日程 |
| bigworld_npc_lod | `/ke* gm bigworld_npc_lod` | LOD 级别分布统计 |

### 11.7 AI LOD（服务端）

| LOD 级别 | 距离 | Pipeline Tick 频率 | Sensor 间隔 |
|----------|------|-------------------|-------------|
| HIGH | 0-100m | 每帧 | 500ms |
| MEDIUM | 100-200m | 每 3 帧 | 1500ms |
| LOW | 200-300m | 每 10 帧 | 5000ms |

### 11.8 异常处理

| 场景 | 处理策略 |
|------|----------|
| 路网数据加载失败 | Spawner 标记 disabled，不生成 NPC，log.Errorf |
| A* 寻路失败 | NPC 回退 Idle，等待下次日程切换 |
| NPC 数量达上限 | 新请求排队，优先回收最远 NPC |
| Y坐标 Raycast 全部失败 | lastValidY 兜底 → 连续 30 帧 → despawn |
| NPC 掉入水面(Y<50) | 传送回最近有效路点 → 失败则 despawn |
| 断线重连 | 全量 NpcDataUpdate(is_all=true) 绕过节流，客户端 diff 更新 |
| 服务器重启 | NPC 全部丢失，Spawner 自动重建（无名市民无需恢复） |
| 配置热更 | 已有 NPC 保持旧配置，新生成使用新配置 |

### 11.9 BigWorld NPC 关键文件索引

| 职责 | 文件路径 |
|------|----------|
| Pipeline 工厂 + BigWorld 注册 | `ecs/res/npc_mgr/v2_pipeline_factory.go` |
| Pipeline 默认维度配置 | `ecs/res/npc_mgr/v2_pipeline_defaults.go` |
| 大世界 ExtHandler | `ecs/res/npc_mgr/bigworld_ext_handler.go` |
| 大世界 Spawner | `ecs/res/npc_mgr/bigworld_npc_spawner.go` |
| 大世界 NPC 配置 | `ecs/res/npc_mgr/bigworld_npc_config.go` |
| BigWorldSceneNpcExt 组件 | `ecs/com/cnpc/bigworld_npc.go` |
| engagement Handler | `common/ai/execution/handlers/bigworld_engagement_handler.go` |
| expression Handler | `common/ai/execution/handlers/bigworld_expression_handler.go` |
| locomotion Handler | `common/ai/execution/handlers/bigworld_locomotion_handler.go` |
| navigation Handler | `common/ai/execution/handlers/bigworld_navigation_handler.go` |
| 大世界 NPC 更新 System | `ecs/system/npc/bigworld_npc_update.go` |
| GM 命令 | `net_func/gm/bigworld.go` |
| Handler 测试 | `common/ai/execution/handlers/bigworld_handlers_test.go` |
| 配置测试 | `ecs/res/npc_mgr/bigworld_npc_config_test.go` |
| NPC 组件测试 | `ecs/com/cnpc/bigworld_npc_test.go` |

> 路径相对于 `P1GoServer/servers/scene_server/internal/`。

### 11.10 网络协议

大世界 NPC **零新增协议**，完全复用现有消息：

| 协议 | 用途 |
|------|------|
| `NpcDataUpdate`（Ntf） | NPC 状态增量/全量同步，通过 `NpcV2Info` 承载 V2 管线状态 |
| `NpcV2Info` | 子结构：anim_state / movement / emotion / behavior_state |
| `NpcMovement` | 移动数据（位置/朝向/速度），服务端额外维护 lastValidY（不下发） |
| `NetEntity` 创建/销毁 | AOI 进出时的实体生命周期通知 |

> 同步节流：`max_sync_per_frame=15`，断线重连全量同步(is_all=true)绕过节流。
