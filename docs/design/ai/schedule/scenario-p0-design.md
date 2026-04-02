# 场景点导航 P0 完善 — 技术设计

> 参考 GTA5 CScenarioManager 机制：管理器定期扫描分配，非日程驱动。

## 1 需求回顾

### 1.1 设计目标

还原 GTA5 场景点系统：NPC 在闲逛/移动时，由 ScenarioManager **定期扫描并分配**附近可用场景点，NPC 自主前往执行动画行为（坐长椅、靠墙、打电话等），形成自然的城市生活细节。

**与旧设计的关键差异**：触发源从"日程条目 BehaviorType=5"改为"Manager 定期扫描分配"。

### 1.2 现有实现

| 模块 | 文件 | 状态 | 改动 |
|------|------|------|------|
| ScenarioPointManager | `ai/scenario/scenario_point_manager.go` | 已完成 | Flags/概率/类型默认值/空间索引 |
| SpatialGrid | `ai/scenario/spatial_grid.go` | 完成 | 不改 |
| ScenarioHandler | `execution/handlers/schedule_handlers.go` | 已完成 | 7 阶段状态机，由 ScenarioSystem 触发 |
| scenarioFinderAdapter | `npc_mgr/scenario_adapter.go` | 完成 | 透传 Flags + Duration |
| Proto NpcScenarioData | `old_proto/scene/npc.proto` | 已完成 | 含 direction(4)/duration(5) |
| 客户端 TownNpcScenarioComp | `S1Town/Entity/NPC/Comp/` | 已完成 | 动画+FSM 集成 |
| 客户端 TownNpcNetData | `S1Town/Entity/NPC/Schedule/` | 已有字段 | 不改 |
| 状态同步 bt_tick_system | `ecs/system/decision/` | 已完成 | phase 细分同步 |
| **ScenarioSystem** | `ecs/system/scenario/scenario_system.go` | **已完成** | 独立 ECS System，分帧扫描+概率判定+冷却 |

### 1.3 P0 工作项

| 编号 | 工作 | 说明 |
|------|------|------|
| G0 | **ScenarioSystem**（核心新增） | 独立 System，定期扫描空闲 NPC，分配场景点 |
| G1 | Flags 标志过滤 | 8 位标志位检查 |
| G2 | 概率筛选 | Probability + ScenarioType 默认概率 |
| G3 | Duration 默认值 | 回退到 ScenarioType.DefaultDuration |
| G4 | 配置加载链路 | 场景初始化时从配置表灌入 Manager |
| G5 | 客户端 FSM + 动画 | ScenarioState + Animancer 三阶段动画 |
| G6 | 单元测试 | Manager + System 测试 |

## 2 架构设计

### 2.1 系统边界

```
配置表 (NpcSchedule.xlsx)
  │ 打表
  ▼
CfgScenarioPoint / CfgScenarioType (bin/config)
  │ 场景初始化加载
  ▼
ScenarioPointManager (空间索引 + 占用管理)
  ▲
  │ 查询/占用/释放
  │
ScenarioSystem (独立 ECS System，分帧扫描)     ← 核心新增
  │ 每 N 帧 tick：
  │   遍历空闲 NPC → 查询附近场景点
  │   → Flags 过滤 + 概率判定 + 距离排序
  │   → 分配成功 → 写入 NpcState
  │
  ▼
ScenarioHandler (Locomotion 维度，执行层)
  │ 读 NpcState.ScenarioPointId → 移动到位 → 动画 → 释放
  ▼
bt_tick_system → NpcScenarioData (Proto 同步)
  │
  ▼
客户端 TownNpcScenarioComp → FSM → Animancer 动画
```

### 2.2 ScenarioSystem vs ScenarioHandler 职责分离

| | ScenarioSystem（新增） | ScenarioHandler（已有） |
|--|----------------------|----------------------|
| 角色 | **决策层** — 谁去哪个场景点 | **执行层** — 移动+动画+释放 |
| 触发 | System.Update() 分帧扫描 | 正交管线 Locomotion 维度 |
| 输入 | NPC 位置 + 空闲状态 | NpcState.ScenarioPointId |
| 输出 | 写入 NpcState.ScenarioPointId | 写入 MoveTarget + 同步 Proto |
| 类比 GTA5 | CScenarioManager | TaskScenario |

