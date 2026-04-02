# 路口决策系统

## GTA5 参考

GTA5 `VehicleIntelligence` 路口决策 6 态：GO / APPROACHING / WAIT_FOR_LIGHTS / WAIT_FOR_TRAFFIC / GIVE_WAY / NOT_ON_JUNCTION。单路口最多 16 入口。

## 设计方案

### 1. 路口决策 FSM

```csharp
public enum JunctionState
{
    NotOnJunction,     // 不在路口范围（正常行驶）
    Approaching,       // 接近路口（前方 40m），准备减速
    WaitForLights,     // 红灯等待（停车线前停车）
    WaitForTraffic,    // 无灯路口，等待交叉方向无车
    GiveWay,           // 强制让行（优先级低的方向）
    Go                 // 绿灯/安全，通过路口
}
```

### 2. 状态转换

```
NotOnJunction
    │ 前方 40m 检测到路口节点
    ▼
Approaching ──── 有信号灯 ───→ 查询信号灯状态
    │                              │
    │                   ┌──────────┤
    │                   │          │
    │              绿灯 │     红/黄灯
    │                   │          │
    │                   ▼          ▼
    │                  Go    WaitForLights
    │                              │
    │                         绿灯切换
    │                              │
    │                              ▼
    │                             Go
    │
    │── 无信号灯 ───→ 检测交叉方向
    │                      │
    │            ┌─────────┤
    │            │         │
    │         无车 │     有车
    │            │         │
    │            ▼         ▼
    │           Go    WaitForTraffic / GiveWay
    │                      │
    │                   无车了
    │                      │
    │                      ▼
    │                     Go
    │
    ▼ 通过路口
NotOnJunction
```

### 3. 路口检测

```csharp
// 在 DrivingAI / VehicleIntelligence 中每帧检测
public JunctionState EvaluateJunction()
{
    // 1. 查询当前路径前方 40m 内的路口节点
    int junctionNode = FindJunctionAhead(40f);
    if (junctionNode < 0) return JunctionState.NotOnJunction;

    int junctionId = _roadGraph.GetJunctionId(junctionNode);
    var junction = _roadGraph.GetJunction(junctionId);

    // 2. 有信号灯 → 查询信号灯状态
    if (junction.HasTrafficLight)
    {
        int myPhase = _roadGraph.GetCyclePhase(junctionNode);
        var lightState = _lightManager.GetState(junctionId, myPhase);

        return lightState switch
        {
            TrafficLightCommand.GO => JunctionState.Go,
            TrafficLightCommand.AMBERLIGHT => EvaluateAmber(distToStopLine),
            _ => JunctionState.WaitForLights
        };
    }

    // 3. 无信号灯 → 检测交叉方向车辆
    if (HasCrossingTraffic(junction))
        return JunctionState.WaitForTraffic;

    return JunctionState.Go;
}
```

### 4. 黄灯决策

```csharp
private JunctionState EvaluateAmber(float distToStopLine)
{
    // 人格参数驱动
    if (_personality.RunsAmberLights && distToStopLine > 5f)
    {
        // 激进型：距离停车线 > 5m 时加速闯过
        return JunctionState.Go;
    }

    // 保守型 / 距离近：减速停车
    return JunctionState.WaitForLights;
}
```

### 5. 停车排队

**停车位计算**：
- 第一辆：停车线前 3m（`StopDistance`）
- 后续车辆：通过碰撞避让自动跟停（不需要显式排队逻辑）

**绿灯起步**：
- 第一辆：立即起步（或根据人格 `GreenLightDelayMs` 延迟）
- 后续：前车起步后自然跟进（碰撞避让距离缩短 → 自动前进）

### 6. 无灯路口让行

```csharp
// 检测交叉方向是否有车辆
private bool HasCrossingTraffic(JunctionData junction)
{
    foreach (var entrance in junction.Entrances)
    {
        // 跳过自己的入口方向
        if (entrance.NodeId == _currentJunctionEntrance) continue;

        // 检测该入口方向 30m 内是否有车辆
        if (HasVehicleNear(entrance.NodeId, 30f))
            return true;
    }
    return false;
}
```

**让行规则**（参考 GTA5）：
- 右侧优先：交叉方向右侧来车优先通过
- 先到先行：同时到达时，先停车的先通过
- 简化实现：客户端本地判断即可，不需要服务端仲裁

**死锁防护**：
- 超时机制：无灯路口等待超过 5 秒后，强制通过（`WaitForTraffic` → `Go`）
- 随机退让：多车同时等待时，各车叠加 0~2 秒随机延迟，打破对称死锁
- 全等待兜底：如果路口所有方向都在等待（全部 WaitForTraffic），由随机退让自动打破（无需判定谁先到）

### 7. 与服务端路口指令的配合

**协议已定义**：

```protobuf
enum JunctionCommand {
    JC_GO = 0;
    JC_APPROACHING = 1;
    JC_WAIT_FOR_LIGHTS = 2;
    JC_WAIT_FOR_TRAFFIC = 3;
    JC_GIVE_WAY = 4;
}

message VehicleApproachJunctionReq { int64 entity_id = 1; int32 junction_id = 2; }
message VehicleLeaveJunctionReq { int64 entity_id = 1; int32 junction_id = 2; }
message JunctionCommandNtf { int64 entity_id = 1; JunctionCommand command = 2; }
```

**使用方式**：
- 交通 NPC 车辆：**客户端本地决策**（不上报服务端），节省带宽
- 玩家驾驶车辆：上报 ApproachJunction/LeaveJunction，服务端记录用于统计
- 服务端可下发 JunctionCommandNtf 强制覆盖本地决策（如任务剧情需要）
