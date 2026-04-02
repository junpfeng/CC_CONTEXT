# 交通系统技术方案对比：GTA5 vs 大世界（樱花校园） vs 小镇

## 1. 概述

本文对比三个交通系统的技术实现，为《五星好市民》交通系统迭代提供参考。

| 系统 | 定位 | 技术栈 | 复杂度 |
|------|------|--------|--------|
| **GTA5** | 3A 开放世界标杆（逆向参考） | C++ / RAGE 引擎 | 极高（~2.5MB 车辆 AI 源码） |
| **大世界 Miami/Sakura** | 本项目主场景交通 | Unity C# + DotsCity ECS + gRPC | 高（服务端仲裁 + 客户端执行） |
| **小镇 S1Town** | 本项目副场景轻量交通 | Unity C# 纯客户端直驱 | 低（固定轨迹巡航） |

**对比维度**：架构模式、路网数据、车辆生成、AI 决策、驾驶人格、信号灯、碰撞躲避、性能优化。

> **Sakura（樱花校园）** 是 Miami 大世界的美术换皮版本（配置 ID=23），交通系统代码和路网数据完全共享，下文统称"大世界"。

## 2. 架构总览

| 维度 | GTA5 | 大世界（Miami/Sakura） | 小镇（S1Town） |
|------|------|----------------------|----------------|
| **架构模式** | 纯客户端单机 | 服务端仲裁 + 客户端执行 | 客户端直驱（服务端仅创建实体） |
| **核心引擎** | RAGE（C++） | DotsCity ECS + GleyNav | 自研 Catmull-Rom 样条 |
| **路网规模** | 大型节点图 + 流式加载 | 50,523 路点（24MB） | 484 路点 → 15 条预配置路线 |
| **车辆密度** | 数百辆（LOD 分级） | 高密度（ECS 驱动） | 最多 15 辆 |
| **AI 复杂度** | 极高（218KB 状态机 + PID） | 高（4 层 FSM 仲裁） | 无 AI（固定轨迹） |
| **信号灯** | 8 种指令 + 路口入口系统 | 5 种状态 + 服务端相位计时 | 无 |
| **碰撞躲避** | 侧闪 + 碰撞追踪 | 侧闪→制动→鸣笛→绕行 | 无 |
| **人格系统** | 17 参数静态查表 | 17 参数服务端下发 | 无（统一参数） |
| **性能优化** | 4 级 AI LOD + 流式加载 | 4 级 LOD + 增量广播 | 距离剔除 + 间隔 Raycast |

### 架构图

```
GTA5:
  CVehiclePopulation(密度) → CarGen(生成) → Pathfind(寻路) → VehicleIntelligence(决策) → PID(控制)
                                                                    ↑
                                                          DriverPersonality(人格) + Junctions(路口)

大世界:
  服务端: TrafficLightSystem + SpeedZoneSystem + JunctionSystem → gRPC 广播
  客户端: DotsCity ECS(物理) + 4层FSM(决策) + AI LOD(优化)

小镇:
  客户端: TownTrafficSpawner(生成) → 服务端创建实体 → TownTrafficMover(Catmull-Rom 巡航)
```

## 3. 路网与数据结构

### GTA5

- **结构**：节点图（`pathfind.h`），单节点最多 32 条边（`PF_MAXLINKSPERNODE`）
- **流式加载**：围绕玩家 1765m 范围实时加载路网（`STREAMING_PATH_NODES_DIST_PLAYER`），异步加载 150m
- **节点切换**：支持矩形/有向线段区域动态开关路网节点（任务系统用）
- **寻路**：BFS/A* 基于节点图，单对象最多占 12 个节点

### 大世界（Miami/Sakura）

- **结构**：RoadPoint 平面数组，50,523 路点，24MB JSON
- **路点 Schema**：
  ```json
  {
    "listIndex": 0,
    "position": {"x": 36.19, "y": 513.0, "z": -165.82},
    "neighbors": [1, 2],      // 后继路点（前进方向）
    "prev": [],               // 前驱路点
    "OtherLanes": [409],      // 平行车道（变道基础）
    "junction_id": 0,         // 路口归属
    "cycle": 0,               // 信号灯相位
    "road_type": 2            // 道路类型
  }
  ```
