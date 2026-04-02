# V2 NPC 日程配置体系设计

> 需求：参考 V1 日程配置，为 V2 NPC 补全独立的日程配置加载和初始化链路，与 V1 完全隔离。

## 1. V1 日程体系深度分析（参考基准）

### 1.1 整体架构

- **代码包**：`common/config/config_npc_schedule/`（node.go + schedule.go）
- **配置目录**：`bin/config/TonwNpcSchedule/`（24 个 NPC JSON 文件，每 NPC 一个）
- **NPC 绑定**：`CfgTownNpc.schedule` 字段 → 文件名（string，如 `"Austing_Schedule"`）
- **全局注册表**：`cfgScheduleMap map[string]*NpcSchedule`，启服时从 JSON 目录加载

### 1.2 数据结构

```
ScheduleFile                          ← JSON 根对象
└─ Items: []CfgNode                   ← 有序日程节点列表（顺序即时间顺序）
   ├─ Key: string                     ← 节点名称（中文，如"呆在家"、"去塔可店"）
   ├─ NodeType: int                   ← 行为类型（2/3/4）
   └─ ActionData: { "类型名": {...} } ← 多态 Action（JSON 嵌套一层按类型名分发）

NpcSchedule
└─ nodeList: []*CfgNode               ← 内存结构，从 ScheduleFile.Items 转换
```

### 1.3 三种 Action 类型逐字段解析

**Type=2 LocationBasedAction（定点活动）— 在开放场所可见地站着/坐着**

| 字段 | 类型 | 含义 | 示例 |
|------|------|------|------|
| Priority | int | 优先级（当前所有配置均为 0） | 0 |
| StartTime | int64 | 生效起始时间（游戏秒，0-86400） | 40800 (11:20) |
| EndTime | int64 | 生效结束时间 | 41400 (11:30) |
| Duration | float64 | 服务器超时时长（秒），实际含义是"在该点停留的时间" | 600.0 (10分钟) |
| Destination | {x,y,z} | 世界坐标目标位置 | {144.7, -3.8, -61.2} |
| FaceDirection | {x,y,z} | 朝向（欧拉角，Y 轴旋转） | {0, 90, 0} |
| FaceDestinationDir | bool | 是否朝向目标方向（覆盖 FaceDirection） | false |
| DestinationThreshold | float64 | 到达判定距离（米） | 0.0 |
| WarpIfSkipped | bool | 错过时段是否传送到目标点 | false |
| IsActionStarted | bool | 动作是否已启动（运行时标志位） | false |

**Type=3 StayInBuilding（进入建筑）— NPC 从地图消失**

| 字段 | 类型 | 含义 | 示例 |
|------|------|------|------|
| Priority | int | 优先级 | 0 |
| StartTime | int64 | 生效起始时间 | 85800 (23:50) |
| EndTime | int64 | 生效结束时间 | 27000 (7:30) ← 跨午夜 |
| Duration | float64 | 进入建筑动画时长（通常 10s） | 10.0 |
| ClinentExitTime | float64 | 客户端延迟隐藏NPC的时间（秒）（注意拼写 typo） | 8.0 |
| BuildingId | int | 建筑 ID | 12 |
| DoorId | int | 门 ID（进出口标识） | 12 |
| BuildingPosition | {x,y,z} | 建筑内坐标（门口位置） | {125.1, -3.8, -145.0} |

**Type=4 MoveToBPointFormAPoint（路点移动）— 从 A 点走到 B 点**

| 字段 | 类型 | 含义 | 示例 |
|------|------|------|------|
| Priority | int | 优先级 | 0 |
| StartTime | int64 | 生效起始时间 | 27000 (7:30) |
| EndTime | int64 | 生效结束时间 | 29700 (8:15) |
| Duration | float64 | 预计行走时间（秒），≈ EndTime - StartTime | 2700.0 (45分钟) |
| APointId | int | 起点导航路点 ID | 353 |
| BPointId | int | 终点导航路点 ID | 5 |
| APosition | {x,y,z} | 起点世界坐标 | {108.0, -3.7, -135.9} |
| ADirection | {x,y,z} | 起点朝向 | {0, 0, 0} |
| BPosition | {x,y,z} | 终点世界坐标 | {146.6, -3.8, -80.9} |
| BDirection | {x,y,z} | 终点朝向 | {0, 180, 0} |

### 1.4 时间模型核心规则

