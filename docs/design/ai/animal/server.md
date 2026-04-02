# 动物系统 — 服务器需求文档

> 设计阶段 — 4 种动物（Dog/Bird/Crocodile/Chicken），资源驱动排期。
>
> 关联协议：[protocol.md](protocol.md)
> 关联客户端：[client.md](client.md)

## 1. 概述

服务器负责动物系统的**全部逻辑决策**：AI 行为（状态机、感知）、实体生命周期（生成/销毁）、交互校验。客户端纯表现，不参与任何逻辑决策。

**服务器职责边界**：
- 动物 AI 行为决策（状态切换、路径规划、目标选择）
- 感知系统（视觉/听觉检测）
- 交互校验（喂食距离、条件检查）
- 实体管理（生成规则、同屏限制、LOD 控制）
- 状态同步（通过协议推送给客户端）

### 1.1 实际可用资源

| 动物 | 模型变体 | 动画 Clip | 定位 |
|------|---------|----------|------|
| Dog（狗） | 2 | idle, walk, run, specialidle（4 个） | 可交互（喂食→跟随） |
| Bird（鸟） | 1 | fly, idle（2 个） | 环境装饰，可飞行 |
| Crocodile（鳄鱼） | 3 | idle, walk（2 个） | 环境装饰 |
| Chicken（鸡） | 1 | squatidle（1 个） | 纯静态装饰 |

### 1.2 现有基础设施盘点

