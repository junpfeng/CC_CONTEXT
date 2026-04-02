# 交通 AI 系统设计方案

> ⚠️ **注意**：本文档为早期通用设计方案。S1Town 小镇已采用轻量方案（仅 TownTrafficMover + TownTrafficSpawner），不含信号灯/限速区/JunctionDecisionFSM。大世界 GTA5 级交通系统的正式设计见 [`big_world_traffic/`](../big_world_traffic/README.md)。
>
> 参考：`E:\workspace\PRJ\GTA\GTA5\docs\design\交通AI需求.md`
> 载具系统现状：[server-vehicle.md](../../../knowledge/server-vehicle.md) / [client-vehicle.md](../../../knowledge/client-vehicle.md)

## 1. 需求回顾

参考 GTA5 交通 AI 源码逆向，为《五星好市民》实现 NPC 车辆交通 AI 系统。

### 1.0 目标场景

| 场景 | 配置ID | 路点文件 | 路点数 | 路口数 | 覆盖面积 | 交通方案 |
|------|--------|---------|--------|--------|---------|---------|
| **Miami（大世界）** | 16 | road_traffic_miami.json | 50,523 | 295 | ~5400万 | DotsCity + GleyNav |
| **Sakura（樱花校园）** | 23 | road_traffic_miami.json（换皮） | 同上 | 同上 | 同上 | 同上 |
| **S1Town（小镇）** | 22 | road_traffic_fl.json | 12,359 | 119 | ~501万 | **轻量方案**（GleyNav + 非 ECS 车辆 AI） |

> **S1Town 技术路线**：小镇走轻量方案——跳过 DotsCity，仅用 GleyNav 加载路点 + `VehicleAIPathPlanningComponent` 驱动车辆 AI。详见 [road-network.md](road-network.md) §启用步骤。

#### S1Town 与 City 的关键差异

| 维度 | City/Sakura | S1Town | 设计影响 |
|------|------------|--------|---------|
| 地图面积 | ~5400万单位² | ~501万单位²（1/10） | LOD 阈值需缩小 |
| 路点数据格式 | RoadPoint 平面数组 | nodes+links 图结构 | 需数据格式转换 |
| 车道分布 | 29% 多车道 | 41.7% 单车道 | 变道场景少 |
| 交通密度 | 高（DotsCity ECS 驱动） | 低（非 ECS，数十辆级） | 性能约束宽松 |
| 道路类型 | 宽阔主干道为主 | 窄路+T型路口居多 | 碰撞参数需调小 |
| 信号灯 | 绝大多数路口有灯 | 大量无灯路口（让行为主） | GiveWay 权重提升 |

### 1.1 现有实现基线

| 子系统 | 现状 | 技术栈 |
|--------|------|--------|
| 路点导航 | Houdini 生成 → 二进制序列化（`trafficWaypoints.bytes`） | 自研 `WaypointManager` + `CustomWaypoint` |
| 信号灯 | Gley DotsCity 插件驱动，编辑器预设时序，**只有二值状态**（CanPass/Standby），**无黄灯/倒计时/网络同步** | `TrafficLightsIntersection`（Gley） |
| 避让 | `GiveWayFSM`：9m 检测距离，通行时间 < 3s 触发，5s 超时强制超车 | 自研 FSM |
| 碰撞检测 | `VehicleAIContext`：前向矩形区域（2.4m 宽 × 可变深度），检测车辆/怪物/行人/玩家 | 自研 |
| 驾驶风格 | `VehicleDriverStyleData`（ScriptableObject）：4 维 AnimationCurve（distance/dir × speed/steer），**非数值参数** | Unity ScriptableObject |
| FSM 协调 | `RCCTrafficStrategyFSM` > `TrafficLightFSM` > `ChaseTarget`，**无显式优先级框架** | 自研多策略 |
| NPC 物理权限 | `VehicleNetMarkFSM`：`LocalNpc`（上行物理）/ `RemoteNpc`（下行 Kinematic） | 自研 |
| 服务端 | 仅状态仲裁（座位/锁/门/喇叭），**无驾驶 AI、无信号灯、无路口逻辑** | ECS |

### 1.2 需求模块与优先级