1. **单位**：游戏秒（0-86400，一天 = 24h × 3600s）
2. **节点时间连续无间隙**：每个节点的 EndTime = 下一个节点的 StartTime
3. **24小时循环**：最后一个节点的 EndTime = 第一个节点的 StartTime，形成闭环
4. **跨午夜**：当 `StartTime > EndTime` 时（如 85800→27000 即 23:50→7:30），匹配逻辑用 OR：`nowTime >= startTime || nowTime <= endTime`
5. **匹配策略**：顺序遍历 nodeList，**第一个**匹配时间段的节点胜出（非优先级排序）

### 1.5 NPC 日程模式分析（24个文件实际数据）

| 模式 | 代表NPC | 节点数 | 特征 |
|------|--------|--------|------|
| 全天宅家 | Benji | 1 | 单节点 StayInBuilding(1→86400) |
| 简单三段 | Blackman | 3 | 警察局→巡逻→站岗，含跨午夜 |
| 标准日程 | Austing | 10 | 家→社区→椅子→塔可店→街机店→家，移动+停留交替 |
| 复杂工作 | Beth | 14 | 家→公交→办公→停车→办公→服装店→仓库→家 |

**核心发现**：V1 日程本质是 **"移动到某地"和"在某地停留"的交替序列**，时间精度到分钟级（如 7:30-8:15 的 45 分钟移动段）。

### 1.6 V1 运行时链路

```
启服: LoadNpcScheduleJsonFile(path) → cfgScheduleMap[文件名] = NpcSchedule
      ↓
创建NPC: cfg.GetSchedule() → GetNpcSchedule(name) → NpcScheduleComp.cfg
      ↓ 每帧
运行时: NpcScheduleComp.GetNowSchedule(nowSeconds) → CfgNode
      ↓ 根据 Action 类型
npcUpdateSystem → 行为树 daily_schedule.json → 4个分支（Move/Stay/Location/会议）
```

### 1.7 V1 路网寻路链路（日程移动的底层依赖）

V1 日程的 `MoveToBPointFormAPoint` 并非直线移动，而是依赖 **路网(RoadNetwork)** 进行寻路：

```
日程 MoveToBPointFormAPoint {APointId=353, BPointId=5}
  ↓ npcUpdateSystem 提取 PointId 写入 Feature
  ↓ SyncFeatureToBlackboard
  ↓ MoveBehaviorNode.OnEnter() 读取 feature_start_point/feature_end_point
  ↓ queryRoadNetworkPath(353, 5)
  ↓ RoadNetworkMgr.MapInfo.FindPathToVec3List(353, 5)
  ↓ A* 算法在路网图中搜索最短路径
  ↓ 返回 []*Vec3 路点坐标序列
  ↓ NpcMoveComp.SetPointList(路点序列)
  ↓ NPC 沿路点逐个行走（EPathFindType_RoadNetWork）
```

**路网系统概要**：
- 配置来源：`bin/config/Waypoints/*.json`（PointCfg + EdgeCfg）
- 核心 API：`MapInfo.FindPathToVec3List(startID, endID)` → `[]*Vec3`
- 辅助 API：`MapInfo.FindNearestPointID(pos)` → 最近路点 ID
- 场景资源：`MapRoadNetworkMgr`（`ResourceType_RoadNetworkMgr`）

**关键结论**：V1 的 `APointId/BPointId` 不只是标识符，而是**路网寻路的必要入参**。`BPosition` 只是终点坐标记录，实际移动路径由路网图 A* 算法计算。

## 2. 现状问题

V2 已有框架（`DayScheduleManager` + `ScheduleHandler`），但存在：

1. **V2 `ScheduleEntry` 缺少关键字段** — 缺少 `TargetPos`（目标位置）和路点 ID（寻路入参）
2. **`DayScheduleManager.MatchEntry` 返回 `*ScheduleEntry`** — 但 Handler 接口需要 `*ScheduleEntryResult`（含 TargetPos）
3. **整个 V2 日程链通过 `V1ScheduleAdapter` 桥接 V1 配置** — 违反隔离原则
4. **无独立的 V2 日程 JSON 配置文件** — 配置数据全部来自 V1
5. **V2 移动无路网寻路** — `ScheduleHandler.OnTick` 仅调用 `SetMoveTarget(targetPos)` 设置单点目标，不经过路网 `FindPathToVec3List`，NPC 只能直线移动
6. **时间精度差异** — V1 秒级(0-86400) vs V2 小时级(0-23)，V1 分钟级时段在小时级下会合并

## 3. 设计目标

1. V2 拥有独立的日程 JSON 配置文件（V2 前缀目录）
2. V2 拥有独立的配置结构和加载代码（V2 前缀命名）
3. V2 NPC 创建时直接使用 V2 templateId，不经过 V1
4. **V2 日程移动优先使用路网路点寻路**（参考 V1 的 PointId → RoadNetwork 链路）
5. V1 系统完全不受影响