- **加载方式**：GleyNav 按配置表 `waypointFile` 字段动态选择 JSON，一次性加载
- **路口规模**：295 个路口，29% 路点有平行车道（`OtherLanes`）

### 小镇（S1Town）

- **原始路网**：`road_traffic_gley.json`，484 路点，nodes+links 图结构，Y 坐标固定 513.0
- **预配置路线**：`traffic_routes.json`，15 条环形巡航路线（从路网离线提取）
- **路线 Schema**：
  ```json
  {
    "routes": [
      { "world_points": [{"x": -94.1, "z": 104.64}, ...] }
    ]
  }
  ```
- **生成工具**：`gen_cruise_routes.py` — 无向图 Dijkstra 寻路 + 4 步后处理（去重→消锯齿→删>120°折返→删短段）
- **关键约束**：双车道路网无向寻路后**必须**后处理消除折返，Catmull-Rom 对 >120° 转折极敏感

## 4. 车辆生成与生命周期

### GTA5

- **密度管理**：`CVehiclePopulation` 计算路网链接密度和视觉空间，动态调节
- **生成系统**：`CarGen`（186KB 源码）
  - 11 种创建规则：ALL / ONLY_SPORTS / NO_BIG / ONLY_BIKES / ONLY_DELIVERY / BOATS 等
  - 13bit 标志位：强制生成、忽略密度、警察/消防/救护专用、昼夜限制、低优先级等
  - 脚本生成上限 80 个，生成队列 32 个
  - 支持 trailer 分配、内部代理绑定、链式场景
- **消亡**：14+ 种从链接移除原因标志，基于距离/密度/脚本指令

### 大世界（Miami/Sakura）

- **生成**：服务端创建车辆实体，DotsCity ECS 接管物理和 AI
- **人格分配**：服务端通过 `VehiclePersonalityNtf` 下发驾驶人格参数
- **生命周期**：ECS 系统管理，支持 AOI 进出的流式加载

### 小镇（S1Town）

- **生成**：`TownTrafficSpawner` 每 2 秒生成 1 辆，上限 15 辆
  - 20 种可用车型（配置 ID 300101-302001）
  - 客户端发 RPC → 服务端 `OnTrafficVehicle` 创建实体 → 客户端分配路线
- **路线分配**：按车辆位置 XZ 平方距离匹配最近未分配路线（`FindClosestRoute`）
- **消亡**：`NeedAutoVanish=false`，不自动消失，由客户端管理
- **贴地**：Raycast 从 Y=50 向下检测（layer 6），碰撞点 + 0.3m

## 5. 车辆 AI 决策

### GTA5

- **核心**：`VehicleIntelligence`（218KB C++ + 40KB 头文件），单文件即超过大多数项目全部 AI 代码
- **路口决策状态机**（6 态）：
  - `GO` — 通行 | `APPROACHING` — 接近 | `WAIT_FOR_LIGHTS` — 等红灯
  - `WAIT_FOR_TRAFFIC` — 让行等间隙 | `NOT_ON_JUNCTION` — 不在路口 | `GIVE_WAY` — 强制让行
- **路口通道过滤**：LEFT / MIDDLE / RIGHT，决定通行方向
- **控制输出**：PID 闭环控制器（`CVehPIDController`）→ 转向 + 油门
- **碰撞闪避**：侧闪持续 2500ms，超时恢复

### 大世界（Miami/Sakura）

- **4 层 FSM 优先级仲裁**（高→低）：
  1. `JunctionDecisionFSM` — 路口指令驱动（服务端下发 6 种指令）
  2. `RCCAIAvoidFSM` — 碰撞躲避（侧闪→紧急制动→鸣笛→绕行）
  3. `LaneChangeFSM` — 变道（前方慢车检测 + 相邻车道可用性）
  4. `RCCTrafficStrategyFSM` — 常规巡航（含 TrafficLightFSM + GiveWayFSM）
- **实现**：`VehicleAIPathPlanningComponent` 维护策略列表，FixedUpdate 从高到低评估 `ShouldActivate()`
- **服务端配合**：路口指令通过 `JunctionCommandNtf` 下发，客户端仅执行不决策

### 小镇（S1Town）