| 模块 | 优先级 | GTA5 参考 | P1 适配要点 |
|------|--------|----------|------------|
| **驾驶人格** | P0 | 纯数值参数查表 | 需兼容现有 AnimationCurve 体系：人格参数叠加到曲线输出上，而非替代曲线 |
| **信号灯服务端权威** | P0 | 8 种信号状态 + 相位序列 | 需替换 Gley 本地计时 → 服务端广播驱动；保留 Gley 视觉组件，仅替换数据源 |
| **路口决策** | P0 | 6 种 JunctionCommand | 新增 `JunctionDecisionFSM`，需设计 FSM 优先级框架解决与现有 FSM 的协调 |
| **限速区** | P0 | 球形触发区 220 个上限 | 服务端管理，客户端与人格巡航速度取 min |
| **碰撞躲避增强** | P0 | 侧闪 2500ms + 碰撞升级 | 扩展现有 `RCCAIAvoidFSM`，增加侧向偏移和升级逻辑 |
| **AI LOD** | P1 | 4 级降级 | 纯客户端计算（距离已知），无需服务端参与 |
| **变道** | P1 | 主动变道 + 转向灯 | 新增 `LaneChangeFSM`，需路点网络支持多车道查询 |
| **鸣笛交互** | P1 | 催促/响应/行人鸣笛 | 复用现有 `VehicleHonkingComp` + `StartCarHorn/StopCarHorn` 协议 |
| 飞行器躲避 | P2 | 三维空间避障 | 暂缓 |
| 车辆任务行为 | P2 | 追逐/护送/逃跑 | 暂缓 |
| 场景化交通 | P2 | 密度/车型分布/时段 | 暂缓 |

### 1.3 关键技术约束

1. **信号灯视觉驱动**：项目路点系统是自研 `WaypointGraph`（非 Gley 插件）。信号灯数据源从本地静态设置改为服务端状态驱动 `CustomWaypoint.CurrentState`。信号灯视觉效果（红绿灯模型切换）由新增 `TrafficLightSyncAdapter` 直接驱动场景灯光对象
2. **驾驶风格兼容**：现有 `VehicleDriverStyleData` 用 AnimationCurve 控制速度/转向曲线。人格参数应作为**曲线输出的乘数/偏移量**（如 `finalSpeed = curve.Evaluate(t) * personality.MaxCruiseSpeed / defaultCruiseSpeed`），不改动曲线本身
3. **FSM 优先级框架**：当前 FSM 切换由 `VehicleAIPathPlanningComponent` 硬编码控制。新增 FSM 后需引入 4 层优先级机制：`JunctionDecision > RCCAIAvoid > LaneChange > RCCTraffic`（`TrafficLightFSM`/`GiveWayFSM` 保持为 `RCCTrafficStrategyFSM` 的内部组件，不升级为独立策略）
4. **路点网络扩展**：现有 `CustomWaypoint` 无车道编号字段。变道功能（P1）需要路点网络支持多车道标识（`laneIndex`）和相邻车道查询
5. **信号灯状态扩展**：现有 `TrafficWaypointState` 只有 `CanPass/Standby`。需扩展为完整的 `TrafficLightCommand`（8 种状态），包括黄灯、方向箭头、行人信号
6. **S1Town 数据格式转换**：S1Town 路点数据（`road_traffic_fl.json`）采用 nodes+links 图结构，与 Miami 的 RoadPoint 平面数组格式不同。GleyNav 按 `List<RoadPoint>` 反序列化，需在加载层增加格式适配（转换 nodes+links → RoadPoint，补充 neighbors/prev/OtherLanes 字段）
7. **场景参数配置化**：LOD 阈值、碰撞检测距离、侧闪时长等核心参数不能硬编码，需按场景 profile 配置（小镇参数整体缩小）

## 2. 架构设计

### 2.1 系统边界与职责划分

**核心原则**：延续现有架构——服务端是状态仲裁者，客户端负责物理和 AI 执行。

| 职责 | 服务端（P1GoServer） | 客户端（freelifeclient） |
|------|---------------------|------------------------|
| 驾驶人格 | 按车辆/NPC 类型分配人格参数，下发给客户端 | 接收人格参数，驱动 AI 行为阈值 |
| 信号灯 | 管理信号灯状态机（相位切换、计时），广播状态 | 接收信号灯状态，FSM 响应（停车/通行/闯灯） |
| 限速区 | 创建/管理限速区，广播给客户端 | 接收限速区数据，与巡航速度取 min |
| 路口决策 | 维护路口入口数据（排队数、相位），下发指令 | 执行路口决策状态机（等待/通行/让行） |
| AI LOD | —（客户端自主计算） | 本地计算距离，按 LOD 等级降级 AI 计算和表现 |
| 碰撞躲避 | 无（客户端物理感知） | 扩展现有 RCCAIAvoidFSM，增加侧闪和升级逻辑 |
| 变道/鸣笛 | 无（纯客户端行为） | 新增变道 FSM + 鸣笛交互逻辑 |
| 物理/PID | 不运行物理 | 现有 IVehicleControl + PID 增强 |