## 4. 架构设计

### 配置隔离矩阵

| 维度 | V1 | V2 |
|------|----|----|
| JSON 目录 | `TonwNpcSchedule/` | `V2TownNpcSchedule/` |
| 时间单位 | 秒（0-86400） | 秒（0-86400），与 V1 一致 |
| 配置结构 | `CfgNode` + Action 多态 | `ScheduleTemplate` + `ScheduleEntry`（扁平结构） |
| 寻路数据 | `APointId/BPointId` | `startPointId/endPointId`（同一套路网） |
| 加载函数 | `LoadNpcScheduleJsonFile()` | `LoadScheduleTemplates(dir)` |
| NPC 绑定 | `cfg.GetSchedule()` → 文件名 | `cfg.GetScheduleV2()` → templateId |
| 移动驱动 | 行为树 → Feature → RoadNetwork | ScheduleHandler → RoadNetwork |

## 5. 详细设计

### 5.1 ScheduleEntry 扩展（新增路点 + 坐标 + V1 缺失字段）

```go
type ScheduleEntry struct {
    StartTime     int64    `json:"startTime"`     // 游戏秒（0-86400），与 V1 一致
    EndTime       int64    `json:"endTime"`       // 游戏秒，支持跨日
    BehaviorType  int32    `json:"behaviorType"`  // 0-7 枚举
    Priority      int32    `json:"priority"`
    Probability   float32  `json:"probability"`
    TargetPos     Vec3Json `json:"targetPos"`     // 目标坐标
    FaceDirection Vec3Json `json:"faceDirection"` // 到达后朝向（欧拉角）
    StartPointId  int32    `json:"startPointId"`  // 路网起点 ID（MoveTo 用）
    EndPointId    int32    `json:"endPointId"`    // 路网终点 ID（MoveTo 用）
    BuildingId    int32    `json:"buildingId"`    // 建筑 ID（EnterBuilding 用）
    DoorId        int32    `json:"doorId"`        // 门 ID（EnterBuilding 用）
    Duration      float64  `json:"duration"`      // 停留/动画时长（秒）
}
```

**时间改秒级的影响范围**（原代码用小时 int32，全部改 int64 秒）：
- `schedule_config.go` — StartTime/EndTime 类型 int32→int64
- `day_schedule_manager.go` — MatchEntry 参数 gameHour→gameSecond，matchTimeRange 同步改
- `schedule_handlers.go:105` — `mtime.NowTimeWithOffset().Hour()` 改为秒级获取
- `schedule_handlers.go:323` — ScenarioHandler.OnTick 同理
- `handlers.ScheduleQuerier` 接口签名 — gameHour→gameSecond
- `handlers.ScenarioFinder` 接口签名 — gameHour→gameSecond

### 5.2 ScheduleEntryResult 扩展

```go
type ScheduleEntryResult struct {
    BehaviorType  int32
    TargetPos     transform.Vec3
    FaceDirection transform.Vec3 // 新增
    StartPointId  int32          // 新增
    EndPointId    int32          // 新增
    BuildingId    int32          // 新增
    DoorId        int32          // 新增
    Duration      float64        // 新增
    Priority      int32
    Probability   float32
}
```

### 5.3 ScheduleHandler 集成路网寻路

ScheduleHandler 新增 `RoadNetQuerier` 接口依赖：

```go
type RoadNetQuerier interface {
    FindPathToVec3List(startID, endID int) ([]*transform.Vec3, error)
    FindNearestPointID(pos *transform.Vec3) (int, int64, *transform.Vec3)
}
```

`OnTick` BehaviorType=1(MoveTo) 分支改造：
1. 从 entry 读取 `StartPointId/EndPointId`
2. 调用 `RoadNetQuerier.FindPathToVec3List` 获取路点序列
3. 通过 `PlanContext.Scene` 扩展接口直接操作 `NpcMoveComp.SetPointList`（与 V1 一致）
4. fallback：若 PointId=0 或路网查询失败，退化为 `SetMoveTarget` 直线移动

路点序列传递方案：扩展 `SceneAccessor` 接口新增 `SetEntityPathPoints(entityID, points)` 方法，底层操作 `NpcMoveComp`，避免 Handler 直接依赖 ECS 组件。

### 5.4 V2 JSON 配置示例

文件：`bin/config/V2TownNpcSchedule/1003_Blackman.json`

