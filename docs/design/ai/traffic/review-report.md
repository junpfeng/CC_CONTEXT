# 交通 AI 设计方案 — 审查报告

> 审查范围：system-design.md、protocol.md、server.md、client.md、tasks.md
> 审查基线：P1GoServer 服务端代码 + freelifeclient 客户端代码
> 审查日期：2026-03-19

---

## 一、严重问题（必须修改，影响正确性或可行性）

### S-1. JunctionCommand 枚举零值语义危险

**位置**：protocol.md §1 JunctionCommand

**问题**：`JC_GO = 0` 是 protobuf 默认零值。任何未初始化的 JunctionCommand 字段都会被解读为"通行"，可能导致车辆在路口不停车直接通过。

**修改建议**：将零值改为安全的默认状态：
```protobuf
enum JunctionCommand {
  JC_NOT_ON_JUNCTION = 0;  // 安全默认值（不在路口）
  JC_GO = 1;
  JC_APPROACHING = 2;
  JC_WAIT_FOR_LIGHTS = 3;
  JC_WAIT_FOR_TRAFFIC = 4;
  JC_GIVE_WAY = 5;
}
```

---

### S-2. 服务端 DriverPersonalityComp 与 Proto 字段不一致

**位置**：server.md §2 vs protocol.md §2 DriverPersonalityData

**问题**：Proto 定义了 16 个字段，但服务端 Go 结构体只有 14 个，缺少：
- `RollsThroughStopSigns`（bool）
- `UseTurnIndicators`（bool）

客户端 C# 有全部 16 个字段。三端字段不一致会导致序列化/反序列化静默丢弃数据。

**修改建议**：服务端 Go 结构体补齐缺失的 2 个字段。

---

### S-3. SpeedZoneSyncNtf 缺少操作类型字段

**位置**：protocol.md §2 SpeedZoneSyncNtf vs system-design.md §审查修复 vs server.md §4

**问题**：system-design.md 审查报告建议"增量同步时携带操作类型（add/remove/update）"，server.md §4 也写了"增量同步携带操作类型"，但实际 Proto 消息 `SpeedZoneSyncNtf` 只有 `repeated SpeedZoneData zones`，**没有操作类型字段**。

当前 `SpeedZoneData.active` 字段只能区分"激活/去激活"，无法表达"新增/删除/更新"语义。

**修改建议**：
```protobuf
enum SpeedZoneOp {
  SZO_ADD = 0;
  SZO_REMOVE = 1;
  SZO_UPDATE = 2;
}

message SpeedZoneData {
  SpeedZoneOp op = 8;  // 新增操作类型
  // ... 现有字段
}
```
或简化：全量同步时不需要 op，增量同步时用 active=false 表示移除（当前设计已隐式支持，但需要在文档中明确语义约定）。

---

### S-4. 服务端 OnTrafficVehicle 显式拒绝 Town 场景（设计未提及）

**位置**：`P1GoServer/servers/scene_server/internal/net_func/vehicle/traffic_vehicle.go:25-63`

**问题**：现有 `OnTrafficVehicle` RPC handler 校验场景类型，**仅允许 City/Sakura，拒绝 Town/Dungeon**。设计文档中 TASK-11/12/15 均写"仅 City/Sakura 场景注入"，但用户明确要在 S1Town 实现交通系统。

**影响**：
- 即使客户端启用了交通系统，服务端也会拒绝 Town 场景的车辆创建请求
- 信号灯系统、限速区系统不会在 Town 场景注入
- 所有设计文档和任务清单中的场景范围需要修改

**修改建议**：
1. 全文档搜索"仅 City/Sakura"，改为"City/Sakura/Town"
2. `OnTrafficVehicle` 白名单加入 Town
3. 场景初始化注入逻辑加入 Town

---

### S-5. S1Town 路点数据格式与现有管线不兼容

**位置**：road-network.md §S1Town vs client.md §3.4 路点扩展

