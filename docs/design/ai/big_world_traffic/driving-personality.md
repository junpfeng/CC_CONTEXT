# 驾驶人格系统

## 现状

- **协议已定义**：`DriverPersonalityType`（6 种类型）、`DriverPersonalityData`（16 参数）、`VehiclePersonalityNtf`
- **客户端框架**：VehicleDriverStyle 目录有 NormalStyle/OverTakeStyle/CollideStyle
- **缺失**：人格参数未实际应用到驾驶行为

## GTA5 参考

GTA5 `DriverPersonality` 25+ 方法按查表返回行为参数。核心理念：**人格参数作为调制因子驱动所有驾驶行为**，不是独立的行为逻辑。

## 设计方案

### 1. 人格参数结构（对齐 `old_proto/scene/vehicle.proto`）

```protobuf
enum DriverPersonalityType {
  DPT_NORMAL = 0;       // 普通
  DPT_CAUTIOUS = 1;     // 谨慎
  DPT_AGGRESSIVE = 2;   // 激进
  DPT_TAXI = 3;         // 出租车
  DPT_BUS = 4;          // 公交
  DPT_TRUCK = 5;        // 卡车
}

message DriverPersonalityData {
  DriverPersonalityType type = 1;          // 人格类型
  float max_cruise_speed = 2;              // 巡航速度上限 (m/s)
  float max_accelerator_input = 3;         // 最大油门 [0-1]
  float corner_speed_modifier = 4;         // 转弯速度缩减系数
  float stop_distance_cars = 5;            // 与前车停车距离 (m)
  float slow_distance_cars = 6;            // 减速触发距离 (m)
  float stop_distance_peds = 7;            // 行人停车距离 (m)
  bool runs_amber_lights = 8;              // 是否闯黄灯
  bool runs_stop_signs = 9;                // 是否闯停车标志
  bool rolls_through_stop_signs = 10;      // 是否滚动通过停车标志
  uint32 green_light_delay_ms = 11;        // 绿灯起步延迟 (ms)
  bool will_change_lanes = 12;             // 是否主动变道
  uint32 lane_change_cooldown_ms = 13;     // 变道冷却 (ms)
  bool use_turn_indicators = 14;           // 是否打转向灯
  float driver_ability = 15;               // 驾驶技术评级
  float aggressiveness = 16;               // 攻击性系数
}

message VehiclePersonalityNtf {
  uint64 vehicle_entity_id = 1;
  DriverPersonalityData personality = 2;
}
```

> 注意：proto 字段顺序和名称必须严格遵循上述定义，不得自行调整。

### 2. 人格预设

| 预设 | 巡航速度 | 激进度 | 闯黄灯 | 变道 | 跟车距离 | 适用车型 |
|------|---------|--------|--------|------|---------|---------|
| Normal | 11~14 | 0.4~0.6 | 偶尔 | 一般 | 5~7m | 轿车 |
| Cautious | 8~11 | 0.1~0.3 | 否 | 很少 | 7~10m | SUV/面包车 |
| Aggressive | 14~18 | 0.8~1.0 | 是 | 频繁 | 3~5m | 跑车/改装车 |
| Taxi | 12~15 | 0.5~0.7 | 偶尔 | 频繁 | 4~6m | 出租车 |
| Bus | 7~10 | 0.0~0.2 | 否 | 不变 | 8~12m | 公交车 |
| Truck | 7~9 | 0.0~0.2 | 否 | 很少 | 10~15m | 货车/大车 |

### 3. 参数应用方式

**核心理念：调制因子，不替代逻辑。**

```csharp
public class PersonalityDriver
{
    private DriverPersonalityData _p;

    // === 速度控制 ===

    // 巡航速度 = 人格上限 × 限速系数
    public float GetEffectiveCruiseSpeed(float roadSpeedLimit)
        => Mathf.Min(_p.MaxCruiseSpeed, roadSpeedLimit);

    // 转弯减速 = 基础减速 × 人格系数
    public float GetCornerSpeed(float baseSpeed, float turnAngle)
        => baseSpeed * _p.CornerSpeedModifier;

    // === 跟车距离 ===

    // 停车距离 = 人格参数（替代硬编码）
    public float GetStopDistanceCars() => _p.StopDistanceCars;
    public float GetSlowDistanceCars() => _p.SlowDistanceCars;
    public float GetStopDistancePeds() => _p.StopDistancePeds;

    // === 信号灯行为 ===

    // 黄灯决策
    public bool ShouldRunAmber(float distToStopLine)
        => _p.RunsAmberLights && distToStopLine > 5f;

    // 绿灯起步延迟
    public int GetGreenLightDelay() => _p.GreenLightDelayMs;

    // === 变道 ===

    public bool WillChangeLanes() => _p.WillChangeLanes;
    public int GetLaneChangeCooldown() => _p.LaneChangeCooldownMs;
}
```

### 4. 服务端人格分配

```go
// 生成交通车辆时分配人格
func assignPersonality(vehicleType int32) *proto.DriverPersonalityData {
    // 1. 根据车型查配置表获取默认人格类型
    baseType := cfg.GetVehicleBase(vehicleType).PersonalityType

    // 2. 获取预设参数
    preset := getPersonalityPreset(baseType)

    // 3. 叠加 ±10% 随机扰动（避免同类型车辆行为一致）
    applyRandomVariation(preset, 0.1)

    return preset
}
```

人格参数随 `VehiclePersonalityNtf` 下发客户端。

### 5. 客户端接收与应用

```csharp
// 收到人格通知
public void OnVehiclePersonalityNtf(long entityId, DriverPersonalityData data)
{
    var vehicle = GetVehicle(entityId);
    vehicle.GetComponent<PersonalityDriver>().Init(data);
}
```

**应用点（替代硬编码）**：

| 行为 | 原硬编码 | 人格驱动 |
|------|---------|---------|
| 巡航速度 | 11 m/s | `personality.MaxCruiseSpeed` |
| 跟车距离 | 8m | `personality.StopDistanceCars` |
| 减速距离 | 15m | `personality.SlowDistanceCars` |
| 转弯减速 | 固定 55% | `personality.CornerSpeedModifier` |
| 黄灯行为 | 一律停车 | `personality.RunsAmberLights` |
| 起步延迟 | 无 | `personality.GreenLightDelayMs` |

### 6. 配置表

在 `RawTables/Traffic/` 新增人格预设配置表：

| 字段 | 类型 | 说明 |
|------|------|------|
| personality_type | int | 人格类型 ID |
| max_cruise_speed_min | float | 巡航速度下限 |
| max_cruise_speed_max | float | 巡航速度上限 |
| aggressiveness_min | float | 激进度下限 |
| aggressiveness_max | float | 激进度上限 |
| ... | ... | 其余参数的 min/max |

服务端在范围内随机取值，确保同类型车辆有自然差异。
