# 交通系统

## 做什么

在大世界场景实现一套完整的 NPC 交通流系统。客户端使用 Gley TrafficSystem 第三方库驱动本地 NPC 车辆 AI（寻路、变道、信号灯），服务端管理交通种子、车辆生命周期和 Promote 机制。两端通过种子同步保证车辆外观与轨迹一致；玩家接近 NPC 车辆时，通过 Promote 将其升级为服务端托管实体，支持碰撞伤害和载具乘坐。

## 涉及端

both

## 触发方式

- 客户端自动：玩家进入大世界场景后，TrafficComponent 初始化，按密度规则在视距范围内自动生成 NPC 车辆
- 服务端自动：TrafficSeedSystem 定期轮换种子，TrafficVehicleSystem 监控车辆生命周期
- 玩家触发：玩家接近 NPC 车辆并交互 → 客户端发送 Promote 请求 → 服务端升级为托管实体

## 预期行为

正常流程：
1. 玩家进入大世界，客户端按 `traffic_create.json` 密度规则在路网上生成 NPC 车辆
2. NPC 车辆由 Gley DrivingAI 驾驶，走路网 A* 路径，遇交叉口执行信号灯/优先权规则
3. 服务端 TrafficSeedSystem 周期性更新种子，客户端同步后以相同随机序列生成车辆外观
4. 玩家接近 NPC 车辆 → 发送 PromoteTrafficVehicle 请求 → 服务端创建对应实体（上限 3/玩家，50/全场景）
5. Promoted 车辆无人使用 30 秒后服务端自动回收；爆炸残骸 60 秒后清理

异常/边界情况：
- 种子不一致（`INVALID_SEED`）：服务端下发最新种子，客户端重新同步，已生成车辆重建
- Promote 上限（`PROMOTE_LIMIT_REACHED`）：拒绝请求，客户端提示
- Promote 冷却（`PROMOTE_COOLDOWN`）：2000ms 内不允许重复请求
- 另一玩家已 Promote（`NPC_ALREADY_PROMOTED`）：返回错误，客户端处理提示

## 不做什么

- 不做服务端 NPC 车辆 AI 驾驶（路径规划和 AI 完全在客户端，服务端只管生命周期）
- 不做信号灯服务端同步（信号灯状态纯客户端 Gley 管理）
- 不做行人与交通的交互（行人路网与车辆路网拓扑独立）
- 不修改 Gley TrafficSystem 第三方库源码（只通过 `APITrafficSystem` 接口调用）

## 参考

- 服务端交通系统：`P1GoServer/servers/scene_server/internal/ecs/system/traffic_vehicle/`
- 服务端交通种子：`P1GoServer/servers/scene_server/internal/ecs/system/traffic_seed/`
- 服务端路网管理：`P1GoServer/servers/scene_server/internal/ecs/res/road_network/`
- 服务端路网寻路：`P1GoServer/servers/scene_server/internal/ecs/res/road_network/road_net_work.go`（注：common/pathfind/road_network/ 下无此文件）
- 服务端 Promote 处理：`P1GoServer/servers/scene_server/internal/net_func/vehicle/vehicle_system_v2.go` ⚠️ 待实现
- 客户端 Gley 库入口：`freelifeclient/.../Libs/Gley/TrafficSystem/Scripts/ToUse/APITrafficSystem.cs`
- 客户端配置加载：`freelifeclient/.../Config/TrafficJsonConfigLoader.cs`、`VehicleJsonConfigLoader.cs`
- 配置源文件：`freelifeclient/RawTables/` 下 traffic / vehicle 相关 JSON

---

## 架构概览

```
客户端                              服务端
─────────────────────────────────   ─────────────────────────────────
TrafficComponent（场景初始化）       TrafficSeedSystem（种子轮换）
  └─ APITrafficSystem.Initialize()    └─ CurrentSeed / SeedVersion
       │
       ├─ DensityManager             TrafficVehicleSystem（生命周期）
       │   └─ 按密度生成/销毁 NPC 车   └─ 自动消失 / Promoted 回收
       │
       ├─ PathFindingManager (A*)    vehicle_system_v2.go（Promote）
       │   └─ 路网寻路                 └─ PromoteTrafficVehicle()
       │
       ├─ DrivingAI                  MapRoadNetworkMgr（路网）
       │   └─ 加速/转向/避障/变道        └─ driveway 路网加载与索引
       │
       └─ IntersectionManager
           └─ 信号灯 / 优先权规则
```

