# Bug 分析：路口所有车辆死锁停车

## Bug 描述

玩家在路口附近观察时，路口处所有 NPC 车辆全部停止行驶，形成永久性堵车。玩家本人未进入路口，不是直接阻碍原因。

## 代码定位

| 文件 | 行号 | 问题 |
|------|------|------|
| `GTA5VehicleAI.cs` | 163-166 | Reroute 触发后调用 `OnRerouteComplete()` 直接重置，无实际绕行 |
| `JunctionDecisionFSM.cs` | 237-239 | `HasCrossingTraffic` 把停止车辆也计入交叉交通，引发相互等待 |

## 根因分析

### 根因 1（主因）：Reroute 是空实现

车辆被前车堵住时，避让状态机按以下链条升级：

```
Idle → Decelerate（减速）→ EmergencyBrake（急刹）
     → Swerve（尝试绕过）→ Horn（鸣笛等待）→ Reroute（触发绕行）
```

到达 Reroute 状态后，代码是这样的：

```csharp
if (_avoidanceFSM.NeedsReroute())
{
    _avoidanceFSM.OnRerouteComplete(); // 简化：重置状态让路径自然重建
}
```

没有真正的 A* 重新寻路，只是把状态重置回 Idle。重置后前车还在原地，于是又从头开始减速 → 急刹 → 绕行尝试 → 重置，**每 10 秒循环一次，永远走不掉**。

路口排队的多辆车全部陷入这个循环，越堵越多。

### 根因 2（放大因素）：HasCrossingTraffic 把停止车辆也算进去

路口让行逻辑用空间网格查询各入口附近有没有车：

```csharp
var nearby = spatialGrid.QueryRadius(entrancePos, 20f);
if (nearby.Count > 0) return true;  // 有车就让行
```

不管车是在走还是停着，只要在 20m 内就返回"有交叉车辆"。

结果：
- A 方向的车停在路口入口等待
- B 方向的车检测到 A 的停止车辆 → 继续等
- A 方向的车检测到 B 的停止车辆 → 继续等
- 互相等，谁都不走

虽然有 5 秒超时强制通行，但超时后车仍被前方停止车辆的避让逻辑卡住（根因 1），实际还是动不了。

### 为什么只有玩家附近的路口出问题

LOD 系统控制 AI 更新频率：
- 距玩家 > 150m：AI 完全不更新（Minimal LOD）
- 距玩家 80~150m：每 3 帧更新一次
- 距玩家 < 80m：每帧更新

远处路口的车 AI 不跑，看起来正常行驶（保持上一帧状态）。只有玩家附近 80m 内的路口，车辆 AI 在真正运行，死锁才会显现出来。

## 修复方案

### 修复 1：实现真正的绕行（或超时后强制前进）

`GTA5VehicleAI.cs`，`UpdateAI` 方法绕行处理部分：

```csharp
// 当前（有问题）：
if (_avoidanceFSM.NeedsReroute())
{
    _avoidanceFSM.OnRerouteComplete();
}

// 修改：超时无法绕行时，跳过当前路点强制前进
if (_avoidanceFSM.NeedsReroute())
{
    bool rerouted = _controller.TrySkipBlockedWaypoint(); // 跳到下一个路点
    _avoidanceFSM.OnRerouteComplete();
}
```

### 修复 2：HasCrossingTraffic 只计移动中的车辆

`JunctionDecisionFSM.cs`，`HasCrossingTraffic` 方法：

```csharp
// 当前（有问题）：
var nearby = spatialGrid.QueryRadius(entrancePos, 20f);
if (nearby.Count > 0) return true;

// 修改：只有速度 > 0.5f 的车才视为有效交叉车辆
var nearby = spatialGrid.QueryRadius(entrancePos, 20f);
for (int n = 0; n < nearby.Count; n++)
{
    if (nearby[n] != null && nearby[n].CurrentSpeed > 0.5f)
        return true;
}
```

## 归因结论

**主要原因**：实现缺陷 — Reroute 是注释写着"简化"的空实现，车辆被堵后永远原地循环，无法真正绕行脱困。

**放大因素**：实现缺陷 — 路口让行检测把停止车辆也算作交叉交通，所有方向互相等待，加速死锁扩散。