- **无 AI 决策**，车辆沿预配置路线匀速行驶
- **运动控制**：`TownTrafficMover` — Catmull-Rom 样条插值
  - 默认速度 11 m/s（≈40 km/h）
  - 弯道减速：角度 > 25° 时触发，最低 55% 原速，减速快（8f）加速慢（2f）
  - 旋转方向：样条切线（`CatmullRomDerivative`），非帧差分
  - 路点预处理：合并 <1.5m 近邻点

## 6. 驾驶人格系统

### GTA5

`DriverPersonality`（21KB）— 纯静态查表，按 NPC/车辆类型返回 17 参数：

| 类别 | 参数 |
|------|------|
| 速度控制 | 驾驶技术、激进度、最大油门、巡航速度 |
| 跟车距离 | 停车距离、减速触发距离、与行人间距 |
| 红灯行为 | 闯黄灯、无视停车标志、缓行通过、起步延迟 |
| 变道策略 | 主动变道、转向灯使用、摩托车穿梭 |
| 鸣笛反应 | 对他车和行人的响应 |

### 大世界（Miami/Sakura）

参考 GTA5 逆向结果，实现同样的 17 参数体系：
- 服务端通过 `VehiclePersonalityNtf` 下发人格参数
- 参数作为 AnimationCurve 的调制因子（乘数/偏移），不替代现有曲线
- 限速区：取 `min(DriverPersonality.MaxCruiseSpeed, SpeedZone.Limit)`

### 小镇（S1Town）

无人格系统，所有车辆使用统一参数：
- 速度：11 m/s（固定）
- 弯道减速：25° 阈值，最低 55%
- 无跟车、无变道、无红灯行为

## 7. 信号灯与路口

### GTA5

- **信号指令**（8 种）：STOP / AMBERLIGHT / GO / FILTER_LEFT / FILTER_RIGHT / FILTER_MIDDLE / PED_WALK / DONTWALK
- **路口入口**（`CJunctionEntrance`）：
  - 单路口最多 16 个入口（`MAX_ROADS_INTO_JUNCTION`）
  - 每入口：位置、方向、停车线距离、排队车数（8bit）、信号相位（4bit）、左转专用相位
  - 标志：右转红灯通行、车道限制、让行、断电
- **铁路道口**：独立灯状态（关闭/左闪烁/右闪烁）
- **容量**：8 信号灯位置/路口，8 路网节点/路口

### 大世界（Miami/Sakura）

- **信号状态**（5 种）：CanPass / Standby / Amber / Arrow / PedestrianCrossing
- **实现链路**：
  ```
  服务端 TrafficLightSystem（相位计时器）
    → TrafficLightStateNtf（AOI 广播，仅状态变化时）
    → 客户端 TrafficLightSyncAdapter → CustomWaypoint.CurrentState → 场景灯光
  ```
- **路口决策**：服务端 6 种指令（GO/APPROACHING/WAIT_FOR_LIGHTS/WAIT_FOR_TRAFFIC/GIVE_WAY/NOT_ON_JUNCTION）
- **关键约束**：客户端仅响应 command 变化，不依赖 remaining_ms 倒计时
- **路口数**：295 个（Miami/Sakura 共享）

### 小镇（S1Town）

- **无信号灯系统**，无路口决策
- 大量无灯路口（41.7% 单车道），如需升级需新增 `IsGiveWay` 标记

## 8. 碰撞躲避与避让

### GTA5

- **侧闪**：检测障碍后横向闪避，持续 2500ms，超时恢复路径
- **玩家碰撞追踪**：记录与玩家碰撞时间戳，影响后续反应
- **飞行器**：独立 3D 空间避碰系统（`FlyingVehicleAvoidance`，30KB）

### 大世界（Miami/Sakura）

`RCCAIAvoidFSM` 4 态升级链：
1. **Idle** — 前方 9m 检测障碍
2. **Swerve** — 侧闪 2500ms（Town 缩短为 1500ms）
3. **EmergencyStop** — 紧急制动
4. **Escalation** — >3s 鸣笛，>5s 绕行（Navmesh 寻路）

人格影响：`Aggressiveness` 调节灵敏度、容忍时间、鸣笛间隔

**GiveWayFSM**（既有）：9m 检测，通行时间 <3s 触发等待，5s 超时强制超车

### 小镇（S1Town）

