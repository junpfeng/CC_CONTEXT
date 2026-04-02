# 信号灯系统

## 现状

- **协议已定义**：`TrafficLightCommand`（8 种指令）、`TrafficLightStateNtf`（服务端→客户端广播）
- **客户端框架存在**：Gley TrafficSystem 本地信号灯 + DotsCity TrafficLightHandler
- **缺失**：服务端相位计时器、客户端未消费服务端 Ntf

## GTA5 参考

GTA5 信号灯 8 种指令：STOP / AMBERLIGHT / GO / FILTER_LEFT / FILTER_RIGHT / FILTER_MIDDLE / PED_WALK / PED_DONTWALK。单路口最多 16 入口、8 个信号灯位置。

## 设计方案

### 1. 服务端：信号灯相位计时器

```go
// TrafficLightPhaseTimer 管理单个路口的信号灯循环
type TrafficLightPhaseTimer struct {
    JunctionId    int32
    PhaseCount    int32           // 相位数（2-4）
    CurrentPhase  int32           // 当前绿灯相位
    State         TrafficLightState // Green/Amber/Red
    RemainingMs   int64           // 当前状态剩余时间

    // 配置（来自配置表）
    GreenDurationMs  int64  // 默认 25000
    AmberDurationMs  int64  // 默认 3000
    RedDurationMs    int64  // = GreenDurationMs * (PhaseCount-1) + AmberDurationMs * (PhaseCount-1)
}
```

**Tick 逻辑**（服务端每秒 Tick）：

```
Green(25s) → Amber(3s) → Red → 切换到下一相位 Green → ...
```

每次状态切换 → AOI 内广播 `TrafficLightStateNtf`。

### 2. 服务端：全局信号灯管理

```go
// TrafficLightSystem 管理所有路口信号灯
type TrafficLightSystem struct {
    timers map[int32]*TrafficLightPhaseTimer  // junctionId → timer
}
```

- 场景初始化时，根据路口数据创建所有 timer
- 每秒 Tick 所有 timer，有状态切换的广播 Ntf
- 只广播 AOI 内的信号灯变化（295 个路口，但同时可见的通常 < 20）

### 3. 协议使用（对齐 `old_proto/scene/vehicle.proto`）

**已有协议（无需新增）**：

```protobuf
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

// 信号灯状态通知（按入口粒度，非按路口整体）
message TrafficLightStateNtf {
  uint32 junction_id = 1;
  repeated TrafficLightEntry lights = 2;
}

message TrafficLightEntry {
  uint32 entrance_index = 1;       // 入口编号
  TrafficLightCommand command = 2; // 当前指令
  uint32 remaining_ms = 3;        // 剩余时间(ms)
}
```

**关键设计点**：Ntf 按入口粒度下发（`repeated TrafficLightEntry`），允许同一路口不同入口处于不同相位（如左转专用绿灯时直行仍红灯）。

### 4. 客户端：信号灯状态接收

```csharp
// 收到服务端 TrafficLightStateNtf
public void OnTrafficLightStateNtf(TrafficLightStateNtf ntf)
{
    var junctionLight = GetOrCreateJunctionLight(ntf.JunctionId);

    // 按入口粒度更新
    foreach (var entry in ntf.Lights)
    {
        junctionLight.UpdateEntrance(entry.EntranceIndex, entry.Command, entry.RemainingMs);
    }

    // 通知路口决策 FSM
    OnJunctionLightChanged?.Invoke(ntf.JunctionId);
}

// 车辆查询自己入口的信号灯状态
public TrafficLightCommand GetLightForEntrance(uint junctionId, uint entranceIndex)
{
    var junctionLight = GetJunctionLight(junctionId);
    return junctionLight?.GetEntranceCommand(entranceIndex) ?? TrafficLightCommand.TlcInvalid;
}
```

**本地插值**：服务端仅在状态切换时广播（非定时），客户端本地用 `remainingMs` 倒计时插值，保证视觉平滑。

### 5. 信号灯配置

通过配置表定义不同路口的信号灯参数：

| 字段 | 类型 | 说明 |
|------|------|------|
| junction_id | int | 路口 ID |
| phase_count | int | 相位数 |
| green_duration_ms | int | 绿灯时长 |
| amber_duration_ms | int | 黄灯时长 |
| has_left_filter | bool | 是否有左转专用相位 |
| pedestrian_phase | bool | 是否有行人相位 |

**默认值**：大部分路口使用默认配置（2 相位、25s 绿灯、3s 黄灯），仅特殊路口单独配置。

### 6. 初始同步

玩家进入场景 / AOI 切换时，需要同步当前可见路口的信号灯状态：

```
玩家进入 AOI → 服务端遍历 AOI 内路口 → 对每个路口发送一次 TrafficLightStateNtf（含当前状态+剩余时间）
```

这确保客户端不会在信号灯状态切换之前处于未知状态（`TLC_INVALID`）。

### 7. 信号灯视觉表现

- 复用 DotsCity `TrafficLightObject` 场景物件
- 服务端状态 → 客户端材质/颜色切换（红/黄/绿）
- 可选：信号灯倒计时 UI（仅玩家视角可见）