**问题**：设计中 CustomWaypoint 扩展字段（JunctionId、EntranceIndex、LaneIndex、AdjacentLaneWaypoints）基于 Miami 的平面数组格式。但 S1Town 的 `road_traffic_fl.json` 使用完全不同的**图结构**（nodes + links）：

| 字段 | Miami（平面数组） | S1Town（图结构） |
|------|-----------------|-----------------|
| OtherLanes | ✅ 每路点有 | ❌ 无此字段 |
| junction_id | ✅ 每路点有 | ✅ 每节点有 |
| cycle（信号相位） | ✅ 有 | ❌ 无 |
| 车道信息 | OtherLanes 索引 | links.lanes 数值 |
| 速度 | 无 | links.speed |

**影响**：
- GleyNav 的 `LoadRoadData()` 按 RoadPoint 平面数组解析 JSON，无法直接加载 S1Town 的 nodes+links 格式
- 变道功能依赖的 OtherLanes/AdjacentLaneWaypoints 在 S1Town 数据中不存在
- 需要**数据格式转换层**或**统一数据格式**

**修改建议**：
1. 编写 S1Town 数据转换工具：nodes+links → RoadPoint 平面数组格式
2. 或在 GleyNav 中新增图结构解析分支
3. 在设计文档中明确数据转换方案

---

### S-6. TASK-01 RPC 注册位置错误

**位置**：tasks.md TASK-01

**问题**：TASK-01 写"在 `service Logic` 中注册 `VehicleApproachJunction`、`VehicleLeaveJunction`"。但从代码基线看，现有车辆 RPC（`OnTrafficVehicle`）注册在 **scene_server** 的 `net_func/vehicle/` 下，不在 logic_server。

路口决策是场景级行为（依赖场景内信号灯系统），应注册在 scene_server。

**修改建议**：改为"在 scene_server 的 net_func/vehicle/ 中注册"。

---

## 二、中等问题（建议修改，影响健壮性或可维护性）

### M-1. TrafficAILodLevel 枚举定义在 Proto 中但无任何消息引用

**位置**：protocol.md §1

**问题**：审查修复已将 LOD 计算下放客户端，移除了 `TrafficAILodNtf`。但 `TrafficAILodLevel` 枚举仍留在 Proto 定义中，没有任何消息引用它——属于死代码。

**修改建议**：从 Proto 中移除此枚举，改为客户端本地 C# enum。

---

### M-2. CfgJunctionPhase 硬编码最多 4 个入口

**位置**：protocol.md §4 CfgJunctionPhase

**问题**：`Entrance0Cmd ~ Entrance3Cmd` 硬编码 4 列。Miami 有 295 个路口，入口数各异（T 型路口 3 入口、环岛可能 5+ 入口）。S1Town 有 119 个路口，同样会有非 4 入口的情况。

**修改建议**：改为纵表结构（每行一个入口）：

| 字段 | 说明 |
|------|------|
| Id | 自增 |
| JunctionId | 路口 ID |
| PhaseIndex | 相位序号 |
| EntranceIndex | 入口编号 |
| Command | 信号（TrafficLightCommand） |

这样任意入口数都能支持，且策划编辑更直观。

---

### M-3. 路口决策缺少超时回退机制

**位置**：client.md §3.3 JunctionDecisionFSM

**问题**：客户端上报 `VehicleApproachJunctionReq` 后进入 Approaching 状态，等待服务端下发 `JunctionCommandNtf`。如果丢包或服务端异常，客户端会永久停在 Approaching 状态（车辆卡死在路口前）。

**修改建议**：Approaching 状态加超时（如 3s），超时后回退为本地决策（读取已同步的信号灯状态自行判断），同时上报异常日志。

---

### M-4. remaining_ms 时间同步问题未落地到 FSM 设计

**位置**：system-design.md §审查报告 第 6 点 vs client.md §2.3