### 2.2 数据流总览

```
服务端                              协议                           客户端
┌──────────────────┐                                    ┌──────────────────────┐
│ TrafficLightMgr  │ ─── TrafficLightStateNtf ────────→ │ TrafficLightFSM      │
│ (信号灯管理)      │                                    │ (信号灯响应)          │
├──────────────────┤                                    ├──────────────────────┤
│ SpeedZoneMgr     │ ─── SpeedZoneSyncNtf ────────────→ │ SpeedZoneComp        │
│ (限速区管理)      │                                    │ (限速约束)            │
├──────────────────┤                                    ├──────────────────────┤
│ JunctionMgr      │ ─── JunctionCommandNtf ──────────→ │ JunctionDecisionFSM  │
│ (路口管理)        │                                    │ (路口决策)            │
├──────────────────┤                                    ├──────────────────────┤
│ DriverPersonality│ ─── VehiclePersonalityNtf ───────→ │ DriverPersonalityComp│
│ (人格分配)        │                                    │ (行为阈值)            │
└──────────────────┘                                    ├──────────────────────┤
                                                        │ VehicleAILodComp     │
                                                        │ (AI 降级，纯客户端)    │
                                                        └──────────────────────┘
                                                         │
                                                         ↓ 驱动
                                                  ┌──────────────────────┐
                                                  │ 现有 AI FSM 体系      │
                                                  │ CarAI → PathPlanning │
                                                  │ → Strategy FSMs      │
                                                  └──────────────────────┘
```

### 2.3 与现有系统的关系

| 现有系统 | 交互方式 | 说明 |
|---------|---------|------|
| TrafficVehicleComp (服务端) | 扩展字段 | 新增 PersonalityId |
| traffic_vehicle_system (服务端) | 扩展 Tick | 新增信号灯计时 |
| VehicleAIComp (客户端) | 注入参数 | 人格参数驱动 FSM 阈值 |
| TrafficLightFSM (客户端) | 增强逻辑 | 从服务端接收状态替代本地模拟 |
| RCCTrafficStrategyFSM (客户端) | 增强 | 集成限速区、路口决策 |
| VehicleNetTransformComp (客户端) | 复用 | LOD 降级时切换同步频率 |

## 3. 协议设计（old_proto）

> 详见 [protocol.md](protocol.md)（枚举定义、消息结构、配置表字段）。

**要点摘要**：
- 4 个新枚举：`TrafficLightCommand`(8种信号)、`JunctionCommand`(6种指令)、`TrafficAILodLevel`(4级)、`DriverPersonalityType`(6种)
- 6 个新消息：`VehiclePersonalityNtf`(人格下发)、`TrafficLightStateNtf`(信号灯广播)、`SpeedZoneSyncNtf`(限速区同步)、`VehicleApproachJunctionReq/LeaveJunctionReq`(客户端上报)、`JunctionCommandNtf`(路口指令)
- **审查修复**：人格独立消息下发（非扩展 OnTrafficVehicleRes）、增加客户端路口上报机制、LOD 移除服务端通知

## 4. 服务端设计（P1GoServer）

> 详见 [server.md](server.md)（数据结构、Tick 逻辑、System 注册）。

**要点摘要**：
- **驾驶人格**：`DriverPersonalityComp` 挂载到交通车辆 Entity，车辆创建时从 `CfgVehicleBase.DefaultPersonality` → `CfgDriverPersonality` 查表填充
- **信号灯**：`TrafficLightSystem` 场景级单例，按相位序列 Tick 驱动，状态变化时 AOI 广播 `TrafficLightStateNtf`
- **限速区**：`SpeedZoneSystem` 固定容量数组（220上限），AOI 进入时增量同步
- **路口决策**：客户端上报 `VehicleApproachJunctionReq` → 服务端查信号灯+排队数 → 下发 `JunctionCommandNtf`
- **AI LOD**：完全下放客户端，服务端不参与（审查修复）
- **System 注册**：新增 `SystemType_TrafficLight`、`SystemType_SpeedZone`，City/Sakura/Town 场景注入

## 5. 客户端设计（freelifeclient）

> 详见 [client.md](client.md)（驾驶人格组件、信号灯适配、路口决策 FSM、碰撞躲避增强、AI LOD、变道与鸣笛）。

