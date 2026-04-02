# 大世界 V2 NPC 系统

## 做什么

基于小镇 V2 NPC 的正交维度 Pipeline 架构，在大世界场景实现一套完整的 NPC 系统。大世界 NPC 与小镇 NPC 共享核心框架（Pipeline 引擎、V2Brain、PlanHandler），但在配置、扩展处理器、生成策略上完全独立。

## 涉及端

both

## 触发方式

- 服务器自动触发：玩家进入大世界场景后，NPC 通过 AOI 动态生成/回收
- GM 调试命令：`/ke* gm bw_npc spawn {cfgId}` 手动生成指定 NPC

## 预期行为

正常流程：
1. 玩家进入大世界，服务器根据 AOI 范围动态创建 NPC 实体，通过现有 NetEntity 协议同步到客户端
2. NPC 由 V2 Pipeline 驱动四个正交维度（engagement/expression/locomotion/navigation）独立决策
3. NPC 按日程配置在路网上移动、执行场景点行为（如驻足观景、坐下休息）
4. 客户端收到状态同步后播放对应动画和表现

异常/边界情况：
- NPC 数量达到上限时：不再生成新 NPC，等有 NPC 被回收后再补充
- 玩家快速移动导致大量 NPC 同时进入 AOI：分帧创建，每帧最多创建 N 个
- NPC 寻路失败（路网不可达）：原地 Idle，日志告警，不崩溃

## 不做什么

- 不做 NPC 战斗/对话交互（engagement 维度只保留基础警戒，不实现战斗状态机）
- 不做 NPC 对玩家的主动社交行为
- 不修改 Pipeline 引擎本身（orthogonal_pipeline.go 零改动）
- 不修改小镇已有的 V2 NPC 配置和处理器

## 参考

- 服务端 Pipeline：`P1GoServer/.../ai/pipeline/orthogonal_pipeline.go`
- 小镇扩展处理器：`P1GoServer/.../npc_mgr/town_ext_handler.go`（大世界需写一个平级的 `bigworld_ext_handler.go`）
- V2Brain 决策：`P1GoServer/.../ai/decision/v2brain/brain.go`（复用，只新增大世界配置 JSON）
- 客户端小镇 NPC：`freelifeclient/.../TownNpcController.cs`（大世界需写平级的 `BigWorldNpcController.cs`）
- AOI 动态生成：参考现有大世界动物系统的生成/回收模式

## 优先级

| 优先级 | 内容 | 说明 |
|--------|------|------|
| P0 | Pipeline 注册 + BigWorld ExtHandler + AOI 生成回收 | 能在大世界看到 NPC 出现和消失 |
| P0 | locomotion + navigation 维度 | NPC 能沿路网移动 |
| P0 | 客户端 BigWorldNpcController + 基础动画 | Idle/Walk/Run 表现正常 |
| P1 | expression 维度 + 日程系统 | NPC 有情绪表达和作息 |
| P1 | engagement 维度基础警戒 | NPC 对玩家接近有反应 |

## 约束

- NPC 生成不能造成帧率突刺，必须分帧
- 大世界 Pipeline 配置（JSON）与小镇完全隔离，修改大世界不影响小镇
- 大世界 ExtHandler 不 import 小镇的任何扩展处理器代码
- 客户端 BigWorldNpcController 与 TownNpcController 平级独立，不继承

---

## 行人路网

### 现有基础与数据验证

**路网类型体系**：`road_point.json` 通过 `type` 字段区分两种路网：

| 类型 | 用途 | 配置常量 |
|------|------|----------|
| `footwalk` | 行人步行路网 | `RoadNetworkTypeFootwalk` |
| `driveway` | 车辆行驶路网 | `RoadNetworkTypeDriveway` |

数据链路：`RawTables/Json/Server/{mapName}/road_point.json` → 打表工具 → `P1GoServer/bin/config/{mapName}/road_point.json` → `MapRoadNetworkMgr` 加载。场景配置通过 `scene.xlsx` 的 `pedWaypointFile` 字段指定行人路网文件名。

**⚠️ 大世界行人路网现状（验证结论）**：