| 现有资源 | 路径 | 复用方式 |
|---------|------|---------|
| **OrthogonalPipeline** | `ai/pipeline/orthogonal_pipeline.go` | 直接复用 4 维度管线框架 |
| **BtTickSystem** | `ecs/system/decision/bt_tick_system.go` | 扩展分发逻辑，增加 Animal 管线路由 |
| **v2_pipeline_defaults.go** | `ecs/res/npc_mgr/v2_pipeline_defaults.go` | 新增 Animal 管线配置 |
| **NpcState** | `ai/state/npc_state.go` | 扩展 `Animal AnimalState` 字段组（精简版） |
| **NpcStateSnapshot** | `ai/state/npc_state_snapshot.go` | 同步扩展（对象池复用） |
| **sensor/plugins/** | `ai/sensor/plugins/` | 复用 Distance（视觉锥形 + 听觉球形） |
| **execution/handlers/** | `ai/execution/handlers/` | 参考模式新建动物 Handler |
| **SceneNpcExtType** | `cnpc/scene_ext.go` | 新增 `Animal = 4` |
| **V2 行为树引擎** | `ai/execution/btree/` | 直接复用（遵循 feedback_v2_btree_isolation） |
| **NpcDataUpdate 协议** | `old_proto/scene/npc.proto` | 追加 animal_info 字段（详见 protocol.md） |

> **注意**：动物系统完全不存在任何实现代码，以上全部为可复用的框架基础设施。

## 2. 架构设计

### 2.1 模块位置

```
servers/scene_server/internal/common/ai/
├── state/npc_state.go              # 扩展 AnimalState 字段组（精简版）
├── execution/handlers/
│   ├── animal_idle.go              # 待机/游荡 Handler
│   ├── animal_follow.go            # 跟随 Handler（狗专用）
│   └── animal_bird_flight.go       # 鸟类飞行 Handler（fly↔idle 简化版）
├── decision/v2brain/config/
│   └── animal_*.json               # 动物决策配置（per AnimalType）
├── pipeline/
│   └── v2_pipeline_defaults.go     # Animal 管线注册
└── animal/
    ├── creature_metadata.go        # 参数定义（精简）
    ├── animal_spawner.go           # 生成规则
    └── animal_lod.go               # AI LOD
```

### 2.2 ECS 集成

- 动物实体作为 NPC 实体，`SceneNpcExtType = 4 (Animal)`
- 复用现有 `BtTickSystem`，通过正交管线配置区分动物行为
- `BtTickSystem` 新增 `animalPipeline *OrthogonalPipeline` 字段，与现有管线并列持有；Tick 时根据 NPC 的 `ExtType` 分发：`ExtType == SceneNpcExtType_Animal` 走 `animalPipeline`，否则走原有管线
- `animalPipeline` 通过 `NewOrthogonalPipeline(animalGuard, animalDims)` 构造，在 `v2_pipeline_defaults.go` 的 `setupOrthogonalPipeline` 函数中与现有管线并列初始化
- **管线互斥说明**：Animal 和 NPC（Town/TownGta/Sakura）是互斥的 ExtType，同一实体只走一条管线

### 2.3 与现有 NPC 系统的关系

| 层次 | 复用 | 新增 |
|------|------|------|
| 实体类型 | NPC 实体框架 | `SceneNpcExtType_Animal = 4` |
| 决策管线 | OrthogonalPipeline（4 维度） | Animal 专属 DimensionConfigs |
| 行为树引擎 | `execution/btree/`（V2 独立引擎） | Animal 行为树配置 |
| 感知系统 | DistanceSensor（视觉+听觉） | 无新增 |
| 状态管理 | NpcState + Snapshot | AnimalState 字段组（精简版） |
| 同步通道 | NpcDataUpdate + AOI | AnimalData 字段 |

## 3. 动物实体管理

### 3.1 SceneNpcExtType_Animal

在 `cnpc/scene_ext.go` 新增：
```go
const SceneNpcExtType_Animal = 4
```

Animal 类型的 NPC 实体通过此标识区分，管线初始化、状态同步、协议填充均以此为分支条件。

### 3.2 NpcState 中的 AnimalState 字段组（精简版）

在 `state/npc_state.go` 中新增以下结构体，挂载在 `NpcState` 上：

```go
// AnimalBaseState 基础属性（客户端可见）
type AnimalBaseState struct {
    AnimalType    uint32  // AnimalType 枚举
    Category      uint32  // AnimalCategory 枚举
    BehaviorState uint32  // AnimalBehaviorState 枚举（当前行为状态）
    IdleSubState  uint32  // 待机子状态
    MoveSpeed     float32 // 当前移动速度
    Heading       float32 // 朝向
    VariantID     uint32  // 外观变体 ID（鳄鱼 3 变体）
}

// AnimalPerceptionState 感知配置（内部状态，不下发客户端）
type AnimalPerceptionState struct {
    AwarenessRadius float32 // 感知半径
    FollowTargetID  uint64  // 跟随目标（狗喂食后设置）
}

// AnimalState 聚合结构，挂载在 NpcState 上
type AnimalState struct {
    Base       AnimalBaseState
    Perception AnimalPerceptionState
}
```

> **必须同步到 Snapshot + FieldAccessor**（遵循 feedback_npcstate_snapshot_sync 约束）。

**Snapshot 同步设计**：
- `NpcStateSnapshot` 需新增 `Animal AnimalState` 字段
- `Snapshot()` 方法需拷贝：`snapshot.Animal = s.Animal`
- `Reset()` 方法需清零：`s.Animal = AnimalState{}`
- `FieldAccessor` 注册客户端可见字段：`Base.BehaviorState`、`Base.IdleSubState`、`Base.MoveSpeed`、`Base.Heading`、`Base.VariantID`、`Perception.FollowTargetID`（内部字段 `Perception.AwarenessRadius` 不注册）

### 3.3 生成与销毁

**生成规则**：
- 动物由 `AnimalSpawner` 管理，根据区域配置（配置表）在指定区域生成
- 生成时检查同屏限制（见第 7 节），超限则排队等待
- 生成位置随机选择区域内 navmesh 有效点
- 鸟类生成在空中固定高度，在区域内随机位置飞行

**销毁规则**：
- 玩家离开 AOI 范围（> 300m）：保留实体但暂停 AI，不推送同步
- 场景卸载：全部移除

### 3.4 配置驱动（CreatureMetadata）

每种动物的参数通过配置表加载，字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `moveSpeed[3]` | float[] | 漫步/慢跑/奔跑速度 |
| `turnRadius` | float | 最小转弯半径 |
| `awarenessRadius` | float | 感知半径 |
| `lodDistances[3]` | float[] | LOD 切换距离 |
| `visionRange` | float | 视觉范围 |
| `visionAngle` | float | 视觉锥角度 |
| `hearingRange` | float | 听觉范围 |
| `flightMinAlt` | float | 最低飞行高度（鸟类） |
| `flightCeiling` | float | 最大飞行高度（鸟类） |

## 4. AI 行为系统

### 4.1 正交管线复用

动物复用 V2 正交管线的 4 维度框架，Handler 配置按动物类型差异化：

| 维度 | 动物 Handler | 职责 |
|------|-------------|------|
| Engagement | AnimalIdleHandler | 待机/游荡决策 |
| Expression | （空，无表情叠加） | — |
| Locomotion | AnimalFollowHandler（狗） / 空（其他） | 跟随运动 |
| Navigation | AnimalNavigateBtHandler / AnimalBirdFlightHandler | 路径导航 / 飞行 |

注册方式：在 `v2_pipeline_defaults.go` 中新增 `animalDimensionConfigs()` 函数，构造 `animalPipeline` 时传入。

### 4.1.1 V2Brain JSON 配置示例

**狗（Dog）— Engagement 维度**：
```json
{
  "system": "engagement",
  "init_plan": "idle",
  "plan_interval": 0,
  "plans": [
    {"name": "idle", "tree_name": "", "desc": "待机/游荡"},
    {"name": "follow", "tree_name": "", "desc": "跟随玩家"}
  ],
  "transitions": [
    {
      "from": "*", "to": "follow", "priority": 1,
      "condition": "Animal.Perception.FollowTargetID != 0",
      "_comment": "喂食后进入跟随状态"
    },
    {
      "from": "follow", "to": "idle", "priority": 2,
      "condition": "Animal.Perception.FollowTargetID == 0",
      "_comment": "跟随时间到期后清除目标，回到待机"
    }
  ]
}
```

**狗（Dog）— Locomotion 维度**：
```json
{
  "system": "locomotion",
  "init_plan": "none",
  "plan_interval": 0,
  "plans": [
    {"name": "none", "tree_name": "", "desc": "无运动指令"},
    {"name": "follow", "tree_name": "", "desc": "跟随"}
  ],
  "transitions": [
    {
      "from": "*", "to": "follow", "priority": 1,
      "condition": "Animal.Perception.FollowTargetID != 0"
    },
    {
      "from": "follow", "to": "none", "priority": 2,
      "condition": "Animal.Perception.FollowTargetID == 0"
    }
  ]
}
```

**鸟（Bird）— Navigation 维度**：
```json
{
  "system": "navigation",
  "init_plan": "fly",
  "plan_interval": 0,
  "plans": [
    {"name": "fly", "tree_name": "", "desc": "飞行巡游"},
    {"name": "idle", "tree_name": "", "desc": "空中悬停"}
  ],
  "transitions": [
    {
      "from": "fly", "to": "idle", "priority": 1,
      "condition": "Animal.Base.IdleSubState == 1",
      "_comment": "达到目标点后悬停"
    },
    {
      "from": "idle", "to": "fly", "priority": 2,
      "condition": "Animal.Base.IdleSubState == 0",
      "_comment": "悬停时间结束后继续飞行"
    }
  ]
}
```

### 4.2 动物行为状态机

**Dog / Crocodile / Chicken — 陆地状态机**：
```
IDLE（Rest/Wander 权重随机）
  └── FollowTargetID != 0 → FOLLOW（狗专属）→ FollowTargetID 清零 → IDLE
```

**Bird — 飞行状态机（简化版）**：
```
FLY（飞行巡游，前往随机目标点）
  └── 到达目标点 → IDLE_AIR（空中悬停 3-8s）→ 重新选目标 → FLY
```

鸟类无停栖（Perch）、起飞（Takeoff）、降落（Landing）状态，全程在空中 fly↔idle 循环。

### 4.3 Handler 设计

所有 Handler 遵循现有约束：
- **场景级共享实例**，禁止在 struct 中存储 NPC 状态
- 状态必须放 `NpcState.AnimalState`
- 业务时间使用 `mtime.NowTimeWithOffset()`

**Handler 列表**：

| Handler | 维度 | 适用动物 | 说明 |
|---------|------|---------|------|
| `AnimalIdleHandler` | Engagement | 全部 | 待机：Rest/Wander 子状态循环，权重随机切换 |
| `AnimalFollowHandler` | Locomotion | 狗 | 跟随玩家，保持 1-2m 距离，FollowTargetID 清零后转 Wander |
| `AnimalNavigateBtHandler` | Navigation | 狗/鳄鱼 | 通用陆地导航：navmesh 寻路至随机游荡点 |
| `AnimalBirdFlightHandler` | Navigation | 鸟 | 飞行：fly↔idle 两种状态，无需 navmesh，直线飞向随机目标点 |

### 4.4 感知系统

复用现有 `sensor/` 框架，所有动物统一使用 DistanceSensor：

| 感知类型 | 插件 | 形状 | 范围来源 | 适用动物 |
|---------|------|------|---------|---------|
| 视觉 | DistanceSensor（锥形） | 前方锥形 | `visionRange` + `visionAngle` | 全部 |
| 听觉 | DistanceSensor（球形） | 球形 | `hearingRange` | 全部 |

无需新增 SmellSensor（无战斗/逃跑行为，无嗅觉需求）。

## 5. 交互系统

### 5.1 喂食系统（狗专属）

请求流程：
1. 客户端发送 `AnimalFeedReq`（animal_id + item_id）
2. 服务器校验：动物类型为 Dog、距离 <= 3m（平方距离，遵循 feedback_squared_distance）、物品为有效食物、动物存活
3. 校验通过：消耗食物物品，设置 `Animal.Perception.FollowTargetID = playerEntityID`
4. 返回 `AnimalFeedResp`（follow_dur=30s）
5. 狗进入 FOLLOW 状态跟随玩家 30s，到期后清除 `FollowTargetID`，Brain 回到 idle plan

**FOLLOW 在管线中的表达**：Locomotion 维度的 `AnimalFollowHandler` 通过 `Animal.Perception.FollowTargetID` 激活。Navigation 维度 `AnimalNavigateBtHandler` 读取 MoveTarget 执行寻路。30s 到期逻辑在 `AnimalFollowHandler.OnTick()` 中检查并清除字段。

## 6. 鸟类飞行系统

服务器管理鸟类飞行的逻辑层面，`AnimalBirdFlightHandler` 负责：

- 在区域内随机选择飞行目标点（水平分量随机，高度约束在 `flightMinAlt~flightCeiling` 范围）
- 飞行路径不使用 navmesh，采用目标点直线飞行（鸟类在空中无障碍物遮挡）
- 到达目标点后切换至 `IDLE_AIR` 悬停状态，悬停时长 `[3, 8]s` 随机
- 悬停结束后重新选择目标点，切回 `FLY` 状态

**同步内容**：位置 + 朝向 + `BehaviorState`（FLY/IDLE_AIR）

**简化说明**：无 Perch/Takeoff/Landing 状态，无 `BirdPerchPoint` 停栖点系统。鸟始终在空中，不降落到地面或树上。

## 7. 性能控制

### 7.1 同屏上限管理

| 类别 | 最大同屏数量 | 说明 |
|------|------------|------|
| 陆地动物（Dog/Crocodile/Chicken） | 12 | 三种总和 |
| 鸟类（Bird） | 20 | 低 LOD 下可放宽至 40 |

超出上限时，`AnimalSpawner` 挂起距玩家最远的动物 AI（保留位置和姿态，停止 Tick 和同步）。

### 7.2 AI LOD 策略

| 距离 | AI Tick 频率 | 感知更新 | 行为树 |
|------|-------------|---------|--------|
| < 50m（Full） | 每帧 | 每帧 | 完整执行 |
| 50-150m（Medium） | 10Hz | 10Hz | 简化（跳过 Expression 维度） |
| 150-300m（Low） | 2Hz | 不更新 | 仅 Navigation |
| > 300m | 不更新 | 不更新 | 暂停 |

鸟类飞行时 Full LOD 扩展至 100m。

维度跳过通过 `DimensionSlot` 的 `suppress` 标志实现。`AnimalLOD` 模块在每帧根据距离设置各维度的 suppress 状态：Medium LOD 时 suppress Expression 维度，Low LOD 时仅保留 Navigation 维度。

### 7.3 CPU 预算

| 场景 | 目标帧时间（AI 部分） |
|------|---------------------|
| 城市区域（少动物） | < 0.5ms |
| 荒野区域（满配额） | < 2.0ms |

### 7.4 内存预算

| 资产类型 | 预算 |
|---------|------|
| CreatureMetadata 配置（4 种） | < 64KB |
| 每种动物 AnimalState | ~80 bytes/实体 |
| 单种动物决策 JSON 配置 | < 8KB |

## 8. 各动物详细规格

### 8.1 Dog（狗）

| 参数 | 值 |
|------|----|
| moveSpeed | 1.5 / 3.0 / 7.0 m/s（漫步/慢跑/奔跑） |
| turnRadius | 0.5m |
| visionRange / visionAngle | 40m / 180° |
| hearingRange | 60m |
| lodDistances | [50, 150, 300]m |
| modelVariants | 2 |

服务器特有逻辑：
- `ScenarioWalkDog` 场景绑定：NPC 沿 navmesh 路径行走，狗 `AnimalFollowHandler` 保持 1-2m
- NPC 消失后清除 `FollowTargetID`，狗进入 Wander
- 喂食交互：`AnimalFeedReq` → `FollowTargetID = playerID` → Follow 30s → 清除 → Idle

### 8.2 Bird（鸟）

| 参数 | 值 |
|------|----|
| moveSpeed（飞行） | 8.0 m/s |
| flightMinAlt | 5m |
| flightCeiling | 80m |
| visionRange / visionAngle | 60m / 270° |
| hearingRange | 40m |
| lodDistances | [100, 200, 300]m |
| modelVariants | 1 |

服务器特有逻辑：
- `AnimalBirdFlightHandler` 管理 fly↔idle 循环
- 飞行目标点随机选区域内水平位置，高度在 `[flightMinAlt, flightCeiling]` 范围内随机
- 悬停时长随机 [3, 8]s

### 8.3 Crocodile（鳄鱼）

| 参数 | 值 |
|------|----|
| moveSpeed | 1.0 / 2.5 m/s（漫步/慢跑） |
| turnRadius | 1.5m |
| visionRange / visionAngle | 30m / 120° |
| hearingRange | 20m |
| lodDistances | [50, 150, 300]m |
| modelVariants | 3 |

服务器特有逻辑：
- 纯环境装饰，仅 Idle（Rest/Wander），无交互
- 三种变体通过 `VariantID` 区分，生成时随机分配

### 8.4 Chicken（鸡）

| 参数 | 值 |
|------|----|
| moveSpeed | 0 m/s（仅静止） |
| visionRange | 10m |
| hearingRange | 10m |
| lodDistances | [30, 100, 200]m |
| modelVariants | 1 |

服务器特有逻辑：
- 纯静态装饰，只有 Rest 子状态，永不 Wander
- `AnimalIdleHandler` 中 Chicken 类型直接锁定 `IdleSubState = Rest`，不执行权重随机

## 9. 实现计划

> 标注 `✅已有` 表示可直接复用，`🔧扩展` 表示在现有基础上改造，`🆕新建` 表示从零实现。

```
基础设施（所有动物前置）
  ├─ 🆕 SceneNpcExtType_Animal = 4（cnpc/scene_ext.go）
  ├─ 🆕 NpcState.Animal 字段组（AnimalBaseState/AnimalPerceptionState）
  ├─ 🔧 NpcStateSnapshot 扩展 + FieldAccessor 注册
  ├─ 🔧 BtTickSystem 扩展 Animal 管线分发
  ├─ 🆕 v2_pipeline_defaults.go 新增 animalDimensionConfigs()
  ├─ 🆕 AnimalSpawner + 同屏限制
  ├─ 🆕 AnimalLOD 模块
  └─ 🆕 CreatureMetadata 配置加载（4 种动物配置条目）

Dog（狗）
  ├─ 🆕 AnimalIdleHandler（待机/游荡）
  ├─ 🆕 AnimalFollowHandler（跟随，30s 倒计时）
  ├─ 🆕 AnimalNavigateBtHandler（陆地 navmesh 导航）
  ├─ 🆕 V2Brain JSON 配置（animal_dog_engagement.json / animal_dog_locomotion.json）
  └─ 🆕 喂食系统（AnimalFeedReq/Resp 处理）

Bird（鸟）
  ├─ 🆕 AnimalBirdFlightHandler（fly↔idle，无 navmesh）
  └─ 🆕 V2Brain JSON 配置（animal_bird_navigation.json）

Crocodile（鳄鱼）
  ├─ ✅ 复用 AnimalIdleHandler + AnimalNavigateBtHandler
  └─ 🆕 CreatureMetadata 鳄鱼配置条目

Chicken（鸡）
  ├─ ✅ 复用 AnimalIdleHandler（锁定 Rest 子状态）
  └─ 🆕 CreatureMetadata 鸡配置条目

协议
  ├─ 🆕 AnimalData + 通知消息 + 交互请求/响应（old_proto 编辑 + 代码生成）
  ├─ NpcDataUpdate 追加 animal_info 字段（字段号需查最新 proto 确认）
  └─ codes.proto 追加动物相关错误码
```
