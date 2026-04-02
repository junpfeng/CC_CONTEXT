# 交通 AI — 协议与配置表设计

> **注意**：本文档针对 S1Town 小镇交通系统（轻量方案）。大世界交通系统（GTA5 式）请参阅 `design/ai/big_world_traffic/`。

> 总体设计见 [system-design.md](system-design.md)（需求回顾、架构总览、风险与审查报告）

## 1. 新增枚举

```protobuf
// 信号灯指令
enum TrafficLightCommand {
  TLC_INVALID = 0;
  TLC_STOP = 1;            // 红灯
  TLC_AMBER = 2;           // 黄灯
  TLC_GO = 3;              // 绿灯
  TLC_FILTER_LEFT = 4;     // 左转箭头
  TLC_FILTER_RIGHT = 5;    // 右转箭头
  TLC_FILTER_MIDDLE = 6;   // 直行箭头
  TLC_PED_WALK = 7;        // 行人通行
  TLC_PED_DONTWALK = 8;    // 行人禁行
}

// 路口决策指令（审查修复 S-1：零值改为安全默认）
enum JunctionCommand {
  JC_NOT_ON_JUNCTION = 0;      // 安全默认值（不在路口）
  JC_GO = 1;                    // 通行
  JC_APPROACHING = 2;           // 接近减速
  JC_WAIT_FOR_LIGHTS = 3;      // 等信号灯
  JC_WAIT_FOR_TRAFFIC = 4;     // 等交通间隙
  JC_GIVE_WAY = 5;              // 让行
}

// AI LOD 等级（审查修复 M-1：LOD 已下放客户端，此枚举从 Proto 移除，改为客户端本地 C# enum）
// 保留注释仅供参考：FULL(< 50m) / TIMESLICE(50-150m) / DUMMY(150-300m) / SUPER_DUMMY(> 300m)
// 距离阈值从 CfgTrafficSceneProfile 配置表读取，按场景差异化

// 驾驶人格类型
enum DriverPersonalityType {
  DPT_NORMAL = 0;       // 普通
  DPT_CAUTIOUS = 1;     // 谨慎
  DPT_AGGRESSIVE = 2;   // 激进
  DPT_TAXI = 3;         // 出租车
  DPT_BUS = 4;          // 公交
  DPT_TRUCK = 5;        // 卡车
}
```

## 2. 新增消息

```protobuf
// 驾驶人格参数（服务端 → 客户端，创建交通车辆时下发）
message DriverPersonalityData {
  DriverPersonalityType type = 1;
  float max_cruise_speed = 2;          // 巡航速度上限
  float max_accelerator_input = 3;     // 最大油门 [0-1]
  float corner_speed_modifier = 4;     // 转弯速度缩减系数
  float stop_distance_cars = 5;        // 与前车停车距离
  float slow_distance_cars = 6;        // 减速触发距离
  float stop_distance_peds = 7;        // 行人停车距离
  bool runs_amber_lights = 8;          // 是否闯黄灯
  bool runs_stop_signs = 9;            // 是否闯停车标志
  bool rolls_through_stop_signs = 10;  // 是否滚动通过停车标志
  uint32 green_light_delay_ms = 11;    // 绿灯起步延迟(ms)
  bool will_change_lanes = 12;         // 是否主动变道
  uint32 lane_change_cooldown_ms = 13; // 变道冷却(ms)
  bool use_turn_indicators = 14;       // 是否打转向灯
  float driver_ability = 15;           // 驾驶技术评级
  float aggressiveness = 16;           // 攻击性系数
}

// 信号灯状态通知（服务端 → 客户端，状态变化时广播）
message TrafficLightStateNtf {
  uint32 junction_id = 1;                     // 路口 ID
  repeated TrafficLightEntry lights = 2;       // 各入口的信号灯状态
}

message TrafficLightEntry {
  uint32 entrance_index = 1;                   // 入口编号
  TrafficLightCommand command = 2;             // 当前信号
  uint32 remaining_ms = 3;                     // 剩余时间(ms)
}

// 限速区同步（服务端 → 客户端）
message SpeedZoneSyncNtf {
  repeated SpeedZoneData zones = 1;
}

message SpeedZoneData {
  uint32 zone_id = 1;
  float center_x = 2;
  float center_y = 3;
  float center_z = 4;
  float radius = 5;
  float max_speed = 6;
  bool active = 7;       // 审查修复 S-3：active 字段语义约定见下
}

// SpeedZone 同步语义约定（审查修复 S-3）：
// - AOI 进入时：全量同步当前可见范围内所有 active=true 的限速区
// - 增量同步时：active=true 表示新增/更新（客户端按 zone_id upsert），active=false 表示移除
// - 客户端收到后按 zone_id 维护本地限速区集合
// P0 阶段使用隐式 active 方案；若未来需更细粒度控制，可新增 SpeedZoneOp 枚举

// 人格下发通知（服务端 → 客户端，车辆创建后独立下发，解耦现有 OnTrafficVehicleRes）
message VehiclePersonalityNtf {
  uint64 vehicle_entity_id = 1;
  DriverPersonalityData personality = 2;
}

// 客户端 → 服务端：车辆接近路口上报（触发路口决策）
message VehicleApproachJunctionReq {
  uint64 vehicle_entity_id = 1;
  uint32 junction_id = 2;
  uint32 entrance_index = 3;
}

// 客户端 → 服务端：车辆离开路口上报
message VehicleLeaveJunctionReq {
  uint64 vehicle_entity_id = 1;
  uint32 junction_id = 2;
}

// 服务端 → 客户端：路口指令通知（收到 ApproachJunction 后下发）
message JunctionCommandNtf {
  uint64 vehicle_entity_id = 1;
  uint32 junction_id = 2;
  JunctionCommand command = 3;
  uint32 entrance_index = 4;
}
```

