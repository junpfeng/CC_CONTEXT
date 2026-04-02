# 大世界交通系统

> 基于 GTA5 逆向工程参考，为大世界（Miami）场景实现的自主交通车辆系统。

## 一、系统概览

### 已完成功能

| 功能 | 状态 | 说明 |
|------|------|------|
| 路网图索引 | ✅ | 50K 路点空间网格索引 + 双向邻接表 |
| A* 寻路 | ✅ | 二叉堆 + 分帧 + LRU 缓存，<3ms |
| 车辆生成 | ✅ | 客户端 Spawner → 服务端 Entity → AOI 同步 → 客户端实例化 |
| 自主巡航 | ✅ | TownVehicleDriver Catmull-Rom 样条移动 |
| 路口决策 FSM | ✅ 框架 | 6 态 FSM（未接入 DrivingAI） |
| 驾驶人格 | ✅ 框架 | 6 种预设 16 参数（未接入 DrivingAI） |
| 碰撞闪避升级链 | ✅ 框架 | 6 态升级（未接入 DrivingAI） |
| 变道控制器 | ✅ 框架 | 5 态 FSM（未接入 DrivingAI） |
| 信号灯计时器 | ✅ 框架 | 服务端相位计时（未注册到场景） |
| 密度管理 | ✅ 框架 | 服务端空间索引（未注册到场景） |

### 数据规模

- 路点：50,523 个
- 路口：~295 个（cycle 数据 1,544 个路点有信号灯相位）
- 车辆配置：20 种车型
- 运行时车辆：64 实例化 / 20 辆自主行驶

## 二、架构

```
┌─────────────────── 客户端 ───────────────────┐
│  BigWorldTrafficSpawner                       │
│    ↓ OnTrafficVehicleReq                      │
│  TrafficRoadGraph ← 路网数据 (road_traffic_miami.json)
│    ↓ FindNearestNode / PickCruiseTarget       │
│  TrafficPathfinder (A*)                       │
│    ↓ 路径                                     │
│  TownVehicleDriver (Catmull-Rom 样条移动)     │
│    ↓ transform.position                       │
│  Vehicle GameObject                           │
└───────────────────────────────────────────────┘
        ↕ Protobuf (OnTrafficVehicleReq/Res)
┌─────────────────── 服务端 ───────────────────┐
│  SpawnTrafficVehicle                          │
│    → Entity (Transform + TrafficVehicleComp   │
│             + VehicleStatusComp)              │
│    → AOI 同步 → 客户端 DataManager.Vehicles  │
│  ServerRoadNetwork (空间索引，密度管理预留)    │
│  TrafficLightSystem (信号灯计时，预留)         │
└───────────────────────────────────────────────┘
```

## 三、核心模块

### 3.1 TrafficRoadGraph（路网图索引）

**文件**: `freelifeclient/.../Traffic/TrafficRoadGraph.cs`

包装 `TrafficWaypointsDataHandlerExternal` 数据，提供：
- **50m 网格空间索引**：`FindNearestNode(pos)` / `FindNodesInRadius(pos, r)`
- **双向邻接表**：`GetBiDirAdjacent(nodeId)` 供 A* 使用
- **路口数据**：按 `junction_id` 分组，提取入口节点和信号灯相位
- **巡航目标选择**：`PickCruiseTarget(from, lastTarget)` 100-300m 范围防折返

**初始化时机**：`TrafficManager.OnEnterScene()` 加载路网文件后调用 `TrafficRoadGraph.Create()`

### 3.2 TrafficPathfinder（A* 寻路）

**文件**: `freelifeclient/.../Traffic/TrafficPathfinder.cs`

- **二叉最小堆**：自实现，避免 SortedSet GC
- **缓冲区复用**：`gScore/cameFrom/inClosed` 三数组复用，避免每次 600KB 分配
- **分帧异步**：`FindPathAsync()` 每帧展开 500 节点后 `UniTask.Yield`
- **LRU 缓存**：50 条路径缓存，LinkedList + Dictionary
- **节点屏蔽**：`BlockNode(id, duration)` 临时拥堵绕行

性能：50K 节点规模下单次寻路 <3ms。

### 3.3 BigWorldTrafficSpawner（车辆生成器）

**文件**: `freelifeclient/.../Traffic/BigWorldTrafficSpawner.cs`