| 项目 | 状态 | 说明 |
|------|------|------|
| `scene.xlsx` Miami 场景 `pedWaypointFile` | **null（未配置）** | 大世界场景未指定行人路网文件 |
| `miaorio_test/road_point.json` footwalk 数据 | **9 个测试点（无效）** | 坐标范围 0~1000，大世界地图范围 -4096~4096，完全不匹配 |
| 车辆路网 `road_traffic_miami.json` | ✅ 50K 路点 | 已被交通系统使用 |
| NPC Spawner 生成点来源 | **使用全部路网点（含车道）** | `GetAllPointPositions()` 不区分 footwalk/driveway |
| 小镇行人路网 `town_ped_road.json` | ✅ 真实数据 | 仅适用于小镇场景，不可用于大世界 |

**结论：大世界行人路网数据完全缺失，需从零构建。**

### 行人路网构建方案

构建顺序：① 生成路网数据 → ② 配置场景加载 → ③ Spawner 切换到 footwalk

**步骤 1：生成行人路网数据**

参考小镇 `town_ped_road.json` 的格式，为大世界创建 `miami_ped_road.json`。数据来源有两种方案：

| 方案 | 说明 | 优劣 |
|------|------|------|
| A. 从车辆路网派生 | 基于 `road_traffic_miami.json` 的 50K 路点，偏移到路侧人行道位置 | 快速，但依赖车道有人行道 |
| B. Houdini/美术手工标注 | 在大世界地图上独立标注人行道、步道、广场等 | 质量高，但工期长 |

**推荐方案 A 先行**：编写脚本从车辆路网提取人行道路点（沿车道法线偏移 3-5m），快速覆盖主干道两侧，后续美术补充公园/广场等非车道区域。

**步骤 2：配置场景加载**

在 `scene.xlsx` 中 Miami 场景（id=16）补填：
- `pedWaypointFile` = `"miami_ped_road"`

**步骤 3：Spawner 切换**

修改 `BigWorldNpcSpawner.initSpawnPoints()`，从 `GetAllPointPositions()` 改为只取 footwalk 类型路点，避免 NPC 生成在机动车道上。

### 路网分区（WalkZone）

`road_point.json` 的 `lists[]` 支持多条子路网，每条子路网按区域命名即为一个 WalkZone：

```
road_point.json
├── name: "miami"
└── lists[]
    ├── {id: 1, name: "downtown_walk", type: "footwalk", points: [...], edges: [...]}
    ├── {id: 2, name: "park_walk",     type: "footwalk", points: [...], edges: [...]}
    └── ...
```

分区示例（具体由美术根据地图实际区域划分）：

| 分区名 | 覆盖区域 | 预估路点数 | 说明 |
|--------|----------|-----------|------|
| downtown_walk | 市中心人行道 | 3000-5000 | 密度最高 |
| park_walk | 公园/绿地步道 | 1000-2000 | 闲逛、跑步 |
| suburb_walk | 郊区/住宅区 | 1000-2000 | 密度较低 |
| beach_walk | 海滩/滨水步道 | 500-1000 | 休闲 |
| commercial_walk | 商业区外围 | 1000-2000 | 购物、等车 |

分区目的：① 美术按区域独立迭代 ② 巡逻路线限定在特定分区内 ③ 均匀分布按分区计算配额。

### 需要新增的路网接口

现有 `Map.FindNearestPointID` 遍历所有子路网（不区分 type），NPC 行人寻路需按类型过滤。新增接口（保持原有无类型方法向后兼容）：

| 新增方法 | 位置 | 说明 |
|---------|------|------|
| `FindNearestPointIDByType(pos, type)` | `Map` | 只在指定 type 的子路网中查找最近路点 |
| `FindPathByType(startID, endID, type)` | `Map` | 只在指定 type 的子路网中执行 A* 寻路 |
| `roadsByType map[RoadNetworkType][]*RoadNetwork` | `Map` | 按类型索引（Init 时构建） |

### 与车辆路网的关系

- footwalk 和 driveway 在 `MapRoadNetworkMgr` 中统一加载，通过 `type` 字段区分
- NPC 行人寻路调用 `FindNearestPointIDByType(pos, "footwalk")`，不会误入车道
- 两套路网空间可能交叉（人行横道），但拓扑完全独立

---

## NPC 巡逻路线配置

### 复用现有 patrol 包

服务端已有完整的巡逻路线系统（`ai/patrol/` 包），大世界 NPC 直接复用，不另建新系统：