**要点摘要**：
- **驾驶人格**：`VehicleDriverPersonalityComp` 挂载到 Vehicle Controller，人格参数作为 AnimationCurve 输出的调制因子（乘数/偏移），不替代曲线
- **信号灯适配**：`TrafficLightSyncAdapter` 监听服务端 `TrafficLightStateNtf`，更新 `CustomWaypoint.CurrentState` 并驱动场景灯光对象；`TrafficLightFSM` 扩展为完整信号状态响应
- **FSM 优先级框架**：4 层优先级 `JunctionDecision > RCCAIAvoid > LaneChange > RCCTraffic`（TrafficLightFSM/GiveWayFSM 作为 RCCTraffic 内部组件），每帧从高到低评估 `ShouldActivate()`
- **路口决策**：新增 `JunctionDecisionFSM`，客户端检测路口入口上报 → 服务端下发指令 → FSM 执行
- **碰撞躲避**：扩展 `RCCAIAvoidFSM`，增加侧闪（2500ms）和碰撞升级逻辑
- **AI LOD**：客户端本地计算，4 级降级（FULL/TIMESLICE/DUMMY/SUPER_DUMMY），无需服务端参与
- **变道/鸣笛**：纯客户端行为，路点网络扩展 `LaneIndex` + `AdjacentLaneWaypoints`

## 6. 配置表设计

> 完整字段定义见 [protocol.md](protocol.md) §3（配置表设计）。

**新增 4 张表**：`CfgDriverPersonality`（人格参数17字段）、`CfgJunction`（路口配置）、`CfgJunctionPhase`（相位子表，替代 JSON 字符串）、`CfgSpeedZone`（限速区）

**现有表扩展**：`CfgVehicleBase` 新增 `DefaultPersonality` 字段（默认驾驶人格 ID）

## 7. 接口契约

### 7.1 协议 ↔ 服务端

| 协议消息 | 方向 | 触发时机 | 频率 |
|---------|------|---------|------|
| VehiclePersonalityNtf | S→C | 交通车辆创建后 | 低频 |
| TrafficLightStateNtf | S→C | 信号灯相位变化 | ~每 3-5s |
| SpeedZoneSyncNtf | S→C | 进入 AOI / 限速区增量变化 | 低频 |
| VehicleApproachJunctionReq | C→S | 车辆接近路口 | 低频 |
| VehicleLeaveJunctionReq | C→S | 车辆离开路口 | 低频 |
| JunctionCommandNtf | S→C | 收到 ApproachJunction 后 | 低频 |

### 7.2 服务端 ↔ 配置

- 信号灯系统初始化时加载 `CfgJunction` 配置
- 车辆生成时查 `CfgVehicleBase.DefaultPersonality` → `CfgDriverPersonality`
- 场景初始化时加载 `CfgSpeedZone`

### 7.3 客户端 ↔ 协议

- 客户端收到 `TrafficVehicleCreateData` 时初始化 `VehicleDriverPersonalityComp`
- 客户端收到 `TrafficLightStateNtf` 时更新本地信号灯缓存，供 `TrafficLightFSM` 查询
- 客户端本地计算 LOD 等级（距离判定），更新 `VehicleAILodComp`，调整 AI Tick 频率

## 8. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 信号灯广播频率过高 | 网络带宽 | 仅状态变化时广播 + AOI 过滤 |
| LOD 切换产生视觉跳变 | 体验 | 加过渡期（如 2s 内渐变） |
| 人格参数平衡性 | 可玩性 | 配置表驱动，可热更调参 |
| 客户端 FSM 复杂度增加 | 维护成本 | 新 FSM 独立实现，不修改现有 FSM 内部逻辑 |
| 现有交通车辆兼容性 | 回归 | 新系统通过功能开关控制（配置表 `EnableTrafficAI`） |
| 路口配置数据量大 | 开发成本 | 初期支持手动配置，后续开发编辑器工具 |
| S1Town 路点数据转换 | 数据完整性 | nodes+links → RoadPoint 转换需补充 OtherLanes/cycle 等字段，转换后校验路点连通性 |
| S1Town 参数不适配 | 体验 | LOD 阈值/碰撞距离/侧闪时长按场景 profile 配置化，小镇单独调参 |
| S1Town 无灯路口比例高 | 行为合理性 | JunctionDecisionFSM 增强 GiveWay 路径权重，无灯路口默认走让行逻辑 |

## 设计审查报告

> 审查日期：2026-03-13，审查依据：现有 P1GoServer ECS 架构 + 客户端 Vehicle AI 代码 + old_proto 协议

### 严重问题（必须修改）