- 每 2s 检查一次，维持 15 辆上限
- `PickSpawnNode`：在玩家 50-200m 范围选择路网节点，**地面碰撞体检测**（从 Y=200 raycast）确保物理场景已加载
- `SpawnVehicleAt`：raycast 修正 Y 坐标 → 发 `OnTrafficVehicleReq` 到服务端

### 3.4 车辆注册与驾驶（Vehicle.cs + TownVehicleDriver）

**注册入口**: `Vehicle.OnInit()` → `shouldRegister` → `RegisterVehicle` → `AssignWaypointPath`

大世界分支（`!SceneManager.IsInTown`）：
1. raycast 修正地面高度
2. `BigWorldTrafficSpawner.AssignWaypointPath` → A* 生成路径
3. `TownVehicleDriver.Init(nearestNode, speed)` → Catmull-Rom 样条巡航

### 3.5 服务端 Entity 生命周期

**文件**: `P1GoServer/.../spawn/vehicle_spawn.go`

关键点：
- `NeedAutoVanish = false`（客户端管理生命周期）
- 所有组件必须在 `AddComponent` **之后**调用 `SetSync()`
- `SetEntityType(EntityType_Vehicle)` 触发 `getVehicleMsg()` 同步

## 四、数据流

```
1. 场景加载
   LoadScene.cs → LoadTrafficAsync(sceneCfgId).Forget()
   → TrafficManager.OnEnterScene(16) → 加载 road_traffic_miami.json
   → TrafficRoadGraph.Create(dataHandler) → 50,523 节点索引

2. 车辆生成
   BigWorldTrafficSpawner.SpawnLoop()
   → PickSpawnNode(playerPos) → 地面检测 → Y 修正
   → OnTrafficVehicleReq → 服务端 SpawnTrafficVehicle
   → Entity(Transform + TrafficVehicle + VehicleStatus) + SetSync()
   → AOI 同步 → 客户端 DataManager.Vehicles

3. 客户端实例化
   VehicleManager._waitingAddList → BaseInfo != null + 距离检查 + 地面检测
   → SpawnVehicle(netData) → Vehicle.OnInit()
   → RegisterVehicle → AssignWaypointPath → TownVehicleDriver.Init()

4. 自主巡航
   TownVehicleDriver.Update()
   → BuildSplineFromPath() → TrafficRoadGraph + A* 寻路 → 样条轨迹
   → Catmull-Rom 插值移动 + 碰撞避让 + AI LOD
```

## 五、配置依赖

| 配置 | 位置 | 说明 |
|------|------|------|
| `UseTrafficSystem` | `RawTables/map/scene.xlsx` 列 Y | Miami(id=16) + 1601-1618 设为 TRUE |
| 路网文件 | `PackResources/road/road_traffic_miami.json` | 50K 路点 |
| 车型 ID | `BigWorldTrafficSpawner.TrafficVehicleCfgIds` | 300101~302001 (20种) |

## 六、已知限制与后续计划

| 项目 | 说明 |
|------|------|
| junction_id 全为 0 | 路网数据源未填充，路口检测需依赖 cycle 数据 |
| 路网 Y 坐标不可信 | 必须从 Y=200 用 Grounds 层 raycast 修正（偏差 ~58m），Default 层会命中建筑屋顶 |
| JunctionDecisionFSM | 框架已实现，未接入实际信号灯判断 |
| PersonalityDriver | 框架已实现，未接入 DrivingAI 调制 |
| AvoidanceUpgradeChain | 框架已实现，未接入 DrivingAI |
| LaneChangeController | 框架已实现，未接入 DrivingAI |
| TrafficLightSystem | 服务端已实现，未注册到场景系统 |
| DensityManager | 服务端已实现，未注册到场景系统 |

## 七、红绿灯视觉系统

### 7.1 放置逻辑

**文件**: `GTA5TrafficSystem.cs` → `SpawnLightsForJunction()`

每 2 秒检查玩家周围 200m 内路口，生成/回收红绿灯 prefab（LOD）。

**每个入口的放置流程**：
1. 取入口节点世界坐标 `entrancePos`
2. 计算出口方向 `outward = entrancePos - junctionCenter`（XZ 归一化）
3. 计算右侧法向量 `right`（顺时针 90°）
4. XZ 偏移：`pos = entrancePos + outward * 3m + right * 6m`（向外退 3m + 右偏 6m 到路边）
5. Y 高度：`FindJunctionGroundY()` 取路面高度
6. 朝向：面向来车方向（`-outward`）
7. 设为 Ignore Raycast 层（防止干扰地面检测）