| 已有能力 | 代码位置 | 说明 |
|---------|---------|------|
| PatrolRoute 路线定义 | `patrol_config.go` | routeId/nodes/links/desiredNpcCount |
| PatrolNode 节点 | `patrol_config.go` | position/heading/duration/behaviorType(int32)/links |
| PatrolRouteManager | `patrol_route_manager.go` | AssignNpc/ReleaseNpc/GetNextNode/节点互斥/负载上限 |
| PatrolHandler 日程集成 | `schedule_handlers.go` | OnEnter→AssignNpc, OnTick→移动+停留+推进, OnExit→释放 |
| 路网桥接 | `schedule_handlers.go` | 通过 NpcState.SetMoveTarget → NpcMoveComp → 路网 A* 寻路 |

**⚠️ 大世界巡逻系统现状（验证结论）**：

| 项目 | 状态 | 说明 |
|------|------|------|
| patrol 代码框架 | ✅ 完整 | LoadPatrolRoutes/PatrolRouteManager/PatrolHandler 全部就绪 |
| 巡逻路线 JSON 配置 | **❌ 不存在** | `bin/config/ai_patrol/bigworld/` 目录无文件 |
| 场景初始化接入 | **❌ 未接入** | `scene_impl.go` 中 `InitLocomotionManagers(nil, nil, nil, roadNetQ)` patrolQuerier 传 nil |
| NPC 默认行为 | ⚠️ 随机漫游 | 使用 `BigWorldDefaultPatrolHandler`，不走巡逻路线 |
| NPC 配置 PatrolRouteId | ⚠️ 字段存在但值为 0 | 所有大世界 NPC 未分配巡逻路线 |

**结论：巡逻管道已通但未接线，需要：① 创建路线 JSON ② 场景初始化接入 PatrolRouteManager ③ NPC 分配路线。**

### 巡逻路线接入步骤

**步骤 1：场景初始化接入**

修改 `scene_impl.go` 大世界初始化，加载巡逻路线并注入：
```
patrolRoutes := patrol.LoadPatrolRoutes("bin/config/ai_patrol/bigworld/")
patrolMgr := patrol.NewPatrolRouteManager(patrolRoutes)
InitLocomotionManagers(schedQ, patrolMgr, scenarioF, roadNetQ)  // patrolQuerier 不再传 nil
```

**步骤 2：创建巡逻路线 JSON**（见下方"巡逻路线数据准备"）

**步骤 3：NPC 行为切换**

将 `BigWorldDefaultPatrolHandler`（随机漫游）改为日程驱动的 `PatrolHandler`，或在默认行为中优先尝试分配巡逻路线。

### 巡逻路线 JSON 配置（复用已有格式）

每条巡逻路线一个 JSON 文件，存放在 `bin/config/ai_patrol/bigworld/`：

```json
{
  "routeId": 1,
  "name": "downtown_loop_A",
  "routeType": 0,
  "desiredNpcCount": 3,
  "walkZone": "downtown_walk",
  "nodes": [
    {"nodeId": 1, "position": {"x": 100, "y": 0, "z": 200}, "heading": 90, "duration": 15000, "behaviorType": 1, "links": [2]},
    {"nodeId": 2, "position": {"x": 120, "y": 0, "z": 220}, "heading": 0,  "duration": 0,     "behaviorType": 0, "links": [3]},
    {"nodeId": 3, "position": {"x": 140, "y": 0, "z": 200}, "heading": 270,"duration": 30000, "behaviorType": 2, "links": [1]}
  ]
}
```

字段说明（复用 PatrolRoute/PatrolNode 已有字段）：

| 字段 | 类型 | 说明 |
|------|------|------|
| routeId | int32 | 全局唯一路线 ID |
| name | string | 调试名称 |
| routeType | int32 | 0=Permanent 永久循环 / 1=Scripted 脚本驱动 |
| desiredNpcCount | int32 | 该路线期望的 NPC 上限（负载均衡依据） |
| **walkZone** | string | **新增**：所属路网分区名，用于均匀分布配额计算 |
| nodes[].nodeId | int32 | 路线内唯一节点 ID |
| nodes[].position | Vec3 | 节点世界坐标 |
| nodes[].heading | float32 | 到达后朝向（度） |
| nodes[].duration | int32 | 停留时长（ms），0=不停留 |
| nodes[].behaviorType | int32 | 到达行为枚举（与 NpcPatrolNodeArriveNtf 一致） |
| nodes[].links | int32[] | 后继节点 ID（环形路线首尾相连；空=开放路线端点，自动折返） |

