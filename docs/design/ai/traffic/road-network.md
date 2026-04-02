# 交通路网现状分析

## 场景与路点数据对应关系

| 场景 | 配置ID | 场景文件 | 车辆路点文件 | 行人路点 |
|------|--------|---------|-------------|---------|
| **Miami（大世界）** | 16 | Miami | road_traffic_miami.json (24MB) | walk_traffic.json |
| **S1Town（小镇）** | 22 | S1Town | **无有效数据**（待制作） | town_ped_road.json |
| **SakuraSchool（樱花校园）** | 23 | Miami（换皮） | — | Sakura.json |

> 配置来源：`freelifeclient/RawTables/map/scene.xlsx`，WaypointFile / PedWaypointFile 字段控制加载。
>
> ⚠️ S1Town 配置表 WaypointFile 当前填的是 `town_vehicle_road.json`，但该文件数据范围（1671×3171m）远超小镇实际区域（约 248×244m），**数据无效**。

## 路点数据集清单

### 生产数据

| 文件 | 大小 | 位置（RawTables 源） | 说明 |
|------|------|---------------------|------|
| road_traffic_miami.json | 24MB | `RawTables/Json/Global/traffic_waypoint/` | Miami 大世界，50,523 路点 |
| road_traffic_fl.json | 3.7MB | `RawTables/Json/Server/` | 遗留数据，范围远超小镇（已废弃） |
| town_vehicle_road.json | — | `RawTables/Json/Global/traffic_waypoint/` | 19,897点，范围远超小镇（已废弃） |
| road_traffic_gley.json | 4.0MB | `RawTables/Json/Server/` | Gley 导出格式 |

### 编译产物 / 缓存

| 文件 | 大小 | 位置 | 说明 |
|------|------|------|------|
| road_traffic_miami.json | 24MB | `Assets/PackResources/Config/Data/traffic_waypoint/` | 客户端运行时加载 |
| road_traffic_gley_miami.json | 11MB | Gley 合并 | 编辑器中间产物 |
| road_traffic_ta.json | 27MB | `Assets/ArtResources/Hdas/RoadSystem/Caches/` | 美术 HDA 缓存 |
| road_traffic_client.json | 50MB | `Assets/ArtResources/Hdas/RoadSystem/Caches/` | 客户端完整缓存 |
| road_traffic_old.json | 4.0MB | — | 遗留数据 |

### 数据分发链路

```
RawTables/Json/ (SVN 源)
  ├─ 打表工具 → Assets/PackResources/Config/Data/traffic_waypoint/ (客户端二进制)
  └─ 打表工具 → Y:/dev/config (服务器配置，TARGET_SERVER_BYTES)
```

## Miami 路点数据结构（road_traffic_miami.json）

### 单路点 Schema

```json
{
  "listIndex": 0,                // 全局路点索引（0-50522）
  "name": "Gley0",              // 编辑器路点名称
  "position": {x, y, z},        // 世界坐标
  "neighbors": [1],             // 后继路点索引数组（支持 1→N 分叉）
  "prev": [],                   // 前驱路点索引数组
  "OtherLanes": [409],          // 平行车道路点索引（变道基础）
  "junction_id": 0,             // 路口 ID（0=非路口，1-294 为路口编号）
  "cycle": 0,                   // 信号灯相位（0-3）
  "road_type": 2,               // 道路类型（1 或 2）
  "streetId": 0,                // 街道 ID
  "regionTag": 0                // 区域标签
}
```

### 统计概览（Miami）

| 指标 | 数值 |
|------|------|
| 总路点数 | 50,523 |
| 路口数 | 295（junction_id 1-294） |
| 多车道路点（有 OtherLanes） | 14,779（29%） |
| road_type=1 路点 | 29,296（58%） |
| road_type=2 路点 | 21,227（42%） |
| 路点间距中位数 | 6.35 单位 |
| 路点间距平均值 | 9.14 单位 |
| X 轴范围 | -7899 ~ 1533（约 9432 单位） |
| Z 轴范围 | -2285 ~ 3442（约 5727 单位） |
| Y 轴范围 | 47.86 ~ 76.10（平坦地形） |