---

## 配置系统

### 配置文件清单

配置存放在 `freelifeclient/RawTables/`，服务端从 `bin/config/` 对应路径读取：

| 文件 | 内容 | 状态 |
|------|------|------|
| `traffic/traffic_settings.json` | 全局流量参数（最大车数、密度距离等） | ⚠️ 待实现 |
| `traffic/traffic_create.json` | 区域创建规则（冷却、生成速率、密度权重） | ⚠️ 待实现 |
| `vehicle/vehicles.json` | 车辆主配置（车型、模型 ID、物理参数） | ⚠️ 待实现（当前为 Excel） |
| `vehicle/vehicle_base.json` | 车辆基础属性（速度、转向、耐久） | ⚠️ 待实现（当前为 Excel） |
| `vehicle/vehicle_create_rules.json` | 车辆生成规则（NPC 车 / 玩家车分类） | ⚠️ 待实现 |
| `traffic_waypoint/*.json` | 路网点位与有向边权重（driveway 类型） | ✓ 已存在（`RawTables/Json/Global/traffic_waypoint/`） |

**当前实际 vehicle 配置（Excel）：**
- `RawTables/vehicle/Vehicle.xlsx` / `VehicleAppendix.xlsx` / `VehiclePart.xlsx` / `VehicleShop.xlsx`

### 服务端配置结构

```go
// TrafficConfig — 场景级全局交通状态（ECS 资源）
type TrafficConfig struct {
    CurrentSeed            int64
    SeedVersion            int32
    SeedChangeIntervalSec  int32
    PromotedCount          int32   // 当前全场景 Promoted 数量
}

// 生成上限常量
MaxPromotedPerPlayer = 3
MaxPromotedPerScene  = 50
PromoteCooldownMs    = 2000
wreckDespawnTimeSec  = 60
promotedRecycleTimeSec = 30
```

### 客户端配置加载

> ⚠️ **待实现**：`TrafficJsonConfigLoader.cs` 和 `VehicleJsonConfigLoader.cs` 均不存在，依赖上方 JSON 配置迁移完成后实现。

```csharp
// 交通流参数
var setting = TrafficJsonConfigLoader.Instance.GetTrafficSetting<TrafficCreateRuleJsonConfig>(key);
var rule    = TrafficJsonConfigLoader.Instance.GetTrafficCreateById(id);

// 车辆属性
var vehicle = VehicleJsonConfigLoader.Instance.GetVehicleById(id);
var base_   = VehicleJsonConfigLoader.Instance.GetVehicleBaseById(id);
```

---

## 路网系统

### 路网类型体系

与行人路网共用同一套 `road_point.json` 加载器，通过 `type` 字段区分：

| 类型 | 用途 |
|------|------|
| `driveway` | 车辆行驶路网（交通系统使用） |
| `footwalk` | 行人步行路网（NPC 行人使用） |

数据链路：`RawTables/Json/Server/{mapName}/road_point.json` → 打表 → `bin/config/{mapName}/road_point.json` → `MapRoadNetworkMgr` 加载。

### 大世界路网数据文件

| 文件 | 路点数 | X 范围 | Z 范围 | 状态 |
|------|--------|--------|--------|------|
| `RawTables/Json/Global/traffic_waypoint/road_traffic_miami.json` | 50,523 | [-7899, 1531] | [-2280, 3443] | ✓ 车辆路网，已使用 |
| `RawTables/Json/Server/miami_ped_road.json` | 47,157 | [-4096, 1531] | [-2284, 3438] | ✓ 行人路网（`footwalk`），数据完整，服务端加载逻辑⚠️待实现 |

**覆盖差异**：车辆路网向西多延伸约 3800 单位（X -4096 → -7899），为郊区公路区域，行人路网未覆盖。核心城区两网重叠良好。

> 可视化对比见 [`docs/viz/roadnet_compare.html`](../viz/roadnet_compare.html)（交互式，支持缩放/图层切换/悬停查点）

