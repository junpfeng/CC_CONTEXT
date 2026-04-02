# 大世界交通系统 — 功能完成度

> 最后更新：2026-03-23

## 架构总览（GTA5 式四层）

| 层 | 模块 | 职责 |
|---|---|---|
| 调度层 | GTA5TrafficSystem | 车辆生命周期、红绿灯视觉生成/回收、协议回调 |
| 决策层 | GTA5VehicleAI | 3 个 FSM（路口/避让/变道），全部客户端本地计算 |
| 控制层 | GTA5VehicleController | Catmull-Rom 路径跟随 + 速度控制 + Y raycast |
| 数据层 | TrafficRoadGraph + SignalLightCache + SpatialGrid | 50K 路点图 + A* 寻路 + 空间网格查询 |

---

## 已完成功能

### 1. 路网 + A* 寻路 ✅

- 50,523 路点、294 路口、双向邻接表（从 `road_traffic_miami.json` 加载）
- `TrafficRoadGraph`：并行数组结构，空间网格索引（50m 单元格）
- `TrafficPathfinder`：分帧 A* + 路径缓存
- 路口数据自动构建：按 `junction_id` 分组节点，`cycle > 0` 标记入口

### 2. 信号灯系统（全链路）✅

**服务端**：
- `JunctionDetectorTool.cs`（Editor 菜单）：从路网数据提取路口，生成 `traffic_server.json`
- `traffic_server_loader.go`：加载路口配置到 `ServerRoadNetwork`
- `TrafficLightSystem`：相位计时 + `OnAfterTick()` 全量广播 `TrafficLightStateNtf`
- `enter.go`：`notifyTrafficLightStateToPlayer()` 新玩家同步

**客户端**：
- `SignalLightCache`：接收服务端 Ntf + 本地时间插值
- `JunctionDecisionFSM`（6 态）：红灯停 / 绿灯行 / 黄灯减速 / 无信号让行
- `TrafficLightRenderer`：挂载 prefab，每 0.5s 查询 SignalLightCache 切换 On/Off 子对象

### 3. 红绿灯 3D 视觉 ✅

- `GTA5TrafficSystem`：加载 `General_TrafficLight_01` prefab，200m 内生成 / 250m 外回收
- 多车道入口去重：`MergeEntrancesByDirection()` 同 cycle + <12m 合并，取最右车道（1544→567 个灯）
- 放置规则：outward 顺时针 90° 偏移 6m（路边），外退 3m，Y 用 Grounds 层 raycast
- 面朝来车方向，Layer 设为 Ignore Raycast 防止 raycast 干扰

### 4. 碰撞避让 ✅

- `AvoidanceUpgradeChain`（6 态升级链）：检测→减速→蠕行→停车→鸣笛→绕行
- 蠕行/停车分级：< 1.5m 停车，否则 0.5 m/s 蠕行
- `SpatialGrid`（泛型 50m 网格）：O(1) 查询邻近车辆，替代全量遍历

### 5. 驾驶人格 ✅

- `PersonalityDriver`：16 参数调制因子
- 5 种预设：Cautious / Normal / Aggressive / Taxi / Truck
- 影响：速度倍率、跟车距离、变道倾向、路口等待容忍度

### 6. AI LOD ✅

- Full（<80m）：完整 AI 决策 + 平滑控制
- Reduced（80~150m）：简化避让 + 降低更新频率
- Minimal（>150m）：仅路径跟随，跳过避让和变道

### 7. 车辆动态生成/回收 ✅

- `SpawnLoop`：玩家 200m 范围内动态生成，最多 20 辆
- 服务端创建实体（`OnTrafficVehicle` 协议） + 客户端注册 GTA5VehicleAI
- `RetroRegisterExistingVehicles()`：处理 Vehicle.OnInit 先于 GTA5TrafficSystem 的时序问题

---

## 待完善

### P1 — 变道安全检查增强

**现状**：基础变道可用（5 态 FSM），安全检查仅查距离。

**可优化**：
- 增加速度预测（t+2s 位置估算），避免高速追尾
- 变道执行中持续监测目标车道，发现危险中止变道

### P1 — 绕行重路由

**现状**：`AvoidanceUpgradeChain` 进入 Reroute 态后直接重置，未触发 A* 绕行。

**可优化**：
- 在 `GTA5VehicleAI.UpdateAI()` 中检测 Reroute 态时调用 `TrafficPathfinder` 重新寻路
- 屏蔽当前堵塞节点 30s，选择替代路径

### P2 — 动态密度管理

**未开始**：
- 视线外生成（玩家看不到的方向优先生成）
- `road_type` 车型权重（主干道大车多，支路小车多）
- 限速区（`SpeedZoneData` 协议已定义，待接入）