### 2.3 与现有代码的迁移要点

#### 2.3.1 删除 ScheduleHandler case 5 触发路径（S2）

现有 `ScheduleHandler.OnTick` 中 `BehaviorType == 5` (UseScenario) 会写入 `CurrentPlan = "scenario"`，
这与 ScenarioSystem 的分配路径冲突。**必须删除 case 5 逻辑**，场景点触发完全由 ScenarioSystem 负责。

```go
// schedule_handlers.go 中删除：
case 5: // UseScenario - 已迁移到 ScenarioSystem
    sched.CurrentPlan = "scenario"
```

#### 2.3.2 改造 ScenarioHandler.OnEnter（S2）

现有 OnEnter 会清零 `ScenarioPointId`，这会覆盖 ScenarioSystem 的预分配结果。
改为：OnEnter 检查 ScenarioPointId 是否已由 ScenarioSystem 赋值，如果有则直接进入 Init 阶段。

```go
func (h *ScenarioHandler) OnEnter(ctx *execution.PlanContext) {
    sched := &ctx.NpcState.Schedule
    if sched.ScenarioPointId == 0 {
        // 异常：无预分配，回退到空闲
        sched.CurrentPlan = ""
        return
    }
    sched.ScenarioPhase = ScenarioPhase_Init
}
```

#### 2.3.3 改造 buildNpcScenarioData（S3）

现有 `bt_tick_system.go` 中 `buildNpcScenarioData` 只同步 phase=0/1，需改为从 NpcState 新增字段读取：

```go
func buildNpcScenarioData(sched *state.ScheduleState) *proto.NpcScenarioData {
    if sched.ScenarioPointId == 0 {
        return nil
    }
    return &proto.NpcScenarioData{
        PointId:      sched.ScenarioPointId,
        ScenarioType: sched.ScenarioTypeId,    // 新增字段
        Phase:        int32(sched.ScenarioPhase),
        Direction:    sched.ScenarioDirection,  // 新增字段
        Duration:     sched.ScenarioDuration,
    }
}
```

### 2.4 工程职责

| 工程 | 职责 |
|------|------|
| P1GoServer | ScenarioSystem + Manager 增强 + 配置加载 + 单元测试 |
| old_proto | 扩展 NpcScenarioData（direction + duration） |
| freelifeclient | ScenarioComp 完善 + FSM 状态 + 动画播放 |
| RawTables | 补充 ScenarioPoint/ScenarioType 配置数据，重新打表 |

## 3 服务端详细设计

### 3.0 ScenarioSystem — 核心新增 (G0)

#### 3.0.1 定位

独立 ECS System（参照 BtTickSystem 模式），负责**决策**：哪些空闲 NPC 应该去哪个场景点。

```
文件：ecs/system/scenario/scenario_system.go
类型：SystemType_Scenario（新增 SystemType 常量）
```

#### 3.0.2 分帧扫描机制（参照 GTA5 CExpensiveProcessDistributer）

不是每帧扫描所有 NPC，而是**分帧轮询**，避免性能尖峰：

```go
type ScenarioSystem struct {
    common.SystemBase
    mgr          *scenario.ScenarioPointManager
    scanInterval int          // 扫描间隔帧数（默认 60，约 1 秒）
    frameCounter int          // 当前帧计数
    npcQueue     []int32      // NPC ID 轮询队列
    queueIndex   int          // 当前扫描位置
    batchSize    int          // 每帧扫描 NPC 数（默认 5）
}
```

**Update() 逻辑**：

```
每帧：
  frameCounter++
  if frameCounter < scanInterval → return
  frameCounter = 0

  从 npcQueue[queueIndex] 开始，扫描 batchSize 个 NPC：
    1. 跳过非空闲 NPC（ScenarioPointId != 0 或 CurrentPlan == "scenario"）
    2. 获取 NPC 位置
    3. 调用 mgr.FindNearestFiltered(pos, gameTime) 查询候选点
    4. 候选点非空 → 概率判定 → 通过则分配
    5. 分配：mgr.Occupy(pointId, npcId) + 写入 NpcState

  queueIndex = (queueIndex + batchSize) % len(npcQueue)
```