**问题**：审查报告明确建议"remaining_ms 仅用于表现（倒计时 UI），行为决策等待下一次 command 变化"。但 client.md 的 TrafficLightFSM 增强方案中没有体现这一约束——未说明 FSM 状态转移是由 command 变化触发还是由 remaining_ms 倒计时到零触发。

**修改建议**：在 client.md §2.3 明确：FSM 状态转移**仅响应 command 字段变化**，remaining_ms 仅驱动 UI 倒计时显示。

---

### M-5. 两套路点系统的数据流未厘清

**位置**：client.md §3.4 vs road-network.md §运行时系统架构

**问题**：运行时存在两套路点数据：
1. **GleyNav RoadPoint**：从 JSON 加载，字段包含 `junction_id`、`OtherLanes`、`cycle`
2. **WaypointGraph CustomWaypoint**：从 binary 加载，字段仅 `Id/Pos/nexts/prevs/CurrentState`

设计要求在 CustomWaypoint 新增 JunctionId/LaneIndex 等字段，但这些数据的源头在 GleyNav RoadPoint 中。设计未说明数据如何从 RoadPoint → CustomWaypoint 传递——是在 `TrafficWaypointsConverter` 转换时映射，还是序列化到 binary 中？

**修改建议**：在 client.md §3.4 补充数据映射链路：
```
GleyNav.RoadPoint (JSON)
  → TrafficWaypointsConverter / RoadPointsToTrafficWaypoints()
    → CustomWaypoint (runtime)
      新字段映射: junction_id → JunctionId, OtherLanes → AdjacentLaneWaypoints
```

---

### M-6. server.md §2 描述与实际语义矛盾

**位置**：server.md §2

**问题**：文档写"纯静态方法，不维护状态"，但 `DriverPersonalityComp` 是一个有 14 个字段的结构体，挂载到 Entity 上。虽然字段在创建后不变，但它不是"静态方法"——它是"只读组件"。

**修改建议**：改为"只读数据组件，创建时填充，运行期间不修改"。

---

## 三、轻微问题（建议改进，影响文档质量）

### L-1. system-design.md 审查报告中的修复标注不完整

**问题**：§审查报告标注了 8 个问题，部分标注"审查修复"但修复内容散落在各子文档中，缺少集中的修复确认清单。读者无法快速确认每个问题是否已落实。

**建议**：在审查报告末尾加"修复追踪表"（问题编号 → 修复位置 → 状态）。

---

### L-2. tasks.md 缺少 S1Town 专项任务

**问题**：所有任务针对 City/Sakura。S1Town 需要额外的前置任务：
- 数据格式转换（nodes+links → RoadPoint）
- 服务端场景白名单扩展
- 客户端 LoadScene.cs Town 分支（verification-todo.md 已有部分改动，需纳入任务体系）

**建议**：新增 TASK-00 级前置任务组。

---

### L-3. client.md 碰撞躲避 §4 状态命名与骨架不一致

**问题**：现有 `RCCAIAvoidFSM` 骨架中状态枚举为 `NavmeshFinding/WayPointFinding`，但设计重新定义为 `Idle/Swerve/EmergencyStop/Escalation`。应明确说明"废弃现有枚举，重新定义"，避免实现时混淆。

---

### L-4. 文档间交叉引用不完整

- server.md §5 AI LOD 定义了 Go 常量（`AL_LodEventScanning` 等），但这些常量与 client.md §5 的 LOD 枚举（`FULL/TIMESLICE/DUMMY/SUPER_DUMMY`）命名不一致
- client.md §6.1 变道 FSM 引用"复用 `VehicleAIContext.GetAForwardDynamicObjectBehindMe()`"，但该方法名暗示"检测后方物体"而非"前方慢车"，需确认方法实际语义

---

## 四、总结