**仅新增 `walkZone` 字段**，其余完全复用已有格式。实现时需在 `PatrolRoute` 结构体和 `patrolRouteJSON` 反序列化结构中同步新增 `WalkZone string` 字段及 `json:"walkZone"` tag。

### 节点间移动与路网的关系

巡逻节点（PatrolNode）定义的是 NPC 的逻辑途经点（稀疏），节点间的实际行走路径由行人路网 A* 自动规划：

```
PatrolHandler.OnTick
  → 目标 = 下一个 PatrolNode.Position
  → NpcState.SetMoveTarget(目标)
  → syncNpcMovement 桥接到 NpcMoveComp
  → MoveEntityViaRoadNet（footwalk 路网 A*）
  → 路网返回密集路点序列 → NPC 逐点移动
```

这意味着：
- 巡逻路线配置只需 10-20 个关键节点，不需要密集铺点
- 实际路径沿行人路网拓扑行走，表现自然
- 路网更新后巡逻路线自动适配新拓扑
- 路网不可达时降级到 NavMesh → 直线（现有三级降级）

**约束**：巡逻路线的所有节点必须位于同一 footwalk 子路网的连通区域内，不支持跨子路网寻路（现有 `Map.FindPath` 要求起终点在同一 RoadNetwork 中）。

### 巡逻路线数据准备

行人路网构建完成后，需要为大世界 NPC 创建实际的巡逻路线 JSON 文件。

**生成策略**：基于行人路网自动生成巡逻路线（而非纯手工配置）：

1. **从路网提取环形路线**：在 footwalk 路网中，用 DFS/BFS 找出若干不重叠的环路（cycle），每个环路作为一条巡逻路线
2. **路线长度控制**：每条路线 8-15 个节点，步行一圈约 3-8 分钟
3. **覆盖率保证**：路线集合应覆盖路网总路点的 80%+，确保 NPC 不扎堆在少数区域
4. **停留点标注**：路线中靠近场景点（bench/观景台/商铺门口）的节点设置 duration > 0 和对应 behaviorType

**输出目录**：`P1GoServer/bin/config/ai_patrol/bigworld/`，每条路线一个 JSON 文件（如 `route_001.json` ~ `route_020.json`）。

**路线数量预估**：大世界 NPC 预算 50 个，每条路线 desiredNpcCount=2-3，需约 **15-25 条路线** 覆盖各 WalkZone。

### NPC 配置表扩展

在 NPC 配置表中新增字段关联巡逻路线：

| 字段 | 类型 | 说明 |
|------|------|------|
| patrolRouteIds | int32[] | 候选巡逻路线 ID 列表（生成时选一条） |
| patrolSpeedScale | float | 步行速度缩放因子（基于 npc.xlsx 的 goSpeed，默认 1.0，老人 0.7，跑步者 1.8） |

速度 = `goSpeed × patrolSpeedScale`，不另设 baseSpeed，避免与现有 NpcMoveComp.RunSpeed 冲突。

### 与日程系统的集成

巡逻作为 V2 日程的一种行为类型，通过已有的 PatrolHandler 驱动：

```json
// V2_BigWorld_npc_xxx.json 日程模板
{
  "entries": [
    {
      "startTime": 28800,
      "endTime": 43200,
      "behaviorType": 10,
      "patrolRouteId": 0,
      "priority": 1
    },
    {
      "startTime": 43200,
      "endTime": 46800,
      "behaviorType": 3,
      "buildingId": 5,
      "duration": 3600
    }
  ]
}
```

- `behaviorType: 10` = PatrolRoute 巡逻行为
- `patrolRouteId: 0` = 从 NPC 配置的 patrolRouteIds 候选列表中自动选择（负载最低的路线）
- 日程时间结束 → PatrolHandler.OnExit → ReleaseAllByNpc 释放路线和节点占用

---

## NPC 均匀分布策略

### 核心思路

NPC 生成由 AOI 驱动，均匀分布策略只在 AOI 覆盖范围内生效——统计玩家 AOI 覆盖了哪些 WalkZone，仅对这些分区按比例分配 NPC 预算，未被覆盖的分区配额为 0。