#### 3.0.3 空闲判定

NPC 可被分配场景点的条件：

```go
func isNpcFreeForScenario(npcState *state.NpcState) bool {
    sched := npcState.Schedule
    return sched.ScenarioPointId == 0 &&
           sched.CurrentPlan != "scenario" &&
           sched.CurrentPlan != "combat" &&
           sched.CurrentPlan != "flee"
}
```

NPC 在以下状态时可被分配：schedule（日程闲逛）、patrol（巡逻）、空字符串（无计划）。
在以下状态时**不可**被分配：scenario（已在场景点）、combat（战斗）、flee（逃跑）。

#### 3.0.4 分配写入

分配成功后写入 NpcState，ScenarioHandler 下一帧读取并接管：

```go
func (s *ScenarioSystem) assignScenario(npcState *state.NpcState, point *scenario.ScenarioPoint, duration int32) {
    npcState.Schedule.ScenarioPointId = point.PointId
    npcState.Schedule.ScenarioDuration = duration
    npcState.Schedule.CurrentPlan = "scenario"
    // ScenarioHandler 在下一帧 OnEnter 时读取这些字段
}
```

#### 3.0.5 NPC 队列维护

- 场景 NPC 创建时加入 `npcQueue`
- NPC 销毁时移除（同时 `mgr.ReleaseByNpc` 清理占用）
- 队列顺序随机化，避免固定扫描顺序导致的"近处 NPC 总是优先"

### 3.1 Flags 过滤 (G1)

在 `ScenarioPointManager.FindNearestFiltered` 中增加 Flags 位检查：

```go
const (
    FlagNoSpawn           uint32 = 1 << 0
    FlagHighPriority      uint32 = 1 << 1
    FlagIndoorOnly        uint32 = 1 << 2
    FlagOutdoorOnly       uint32 = 1 << 3
    FlagWeatherSensitive  uint32 = 1 << 4  // P1，本次不处理
    FlagTimeRestricted    uint32 = 1 << 5
    FlagExtendedRange     uint32 = 1 << 6
    FlagStationaryReaction uint32 = 1 << 7
)
```

过滤规则（FindNearestFiltered 内，gameTime 由 ScenarioSystem 传入）：
1. `FlagNoSpawn` → 跳过
2. `FlagTimeRestricted` → 检查 gameTime 是否在 TimeStart~TimeEnd 范围内
3. `FlagHighPriority` → 排序权重 +1000（优先分配）
4. `FlagExtendedRange` → 该点的匹配半径 ×2
5. 容量检查：`CurrentUsers >= MaxUsers` → 跳过
6. 其余标志位本次记录但不处理（P1/P2）

### 3.2 概率筛选 (G2)

FindNearestFiltered 返回候选列表后，ScenarioSystem 按 Probability 做概率判定：
- `point.Probability == 0` → 使用 `CfgScenarioType.DefaultProbability`
- `rand.Intn(100) < probability` → 通过，否则跳过
- 所有候选都被淘汰 → 本轮不分配（下次扫描重试）

### 3.3 Duration 默认值 (G3)

分配时确定实际停留时长：
- `point.Duration > 0` → 使用 point.Duration
- 否则 → 查 `CfgScenarioType.DefaultDuration`
- 写入 `NpcState.Schedule.ScenarioDuration`

### 3.4 寻路设计 — 前往场景点与返回日程路线

#### 3.4.1 问题

场景点坐标不在路网节点上（在长椅旁、墙壁边等），而日程系统使用路网寻路（`SetEntityRoadNetPath`，基于节点 ID）。需要解决：
1. NPC 如何从路网上偏离到场景点
2. NPC 如何从场景点回到路网

#### 3.4.2 前往场景点：路网 + NavMesh 两段式

