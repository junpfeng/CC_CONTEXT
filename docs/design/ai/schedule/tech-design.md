# NPC 日程与巡逻系统——技术设计

> 版本：v1.1 | 日期：2026-03-19 | 状态：已实现（回溯更新 V2 日程+Scenario P0 变更）
> ✅ **审查状态**：Phase 6 已通过，9 个严重/中等问题已全部修复（FIX-1~FIX-9），详见 `review-report.md`。
> 需求文档：`server.md` / `protocol.md` / `client.md`

## 目录

1. [需求回顾](#1-需求回顾)
2. [架构设计](#2-架构设计)
3. [服务器详细设计](#3-服务器详细设计)
4. [协议设计](#4-协议设计)
5. [客户端详细设计](#5-客户端详细设计)
6. [配置设计](#6-配置设计)
7. [事务性设计](#7-事务性设计)
8. [接口契约](#8-接口契约)
9. [风险与缓解](#9-风险与缓解)

---

## 1 需求回顾

四大子系统，三个工程协同：

| 子系统 | 核心能力 | P0 范围 |
|--------|---------|---------|
| PopSchedule | 按时段×区域动态调控 NPC 数量和类型 | 6 时段配额、渐变 Spawn/Despawn、类型权重 |
| DaySchedule | NPC 按时间表执行日常行为序列 | 模板驱动、8 种行为类型、中断恢复 |
| Patrol | 沿预设路线循环巡逻 | 闭环/开放路线、节点停留动画、多 NPC 互斥 |
| ScenarioPoint | 城市活动节点占用与动画 | 占用/释放、时间过滤、平方距离搜索 |

**工程分工**：服务端（决策+调度） → 协议（状态同步+事件通知） → 客户端（纯表现）

## 2 架构设计

### 2.1 系统边界

```
┌─ P1GoServer ─────────────────────────────────────────────────────┐
│                                                                   │
│  NpcManager 层（管线外）                                           │
│  ├─ PopScheduleManager   按时段评估配额，门控 Spawn/Despawn        │
│  ├─ DayScheduleManager   管理日程模板，按游戏时间匹配条目           │
│  ├─ PatrolRouteManager   管理路线数据，分配/释放 NPC 到路线         │
│  └─ ScenarioPointManager 管理场景点，空间索引，占用/释放            │
│                                                                   │
│  V2 正交管线（Locomotion 维度）                                     │
│  ├─ ScheduleHandler      日程路由器（Idle/MoveTo/Work/Rest/过渡）   │
│  ├─ PatrolHandler        巡逻状态机（MoveToNode/Stand/Select）     │
│  ├─ ScenarioHandler      场景点交互（移动/执行/释放）               │
│  └─ GuardHandler         固定站岗                                  │
│                                                                   │
│  State 层                                                         │
│  └─ NpcState.ScheduleState  扩展 5 字段                           │
│                                                                   │
│  Config 层                                                        │
│  ├─ bin/config/V2TownNpcSchedule/   V2 日程模板 JSON（24 个 NPC） │
│  └─ bin/config/ai_patrol/           巡逻路线 JSON（待建）         │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
                    │ Proto 同步
                    ▼
┌─ old_proto ──────────────────────────────────────────────────────┐
│  scene/npc.proto                                                  │
│  ├─ NpcState 枚举 +4 值 (Patrol=17, Guard=18, Scenario=19,       │
│  │   ScheduleIdle=20)                                             │
│  ├─ TownNpcData +3 子消息 (schedule_data=17, patrol_data=18,     │
│  │   scenario_data=19)                                            │
│  ├─ 3 新枚举 (ScheduleBehaviorType, ScenarioPhase,               │
│  │   ScheduleChangeReason, PatrolAlertLevel)                      │
│  └─ 4 Ntf 消息                                                   │
└───────────────────────────────────────────────────────────────────┘
                    │ 生成代码
                    ▼
┌─ freelifeclient ─────────────────────────────────────────────────┐
│  FSM 层                                                           │
│  ├─ TownNpcPatrolState       巡逻移动表现                         │
│  ├─ TownNpcGuardState        站岗表现                             │
│  ├─ TownNpcScenarioState     场景点交互动画                       │
│  └─ TownNpcScheduleIdleState 日程空闲                             │
│                                                                   │
│  组件层                                                           │
│  ├─ TownNpcScenarioComp      场景点交互状态管理（async，需 CancelToken） │
│  └─ TownNpcPatrolVisualComp  巡逻视觉（警惕姿态/LookAt）                │
└───────────────────────────────────────────────────────────────────┘
```

### 2.2 数据流

```
PopScheduleManager ──(配额门控)──→ Spawn NPC + 分配行为类型
         │
         ▼
DayScheduleManager.Evaluate(gameTime, npcState)
         │ 写入 ScheduleState（templateId, entryIndex, targetPos）
         ▼
Locomotion 维度 Brain 决策 → 选择 plan name
         │
         ▼
PlanExecutor.Execute(plan) → ScheduleHandler / PatrolHandler / ScenarioHandler
         │ 写入 MoveTarget(source=SCHEDULE)
         ▼
Navigation 维度 → NavigateBtHandler → 路网 A* 寻路 → 移动
         │
         ▼
mapNpcStateToProto → TownNpcData(schedule_data/patrol_data/scenario_data)
         │
         ▼
客户端 FSM → 动画表现
```

### 2.3 与现有系统集成点

| 集成点 | 方式 | 说明 |
|--------|------|------|
| PlanExecutor | 注册新 Handler | Locomotion 维度新增 4 个 plan |
| V2Brain | 新增 locomotion 决策规则 | JSON 配置新增 schedule/patrol/scenario/guard 条件 |
| MoveTarget 仲裁 | 复用 MoveSourceSchedule=3 | 已有优先级档位 |
| scheduleWriteBack | 复用 | Pipeline 步骤 5 回写 ScheduleState.TargetPos |
| BtTickSystem | 无改动 | 管线入口不变 |
| mapNpcStateToProto | 扩展 | 新增子消息序列化 |

## 3 服务器详细设计

### 3.1 模块划分

所有新代码位于 `servers/scene_server/internal/common/ai/` 下：

```
ai/
├─ state/
│   └─ npc_state.go              # ScheduleState 扩展 5 字段 + Snapshot 同步
├─ schedule/                     # 【新建】日程与人口调度
│   ├─ pop_schedule_manager.go   # 人口配额管理器
│   ├─ day_schedule_manager.go   # 日程模板管理与条目匹配
│   ├─ schedule_config.go        # 日程 JSON 配置结构 + 加载
│   └─ schedule_config_test.go
├─ patrol/                       # 【新建】巡逻系统
│   ├─ patrol_route_manager.go   # 路线管理、NPC 分配/释放
│   ├─ patrol_config.go          # 巡逻 JSON 配置结构 + 加载
│   └─ patrol_config_test.go
├─ scenario/                     # 【新建】场景点系统
│   ├─ scenario_point_manager.go # 场景点管理、空间索引、占用/释放
│   ├─ spatial_grid.go           # Grid 空间分区索引
│   └─ spatial_grid_test.go
├─ execution/
│   └─ handlers/
│       └─ schedule_handlers.go  # 【新建】ScheduleHandler/PatrolHandler/ScenarioHandler/GuardHandler
└─ decision/
    └─ v2brain/                  # 现有 V2Brain 配置新增 locomotion 决策规则
```

Manager 层在管线外，由 `npc_mgr` 包初始化并注入到 Handler 中（依赖注入，避免循环 import）。

### 3.2 NpcState 扩展

在 `ScheduleState` 新增 5 字段（复用已有 8 字段）：

```go
type ScheduleState struct {
    // --- 已有字段（复用） ---
    CurrentNode     int32          // 当前日程节点 ID
    NextNodeTime    int64          // 下一节点触发时间戳
    IsInterrupted   bool           // 是否被中断
    InterruptTime   int64          // 中断时间戳
    PauseAccum      int64          // 累计暂停时长（毫秒）
    MeetingState    int32          // 会议状态
    CurrentPlan     string         // 当前决策计划名
    HasTarget       bool           // 是否有日程目标
    TargetPos       transform.Vec3 // 日程目标位置（Pipeline 步骤 5 回写用）
    ActiveStartTime int64          // 当前正在执行的日程条目 StartTime（用于检测条目切换）

    // --- 日程与巡逻系统新增 ---
    ScheduleTemplateId int32     // 日程模板 ID（0=无日程）
    PatrolRouteId      int32     // 巡逻路线 ID（0=无巡逻）
    PatrolDirection    int32     // 巡逻方向（0=forward, 1=backward）
    ScenarioPointId    int32     // 占用的场景点 ID（0=无）
    ScenarioDuration   int32     // 场景点停留时长（秒，0=使用默认值）
    AlertLevel         int32     // 警惕等级（0=casual, 1=alert）

    // --- 场景点执行状态（ScenarioSystem 分配后由 ScenarioHandler 维护）---
    ScenarioTypeId        int32          // 场景点类型 ID（用于 Proto 同步和配置查询）
    ScenarioDirection     float32        // 场景点朝向（弧度，用于 Proto 同步）
    ScenarioPhase         int32          // 当前执行阶段（0-6: Init→WalkToNearNode→WalkToPoint→Enter→Loop→Leave→WalkBackToRoad）
    ScenarioNearNodeId    int32          // 场景点最近的路网节点 ID
    ScenarioNearNodePos   transform.Vec3 // 该路网节点的世界坐标
    ScenarioCooldownUntil int64          // 冷却截止时间戳（毫秒）
}
```

**Snapshot 同步**：ScheduleState 整体复制（值类型 struct），新增字段自动包含。注意 `ScenarioNearNodePos` 为 `transform.Vec3` 值类型，同样安全拷贝。

**验证**：ScheduleState 为纯值类型（无 slice/map/pointer），struct copy 即深拷贝。共 24 个字段，分三组：核心日程(10)、日程巡逻扩展(6)、场景点执行状态(8)。

### 3.3 Handler 设计

所有 Handler 遵循现有模式：**无状态共享单例**，状态存 NpcState。

#### 3.3.1 ScheduleHandler（日程路由器）

```go
// 注册 plan name: "schedule"
type ScheduleHandler struct {
    scheduleMgr  *schedule.DayScheduleManager  // 依赖注入
    scenarioMgr  *scenario.ScenarioPointManager
}

func (h *ScheduleHandler) OnEnter(ctx *PlanContext) {
    // 读取 ScheduleState.ScheduleTemplateId，初始化日程执行
}

func (h *ScheduleHandler) OnTick(ctx *PlanContext) {
    // 1. 检查日程中断/恢复
    // 2. 匹配当前时段日程条目（无匹配时 fallback 到 Idle）
    // 3. 按 BehaviorType 分发：
    //    - Idle/MoveTo/Work/Rest: 自身处理，写入 MoveTarget(SCHEDULE)
    //    - Patrol/UseScenario/Guard: 直接通过 ctx.SwitchPlan("patrol"/"scenario"/"guard")
    //      切换到对应 Handler（同帧生效，无延迟）
    //    - EnterBuilding: 标记 Despawn 请求
    //    - ExitBuilding: 初始化后切换到下一行为
}

func (h *ScheduleHandler) OnExit(ctx *PlanContext) {
    // 清理 ScheduleState 的临时标记
}
```

**路由机制**：ScheduleHandler 通过 `ctx.SwitchPlan(planName)` 直接请求 PlanExecutor 在同帧内切换到目标 Handler（patrol/scenario/guard），避免经 Brain 二次决策产生的一帧延迟。PlanExecutor.SwitchPlan 调用当前 Handler.OnExit + 目标 Handler.OnEnter，同帧生效。

**Brain 决策配合**：V2Brain locomotion 规则仅负责初始 plan 选择（NPC spawn 时或日程无活跃 Handler 时），ScheduleHandler 运行中的子行为切换由 Handler 自身驱动，不依赖 Brain。

#### 3.3.2 PatrolHandler

```go
// 注册 plan name: "patrol"
type PatrolHandler struct {
    patrolMgr *patrol.PatrolRouteManager
}
```

**状态机**（通过 ScheduleState 字段驱动，非 Go FSM）：
- `CurrentNode` = 当前目标节点 ID
- `NextNodeTime` = 节点停留到期时间
- `PatrolDirection` = 遍历方向

OnTick 逻辑：
1. 若无目标节点 → Start: 查找最近节点，设 CurrentNode
2. 若未到达目标 → MoveToNode: SetMoveTarget(nodePos, SCHEDULE)
3. 若已到达且停留中 → StandAtNode: 等待 Duration 到期
4. 停留到期 → SelectNext: 按 Links + Direction 选择下一节点

**节点互斥**：PatrolRouteManager 维护每节点占用 NPC ID 集合，分配前检查。

#### 3.3.3 ScenarioHandler

```go
// 注册 plan name: "scenario"
type ScenarioHandler struct {
    scenarioMgr ScenarioFinder     // 查询+占用+释放
    roadNetMgr  RoadNetQuerier     // 路网寻路（可选，nil 时直线移动）
}
```

**7 阶段状态机**（由 `ScenarioPhase` 字段驱动，参考 GTA5 CScenarioManager）：

| 阶段 | 名称 | 说明 |
|------|------|------|
| 0 | Init | 初始化：计算场景点最近路网节点，规划路径 |
| 1 | WalkToNearNode | 经路网移动到场景点附近的道路节点 |
| 2 | WalkToPoint | 从路网节点直线步行到场景点精确位置 |
| 3 | Enter | 到达后播放 Enter 动画 |
| 4 | Loop | 持续播放 Loop 动画，等待 Duration 到期 |
| 5 | Leave | 播放 Leave 动画 |
| 6 | WalkBackToRoad | 返回路网节点，完成后释放场景点 |

**保护机制**：移动阶段 30s 超时强制释放；完成后写入 30s ScenarioCooldownUntil 冷却。

> 完整设计详见 `scenario-p0-design.md`。

#### 3.3.4 GuardHandler

```go
// 注册 plan name: "guard"
type GuardHandler struct{}
```

最简 Handler：OnEnter 设置固定位置 + 朝向，OnTick 无操作（站岗无需移动），OnExit 清理。

#### 3.3.5 注册方式

在 `v2_pipeline_defaults.go` 的 Locomotion 维度注册回调中新增：

```go
// locomotion dimension
func(exec *PlanExecutor) {
    exec.RegisterHandler("on_foot", &OnFootHandler{})
    // 新增
    exec.RegisterHandler("schedule", &ScheduleHandler{scheduleMgr: mgr, scenarioMgr: sMgr})
    exec.RegisterHandler("patrol", &PatrolHandler{patrolMgr: pMgr})
    exec.RegisterHandler("scenario", &ScenarioHandler{scenarioMgr: sMgr})
    exec.RegisterHandler("guard", &GuardHandler{})
}
```

Manager 实例由 `npc_mgr` 包创建，通过闭包注入 Handler。

### 3.4 PopSchedule 人口调度

```go
// ai/schedule/pop_schedule_manager.go
type PopScheduleManager struct {
    allocations map[int32]map[int32]*PopAllocation // regionId → timeSlot → allocation
    regions     map[int32]*Region                   // regionId → region 定义
    overrides   map[int32]*PopAllocation            // regionId → 临时覆盖（脚本用, P1）
}

type PopAllocation struct {
    MaxAmbientNpc  int32
    MaxScheduleNpc int32
    MaxPatrolNpc   int32
    MaxScenarioNpc int32
    NpcGroupWeights map[string]int32
}

type Region struct {
    RegionId int32
    Center   transform.Vec3
    Radius   float32
}
```

**核心方法**：

| 方法 | 说明 |
|------|------|
| `Evaluate(gameHour int32, playerPositions []Vec3)` | 每 Tick 调用，计算各区域当前时段配额，返回需 Spawn/Despawn 的 delta |
| `GetTimeSlot(gameHour int32) int32` | 0-23 小时 → 0-5 时段索引 |
| `SelectNpcType(allocation *PopAllocation) string` | 按权重随机选择 NPC 类型组 |
| `SetOverride(regionId int32, alloc *PopAllocation)` | P1：脚本临时覆盖 |
| `ClearOverride(regionId int32)` | P1：恢复原始配额 |

**调用位置**：NpcManager 的主循环（管线外），每秒调用一次 `Evaluate`（配额变化频率低，无需每帧评估），根据返回 delta 执行 Spawn/Despawn。

**渐变过渡**：每 Tick 最多 Spawn 1 个 + Despawn 1 个，避免帧峰值。

### 3.5 DaySchedule 日程管理器

```go
// ai/schedule/day_schedule_manager.go
type DayScheduleManager struct {
    templates map[int32]*ScheduleTemplate // templateId → template
}

type ScheduleTemplate struct {
    TemplateId int32
    Name       string
    Entries    []ScheduleEntry // 按 StartTime 升序
}

type ScheduleEntry struct {
    StartTime     int64    `json:"startTime"`     // 开始时间（游戏秒 0-86400），与 V1 一致
    EndTime       int64    `json:"endTime"`       // 结束时间（游戏秒，支持跨日）
    LocationId    int32    `json:"locationId"`    // 目标地点 ID
    BehaviorType  int32    `json:"behaviorType"`  // 行为类型枚举
    Priority      int32    `json:"priority"`      // 优先级（高覆盖低）
    Probability   float32  `json:"probability"`   // 执行概率 0.0-1.0
    TargetPos     Vec3Json `json:"targetPos"`     // 目标世界坐标
    FaceDirection Vec3Json `json:"faceDirection"` // 到达后朝向（欧拉角）
    StartPointId  int32    `json:"startPointId"`  // 路网起点 ID（MoveTo 行为用）
    EndPointId    int32    `json:"endPointId"`    // 路网终点 ID（MoveTo 行为用）
    BuildingId    int32    `json:"buildingId"`    // 建筑 ID（EnterBuilding 行为用）
    DoorId        int32    `json:"doorId"`        // 门 ID（EnterBuilding 行为用）
    Duration      float64  `json:"duration"`      // 停留/动画时长（秒）
}
```

**核心方法**：

| 方法 | 说明 |
|------|------|
| `MatchEntry(templateId int32, gameSecond int64) *ScheduleEntry` | 匹配当前秒级时段最高优先级条目，处理跨日 |
| `GetTemplate(templateId int32) *ScheduleTemplate` | 获取模板 |
| `LoadTemplates(dirPath string) error` | 从 JSON 目录加载所有模板 |

**跨日匹配**：当 `StartTime > EndTime`，匹配条件为 `second >= StartTime OR second < EndTime`。

**概率判定**：首次进入条目时掷骰，结果缓存在 ScheduleState 中（通过 CurrentNode 索引），避免每帧重复判定。

### 3.6 Patrol 巡逻管理器

```go
// ai/patrol/patrol_route_manager.go
type PatrolRouteManager struct {
    routes     map[int32]*PatrolRoute // routeId → route
    nodeOccup  map[int64]int32       // npcEntityId → occupied nodeId（互斥用）
    npcToRoute map[int64]int32       // npcEntityId → routeId（反向索引，清理用）
}

type PatrolRoute struct {
    RouteId         int32
    Name            string
    RouteType       int32 // 0=Permanent, 1=Scripted
    Nodes           []PatrolNode
    DesiredNpcCount int32
    // CurrentNpcCount 不单独维护，用 len(AssignedNpcs) 代替，避免计数漂移
    AssignedNpcs    map[int64]bool // npcEntityId set
}

type PatrolNode struct {
    NodeId       int32
    Position     transform.Vec3
    Heading      float32
    Duration     int32  // 停留 ms，0=不停留
    BehaviorType int32  // 动画枚举 ID（与 NpcPatrolNodeArriveNtf.behavior_type 一致）
    Links        []int32
}
```

**核心方法**：

| 方法 | 说明 |
|------|------|
| `AssignNpc(routeId int32, npcId int64) (startNodeId int32, ok bool)` | 分配 NPC 到路线，返回最近起始节点 |
| `ReleaseNpc(routeId int32, npcId int64)` | 释放 NPC，从 AssignedNpcs 移除 + 清理 npcToRoute 反向索引 |
| `ReleaseAllByNpc(npcId int64)` | 通过 npcToRoute 反向索引释放该 NPC 的所有占用（路线分配+节点互斥），供 CleanupNpcResources 调用 |
| `GetNextNode(routeId, currentNodeId, direction int32) (int32, int32)` | 返回下一节点 ID + 新方向 |
| `IsNodeOccupied(routeId, nodeId int32, excludeNpc int64) bool` | 节点互斥检查 |
| `FindNearestNode(routeId int32, pos Vec3) int32` | 平方距离查找最近节点 |

**开放路线反向**：到达端点（Links 为空）时翻转 `PatrolDirection`，从当前节点反向遍历。

**分叉选择**：Links 有多个时随机选择（uniform），Alert 状态下优先选择距离警报目标更近的节点。

### 3.7 ScenarioPoint 场景点管理器

```go
// ai/scenario/scenario_point_manager.go
type ScenarioPointManager struct {
    points map[int32]*ScenarioPoint // pointId → point
    grid   *SpatialGrid            // 空间分区索引
}

type ScenarioPoint struct {
    PointId       int32
    ScenarioType  int32
    Position      transform.Vec3
    Direction     float32
    MaxUsers      int32
    CurrentUsers  int32
    TimeStart     int32  // 0=不限
    TimeEnd       int32  // 0=不限
    Duration      int32  // 秒，0=类型默认
    Probability   int32  // 百分比，0=类型默认
    Radius        float32
    Flags         uint32
    OccupiedNpcs  map[int64]bool // npcEntityId set
}
```

**空间索引**（Grid）：

```go
// ai/scenario/spatial_grid.go
type SpatialGrid struct {
    cellSize float32                    // 格子边长（推荐 20-50m）
    cells    map[CellKey][]*ScenarioPoint // (cx, cz) → 点列表
}

type CellKey struct { X, Z int32 }

func (g *SpatialGrid) Query(center Vec3, radius float32) []*ScenarioPoint
func (g *SpatialGrid) Insert(point *ScenarioPoint) // 插入前校验坐标范围 [-10000, 10000]，超出拒绝并 Error 日志
func (g *SpatialGrid) Remove(pointId int32)
```

**核心方法**：

| 方法 | 说明 |
|------|------|
| `FindNearest(pos Vec3, radius float32, gameHour int32, npcType string) *ScenarioPoint` | 搜索+过滤+排序，返回最优点 |
| `Occupy(pointId int32, npcId int64) bool` | 占用，CurrentUsers < MaxUsers 才成功 |
| `Release(pointId int32, npcId int64)` | 释放 |
| `IsAvailable(point, gameHour) bool` | 检查时间段+标志位+占用数 |

**搜索流程**：Grid.Query(pos, searchRadius) → 过滤(时间+概率+标志+占用) → 排序(距离²+优先级) → 返回最优。

**距离判断**：全部使用 `dx*dx + dz*dz` vs `radius*radius`，禁止 sqrt 和曼哈顿距离。

### 3.8 配置加载

复用 V2Brain 的配置加载模式：启动时从 JSON 文件加载到内存。

```go
// ai/schedule/schedule_config.go
func LoadScheduleTemplates(dirPath string) (map[int32]*ScheduleTemplate, error)
// 遍历 dirPath 下所有 .json 文件，反序列化为 ScheduleTemplate

// ai/patrol/patrol_config.go
func LoadPatrolRoutes(dirPath string) (map[int32]*PatrolRoute, error)
// 遍历 dirPath 下所有 .json 文件，反序列化为 PatrolRoute
```

**配置路径**：
- 日程模板：`bin/config/V2TownNpcSchedule/*.json`（24 个 NPC 模板，templateId 1001-1024）
- 巡逻路线：`bin/config/ai_patrol/*.json`（待建，当前巡逻配置尚未以独立 JSON 目录形式存在）
- 人口配额/场景点/场景类型：Excel 配置表（通过打表工具生成二进制，复用现有加载机制）

**校验**：加载时检查引用完整性（locationId 对应坐标有效，route node links 指向有效 nodeId），错误直接 Fatal 阻止启动。

**初始化保证**：
- 所有含 `map[int64]bool` 的运行时字段（`PatrolRoute.AssignedNpcs`、`ScenarioPoint.OccupiedNpcs`）在 Manager 构造或配置加载后统一初始化为 `make(map[int64]bool)`，避免 nil map panic
- `PopAllocation.NpcGroupWeights` 加载时校验至少有一个正权重值，否则 Fatal 阻止启动

**热更新**：预留 `Reload()` 接口，重新加载 JSON 并原子替换内存数据。基础版不实现热更，启动时一次性加载。

## 4 协议设计

**目标文件**：`old_proto/scene/npc.proto`

### 4.1 NpcState 枚举扩展

```protobuf
// 在现有 Angry=16 之后追加
Patrol       = 17;  // 巡逻移动
Guard        = 18;  // 站岗警戒
Scenario     = 19;  // 场景点行为
ScheduleIdle = 20;  // 日程空闲
```

### 4.2 新增枚举

```protobuf
enum ScheduleBehaviorType {
    SBT_Idle          = 0;
    SBT_MoveTo        = 1;
    SBT_Work          = 2;
    SBT_Rest          = 3;
    SBT_Patrol        = 4;
    SBT_UseScenario   = 5;
    SBT_EnterBuilding = 6;
    SBT_ExitBuilding  = 7;
}

enum ScenarioPhase {
    SP_Enter = 0;
    SP_Loop  = 1;
    SP_Leave = 2;
}

enum ScheduleChangeReason {
    SCR_Normal        = 0;
    SCR_Interrupted   = 1;
    SCR_Resumed       = 2;
    SCR_ScriptOverride = 3;
}

enum PatrolAlertLevel {
    PAL_Casual = 0;
    PAL_Alert  = 1;
}
```

### 4.3 子消息

```protobuf
message NpcScheduleData {
    int32 template_id  = 1;
    int32 entry_index  = 2;
    int32 behavior     = 3; // ScheduleBehaviorType
}

message NpcPatrolData {
    int32 route_id     = 1;
    int32 node_id      = 2;
    int32 alert_level  = 3; // PatrolAlertLevel
    Vec3  look_at_pos  = 4;
    int32 direction    = 5; // 0=forward, 1=backward（客户端朝向插值用）
}

message NpcScenarioData {
    int32 point_id       = 1;
    int32 scenario_type  = 2;
    int32 phase          = 3; // ScenarioPhase
    float direction      = 4; // 朝向（弧度）
    int32 duration       = 5; // 停留时长（秒，客户端用于表现计时）
}
```

### 4.4 TownNpcData 扩展

```protobuf
message TownNpcData {
    // 现有字段 1-16 不变
    NpcScheduleData schedule_data = 17;
    NpcPatrolData   patrol_data   = 18;
    NpcScenarioData scenario_data = 19;
}
```

### 4.5 通知消息

```protobuf
message NpcScheduleChangeNtf {
    int64 npc_id        = 1;
    int32 prev_behavior = 2; // ScheduleBehaviorType
    int32 new_behavior  = 3; // ScheduleBehaviorType
    Vec3  target_pos    = 4;
    int32 change_reason = 5; // ScheduleChangeReason
}

message NpcPatrolNodeArriveNtf {
    int64 npc_id        = 1;
    int32 node_id       = 2;
    int32 behavior_type = 3; // 动画枚举 ID
    int32 duration_ms   = 4;
}

message NpcPatrolAlertChangeNtf {
    int64 npc_id      = 1;
    int32 alert_level = 2; // PatrolAlertLevel
    Vec3  look_at_pos = 3;
}

message NpcScenarioEnterNtf {
    int64 npc_id        = 1;
    int32 point_id      = 2;
    int32 scenario_type = 3;
    Vec3  position      = 4;
    float direction     = 5;
}

message NpcScenarioLeaveNtf {
    int64 npc_id   = 1;
    int32 point_id = 2;
}
```

### 4.6 NpcWeakStateCommand 废弃

`patrol_*` 字段 (6-12) 标记 `[deprecated = true]`，过渡期服务端双写，新客户端忽略。

### 4.7 消息注册

新增 5 个 Ntf 消息需注册到 scene_server 的消息分发表（`1.generate.py` 自动生成 scene 服务注册代码）。

## 5 客户端详细设计

### 5.1 FSM 状态注册

在 `TownNpcFsmComp` 的 `_stateTypes` 数组中追加 4 个状态（索引 = NpcState 枚举值 - 1）：

| 数组索引 | NpcState 枚举 | FSM State 类 |
|---------|--------------|-------------|
| 16 | Patrol(17) | TownNpcPatrolState |
| 17 | Guard(18) | TownNpcGuardState |
| 18 | Scenario(19) | TownNpcScenarioState |
| 19 | ScheduleIdle(20) | TownNpcScheduleIdleState |

### 5.2 FSM State 实现

**TownNpcPatrolState**：
- OnEnter: 根据 patrol_data.alert_level 设置移动速度和姿态
- OnUpdate: 移动插值（复用 TownNpcMoveComp）
- OnExit: 恢复默认姿态

**TownNpcGuardState**：
- OnEnter: 播放站岗动画 `AnimationComp.Play(TransitionKey.Guard)`
- OnUpdate: 无操作（固定位置）
- OnExit: 过渡到 Idle

**TownNpcScenarioState**：
- OnEnter: 读取 scenario_data，通过 ScenarioComp 启动交互序列
- OnUpdate: ScenarioComp 管理动画阶段（Enter→Loop→Leave）
- OnExit: ScenarioComp 清理

**TownNpcScheduleIdleState**：
- OnEnter: 播放 Idle 动画
- OnUpdate: 无操作（等待服务端切换）
- OnExit: 无

### 5.3 新增组件

**ScenarioComp**（async，需 CancellationToken）：
```csharp
public class ScenarioComp : Comp
{
    private CancellationTokenSource _cts;
    private int _currentPointId;
    private int _scenarioType;
    private ScenarioPhase _phase;

    public override void OnAdd(ICompOwner owner) { ... }
    public override void OnClear()
    {
        _cts?.Cancel();
        _cts?.Dispose();
    }

    // 进入场景点：移动对齐 → 播放进入动画 → 循环动画
    public async UniTaskVoid StartScenario(NpcScenarioEnterNtf ntf, CancellationToken ct) { ... }
    // 离开场景点：播放离开动画 → 通知 FSM
    public async UniTaskVoid LeaveScenario(CancellationToken ct) { ... }
}
```

**PatrolVisualComp**（无 async）：
```csharp
public class PatrolVisualComp : Comp
{
    private int _alertLevel;
    private Vector3 _lookAtTarget;

    public void SetAlertLevel(int level, Vector3 lookAtPos) { ... }
    public void OnNodeArrive(int behaviorType, int durationMs) { ... }
}
```

### 5.4 Ntf 消息处理

| 消息 | 处理逻辑 |
|------|---------|
| NpcScheduleChangeNtf | 根据 change_reason 选择过渡方式，EnterBuilding 触发渐隐→Despawn |
| NpcPatrolNodeArriveNtf | PatrolVisualComp.OnNodeArrive → 播放节点停留动画 |
| NpcPatrolAlertChangeNtf | PatrolVisualComp.SetAlertLevel → 切换姿态/LookAt |
| NpcScenarioEnterNtf | ScenarioComp.StartScenario → 三段动画序列 |
| NpcScenarioLeaveNtf | ScenarioComp.LeaveScenario → 离开动画 |

### 5.5 组件注册

两个新 Comp 在对应 Controller 的 `OnInit` 中 `AddComp`。

## 6 配置设计

### 6.1 JSON 配置（服务端）

| 配置 | 目录 | 文件命名 | 说明 |
|------|------|---------|------|
| 日程模板 | `bin/config/ai_schedule/` | `{templateId}_{name}.json` | 每文件一个模板 |
| 巡逻路线 | `bin/config/ai_patrol/` | `{routeId}_{name}.json` | 每文件一条路线 |

### 6.2 Excel 配置表（打表工具生成）

| 配置表 | Sheet 名 | 关键列 | 说明 |
|--------|---------|--------|------|
| 人口配额表 | PopAllocation | RegionId, TimeSlot, MaxAmbient, MaxSchedule, MaxPatrol, MaxScenario, GroupWeights | 时段×区域 |
| 区域定义表 | Region | RegionId, Name, CenterX/Y/Z, Radius | 场景区域 |
| 场景点表 | ScenarioPoint | PointId, Type, PosX/Y/Z, Direction, MaxUsers, TimeStart, TimeEnd, Duration, Probability, Radius, Flags | 场景点 |
| 场景类型表 | ScenarioType | TypeId, Name, EnterAnim, LoopAnim, LeaveAnim, DefaultDuration, DefaultProbability | 动画映射 |
| NPC 类型组表 | NpcGroup | GroupId, Name, ModelIds, BehaviorCategory, ScheduleTemplateId | 类型→模板 |

### 6.3 V2Brain Locomotion 决策配置

在 `bin/config/ai_decision_v2/locomotion.json`（和 `gta_locomotion.json`）中新增决策规则：

```json
{
  "rules": [
    {"condition": "schedule.templateId > 0 && schedule.currentPlan == 'schedule'", "plan": "schedule"},
    {"condition": "schedule.patrolRouteId > 0 && schedule.currentPlan == 'patrol'", "plan": "patrol"},
    {"condition": "schedule.scenarioPointId > 0 && schedule.currentPlan == 'scenario'", "plan": "scenario"},
    {"condition": "schedule.currentPlan == 'guard'", "plan": "guard"},
    {"condition": "true", "plan": "on_foot"}
  ]
}
```

Brain locomotion 规则仅在初始选择 plan 时使用，ScheduleHandler 运行中的子行为切换由 Handler 直接驱动（见 §3.3.1）。

**FieldAccessor 注册**（必须）：`decision/v2brain/expr/field_accessor.go` 的 `resolveSchedule` 方法中，必须注册 5 个新增字段的访问器，否则 Brain 条件表达式无法解析：

```go
// field_accessor.go resolveSchedule 新增
"templateId":     func(s *ScheduleState) interface{} { return s.ScheduleTemplateId },
"patrolRouteId":  func(s *ScheduleState) interface{} { return s.PatrolRouteId },
"patrolDirection":func(s *ScheduleState) interface{} { return s.PatrolDirection },
"scenarioPointId":func(s *ScheduleState) interface{} { return s.ScenarioPointId },
"alertLevel":     func(s *ScheduleState) interface{} { return s.AlertLevel },
```

## 7 事务性设计

### 7.1 场景点占用/释放的原子性

**问题**：NPC Despawn 或中断时必须释放已占用的场景点，否则泄漏。

**方案**：
- ScenarioPointManager.Occupy 返回 bool，失败不重试
- NPC Despawn 流程中，统一调用 `CleanupNpcResources(npcId)` 释放所有资源
- 在 NpcManager.RemoveNpc 中挂钩清理回调

**CleanupNpcResources 完整清理清单**：
1. `ScenarioPointManager.ReleaseByNpc(npcId)` — 释放场景点占用
2. `PatrolRouteManager.ReleaseAllByNpc(npcId)` — 释放路线分配 + 节点互斥（通过 npcToRoute 反向索引，无需 routeId 参数）
3. `ScheduleState` 清理 — 随 NpcState 回收自动清除（值类型，无泄漏风险）
4. `PopScheduleManager` 区域计数 — 由 Evaluate 每帧重算，无需主动清理

### 7.2 巡逻路线 NPC 计数一致性

**问题**：CurrentNpcCount 与实际分配 NPC 数可能不一致（异常退出、panic 恢复）。

**方案**：
- AssignedNpcs 使用 map[int64]bool 精确追踪，CurrentNpcCount = len(AssignedNpcs)
- 不单独维护 counter，避免计数漂移

### 7.3 日程中断恢复

**问题**：中断期间日程时间继续流逝，恢复时可能已跨条目。

**方案**：
- 恢复时重新调用 MatchEntry(当前游戏时间)，跳到当前有效条目；若无匹配条目则 fallback 到 Idle plan
- PauseAccum 累计中断时长，用于日志/统计，不影响日程匹配。设置上限 clamp（24h 游戏时间等价值），超限触发 Error 日志并强制恢复日程

### 7.4 并发控制

本系统无跨 goroutine 并发问题：
- 所有 Manager 和 Handler 在 scene_server 主循环单线程中执行
- NpcState 读写在同一帧内串行（Pipeline 维度顺序执行）
- 无需加锁
- **约束**：Manager 的所有 public 方法禁止在非主线程调用；热更新 Reload 如实现则必须在主线程执行

## 8 接口契约

### 8.1 协议 ↔ 服务器

| 契约 | 说明 |
|------|------|
| NpcState 枚举新增值不影响旧客户端 | 未知值 fallback 到 Idle（客户端已有兜底） |
| TownNpcData 子消息可选 | 无日程/巡逻/场景点时不携带，旧客户端自动忽略高字段号 |
| Ntf 消息单向推送 | 无需客户端确认，丢失可容忍（下次全量同步恢复） |
| patrol_* deprecated 双写 | 过渡期服务端同时写入旧字段，新客户端忽略 |

### 8.2 配置 ↔ 服务器

| 契约 | 说明 |
|------|------|
| JSON 配置启动时加载 | 缺失或格式错误 → Fatal 阻止启动 |
| Excel 配置表通过打表工具生成 | 二进制文件缺失 → Fatal |
| locationId 引用有效性 | 启动时校验，无效 → Error 日志 + 跳过该条目 |
| routeId node links 有效性 | 启动时校验，无效 → Fatal |

### 8.3 服务器 ↔ 客户端状态映射

| 服务端 NpcState | 客户端 FSM 索引 | 客户端 State 类 |
|----------------|----------------|----------------|
| Patrol(17) | 16 | TownNpcPatrolState |
| Guard(18) | 17 | TownNpcGuardState |
| Scenario(19) | 18 | TownNpcScenarioState |
| ScheduleIdle(20) | 19 | TownNpcScheduleIdleState |

## 9 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| Locomotion 维度 Handler 路由复杂度 | ScheduleHandler 需在运行时切换 plan，可能与 Brain 决策冲突 | ScheduleHandler 通过 ctx.SwitchPlan 直接切换（同帧生效），Brain 仅负责初始 plan 选择，运行中不干预 |
| PopSchedule Spawn/Despawn 帧峰值 | 时段切换时大量 NPC 变动 | 每 Tick 限 1 Spawn + 1 Despawn，渐变过渡 |
| 场景点搜索性能 | 大量场景点时暴力搜索慢 | SpatialGrid O(1) 分区查询，每格仅少量点 |
| 巡逻节点互斥死锁 | 多 NPC 同路线互相阻塞 | 节点占用仅在停留时生效，移动中不占用；超时 15s 强制释放 |
| 配置表数量多、首次创建工作量大 | 5 张 Excel 表 + 2 组 JSON | 先创建最小可用配置（1 个区域、1 个日程模板、1 条巡逻路线、几个场景点），验证流程后再扩充 |
| NpcState Snapshot 遗漏新字段 | 决策读到脏数据 | ScheduleState 是值类型 struct，整体 copy 自动包含新字段，无风险 |
| 循环 import（Manager ↔ Handler） | 编译失败 | Manager 在 schedule/patrol/scenario 包，Handler 在 execution/handlers 包，Handler 通过接口引用 Manager |

### 9.1 依赖注入避免循环 import

```
npc_mgr 包（初始化层）
    ├─ 创建 Manager 实例（schedule/patrol/scenario 包）
    ├─ 创建 Handler 实例（execution/handlers 包），注入 Manager
    └─ 注册 Handler 到 PlanExecutor

Handler 通过接口引用 Manager：
    type ScheduleQuerier interface { MatchEntry(templateId, gameHour int32) *ScheduleEntry }
    type PatrolQuerier interface { GetNextNode(...) (int32, int32); IsNodeOccupied(...) bool }
    type ScenarioFinder interface { FindNearest(...) *ScenarioPoint; Occupy(...) bool; Release(...) }
```

Manager 实现接口，Handler 持有接口引用，无包间循环依赖。