### 分区配额配置

在巡逻路线 JSON 的同级目录新增 `npc_zone_quota.json`：

```json
{
  "totalNpcBudget": 50,
  "recycleHysteresis": 2,
  "zones": [
    {"walkZone": "downtown_walk", "densityWeight": 0.35, "maxNpc": 20},
    {"walkZone": "park_walk",     "densityWeight": 0.20, "maxNpc": 12},
    {"walkZone": "suburb_walk",   "densityWeight": 0.15, "maxNpc": 8},
    {"walkZone": "beach_walk",    "densityWeight": 0.15, "maxNpc": 8},
    {"walkZone": "commercial_walk","densityWeight": 0.15, "maxNpc": 8}
  ]
}
```

- `densityWeight`：分区密度权重（相对值，运行时归一化到 AOI 覆盖的分区集合）
- `maxNpc`：分区硬上限
- `recycleHysteresis`：回收滞后余量（防止频繁生成/回收抖动）

### AOI 驱动的动态配额分配

```
每 N 秒（如 5s）执行一次配额计算：
1. 收集所有玩家 AOI 覆盖的 WalkZone 集合 coveredZones（判定方式：取 WalkZone 的 AABB 包围盒与 AOI 做相交测试）
2. 对 coveredZones 中的分区，按 densityWeight 归一化：
   zoneQuota[z] = totalNpcBudget × (z.densityWeight / sum(coveredZones.densityWeight))
   zoneQuota[z] = min(zoneQuota[z], z.maxNpc)
3. 各分区当前 NPC 数 < zoneQuota → 触发生成
4. 各分区当前 NPC 数 > zoneQuota + recycleHysteresis（默认 2，可在配置中调整） → 标记可回收（等 NPC 离开 AOI 时优先回收）
```

关键：未被任何玩家 AOI 覆盖的分区配额为 0，不浪费预算。

### 路线负载均衡

复用已有 `PatrolRouteManager.AssignNpc` 的负载机制：

1. **desiredNpcCount 上限**：每条路线有期望 NPC 上限，满员不再分配
2. **最低负载优先**：NPC 生成时，在候选 patrolRouteIds 中选择 `AssignedNpcs` 数量最少且未满员的路线
3. **起点自动错开**：`AssignNpc` 通过 `FindNearestNode(npcPos)` 确定起始节点。不同 NPC 从路线的不同位置生成，天然分散

### 生成位置策略

NPC 不在固定 `birthPos` 生成，而是在巡逻路线节点上生成：

1. 配额计算确定某分区需补充 NPC
2. 选择该分区内负载最低的巡逻路线
3. `AssignNpc` 返回路线上离当前生成位置最近的节点作为起点
4. NPC 在该节点坐标处创建，立即进入巡逻状态沿路线前进

### 视觉效果

- 市中心人多、郊区人少（密度权重控制，符合直觉）
- 同一条路线上 NPC 间距均匀（节点互斥 + 起点错开）
- NPC 有明确行走方向和目的地（沿巡逻路线循环）
- 不同 NPC 走不同路线（负载均衡分配），视觉多样性好
- 玩家移动到新区域时，NPC 自然出现在路网上（AOI 驱动生成）

---

## 小地图 NPC 显示

### 需求

大世界小地图新增 NPC 追踪图例按钮，点击后在小地图上显示/隐藏 NPC 位置标记。**默认隐藏**（大世界 NPC 数量多，全显示会导致小地图杂乱）。

### 小镇参考实现

小镇已有完整的 NPC 小地图追踪功能，核心架构：

| 组件 | 文件 | 职责 |
|------|------|------|
| MapPanel | `UI/Pages/Panels/MapPanel.cs` | 主面板，管理图例列表和 Toggle 按钮交互 |
| MapLegendControl | `UI/Managers/Map/TagInfo/MapLegendControl.cs` | 图例控制核心，创建/更新/删除图例数据 |
| MapTownNpcLegend | `UI/Managers/Map/TagInfo/MapLegendBase.cs` | 小镇 NPC 图例数据类 |
| LegendListWidget | `UI/Pages/Widgets/LegendListWidget.cs` | 图例列表条目 UI 组件 |
| CfgLegendType | `Config/Gen/CfgLegendType.cs` | 配置表生成代码（icon.xlsx LegendType_c） |