```
NPC 当前位置（路网上）
  │
  ├─ 阶段1: 路网寻路到最近节点
  │   FindNearestPointID(scenarioPoint.Position) → nearNodeId
  │   roadNetMgr.FindPathToVec3List(currentNodeId, nearNodeId) → 路网路径
  │   SetEntityRoadNetPath(entityID, pathPoints)
  │
  ├─ 阶段2: 到达最近节点后，NavMesh 短距离直走
  │   NpcState.SetMoveTarget(scenarioPoint.Position)
  │   NavMesh A* 直达场景点（通常 < 5m）
  │
  ▼
到达场景点，开始执行动画
```

**ScenarioHandler 内部状态机**（服务端内部使用）：

```go
const (
    ScenarioPhase_Init            = 0  // 初始化：计算最近节点、决定是否需要路网寻路（内部，不同步）
    ScenarioPhase_WalkToNearNode  = 1  // 路网寻路到最近节点
    ScenarioPhase_WalkToPoint     = 2  // NavMesh 直走到场景点
    ScenarioPhase_Enter           = 3  // 播放进入动画
    ScenarioPhase_Loop            = 4  // 循环动画
    ScenarioPhase_Leave           = 5  // 播放离开动画
    ScenarioPhase_WalkBackToRoad  = 6  // NavMesh 走回最近路网节点
)
```

> Phase 0 (Init) 是单帧内部阶段，同一帧内立即转入 Phase 1 或 2，**不同步到客户端**。
> 协议同步的 phase 值 = 服务端内部 phase 值（1-6），客户端收不到 phase=0。

**Init + 移动阶段详细逻辑**：

```go
const (
    scenarioMaxNavMeshDist float32 = 10.0  // NavMesh 直走最大距离（超过则放弃）
)

// ScenarioHandler.OnTick 中：
case ScenarioPhase_Init:
    // 已由 ScenarioSystem 完成分配，此处计算路网衔接
    nearNodeId, _, nearNodePos := roadNet.FindNearestPointID(&sched.TargetPos)
    if nearNodePos == nil {
        // 异常：找不到最近路网节点，释放场景点回退空闲
        h.abortScenario(ctx, sched)
        return
    }
    // 检查场景点与最近路网节点的 NavMesh 距离是否合理
    navDist := distanceSqXZ(*nearNodePos, sched.TargetPos)
    if navDist > scenarioMaxNavMeshDist * scenarioMaxNavMeshDist {
        // 场景点离路网太远，放弃
        h.abortScenario(ctx, sched)
        return
    }
    sched.ScenarioNearNodeId = int32(nearNodeId)
    sched.ScenarioNearNodePos = *nearNodePos

    // 获取 NPC 当前所在的路网节点
    currentNodeId, _, _ := roadNet.FindNearestPointID(&npcPos)

    if currentNodeId == nearNodeId {
        // 已经在最近节点附近，直接 NavMesh 走
        sched.ScenarioPhase = ScenarioPhase_WalkToPoint
    } else {
        // 路网寻路到最近节点
        pathPoints, err := roadNet.FindPathToVec3List(currentNodeId, nearNodeId)
        if err != nil || len(pathPoints) == 0 {
            // 路网寻路失败，释放场景点回退空闲
            h.abortScenario(ctx, sched)
            return
        }
        ctx.Scene.SetEntityRoadNetPath(ctx.EntityID, pathPoints, direction)
        sched.ScenarioPhase = ScenarioPhase_WalkToNearNode
    }

case ScenarioPhase_WalkToNearNode:
    // 检查是否到达最近路网节点
    distSq := distanceSqXZ(npcPos, sched.ScenarioNearNodePos)
    if distSq <= arrivalDistSq {
        sched.ScenarioPhase = ScenarioPhase_WalkToPoint
    }

case ScenarioPhase_WalkToPoint:
    // NavMesh 直走到场景点
    ctx.NpcState.SetMoveTarget(sched.TargetPos, state.MoveSourceSchedule)
    distSq := distanceSqXZ(npcPos, sched.TargetPos)
    if distSq <= arrivalDistSq {
        sched.ScenarioPhase = ScenarioPhase_Enter
    }
```