## 运行时系统架构

### 三套并行系统

```
┌─────────────────────────────────────────────────┐
│            Gley TrafficSystem（编辑器层）          │
│  编辑道路/车道/路口 → 导出 JSON                    │
│  数据：miami_Road.json + miami_RoadConnections.json│
└──────────────────────┬──────────────────────────┘
                       │ TrafficWaypointsConverter
                       ▼
┌─────────────────────────────────────────────────┐
│         WaypointGraph（运行时寻路层）               │
│  CustomWaypoint {Id, Pos, nexts, prevs}          │
│  加载：trafficWaypoints.bytes                     │
│  查询：Octree 空间索引 + A* 寻路                   │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│        DotsCity / GleyNav（DOTS 物理层）           │
│  高性能车辆物理模拟                                │
│  RoadPoint → TrafficWaypoint 转换                 │
│  独立加载 road_traffic_miami.json                  │
└─────────────────────────────────────────────────┘
```

### 运行时加载流程

1. `TrafficManager` 初始化
2. GleyNav 加载 `road_traffic_miami.json` → `RoadPoint[]`
3. `TrafficWaypointsDataHandlerExternal.RoadPointsToTrafficWaypoints()` 转换为 `TrafficWaypoint[]`
4. `WaypointManager` 加载 `trafficWaypoints.bytes` → `WaypointGraph`（Octree 索引）
5. `VehicleAIPathPlanningComponent` 使用 `WaypointGraph` 进行逐路点导航

### 编辑工具链

| 工具 | 位置 | 功能 |
|------|------|------|
| TrafficWaypointDrawer | `Tools/Editor/TrafficSystem/EditorDrawer/` | 可视化绘制路点 |
| TrafficWaypointCreator | `Tools/Editor/TrafficSystem/EditorDrawer/` | 创建新路点 |
| EditWaypointWindow | `Tools/Editor/TrafficSystem/SetupWindows/WaypointSetup/` | 编辑路点属性 |
| TrafficWaypointsConverter | `Tools/Editor/TrafficSystem/EditorDrawer/` | Gley ↔ 运行时格式转换 |
| SwitchWaypointDirection | `Tools/Editor/TrafficSystem/Other/` | 切换路点方向 |
| MainMenuWindow | — | 配置 JSON 导入/导出路径 |

## 交通 AI 设计文档要求的扩展

现有 `CustomWaypoint` 字段：`{Id, Pos, nexts, prevs, CurrentState, ParentGraph}`

设计文档要求新增（见 client.md）：

| 新增字段 | 用途 | 现有数据是否已覆盖 |
|---------|------|-------------------|
| JunctionId | 路口归属 | ✅ JSON 中已有 junction_id |
| EntranceIndex | 路口入口编号 | ❌ 需新增 |
| LaneIndex | 车道编号 | ⚠️ JSON 有 OtherLanes（平行车道索引），但无显式编号 |
| AdjacentLaneWaypoints | 相邻车道路点列表 | ✅ JSON 中 OtherLanes 已有 |

## S1Town 小镇路网现状

### ⚠️ 当前无有效车辆路网

现存的两份车辆路网文件均**不可用**：

| 文件 | 问题 |
|------|------|
| `town_vehicle_road.json`（19,897点） | 覆盖 1671×3171m，远超小镇实际范围 248×244m |
| `road_traffic_fl.json`（12,359节点） | 覆盖 1661×3018m，同样远超小镇范围 |

两份数据来源不明，可能来自更大地图的 Gley 编辑器导出，**不代表小镇的实际道路布局**。

### 唯一有效路网：行人路网

| 文件 | 节点 | 边 | 范围 | 用途 |
|------|------|-----|------|------|
| `town_ped_road.json` | 621 | 685 | X[-75,173] Z[-173,71]（248×244m） | NPC 步行导航/日程 |

行人路网范围与小镇实际区域匹配，数据可靠。