小镇 NPC 追踪的 Toggle 流程：
1. 用户点击图例列表中 ID=125 的按钮
2. `MapPanel.SelectNewType()` 识别为 Toggle 类型，调用 `MapLegendControl.ToggleShowAllTownNpc(bool)`
3. 开启时：遍历所有小镇 NPC，为无图例的 NPC 添加头像图标（`MapTownNpcLegend`）
4. 关闭时：移除追踪模式的图例，保留有订单/潜在客户等条件图例
5. 通过 `IsTrackingMode` 标记区分条件图例和追踪图例

### 大世界实现方案

#### 1. 配置表新增

在 `icon.xlsx` 的 `LegendType_c` 表新增一条：

| id | name | order | typeIcon | showInDungeon |
|----|------|-------|----------|---------------|
| 127 | 大世界NPC | 50 | legend_bw_npc | 0 |

> ID 需确认不与现有条目冲突，127 为示例值。

同时在 `MapIcon` 表新增大世界 NPC 的图标配置：

| 字段 | 值 | 说明 |
|------|-----|------|
| legendType | 127 | 关联到新增的 LegendType |
| iconType | 通用 NPC 图标 | 大世界 NPC 无个人头像，统一使用人形图标 |
| iconColor | 区分颜色 | 与小镇 NPC 图标区分（如浅蓝色） |
| edgeDisplay | 0 | 不显示边缘指示器（NPC 数量多，边缘会很杂） |

#### 2. 图例数据类

新增 `MapBigWorldNpcLegend`（平级于 `MapTownNpcLegend`），区别：

| 对比项 | 小镇 MapTownNpcLegend | 大世界 MapBigWorldNpcLegend |
|--------|----------------------|---------------------------|
| 图标来源 | NPC 个人头像（NpcContactMapGroupMap） | 统一人形图标（无个人头像） |
| 条件图例 | 有订单/潜在客户自动显示 | 无条件图例（全靠 Toggle） |
| 默认状态 | 隐藏 | 隐藏 |
| 数量级 | 几十个 | 可能上百个（AOI 内） |

#### 3. MapLegendControl 扩展

在 `MapLegendControl` 中新增：

```
// 新增字段
BigWorldNpcTrackingLegendTypeId = 127  // 大世界 NPC 追踪图例类型 ID
ShowAllBigWorldNpc bool                // 当前是否显示大世界 NPC

// 新增方法
ToggleShowAllBigWorldNpc(bool show)
  开启：遍历 AOI 内所有大世界 NPC → 添加 MapBigWorldNpcLegend
  关闭：移除所有大世界 NPC 图例
  触发 EventId.UpdateLegendsInfo 刷新 UI

OnBigWorldNpcSpawned(netId)           // 监听大世界 NPC 生成事件
  若 ShowAllBigWorldNpc → 自动添加图例

OnBigWorldNpcDespawned(netId)         // 监听大世界 NPC 回收事件
  移除对应图例
```

#### 4. MapPanel Toggle 处理

在 `MapPanel.SelectNewType()` 中增加大世界 NPC 的 Toggle 分支：

```
if (type == MapLegendControl.BigWorldNpcTrackingLegendTypeId)
{
    bool newState = !legendControl.ShowAllBigWorldNpc;
    legendControl.ToggleShowAllBigWorldNpc(newState);
    trackingWidget.ToggleSelectedStyle(newState);
    return;
}
```

#### 5. 场景感知

图例按钮仅在大世界场景中显示：
- `MapPanel` 初始化时检查当前场景类型
- 大世界场景：显示 ID=127 的图例按钮，隐藏小镇专用按钮（ID=125 NPC追踪、ID=122 潜在客户）
- 小镇场景：反之

### 性能考虑

- **默认隐藏**：避免大量 NPC 图标同时渲染
- **无边缘指示器**：`edgeDisplay=0`，不显示屏幕外 NPC 的方向箭头
- **统一图标**：不逐个加载 NPC 头像资源，降低 Draw Call
- **AOI 联动**：NPC 被 AOI 回收时自动移除图例，不残留

### 优先级

P1（依赖 P0 的 NPC 生成/回收和客户端 Controller 完成后才能接入小地图）