#### 3.4.3 返回日程路线：NavMesh + 路网两段式

```
NPC 在场景点（不在路网上）
  │
  ├─ 阶段1: NavMesh 短距离直走到最近路网节点
  │   使用之前记录的 ScenarioNearNodeId / ScenarioNearNodePos
  │   NpcState.SetMoveTarget(nearNodePos)
  │
  ├─ 到达路网节点后：
  │   ScenarioHandler.OnExit() → CurrentPlan = ""
  │
  ▼
ScheduleHandler 重新接管
  │ 从 NPC 当前位置（已在路网节点上）正常路网寻路
  ▼
继续日程
```

**离开阶段详细逻辑**：

```go
case ScenarioPhase_Leave:
    // 播放离开动画，完成后进入回路阶段
    if leaveAnimDone || noLeaveAnim {
        sched.ScenarioPhase = ScenarioPhase_WalkBackToRoad
    }

case ScenarioPhase_WalkBackToRoad:
    // NavMesh 直走回最近路网节点
    ctx.NpcState.SetMoveTarget(sched.ScenarioNearNodePos, state.MoveSourceSchedule)
    distSq := distanceSqXZ(npcPos, sched.ScenarioNearNodePos)
    if distSq <= arrivalDistSq {
        // 已回到路网，退出 ScenarioHandler
        // OnExit 会清理状态，ScheduleHandler 下一帧接管
        sched.CurrentPlan = ""
    }
```

**异常回退辅助方法**（B1）：

```go
// 放弃场景点：释放占用，回退空闲
func (h *ScenarioHandler) abortScenario(ctx *execution.PlanContext, sched *state.ScheduleState) {
    if sched.ScenarioPointId > 0 {
        h.scenarioMgr.Release(sched.ScenarioPointId, int64(ctx.EntityID))
    }
    sched.ScenarioPointId = 0
    sched.ScenarioPhase = 0
    sched.CurrentPlan = ""
    log.Debugf("[ScenarioHandler] abortScenario, entityID=%d", ctx.EntityID)
}
```

**冷却机制**（B2）：

ScenarioHandler.OnExit 中设置冷却：

```go
func (h *ScenarioHandler) OnExit(ctx *execution.PlanContext) {
    sched := &ctx.NpcState.Schedule
    // ... 释放场景点、清理字段 ...
    sched.ScenarioCooldownUntil = nowMs + 30000  // 30 秒冷却
    sched.CurrentPlan = ""
}
```

ScenarioSystem 空闲判定中检查冷却：

```go
func isNpcFreeForScenario(npcState *state.NpcState, nowMs int64) bool {
    sched := npcState.Schedule
    return sched.ScenarioPointId == 0 &&
           sched.CurrentPlan != "scenario" &&
           sched.CurrentPlan != "combat" &&
           sched.CurrentPlan != "flee" &&
           nowMs >= sched.ScenarioCooldownUntil  // 冷却期内不分配
}
```

#### 3.4.4 NpcState 新增字段（S4）

```go
type ScheduleState struct {
    // ... 已有字段（ScenarioPointId, ScenarioDuration, HasTarget, TargetPos 等）...

    // 新增字段：
    ScenarioTypeId       int32           // 场景点类型 ID（用于 Proto 同步和配置查询）
    ScenarioDirection    float32         // 场景点朝向（用于 Proto 同步）
    ScenarioPhase        int32           // 当前执行阶段（0-6，见 §3.4.2 枚举）
    ScenarioNearNodeId   int32           // 场景点最近的路网节点 ID
    ScenarioNearNodePos  transform.Vec3  // 该节点的世界坐标
    ScenarioCooldownUntil int64          // 冷却截止时间戳（毫秒），此前不可被再次分配
}
```

**Snapshot 同步**：所有新增字段均需加入 `ScheduleState.ToSnapshot()` / `FromSnapshot()`。

**FieldAccessor 注册**：