### 配置表现状（scene.xlsx ID=22）

| 字段 | 当前值 | 说明 |
|------|--------|------|
| WaypointFile | `town_vehicle_road.json` | ⚠️ 指向无效数据 |
| PedWaypointFile | `town_ped_road.json` | ✅ 正确 |
| UseTrafficSystem | TRUE | 已启用，但车辆路网数据无效 |

### 待办：制作小镇车辆路网

需要基于小镇实际道路布局，制作符合 Gley 平面数组格式（与 Miami 一致）的车辆路网数据。

## S1Town 交通系统启用分析

### Town 被排除的原因

**核心原因是业务设计决策**，代码排斥是下游防护措施：

1. **业务层面**：Town 场景设计为轻量级 NPC 日程系统，策划未规划车辆交通（scene.xlsx useTrafficSystem=FALSE）
2. **架构层面**：Town 有独立初始化路径（`TownManagerOfManagers.OnEnterTown()`），不经过 DotsCity 交通初始化
3. **数据层面**：City/Sakura 共享 Miami 路网（24MB），Town 路网独立（road_traffic_fl.json 3.7MB）

### 代码排斥位置

**文件**：`Assets/Scripts/Gameplay/Managers/LaunchManager/State/LoadScene.cs`

```csharp
// L331-336: 仅 City/Sakura 读取 openTraffic 标志
if (enterSceneRes.Data.SceneType.EnumType == SceneTypeProtoType.City
    || enterSceneRes.Data.SceneType.EnumType == SceneTypeProtoType.Sakura)
{
    Define.openTraffic = enterSceneRes.Data.IsOpenTraffic;
    StreamingSceneManager.openTraffic = Define.openTraffic;
}

// L360: Town 和 Dungeon 被排除
if (Define.openTraffic
    && enterSceneRes.Data.SceneType.EnumType != SceneTypeProtoType.Dungeon
    && enterSceneRes.Data.SceneType.EnumType != SceneTypeProtoType.Town)
{
    await CityManager.ChangeCity("Scene/Miami", ...);  // 初始化 DotsCity
}
else
{
    CityManager.DisableSystem();  // 禁用交通
}
```

**双重阻塞**：
1. L331-336：Town 不会设置 `Define.openTraffic = true`
2. L360：即使 openTraffic 为 true，Town 仍被条件排除

### 三种场景对比

| 场景 | 路点文件 | 路点格式 | 初始化系统 | 交通 |
|------|---------|---------|-----------|------|
| City | road_traffic_miami.json | 平面数组（50K） | CityManager.ChangeCity | ✅ |
| Sakura | road_traffic_miami.json（换皮） | 平面数组（50K） | CityManager.ChangeCity | ✅ |
| Town | road_traffic_fl.json | 图结构（12K） | TownManagerOfManagers | ❌ |

### 运行时交通架构（修正）

```
两层架构：
┌───────────────────────────────────────────────┐
│  GleyNav（路点数据层）                           │
│  根据 SceneInfo.waypointFile 动态加载路点文件     │
│  OnEnterScene → GleyNav.Init(path) → A* 寻路   │
└───────────────────┬───────────────────────────┘
                    │ TransportGleyNav.RoadPoints
                    ▼
┌───────────────────────────────────────────────┐
│  DotsCity（车辆物理/AI 层）                      │
│  TrafficManager + ECS 交通模拟                   │
│  依赖 Hub.prefab + EntitySubScene（场景资源）     │
│  依赖 GleyNav 提供路点数据                       │
└───────────────────────────────────────────────┘
```

**关键发现**：
- road_traffic_fl.json 是**死文件**，运行时从未加载
- GleyNav 根据 `ConfigLoader.SceneInfoMap[sceneCfgId].waypointFile` 选择路点文件
- 完整车辆交通**必须有 DotsCity 场景资源**（Hub.prefab + EntitySubScene）
- S1Town **缺少 DotsCity 场景资源**——这是最大的启用障碍

### 启用步骤

#### 阶段一：代码层面解除 Town 排斥 ✅ 已完成