```json
{
  "templateId": 1003, "name": "Blackman",
  "entries": [
    {"startTime":14460,"endTime":72060,"behaviorType":6,
     "targetPos":{"x":-7.63,"y":0.19,"z":-37.93},"buildingId":0},
    {"startTime":72060,"endTime":75660,"behaviorType":1,
     "targetPos":{"x":33.99,"y":0.14,"z":-54.50},
     "startPointId":616,"endPointId":38},
    {"startTime":75660,"endTime":14460,"behaviorType":2,
     "targetPos":{"x":33.99,"y":0.14,"z":-54.50}}
  ]
}
```

### 5.5 初始化接线改造

scene_impl.go 替换 V1ScheduleAdapter → V2 独立路径：
- 创建 `DayScheduleManager("V2TownNpcSchedule")`
- 创建 `V2ScheduleAdapter(mgr)`
- 调用 `InitLocomotionManagers(adapter, nil, nil)`

### 5.6 NPC 创建绑定

scene_npc_mgr.go：直接从 `cfg.GetScheduleV2()` 读 templateId 写入 `npcState.Schedule.ScheduleTemplateId`，移除 V1ScheduleAdapter 依赖。

## 6. 实际文件变更清单

> 以下为最终实施结果（P1GoServer 下路径省略 `servers/scene_server/internal/`）

### 代码修改（14 个）

| 文件 | 说明 |
|------|------|
| `common/ai/schedule/schedule_config.go` | ScheduleEntry 扩展（int64 秒级 + TargetPos/FaceDirection/PointId/BuildingId/DoorId/Duration） |
| `common/ai/schedule/day_schedule_manager.go` | MatchEntry 改秒级 + FindTemplateIdByName |
| `common/ai/execution/plan_handler.go` | SceneAccessor 新增 SetEntityRoadNetPath |
| `common/ai/execution/handlers/schedule_handlers.go` | RoadNetQuerier 接口 + 路网寻路集成 + 接口签名改秒级 |
| `common/ai/execution/handlers/schedule_handlers_test.go` | mock 签名同步 + 3 个路网测试 |
| `common/ai/execution/handlers/handlers_test.go` | mock 新增 SetEntityRoadNetPath stub |
| `common/ai/scenario/scenario_point_manager.go` | FindNearest 改秒级 |
| `common/ai/scenario/spatial_grid_test.go` | 测试参数同步 |
| `ecs/system/decision/scene_accessor_adapter.go` | 实现 SetEntityRoadNetPath（操作 NpcMoveComp） |
| `ecs/res/npc_mgr/locomotion_managers.go` | InitLocomotionManagers 新增 roadNetQuerier 参数 |
| `ecs/res/npc_mgr/v2_pipeline_defaults.go` | NewScheduleHandler 传入 roadNetQuerier |
| `ecs/res/npc_mgr/scene_npc_mgr.go` | 用 cfg.GetScheduleV2() 直接读 templateId，移除 V1 adapter |
| `ecs/res/npc_mgr/scenario_adapter.go` | 签名 gameHour→gameSecond |
| `ecs/scene/scene_impl.go` | V2 独立初始化 + 路网注入，移除 V1ScheduleAdapter 和 confignpcschedule import |

### 新建文件（28 个）

| 文件 | 说明 |
|------|------|
| `bin/config/V2TownNpcSchedule/*.json` (24 个) | V2 日程模板，从 V1 转换 |
| `ecs/res/npc_mgr/v2_schedule_adapter.go` | DayScheduleManager → ScheduleQuerier 适配器 |
| `ecs/res/npc_mgr/v2_schedule_adapter_test.go` | 5 个测试用例 |
| `common/ai/schedule/day_schedule_manager_test.go` | 6 个测试用例 |

### 删除文件（1 个）

| 文件 | 说明 |
|------|------|
| `ecs/res/npc_mgr/v1_schedule_adapter.go` | V1 桥接移除 |

### 自动生成（2 个）

| 文件 | 说明 |
|------|------|
| `common/config/cfg_townnpc.go` | 打表生成，含 GetScheduleV2() int32 |
| `bin/config/cfg_townnpc.bytes` | 打表生成，含 scheduleV2 数据 |

### 配置表（1 个）

| 文件 | 说明 |
|------|------|
| `freelifeclient/RawTables/TownNpc/npc.xlsx` | M 列新增 ScheduleV2(int, S)，24 行填入 templateId |

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 路网查询失败 | fallback 到 SetMoveTarget 直线移动 |
| V2TownNpcSchedule 目录不存在 | 容错返回空 map |
| DayScheduleManager 加载失败 | adapter 内 nil guard 兜底 |
| ScheduleHandler 新增接口依赖 | 允许 nil，nil 时跳过路网寻路 |
| SetEntityRoadNetPath 返回 false | 当前未检查返回值，后续可补 fallback |