```go
// field_accessor.go 中新增：
RegisterField("schedule.scenario_phase", func(s *NpcState) interface{} { return s.Schedule.ScenarioPhase })
RegisterField("schedule.scenario_type",  func(s *NpcState) interface{} { return s.Schedule.ScenarioTypeId })
RegisterField("schedule.scenario_cooldown", func(s *NpcState) interface{} { return s.Schedule.ScenarioCooldownUntil })
```

> ScenarioNearNodeId/Pos 为 Handler 内部使用，不需要暴露给行为树表达式。

#### 3.4.5 流程总览

```
                    路网寻路              NavMesh直走
  NPC(路网上) ─────────────→ 最近节点 ──────────→ 场景点
                                                    │
                                              执行动画(Enter→Loop→Leave)
                                                    │
                    路网寻路              NavMesh直走  │
  日程恢复 ←──────────────── 最近节点 ←──────────── 场景点
  (ScheduleHandler)         (回到路网)
```

**设计要点**：
- 路网→场景点、场景点→路网 都是"路网 + NavMesh"混合寻路
- `ScenarioNearNodeId` 在分配时计算一次，前往和返回共用
- NavMesh 短距离直走通常 < 5m，不会穿越不合理区域
- 返回到路网节点后才交还控制权给 ScheduleHandler，确保日程恢复时 NPC 在路网上

### 3.5 配置与加载 (G4)

#### 3.5.1 现有配置表状态

配置已在 `NpcSchedule.xlsx` 中定义（ScenarioPoint / ScenarioType 两个 Sheet），打表工具已生成：
- Go: `common/config/cfg_scenariopoint.go` / `cfg_scenariotype.go`（已有完整 Getter）
- C#: `Config/Gen/CfgScenarioPoint.cs` / `CfgScenarioType.cs`
- 二进制: `bin/config/cfg_scenariopoint.bytes` / `cfg_scenariotype.bytes`

**当前问题**：二进制文件仅 ~260 / ~197 bytes（约 1-2 条测试数据），需要填充实际场景点。

#### 3.5.2 CfgScenarioPoint 字段（已有，无需改表结构）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | int32 | 场景点唯一 ID |
| scenarioType | int32 | 关联 CfgScenarioType.id |
| posX, posY, posZ | float32 | 世界坐标 |
| direction | float32 | 朝向（弧度） |
| maxUsers | int32 | 最大同时占用 NPC 数 |
| timeStart | int32 | 有效起始时间（游戏时间小时，0=不限） |
| timeEnd | int32 | 有效结束时间（0=不限） |
| duration | int32 | 停留秒数（0=使用类型默认） |
| probability | int32 | 触发概率%（0=使用类型默认） |
| radius | float32 | 交互半径 |
| flags | int32 | 标志位（见 §3.1） |

> **注意**：无 sceneId 字段。当前只有 Town 场景使用场景点，所有点全量加载。
> 未来多场景时需加 sceneId 字段并按场景过滤（参照 CfgSpawnPoints 模式）。

#### 3.5.3 CfgScenarioType 字段（已有，无需改表结构）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | int32 | 类型 ID |
| name | string | 类型名称 |
| enterAnim | string | 进入动画名 |
| loopAnim | string | 循环动画名 |
| leaveAnim | string | 离开动画名 |
| defaultDuration | int32 | 默认停留秒数 |
| defaultProbability | int32 | 默认概率% |

#### 3.5.4 ScenarioType 初始数据

| Id | Name | EnterAnim | LoopAnim | LeaveAnim | Duration | Probability |
|----|------|-----------|----------|-----------|----------|-------------|
| 1 | Bench | sit_down | sit_idle | stand_up | 60 | 80 |
| 2 | Stall | approach | browse | turn_leave | 30 | 60 |
| 3 | LeanWall | lean_start | lean_idle | lean_end | 45 | 70 |
| 4 | Phone | phone_pickup | phone_talk | phone_hangup | 40 | 50 |
| 5 | Exercise | exercise_start | exercise_loop | exercise_end | 90 | 40 |
| 6 | Watch | - | watch_idle | - | 20 | 90 |
| 7 | Guard | - | guard_idle | - | 120 | 100 |

> 动画名为占位符，需与客户端实际动画资源名对齐。`-` 表示该阶段无专属动画（直接跳过）。