| 步骤 | 改动内容 | 文件 | 状态 |
|------|---------|------|------|
| 1.1 | Town 加入 openTraffic 读取条件 | `LoadScene.cs` | ✅ |
| 1.2 | Town 走独立分支（调用 TrafficManager，跳过 DotsCity） | `LoadScene.cs` | ✅ |

#### 阶段二：配置表启用 ✅ 已完成

| 步骤 | 改动内容 | 文件 | 状态 |
|------|---------|------|------|
| 2.1 | S1Town `useTrafficSystem` → TRUE | `RawTables/map/scene.xlsx` | ✅ |
| 2.2 | S1Town `waypointFile` → `road_traffic_fl.json` | `RawTables/map/scene.xlsx` | ✅ |
| 2.3 | 打表生成 `cfg_sceneinfo.bytes` | — | ✅ |
| 2.4 | `road_traffic_fl.json` 拷贝到 PackResources | — | ✅ |

> 详见 [verification-todo.md](verification-todo.md)

#### 阶段三：技术路线决策 — 采用轻量方案

**决策**：S1Town 采用**轻量方案**——GleyNav + 非 ECS 车辆 AI，**不搭建 DotsCity 场景**。

理由：
1. 小镇交通密度低（数十辆级），非 ECS 性能足够
2. 车辆 AI 有独立于 DotsCity 的完整路径（Waypoint + GleyNav → `VehicleAIPathPlanningComponent`）
3. 避免搭建 Hub.prefab + EntitySubScene 的大量工作

**轻量方案流程**：
1. `TrafficManager.OnEnterScene()` 初始化 GleyNav 加载路点
2. `VehicleAIPathPlanningComponent`（非 ECS）驱动车辆寻路
3. 跳过 `CityManager.ChangeCity()`（不加载 DotsCity）
4. 信号灯/限速区由服务端管理，通过协议同步（与 City 相同）

#### 阶段四：数据格式转换（待实现）

S1Town 的 `road_traffic_fl.json` 采用 nodes+links 图结构，GleyNav 按 `List<RoadPoint>` 反序列化。需要适配：

**方案**：在 GleyNav 加载层增加格式检测分支——若 JSON 包含 `nodes` + `links` 顶层字段，走图结构解析：

```
nodes+links 转换规则：
1. 每个 node → 一个 RoadPoint（position、junction_id 直接映射）
2. links 的 from/to → 构建 neighbors 和 prev 邻接表
3. links.lanes > 1 → 为同一 link 生成多个平行 RoadPoint，填充 OtherLanes
4. links.road_id → road_type 映射
5. links.speed → 如果非零，覆盖 road_type 默认限速
6. cycle 字段默认 0（无灯路口），有灯路口从 CfgJunction 配置中补充
```

> 转换后校验：路点连通性、路口入口数、vehicle spawn point 可达性。

### 兼容性评估

| 检查项 | 结果 |
|--------|------|
| GleyNav 多场景支持 | ✅ 根据 SceneInfo.waypointFile 动态加载 |
| 路点数据就绪 | ❌ 当前无有效车辆路网数据，需制作 |
| DotsCity 场景资源 | ❌ S1Town 无 Hub.prefab / EntitySubScene，需从零搭建 |
| CityManager 路径 | ❌ 硬编码 `"Scene/Miami"`，需参数化 |

### 风险评估

- **低风险**：LoadScene.cs 条件修改，不影响 City/Sakura 现有逻辑
- **高风险**：CityManager.ChangeCity 加载 DotsCity 场景，Town 无对应资源会导致加载失败
- **待验证**：TownManagerOfManagers 与 DotsCity 是否有初始化冲突

## 待办事项

1. **制作小镇车辆路网**：基于实际道路布局制作，采用 Gley 平面数组格式（与 Miami 一致）
2. **轻量方案可行性**：VehicleAIPathPlanningComponent 能否独立于 DotsCity 运行
3. **Miami Hub.prefab 结构**：搭建 Town 版本需要了解其组件构成
