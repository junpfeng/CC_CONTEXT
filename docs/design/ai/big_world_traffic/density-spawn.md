# 密度与生成管理

## 现状

- **服务端**：`cfg_vehiclecreaterule` 刷车规则配置表（冷却/密度/概率）、`cfg_roadtype` 道路类型配置表
- **交通载具系统**：`traffic_vehicle_system.go` 管理交通载具自动消失
- **缺失**：动态密度控制、基于玩家位置的生成/回收、类型权重规则

## GTA5 参考

GTA5 动态密度系统：围绕玩家 1765m 流式加载路网，11 种生成规则，根据区域/时间/天气动态调整车流密度。我们简化为围绕玩家固定半径管理。

## 前置依赖：服务端路网空间查询

客户端路网由 GleyNav/WaypointManager 加载（50K 路点 + Octree），但服务端密度管理同样需要路网空间查询（FindNodesInRadius）。

**方案：服务端轻量路网索引**

服务端场景初始化时加载路网 JSON，构建轻量级空间索引：

```go
// ServerRoadNetwork 服务端路网（仅位置+类型，不含物理数据）
type ServerRoadNetwork struct {
    Nodes     []RoadNode          // 50K 路点（position + road_type + junction_id）
    Grid      map[GridKey][]int32 // 网格索引（50m 格子），用于快速范围查询
}

type RoadNode struct {
    Position   Vec3
    RoadType   int32
    JunctionId int32
    // 注意：不存储 Neighbors，密度管理仅需空间查询不需图遍历
    // 如果后续服务端需要路径验证再按需加载
}

// 范围查询：O(1) 网格定位 + 遍历格子内节点
func (rn *ServerRoadNetwork) FindNodesInRadius(center Vec3, radius float32) []int32
```

- 内存占用：50K 节点 × ~40 字节 ≈ 2MB（可接受）
- 网格索引：50m 格子，覆盖区域 ~5400 万 m² → ~21,600 格子
- 仅在密度管理 Tick 中使用，不参与物理计算

## 设计方案

### 1. 密度管理器（服务端）

```go
// DensityManager 动态管理交通车辆密度
type DensityManager struct {
    maxVisible    int     // AOI 内最大可见数（默认 15）
    spawnRadius   float32 // 生成半径 150~250m（视线外）
    despawnRadius float32 // 回收半径 300m
    minDistance   float32 // 最小生成间距 30m（避免扎堆）
}
```

### 2. 生成策略

**生成触发**（服务端每 2 秒 Tick）：

```
1. 统计玩家 AOI 内交通车辆数量
2. 如果 < maxVisible:
   a. 在玩家 spawnRadius 范围内找路网节点
   b. 排除玩家视线方向 60° 锥形内的节点（避免眼前凭空出现）
   c. 排除已有车辆 minDistance 内的节点
   d. 根据节点 road_type 查配置表确定车型权重
   e. 生成车辆 + 分配人格 + 通知客户端
```

### 3. 回收策略

```
1. 每 5 秒遍历所有交通车辆
2. 距离所有玩家 > despawnRadius → 回收
3. 回收 = 销毁服务端实体 + 通知客户端
```

### 4. 车型权重规则

基于路网节点的 `road_type` 决定车型分布：

| road_type | 描述 | 轿车 | SUV | 货车 | 公交 | 跑车 | 出租车 |
|-----------|------|------|-----|------|------|------|--------|
| 1 | 主干道 | 40% | 15% | 15% | 10% | 5% | 15% |
| 2 | 支路 | 50% | 20% | 10% | 5% | 5% | 10% |

**配置表驱动**：在 `cfg_vehiclecreaterule` 中按 road_type 配置车型权重，无需硬编码。

### 5. 限速区

**两层限速**：

**A. 路段限速**（基于 `road_type`，复用 `cfg_roadtype` 配置表）：

| road_type | 限速 (m/s) | 说明 |
|-----------|-----------|------|
| 1 | 16 | 主干道 |
| 2 | 11 | 支路 |

**B. 球形限速区**（对齐 `old_proto/scene/vehicle.proto` 已有协议）：

```protobuf
// 已定义，服务端 → 客户端
message SpeedZoneSyncNtf {
  repeated SpeedZoneData zones = 1;
}
message SpeedZoneData {
  uint32 zone_id = 1;
  float center_x = 2; float center_y = 3; float center_z = 4;
  float radius = 5;
  float max_speed = 6;
  bool active = 7;     // true=新增/更新, false=移除
}
```

用于学校、医院、施工区域等特殊限速场景。服务端在玩家进入 AOI 时同步 SpeedZoneData，客户端本地检测车辆是否在限速区内。

**客户端应用**：

```csharp
// 车辆进入新路段时更新限速
float roadSpeedLimit = _roadGraph.GetSpeedLimit(_currentNode);
float zoneSpeedLimit = _speedZoneManager.GetSpeedLimitAt(transform.position);
float effectiveLimit = Mathf.Min(roadSpeedLimit, zoneSpeedLimit);
float effectiveSpeed = _personality.GetEffectiveCruiseSpeed(effectiveLimit);
```

三者取 min：人格巡航速度、路段限速、球形限速区。

### 6. 生成位置选择

```go
func (dm *DensityManager) findSpawnNode(playerPos Vec3, playerForward Vec3) (int32, bool) {
    // 1. 在 spawnRadius 圆环内找候选节点
    candidates := dm.roadGraph.FindNodesInRadius(playerPos, dm.spawnRadius)

    // 2. 过滤
    var valid []int32
    for _, nodeId := range candidates {
        nodePos := dm.roadGraph.GetNodePos(nodeId)
        dist := distance(playerPos, nodePos)

        // 排除太近的
        if dist < dm.spawnRadius * 0.6 { continue }

        // 排除玩家视线方向（60° 锥形）
        dir := normalize(nodePos - playerPos)
        if dot(dir, playerForward) > 0.87 { continue }  // cos(30°)

        // 排除已有车辆附近
        if dm.hasVehicleNear(nodePos, dm.minDistance) { continue }

        valid = append(valid, nodeId)
    }

    if len(valid) == 0 { return 0, false }

    // 3. 随机选择
    return valid[rand.Intn(len(valid))], true
}
```

### 7. 性能考量

| 指标 | 方案 |
|------|------|
| 服务端 Tick 频率 | 密度检查 2s，回收检查 5s |
| 路网空间查询 | 复用 WaypointManager 的 Octree，O(log n) |
| 最大交通车辆 | 单场景 50 辆（AOI 内可见 ~15 辆） |
| 生成间隔 | 每次 Tick 最多生成 2 辆，避免瞬间大量创建 |
| 网络带宽 | 生成/回收仅通知 AOI 内玩家，信号灯广播限 AOI |

### 8. 与现有系统的关系

- **替代** `TownTrafficSpawner` 的固定生成逻辑
- **复用** `traffic_vehicle_system.go` 的实体管理框架
- **复用** `cfg_vehiclecreaterule` 配置表结构
- **新增** 密度管理 Tick、视线外生成算法