#### 3.5.5 ScenarioPoint 配置数据

已在 `freelifeclient/RawTables/TownNpc/NpcScenarioConfig.xlsx` 中配置 20 个场景点，
基于 NpcMeetingPoint 的 11 个实际地标坐标偏移生成。7 种类型覆盖：

| 类型 | 数量 | 分布 |
|------|------|------|
| Bench_Sit | 4 | 北面滨水区、酒吧前、旅店门口、滑板公园 |
| Lean_Wall | 4 | 集装箱旁、酒吧前墙壁、建筑工地后面、理发店旁 |
| Phone_Call | 3 | 披萨店后面、旅店门口、理发店旁(夜间) |
| Stall_Browse | 2 | 披萨店后面(白天)、塔可店后面(白天) |
| Exercise | 2 | 篮球场(白天)、滑板公园(白天) |
| Watch | 3 | 篮球场(3人)、建筑工地(2人)、滑板公园(2人) |
| Guard | 2 | 靶场后面(高优)、北面滨水区(高优) |

> 详细数据见 `NpcScenarioConfig.xlsx` ScenarioPoint Sheet。
> 旧的 `NpcSchedule.xlsx` 中 ScenarioPoint/ScenarioType Sheet 为测试占位数据，后续迁移到 TownNpc 目录后删除。

#### 3.5.6 加载链路（参照 SpawnPointManager 模式）

```go
// scene_impl.go init() 中新增：
func initScenarioPoints(scene common.Scene) {
    mgr := scene.GetResource(ScenarioPointManager)
    for _, cfg := range config.GetCfgMapScenarioPoint() {
        mgr.AddPoint(ScenarioPoint{
            PointId:      cfg.GetId(),
            ScenarioType: cfg.GetScenarioType(),
            Position:     Vec3{cfg.GetPosX(), cfg.GetPosY(), cfg.GetPosZ()},
            Direction:    cfg.GetDirection(),
            MaxUsers:     cfg.GetMaxUsers(),
            TimeStart:    cfg.GetTimeStart(),
            TimeEnd:      cfg.GetTimeEnd(),
            Duration:     cfg.GetDuration(),
            Probability:  cfg.GetProbability(),
            Radius:       cfg.GetRadius(),
            Flags:        uint32(cfg.GetFlags()),
        })
    }
}
```

**调用时机**：`scene.init()` → 创建 ScenarioPointManager → `initScenarioPoints()` 灌入配置数据。
**依赖**：ConfigLoader 已加载完 `cfg_scenariopoint.bytes`（在 scene init 之前）。

## 4 协议设计

### 4.1 扩展 NpcScenarioData

```protobuf
message NpcScenarioData {
    int32 point_id = 1;       // 已有
    int32 scenario_type = 2;  // 已有
    int32 phase = 3;          // 已有，扩展为 7 阶段
    float direction = 4;      // 新增：朝向
    int32 duration = 5;       // 新增：停留时长（客户端用于表现计时）
}
```

### 4.2 Phase 定义（服务端 → 客户端）

| phase 值 | 服务端枚举 | 含义 | 客户端行为 |
|----------|-----------|------|----------|
| 1 | WalkToNearNode | 路网寻路中 | 正常行走动画 |
| 2 | WalkToPoint | NavMesh 直走到场景点 | 正常行走动画 |
| 3 | Enter | 到达场景点 | 播放 EnterAnim + 设置朝向 |
| 4 | Loop | 执行中 | 播放 LoopAnim（循环） |
| 5 | Leave | 离开场景点 | 播放 LeaveAnim |
| 6 | WalkBackToRoad | NavMesh 走回路网 | 正常行走动画 |

> phase 0 (Init) 为服务端单帧内部阶段，不下发客户端。
> `point_id == 0` 表示无场景点，客户端清空状态。
> 客户端只需关心 phase 3/4/5（动画相关），phase 1/2/6 期间 NPC 正常走路，无需特殊处理。

### 4.3 同步时机