> **审查修复**：
> 1. 人格下发改为独立 `VehiclePersonalityNtf`，不扩展 `OnTrafficVehicleRes`（向后兼容）
> 2. 路口决策增加客户端上报机制 `VehicleApproachJunctionReq/LeaveJunctionReq`，解决服务端不知车辆位置的问题
> 3. LOD 计算下放客户端自主执行（见客户端设计 §5），移除 `TrafficAILodNtf`

## 3. 现有消息扩展

无需扩展现有消息。人格数据通过独立 `VehiclePersonalityNtf` 下发。

## 4. 配置表设计

### 4.1 新增配置表

**CfgDriverPersonality**（驾驶人格配置）

| 字段 | 类型 | 说明 |
|------|------|------|
| Id | int | 人格类型 ID（对应 DriverPersonalityType） |
| Name | string | 人格名称 |
| MaxCruiseSpeed | float | 巡航速度上限(m/s) |
| MaxAcceleratorInput | float | 最大油门 [0-1] |
| CornerSpeedModifier | float | 转弯速度系数 [0-1] |
| StopDistanceCars | float | 前车停车距离(m) |
| SlowDistanceCars | float | 减速触发距离(m) |
| StopDistancePeds | float | 行人停车距离(m) |
| RunsAmberLights | bool | 闯黄灯 |
| RunsStopSigns | bool | 闯停车标志 |
| RollsThroughStopSigns | bool | 滚动通过停车标志 |
| GreenLightDelayMs | int | 绿灯起步延迟(ms) |
| WillChangeLanes | bool | 主动变道 |
| LaneChangeCooldownMs | int | 变道冷却(ms) |
| UseTurnIndicators | bool | 打转向灯 |
| DriverAbility | float | 驾驶技术 [0-1] |
| Aggressiveness | float | 攻击性 [0-1] |

**CfgJunction**（路口配置）

| 字段 | 类型 | 说明 |
|------|------|------|
| Id | int | 路口 ID |
| EntranceCount | int | 入口数（动态，支持 T 型/环岛） |
| DefaultCycleMs | int | 默认信号周期(ms)，无灯路口填 0 |
| IsGiveWay | bool | 是否让行路口（无灯路口标记） |
| HasTrafficLight | bool | 是否有信号灯（false = 无灯路口，客户端走减速/让行逻辑） |

**CfgJunctionPhase**（路口相位子表，审查修复 M-2：改为纵表结构，支持任意入口数）

| 字段 | 类型 | 说明 |
|------|------|------|
| Id | int | 自增 ID |
| JunctionId | int | 关联路口 ID |
| PhaseIndex | int | 相位序号 |
| DurationMs | int | 持续时间(ms)（同 PhaseIndex 的所有行共享此值） |
| EntranceIndex | int | 入口编号（0-based） |
| Command | int | 该入口在此相位的信号（TrafficLightCommand 枚举值） |

> 每个路口的一个相位拆为 N 行（N = 入口数），支持 T 型路口（3 入口）、十字路口（4 入口）、环岛（5+ 入口）。

**CfgSpeedZone**（限速区配置）

| 字段 | 类型 | 说明 |
|------|------|------|
| Id | int | 区域 ID |
| CenterX/Y/Z | float | 中心坐标 |
| Radius | float | 半径(m) |
| MaxSpeed | float | 限速(m/s) |
| SceneId | int | 所属场景 |

**CfgTrafficSceneProfile**（场景交通参数 Profile）

| 字段 | 类型 | 说明 |
|------|------|------|
| Id | int | 场景 ID |
| MaxTrafficVehicles | int | 最大交通车辆数 |
| MaxSpeedZones | int | 限速区上限 |
| DefaultSpeedLimit | float | 默认限速(m/s) |
| LodFullDist | float | FULL LOD 阈值(m) |
| LodTimesliceDist | float | TIMESLICE 阈值(m) |
| LodDummyDist | float | DUMMY 阈值(m) |
| CollisionDetectDist | float | 碰撞检测距离(m) |
| SwerveDurationMs | int | 侧闪最大时长(ms) |
| JunctionLookahead | int | 路口前瞻路点数 |
| JunctionTimeoutMs | int | 路口决策超时(ms) |

### 4.2 现有配置表扩展

**CfgVehicleBase** 新增字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| DefaultPersonality | int | 默认驾驶人格 ID |

## 5. 接口契约

### 5.1 协议 ↔ 服务端

| 协议消息 | 方向 | 触发时机 | 频率 |
|---------|------|---------|------|
| VehiclePersonalityNtf | S→C | 交通车辆创建后 | 低频 |
| TrafficLightStateNtf | S→C | 信号灯相位变化 | ~每 3-5s |
| SpeedZoneSyncNtf | S→C | 进入 AOI / 限速区增量变化 | 低频 |
| VehicleApproachJunctionReq | C→S | 车辆接近路口 | 低频 |
| VehicleLeaveJunctionReq | C→S | 车辆离开路口 | 低频 |
| JunctionCommandNtf | S→C | 收到 ApproachJunction 后 | 低频 |

### 5.2 服务端 ↔ 配置

- 信号灯系统初始化时加载 `CfgJunction` 配置
- 车辆生成时查 `CfgVehicleBase.DefaultPersonality` → `CfgDriverPersonality`
- 场景初始化时加载 `CfgSpeedZone`

### 5.3 客户端 ↔ 协议

- 客户端收到 `VehiclePersonalityNtf` 时初始化 `VehicleDriverPersonalityComp`
- 客户端收到 `TrafficLightStateNtf` 时更新本地信号灯缓存，供 `TrafficLightFSM` 查询
- LOD 计算完全在客户端本地执行，无需协议参与