| 级别 | 数量 | 核心关切 |
|------|------|---------|
| 严重（S） | 6 | 枚举零值安全、三端字段不一致、S1Town 场景和数据格式不兼容、RPC 注册位置 |
| 中等（M） | 6 | 死代码枚举、硬编码入口数、超时回退、时间同步、双路点系统数据流、描述矛盾 |
| 轻微（L） | 4 | 文档完整性、任务覆盖、命名一致性 |

**最核心的阻塞项**：S-4 + S-5（S1Town 场景支持）。

### 修复追踪表

| 问题 | 修复位置 | 状态 |
|------|---------|------|
| S-1 零值语义 | protocol.md §1 JunctionCommand | ✅ 已修复（JC_NOT_ON_JUNCTION=0） |
| S-2 三端字段不一致 | server.md §2 | ✅ Go 结构体已补齐 RollsThroughStopSigns + UseTurnIndicators |
| S-3 SpeedZone 缺操作类型 | protocol.md §2 | ✅ 已明确语义约定（active=true→upsert, active=false→移除） |
| S-4 Town 场景排斥 | server.md §8 + client.md §8 + road-network.md §启用步骤 | ✅ 设计已更新，客户端代码已改 |
| S-5 数据格式不兼容 | road-network.md §阶段四 + client.md §8.2 | ✅ 设计已更新（GleyNav 加载层适配） |
| S-6 RPC 注册位置 | tasks.md TASK-01 | ✅ 已修正为 scene_server net_func/vehicle/ |
| M-1 死枚举 | protocol.md §1 | ✅ 已从 Proto 移除，改为客户端本地 enum |
| M-2 硬编码 4 入口 | protocol.md §4 CfgJunctionPhase | ✅ 已改为纵表结构（每行一入口） |
| M-3 路口决策超时 | client.md §8.4 | ✅ 已补充无灯路口+超时回退 |
| M-4 remaining_ms 语义 | client.md §2.3 | ✅ 已明确：FSM 仅响应 command 变化，remaining_ms 仅驱动 UI |
| M-5 双路点系统数据流 | client.md §3.4 | ✅ 已补充 RoadPoint → CustomWaypoint 映射链路 |
| M-6 描述矛盾 | server.md §2 | ✅ 已修正为"只读数据组件" |

---

## 五、S1Town 适配审查补充（2026-03-19）

### 技术路线决策

S1Town 采用**轻量方案**（GleyNav + 非 ECS 车辆 AI），不搭建 DotsCity 场景。理由：
- 小镇交通密度低，非 ECS 性能足够
- 车辆 AI 已有独立于 DotsCity 的完整路径
- 避免 Hub.prefab + EntitySubScene 的搭建工作

### 新增适配问题

| # | 问题 | 严重度 | 修复方案 |
|---|------|--------|---------|
| T-1 | LOD 阈值硬编码，300m 覆盖小镇全图 | 中等 | 新增 `CfgTrafficSceneProfile`，LOD 阈值按场景配置 |
| T-2 | 碰撞/侧闪参数按大地图设计 | 中等 | 同 T-1，参数配置化 |
| T-3 | S1Town 大量无灯路口 | 中等 | JunctionDecisionFSM 增加无灯路口路径（减速通过/让行） |
| T-4 | nodes+links 数据缺 OtherLanes | 低（P1变道） | 转换时从 links.lanes 推导平行车道关系 |
| T-5 | S1Town links.speed 全为 0 | 低 | road_type 映射默认限速，后续可在 CfgSpeedZone 补充 |

### 已完成的改动

- 客户端 LoadScene.cs：Town 走独立分支（加载路点，跳过 DotsCity）
- 配置表 scene.xlsx：S1Town UseTrafficSystem=TRUE, WaypointFile=road_traffic_fl.json
- 路点数据 road_traffic_fl.json 已部署到 PackResources

### 待验证

进入 S1Town Play 模式验证路点加载是否成功（见 [verification-todo.md](verification-todo.md)）