### 路网数据结构

```go
type RoadNetwork struct {
    points   []*Point
    pointMap map[int]*Point
    config   *RoadNetworkCfg
}

type Point struct {
    ID       int
    Index    int
    Position Vec3
    Edges    []*Edge   // 有向出边列表
}

type Edge struct {
    ToID   int
    Weight float32
}
```

### 寻路算法

服务端 `road_net_work.go` 提供 Dijkstra 寻路：

| 方法 | 说明 |
|------|------|
| `GetPointByID(id)` | 按 ID 查询路点 |
| `GetNextWaypoint(currentID, targetID)` | 返回从当前点到目标的下一个路点 |
| `RandomSelectNextPoint(currentID)` | 随机选取一个出边，用于随机漫游 |

---

## 种子同步机制

交通流的随机性（车辆颜色、外观、生成顺序）由服务端统一下发的种子控制，确保双端一致：

```
服务端 TrafficSeedSystem
  → 每 SeedChangeIntervalSec 秒生成新种子
  → 下行同步到所有玩家客户端
  → 客户端以该种子初始化随机数生成器
  → 生成的车辆颜色/型号与服务端预期一致

Promote 时校验：
  服务端记录发出种子版本(SeedVersion)
  Promote 请求携带客户端当前版本
  版本不一致 → INVALID_SEED → 服务端重新下发种子
```

---

## Promote 机制

Promote 是将"客户端本地 NPC 车辆"升级为"服务端托管实体"的过程，用于支持玩家进入/碰撞/伤害交互。

### 流程

```
玩家靠近 NPC 车辆并交互
  → 客户端发送 PromoteTrafficVehicle 请求
       携带：vehicleNetId、seed 版本、车辆位置
  → 服务端校验：
       ① 单玩家上限（MaxPromotedPerPlayer=3）
       ② 全场景上限（MaxPromotedPerScene=50）
       ③ 冷却检查（PromoteCooldownMs=2000）
       ④ 种子版本一致性
  → 成功：创建服务端 TrafficVehicle 实体，设 Promoted=true
  → 失败：返回对应 VehicleErrorCode
```

### 错误码

| 错误码 | 值 | 说明 |
|--------|----|------|
| NPC_ALREADY_PROMOTED | 14 | 另一玩家已 Promote 该车 |
| INVALID_SEED | 15 | 客户端种子版本与服务端不一致 |
| PROMOTE_LIMIT_REACHED | 28 | 单玩家或全场景 Promote 数量达上限 |
| PROMOTE_COOLDOWN | 29 | 请求频率过高（2s 冷却） |

### 回收策略

- Promoted 车辆无人乘坐超过 **30 秒** → 服务端标记 `NeedAutoVanish`，系统回收
- 爆炸残骸超过 **60 秒** → 自动清理
- 回收时 `PromotedCount--`，释放配额

---

## 客户端 NPC 车辆 AI

### Gley TrafficSystem 架构

客户端交通流完全由 **Gley TrafficSystem**（第三方库）驱动，禁止修改其源码，只通过 `APITrafficSystem` 接口调用：

```csharp
// 初始化（场景加载时）
APITrafficSystem.Initialize(trafficConfig);

// 生成/销毁
APITrafficSystem.SpawnVehicle(vehicleCfgId, position, rotation);
APITrafficSystem.RemoveVehicle(vehicleIndex);
```

### 主要管理器

| 管理器 | 文件 | 职责 |
|--------|------|------|
| DensityManager | `Traffic/Managers/DensityManager.cs` | 根据密度规则生成/销毁车辆 |
| ActiveCellsManager | `Traffic/Managers/ActiveCellsManager.cs` | 视距网格激活管理（视距内详细 AI，视距外冻结） |
| PathFindingManager | `Traffic/Managers/PathFindingManager.cs` | A* 路网寻路 |
| DrivingAI | `Traffic/Scripts/Internal/DrivingAI.cs` | 加速/转向/避障/变道驾驶决策 |
| IntersectionManager | `Traffic/Managers/IntersectionManager.cs` | 路口规则处理 |
| WaypointManager | `Traffic/Managers/WaypointManager.cs` | 路网节点与交叉点管理 |

