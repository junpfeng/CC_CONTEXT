# 根因分析报告 - Bug #1

## Bug 描述

玩家角色站在路口中央时，来自多方向的 NPC 车辆全部停止行驶，形成永久性堵车。

## 直接原因

**双重实现缺陷共同导致死锁：**

### 缺陷 1：玩家障碍上报为 Vehicle 类型，触发无限 Reroute 循环

`GTA5VehicleAI.cs:260-262`：

```csharp
_avoidanceFSM.UpdateObstacle(found, closestDist, closestPos,
    found ? AvoidanceUpgradeChain.ObstacleType.Vehicle : AvoidanceUpgradeChain.ObstacleType.None,
    closestDot);
```

玩家被检测到（第 239-258 行）后，障碍类型被硬编码为 `ObstacleType.Vehicle`，而不是 `ObstacleType.Player`。
`AvoidanceUpgradeChain.cs:27` 已定义 `Player` 枚举值，但**从未被使用**。

`AvoidanceUpgradeChain.Evaluate()` 对 `Pedestrian` 有特殊处理（直接 EmergencyBrake，不升级），而 `Player` 没有任何特殊分支，与普通 Vehicle 走相同的升级链：

```
Idle → Decelerate(2s) → EmergencyBrake(3s) → Swerve(2s) → Horn(3s) → Reroute
```

玩家不像真实车辆会移开，10 秒后 Reroute 触发，`GTA5VehicleAI.cs:163-165` 仅调用 `OnRerouteComplete()` 重置状态到 Idle，不做任何实际绕行：

```csharp
if (_avoidanceFSM.NeedsReroute())
{
    _avoidanceFSM.OnRerouteComplete(); // 简化：重置状态让路径自然重建
}
```

重置后玩家依然原地，立刻再次触发升级链，**每 10 秒循环一次，车辆永远走不掉**。

### 缺陷 2：HasCrossingTraffic 把停止车辆也计为交叉交通，级联扩散死锁

`JunctionDecisionFSM.cs:238-239`：

```csharp
var nearby = spatialGrid.QueryRadius(entrancePos, 20f);
if (nearby.Count > 0) return true;
```

只要 20m 内有任意车辆（无论是在行驶还是已停止），均返回"有交叉车辆"。
缺陷 1 造成的停止车辆被缺陷 2 识别为"正在通行的交叉交通"，导致所有方向互相等待，级联死锁扩散至整个路口。

## 根本原因分类

**实现缺陷（双重）**
- 缺陷 1：知识盲区 — `ObstacleType.Player` 枚举已定义但从未接入检测逻辑，玩家按 Vehicle 处理，没有针对"障碍永远不会自行移开"的场景设计出路
- 缺陷 2：遗漏检查 — `HasCrossingTraffic` 缺少速度过滤，停止车辆不应被视为有效交叉交通

## 影响范围

| 位置 | 影响 |
|------|------|
| `GTA5VehicleAI.cs:260-262` | 所有玩家附近（<12m）的 NPC 车辆均受影响 |
| `AvoidanceUpgradeChain.cs:27` | `ObstacleType.Player` 定义存在但全系统未使用 |
| `JunctionDecisionFSM.cs:238-239` | 路口所有入口均受影响，停止车辆相互计入等待条件 |
| LOD 系统（`GTA5VehicleAI.cs:266+`） | 死锁仅在玩家 80m 内可见（LOD Full 范围内 AI 实际运行） |

## 修复方案

### 修复 1：玩家障碍使用正确类型，并在 AvoidanceUpgradeChain 中添加 Player 特殊处理

**`GTA5VehicleAI.cs:260-262`** — 修改障碍类型判断：

```csharp
// 区分玩家和车辆类型（需要记录 foundPlayer 布尔）
var obstacleType = foundPlayer
    ? AvoidanceUpgradeChain.ObstacleType.Player
    : (found ? AvoidanceUpgradeChain.ObstacleType.Vehicle : AvoidanceUpgradeChain.ObstacleType.None);
_avoidanceFSM.UpdateObstacle(found || foundPlayer, closestDist, closestPos, obstacleType, closestDot);
```

**`AvoidanceUpgradeChain.cs`** — 在 `Evaluate()` 中添加 Player 分支（仿照 Pedestrian，直接 EmergencyBrake，不进入 Reroute 循环）：

```csharp
if (CurrentObstacleType == ObstacleType.Player || CurrentObstacleType == ObstacleType.Pedestrian)
{
    float stopDist = personality?.StopDistancePeds ?? 6f;
    SpeedMultiplier = ObstacleDistance < stopDist ? 0f : CreepSpeed;
    SteeringOffset = 0f;
    if (CurrentState != AvoidanceState.EmergencyBrake)
        TransitionTo(AvoidanceState.EmergencyBrake);
    return;
}
```

### 修复 2：HasCrossingTraffic 只计速度 > 阈值的移动车辆

**`JunctionDecisionFSM.cs:238-239`** — 添加速度过滤：

```csharp
var nearby = spatialGrid.QueryRadius(entrancePos, 20f);
for (int n = 0; n < nearby.Count; n++)
{
    if (nearby[n] != null && nearby[n].CurrentSpeed > 0.5f)
        return true;
}
```

## 是否需要固化防护

**是** — 建议新增规则：**新增 ObstacleType 枚举值后，必须同步检查 Evaluate() 中是否有对应处理分支**，防止出现已定义枚举但从未生效的死代码。

## 修复风险评估

**低** —
- 修复 1 仅在 Player 分支添加处理，不改变车辆对车辆的避让逻辑
- 修复 2 只收紧了"有效交叉车辆"的认定条件（添加速度过滤），已停止的车辆不再阻塞路口，符合预期
- 均属局部分支添加，不影响现有 FSM 状态机流程