### 7.2 大世界 Y 高度修正（重要）

大世界场景层级结构：
- **Grounds 层 (layer 6)**：地形/路面网格，Y≈60
- **Default 层 (layer 0)**：POI 建筑（KoreanFood / Police 等），Y≈70-90
- POI 建筑覆盖区域**没有** Grounds 层碰撞体

**问题**：从 Y=200 向下 Raycast 用 Default+Grounds 混合 mask 会命中建筑屋顶 (Y≈75)，而非路面 (Y≈60)。

**解决方案** — `FindJunctionGroundY()`：
1. 只用 **Grounds 层** (layer 6) Raycast
2. 先遍历路口所有节点位置
3. 未命中则从路口中心螺旋外扩搜索（15m 步进，最远 80m）
4. 结果按路口 ID 缓存，同一路口只搜索一次

### 7.3 Prefab 说明

- 路径：`Assets/ArtResources/Scene/SceneObject/UGC_UrbanInteractiveObjects/General_TrafficLight_01.prefab`
- **原点在模型底部**（`bounds.min.y ≈ pos.y`，模型向上延伸约 10m）
- 无需额外 Y 偏移（`prefabHeightOffset = 0`）

### 7.4 信号灯状态同步

`TrafficLightRenderer`（挂载在 prefab 上）每 0.5s 轮询 `SignalLightCache`，根据服务端下发的 `TrafficLightStateNtf` 切换绿/红/黄灯子对象。

### 7.5 注意事项

| 事项 | 说明 |
|------|------|
| Raycast 层级 | 红绿灯 Y 修正**必须只用 Grounds 层**，Default 层会命中建筑屋顶 |
| 路网 Y 不可信 | `TrafficWaypointsDataHandlerExternal.RaycastGroundY` 从 Y=50 起射，打不到 BigWorld 地面 Y≈60，节点 Y 默认 1.5 |
| XZ 偏移先于 Y | 先在入口节点原始 XZ 取路面 Y，再做 XZ 偏移（避免偏移后 XZ 落入建筑上方） |
| Prefab 原点 | 实测在底部，不要靠注释猜 |

## 八、文件清单

### 客户端新增
| 文件 | 行数 | 职责 |
|------|------|------|
| `TrafficRoadGraph.cs` | ~350 | 路网图空间索引 |
| `TrafficPathfinder.cs` | ~320 | A* 寻路 |
| `JunctionDecisionFSM.cs` | ~260 | 路口决策 FSM |
| `PersonalityDriver.cs` | ~190 | 驾驶人格 |
| `AvoidanceUpgradeChain.cs` | ~230 | 碰撞闪避升级链 |
| `LaneChangeController.cs` | ~260 | 变道控制器 |
| `BigWorldTrafficSpawner.cs` | ~240 | 车辆生成器 |
| `GTA5TrafficSystem.cs` | ~450 | 车辆生成+红绿灯视觉 |
| `TrafficLightRenderer.cs` | ~110 | 红绿灯状态渲染 |
| `SignalLightCache.cs` | ~100 | 信号灯状态缓存 |

路径前缀：`freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Managers/VehicleCar/Traffic/`

### 客户端修改
| 文件 | 修改 |
|------|------|
| `TrafficManager.cs` | init/OnEnterScene/OnDestroy 集成 |
| `DrivingAI.cs` | NoWaypointsAvailable A* 重路由 |
| `WaypointManager.cs` | TryGenerateCruisePath |
| `TownVehicleDriver.cs` | 支持 TrafficRoadGraph 数据源 |
| `Vehicle.cs` | BigWorld 分支 + 地面高度修正 |
| `LoadScene.cs` | City 场景 LoadTrafficAsync |
| `SwitchUniverseNtf.cs` | OnEnterScene 位置调整 |

### 服务端新增
| 文件 | 职责 |
|------|------|
| `traffic_light_system.go` | 信号灯相位计时 |
| `server_road_network.go` | 空间索引 |
| `density_manager.go` | 密度管理 |
| `junction_handler.go` | 路口进出处理 |

路径前缀：`P1GoServer/servers/scene_server/internal/ecs/system/traffic_vehicle/`

### 服务端修改
| 文件 | 修改 |
|------|------|
| `vehicle_spawn.go` | NeedAutoVanish=false + SetSync 顺序 |
| `ecs.go` | SystemType_TrafficLight/DensityManager |
| `vehicle_pb.go` | type 关键字冲突修复 |