### 路口类型

Gley 支持 5 种路口类型，均配置驱动：

| 类型 | 说明 |
|------|------|
| TrafficLightsIntersection | 信号灯十字路口 |
| TrafficLightsCrossing | 信号灯行人过街 |
| PriorityIntersection | 优先权十字路口（主路优先） |
| PriorityCrossing | 优先权行人过街 |
| PedestrianCrossing | 纯行人过街 |

---

## 车辆生命周期

```
[创建]
  SpawnTrafficVehicle()
    ├─ 添加 TrafficVehicleComp（IsTrafficSystem=true）
    ├─ 添加 VehicleStatusComp（座位管理）
    └─ 添加 VehiclePhysicsComp

[运行]
  DrivingAI 每帧更新位置/速度
  玩家接近 → PromoteTrafficVehicle（可选）

[消失]
  ├─ 普通 NPC：离开所有玩家 AOI 后标记 NeedAutoVanish → 销毁
  ├─ Promoted 无人使用 30s → 服务端回收
  └─ 爆炸残骸 60s → 服务端清理
```

---

## 性能约束

- **手游预算**：视距外车辆由 `ActiveCellsManager` 冻结 AI，只保留最低位置插值
- **分帧生成**：密度更新周期 `VehicleGenerateCoolDown` 控制生成间隔，避免单帧突刺
- **Promoted 硬上限**：MaxPromotedPerScene=50，防止服务端实体过多
- **路网规模**：大世界 driveway 路网约 50K 路点，Dijkstra 查询必须在缓存层完成，不每帧重算
- **种子机制**：避免双端独立随机导致不一致，减少同步带宽（只同步一个 int64 种子）

---

## 待实现项方案

详见 [`docs/Version/impl/traffic_pending_impl.md`](../impl/traffic_pending_impl.md)，包含所有 ⚠️ 标注项的参考实现路径、代码结构和实现顺序（参考 `E:\workspace\PRJ\P1_1`）。

---

## 关键文件速查

| 功能 | 路径 | 状态 |
|------|------|------|
| 服务端交通载具系统 | `P1GoServer/.../ecs/system/traffic_vehicle/traffic_vehicle_system.go` | ✓ |
| 服务端交通种子系统 | `P1GoServer/.../ecs/system/traffic_seed/traffic_seed_system.go` | ⚠️ 目录不存在 |
| 服务端交通配置资源 | `P1GoServer/.../ecs/res/traffic_config.go` | ⚠️ 不存在 |
| 服务端路网管理 | `P1GoServer/.../ecs/res/road_network/road_network_mgr.go` | ✓ |
| 服务端路网寻路 | `P1GoServer/.../ecs/res/road_network/road_net_work.go`（注：实际在 ecs/res/，非 common/pathfind/） | ✓ |
| 服务端 Promote 处理 | `P1GoServer/.../net_func/vehicle/vehicle_system_v2.go` | ⚠️ 不存在（目录下只有 vehicle_door/horn/ops.go） |
| 服务端车辆生成 | `P1GoServer/.../ecs/spawn/vehicle_spawn.go` | ✓ |
| 客户端 Gley API 入口 | `freelifeclient/.../Libs/Gley/TrafficSystem/Scripts/ToUse/APITrafficSystem.cs` | ✓ |
| 客户端寻路 | `freelifeclient/.../Libs/Gley/TrafficSystem/.../PathFindingManager.cs` | ✓ |
| 客户端驾驶 AI | `freelifeclient/.../Libs/Gley/TrafficSystem/.../DrivingAI.cs` | ✓ |
| 客户端路口管理 | `freelifeclient/.../Libs/Gley/TrafficSystem/.../IntersectionManager.cs` | ✓ |
| 客户端交通配置加载 | `freelifeclient/.../Config/TrafficJsonConfigLoader.cs` | ⚠️ 不存在 |
| 客户端车辆配置加载 | `freelifeclient/.../Config/VehicleJsonConfigLoader.cs` | ⚠️ 不存在 |
| Proto 消息定义 | `freelifeclient/.../Net/Proto/vehicle.pb.cs` | ✓ |