- **无碰撞躲避**，车辆沿固定轨迹行驶，可穿越障碍物
- 如需升级，建议复用大世界的 RCCAIAvoidFSM 框架，缩小检测参数

## 9. 性能优化

### GTA5

| 手段 | 细节 |
|------|------|
| **AI LOD 4 级** | Full → TimeSlice（分帧）→ Dummy（仅物理）→ SuperDummy（仅路径跟随） |
| **路网流式加载** | 玩家周围 1765m 实时加载，异步 150m |
| **任务保护** | 任务车辆禁止降级为 Dummy/SuperDummy |
| **停泊跳过** | 停止/停泊车辆不更新 AI |
| **限速区容量** | 全局最多 220 个（`MAX_ROAD_SPEED_ZONES`） |
| **生成队列** | 最多 32 辆同时排队创建 |

### 大世界（Miami/Sakura）

| 手段 | 细节 |
|------|------|
| **AI LOD 4 级** | FULL(<50m) → TIMESLICE(50-150m, 每 3 帧) → DUMMY(150-300m, 每 10 帧) → SUPER_DUMMY(>300m, 每 30 帧) |
| **信号灯增量广播** | 仅状态变化时 AOI 广播，非定时推送 |
| **AI 时间分片** | TIMESLICE 模式分散到多帧避免帧卡顿 |
| **限速区增量同步** | AOI 进入全量 → 后续仅增量 |
| **函数开关** | `EnableTrafficAI` 配置表标志，灰度启用 |

### 小镇（S1Town）

| 手段 | 细节 |
|------|------|
| **距离剔除** | 显示 200m / 隐藏 220m（滞后带消除边缘闪烁） |
| **间隔 Raycast** | 每 5 帧一次贴地检测，Y 轴 Lerp 平滑（速度 5.0） |
| **路点预过滤** | Init 时合并 <1.5m 短段（路点从 ~130 降至 ~65） |
| **弯道角预计算** | `PrecomputeAngles` 一次性计算，运行时查表 |
| **安全限制** | 单帧最多跨 3 段 + segmentLength 下限 0.1m |
| **高度保护** | 新高度与目标差 >8m 时拒绝更新 |

## 10. 总结

### 完整维度对比

| 维度 | GTA5 | 大世界（Miami/Sakura） | 小镇（S1Town） |
|------|------|----------------------|----------------|
| 架构 | 纯客户端 C++ | C-S 混合（服务端仲裁） | 客户端直驱 |
| 路网 | 节点图 + 流式加载 | 50K RoadPoint 平面数组 | 484 路点 → 15 条预配置路线 |
| 车辆上限 | 数百（密度动态调节） | 高密度（ECS） | 15 辆 |
| 生成策略 | 11 种规则 + 密度计算 | 服务端实体 + ECS | 每 2 秒 1 辆，位置匹配路线 |
| AI 决策 | 6 态路口 + PID 控制 | 4 层 FSM 仲裁 | 无（固定轨迹） |
| 驾驶人格 | 17 参数查表 | 17 参数服务端下发 | 无 |
| 信号灯 | 8 种指令 | 5 种状态 + AOI 广播 | 无 |
| 碰撞躲避 | 侧闪 + 碰撞追踪 | 4 态升级链 | 无 |
| 性能优化 | 4 级 LOD + 流式加载 | 4 级 LOD + 增量同步 | 距离剔除 + 间隔 Raycast |
| 变道 | DriverPersonality 驱动 | LaneChangeFSM（P1） | 无 |
| 限速区 | 球形触发（220 上限） | 球形触发 + AOI 同步 | 无 |

### 技术选型启示

1. **小镇当前方案合理**：15 辆车 + 固定轨迹已满足小地图的表现需求，无需上 ECS
2. **升级路径清晰**：如需提升小镇交通品质，可逐步引入：
   - P1：碰撞躲避（复用 `RCCAIAvoidFSM`，缩小参数）
   - P2：信号灯（需补路口数据 + 服务端 `TrafficLightSystem` 支持）
   - P3：驾驶人格（差异化车辆行为）
3. **GTA5 参考价值**：路口决策 6 态机、AI LOD 4 级分层、限速区系统均已在大世界方案中落地
4. **关键差异点**：GTA5 是纯客户端单机方案，P1 需要多人同步，因此将路口决策和人格分配上移到服务端是正确选择