**1. `TrafficVehicleCreateData` 扩展方式不可行**

设计中写"在现有 `OnTrafficVehicle` 响应中追加"，但实际协议是 `OnTrafficVehicleRes`，只有 `vehicle_entity` 一个字段。设计引用了一个不存在的 `TrafficVehicleCreateData` 消息。需要明确：是扩展 `OnTrafficVehicleRes` 加字段，还是新增一条独立的 `VehiclePersonalityNtf` 在车辆创建后单独下发。建议后者——独立消息解耦更好，且向后兼容。

**2. 路口决策服务端下发指令，但缺少客户端上报机制**

`JunctionCommandNtf` 按车辆粒度下发路口指令，但服务端不运行物理、不知道车辆精确位置，无法判断"车辆接近路口"这一触发条件。设计中仅提到 `VehicleAtJunctionReq` 用于排队计数，但触发路口决策本身的时机未设计。需要补充：客户端检测到接近路口时主动上报 `VehicleApproachJunctionReq`，服务端据此下发 `JunctionCommandNtf`；或者改为客户端自主决策路口行为（仅依赖已同步的信号灯状态），去掉服务端逐车指令。

**3. 信号灯系统设计为独立 System，但路径放在 `ecs/system/traffic_light/`，与现有 `TrafficVehicleSystem` 的单例注册模式不一致**

现有 ECS 中 System 类型通过 `common.SystemType` 枚举注册（见 `ecs.go`），设计中新增了 `TrafficLightSystem` 和 `SpeedZoneSystem` 两个场景级系统，但未提及枚举注册和场景初始化注入。需补充 `SystemType_TrafficLight`、`SystemType_SpeedZone` 的注册，以及在场景初始化时 `AddSystem` 的位置。

### 建议改进（推荐修改）

**4. LOD 计算开销：每 N 帧遍历所有交通车辆**

设计中 LOD 计算"每 30 帧遍历交通车辆，计算与最近玩家的距离"。交通车辆可能上百辆，每次全量遍历并发送 `TrafficAILodNtf`（repeated 消息）会产生带宽尖峰。建议：仅在 LOD 等级实际变化时才加入通知列表；或者将 LOD 计算下放到客户端（客户端知道自己和所有车辆的距离），服务端无需参与。

**5. `SpeedZoneSyncNtf` 全量同步方式粗糙**

"玩家进入 AOI 时全量同步"在限速区数量多（上限 220）时包体过大。建议：AOI 进入时只同步玩家可见范围内的限速区；增量同步时携带操作类型（add/remove/update）而非全量重发。

**6. 信号灯 `remaining_ms` 字段的时间同步问题**

`TrafficLightEntry.remaining_ms` 下发后，客户端需要本地倒计时。但网络延迟会导致客户端与服务端不同步（客户端看到还剩 500ms 时服务端已切相位）。建议：客户端收到 `remaining_ms` 后本地倒计时仅用于表现（如倒计时 UI），实际行为决策等待下一次 `TrafficLightStateNtf` 的 command 变化。

**7. 客户端 `VehicleDriverPersonalityComp` 继承 `Comp` 但缺少 Controller 注册说明**

根据项目约定，新 Comp 必须在 Controller.OnInit 中 AddComp。设计中未说明在哪个 Controller 注册，也未说明与现有 `VehicleDriverStyleData`（ScriptableObject）的迁移/共存策略。

**8. 配置表 `CfgJunction.PhaseSequence` 用 JSON 字符串不够规范**

Excel 配置表中嵌入 JSON 字符串不利于策划编辑和校验。建议拆为子表 `CfgJunctionPhase`（JunctionId + PhaseIndex + DurationMs + 各入口 Command），或用竖线分隔的简化格式。

### 确认无问题的部分

- **职责划分合理**：延续"服务端仲裁 + 客户端执行"的现有模式，信号灯状态由服务端权威管理是正确的
- **协议枚举设计完整**：`TrafficLightCommand`、`JunctionCommand`、`TrafficAILodLevel`、`DriverPersonalityType` 覆盖了 GTA5 参考文档中的核心状态，预留值合理
- **驾驶人格参数化**：配置表驱动、按车辆类型索引的设计合理，支持热更
- **风险与缓解措施**：功能开关 `EnableTrafficAI`、AOI 过滤、LOD 渐变过渡等措施到位
- **新 FSM 独立实现**：不侵入现有 FSM 内部逻辑，降低回归风险
- **碰撞躲避和变道设计为纯客户端行为**：符合"服务端不运行物理"的架构约束