| 服务端事件 | 写入 Proto |
|-----------|-----------|
| ScenarioSystem 分配成功，Init 完成 | point_id, scenario_type, phase=1, direction, duration |
| 到达最近路网节点 | phase=2 |
| 到达场景点 | phase=3 |
| EnterAnim 时长结束 | phase=4 |
| 停留时长到期 | phase=5 |
| LeaveAnim 时长结束 | phase=6 |
| 回到路网节点 | 清空 scenario_data（point_id=0） |

## 5 客户端详细设计

### 5.1 TownNpcScenarioComp 完善

补全现有 TODO：
- `StartScenario(pointId, type, direction, duration)` → 记录状态
- `OnPhaseChanged(phase)` → phase 2/3/4 时触发动画，其余忽略
- `LeaveScenario()` → 清理状态，恢复 FSM

### 5.2 FSM 状态 — TownNpcScenarioState

新增 FSM 状态（参照 TownNpcPatrolState 模式）：

```
OnEnter:
  从 ScenarioComp 读取 scenarioType → 查 CfgScenarioType 配置
  缓存 enterAnim / loopAnim / leaveAnim

OnUpdate:
  根据当前 phase 驱动动画：

  phase 0/1 (行走中):
    不做特殊处理，NPC 自然行走（Transform 同步驱动）

  phase 2 (Enter):
    设置朝向 direction
    播放 EnterAnim（如果有）
    无 EnterAnim → 直接等待服务端推 phase=3

  phase 3 (Loop):
    播放 LoopAnim（循环模式）

  phase 4 (Leave):
    播放 LeaveAnim（如果有）
    无 LeaveAnim → 等待服务端推 phase=5

  phase 5 (走回路网):
    停止场景点动画，恢复行走状态

  point_id == 0:
    退出 ScenarioState

OnExit:
  停止所有使用过的动画层
  清理 ScenarioComp 状态
```

### 5.3 动画映射

ScenarioType 配置表的 EnterAnim/LoopAnim/LeaveAnim 字段对应 Animancer 动画资源路径。客户端通过 ScenarioType Id 查配置表获取动画名。

## 6 事务性设计

场景点占用是跨 NPC 共享资源，需保证：

- **原子性**：ScenarioSystem 在单线程 Update 中完成"查询+占用+写 NpcState"，无并发竞争
- **释放保障（三层兜底）**：
  1. **正常释放**：ScenarioHandler.OnExit → `mgr.Release(pointId, npcId)`
  2. **超时释放**：ScenarioHandler 停留时长到期 → 主动退出 → 触发 OnExit
  3. **销毁兜底**：NPC 销毁时 ScenarioSystem 调用 `mgr.ReleaseByNpc(npcId)` 清理所有占用
- **冷却机制**：NPC 离开场景点后设置冷却时间（如 30 秒），避免刚离开又被分配到同一个点
- **无需持久化**：纯运行时状态，服务重启后重新初始化

## 7 单元测试设计

| 测试文件 | 覆盖范围 |
|---------|---------|
| `scenario/scenario_point_manager_test.go` | Flags 过滤、概率筛选、Duration 默认值、占用/释放、时间窗口、容量限制 |
| `scenario/scenario_system_test.go` | 空闲判定、分帧扫描、分配写入、冷却机制、NPC 队列维护 |

## 8 风险与缓解

| 风险 | 缓解 |
|------|------|
| 配置表数据极少（1-2 条） | 补充 ScenarioType 7 种 + ScenarioPoint 5+ 测试点，重新打表 |
| 场景点坐标需从 Unity 标定 | 先用 Unity MCP 截图确定大致位置，填入配置表 |
| 客户端动画资源可能不存在 | ScenarioType 动画名先用占位符，与美术对齐后替换 |
| Phase 同步延迟导致动画跳变 | P0 纯服务端驱动（phase 切换频率低，延迟可接受）；本地预测标记 P1 优化 |
| 无 sceneId 字段 | 当前单场景全量加载可行，多场景时需加字段 |
| ScenarioSystem 与 ScheduleHandler 冲突 | 空闲判定排除 scenario 状态；移除 BehaviorType=5 触发路径 |

