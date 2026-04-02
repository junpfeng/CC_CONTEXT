# 碰撞闪避系统

## 现状

- **小镇**：前向矩形检测（2.5m×15m），三段式减速（跟车→紧急制动→蠕行），过滤对向来车
- **大世界**：DrivingAI 触发器检测，Forward/Follow/Overtake/Reverse/StopInDistance/AvoidReverse 6 种行为
- **缺失**：侧闪、绕行寻路、升级链、行人避让

## GTA5 参考

GTA5 碰撞避让：2.5s 侧闪持续时长 + 碰撞时间戳跟踪 + 6 态升级链。侧闪方向取较空旷一侧。

## 设计方案

### 1. 闪避升级链（6 态 FSM）

```csharp
public enum AvoidanceState
{
    Idle,            // 无障碍（正常行驶）
    Decelerate,      // 减速跟车（前方 15~25m 有车）
    EmergencyBrake,  // 紧急制动（前方 < 5m）
    Swerve,          // 侧闪（持续被挡 > 1.5s）
    Horn,            // 鸣笛（持续被挡 > 3s）
    Reroute          // 绕行寻路（持续被挡 > 5s）
}
```

### 2. 状态转换

```
Idle
  │ 前方 25m 检测到障碍
  ▼
Decelerate（减速至 30% 原速，跟车保持 slow_distance_cars）
  │ 距离 < stop_distance_cars
  ▼
EmergencyBrake（速度降至蠕行 0.5 m/s，不完全停车）
  │ 持续被挡 > 1.5s
  ▼
Swerve（横向偏移 2m，持续 2s，保持 30% 原速前进）
  │ 侧闪完成但仍被挡
  ▼
Horn（触发鸣笛事件，通知前车）
  │ 持续被挡 > 5s
  ▼
Reroute（A* 重新寻路绕行，屏蔽当前障碍节点 30s）
  │ 新路径成功
  ▼
Idle（沿新路径行驶）

任何状态 → 障碍消失 → Idle
```

### 3. 障碍检测

```csharp
public struct ObstacleInfo
{
    public bool HasObstacle;
    public float Distance;         // 到障碍物的距离
    public Vector3 ObstaclePos;
    public ObstacleType Type;      // Vehicle / Pedestrian / Player / Static
    public float DirectionDot;     // 方向点积（过滤对向来车）
}

public enum ObstacleType { Vehicle, Pedestrian, Player, Static }
```

**检测方式**：
- 复用 DrivingAI 的触发器系统（前方扇形区域）
- 补充：对向来车过滤（`dirDot < 0` 跳过）
- 补充：行人检测（`EntityType.Npc` + 步行状态判断）

### 4. 侧闪实现

```csharp
private void ExecuteSwerve()
{
    // 1. 选择侧闪方向：检测左右空间，取较空旷一侧
    float leftSpace = CheckSideSpace(Vector3.left, 3f);
    float rightSpace = CheckSideSpace(Vector3.right, 3f);
    Vector3 swerveDir = leftSpace > rightSpace ? Vector3.left : Vector3.right;

    // 2. 施加横向偏移目标
    _swerveOffset = swerveDir * 2f;  // 2m 偏移量
    _swerveTimer = 2f;               // 持续 2 秒

    // 3. 侧闪期间速度 = 30% 原速
    _speedMultiplier = 0.3f;
}

// 每帧在控制层应用偏移
private void ApplySwerveOffset(float dt)
{
    if (_swerveTimer <= 0) return;
    _swerveTimer -= dt;

    // 平滑偏移
    Vector3 targetPos = _basePosition + transform.TransformDirection(_swerveOffset);
    transform.position = Vector3.Lerp(transform.position, targetPos, dt * 3f);

    if (_swerveTimer <= 0)
        _swerveOffset = Vector3.zero;
}
```

### 5. 绕行寻路

```csharp
private async void ExecuteReroute()
{
    // 1. 屏蔽障碍物所在路段的节点（前后各 3 个节点）
    var blockedNodes = GetBlockedNodesAround(_obstacleNearestNode, 3);
    foreach (var node in blockedNodes)
        _pathfinder.BlockNode(node, 30f);  // 屏蔽 30 秒

    // 2. A* 重新寻路到原目标
    var newPath = await _pathfinder.FindPathAsync(_currentNode, _targetNode, _ct);

    if (newPath != null && newPath.Count > 0)
    {
        // 3. 替换当前路径
        _currentPath = newPath;
        _currentPathIndex = 0;
        _avoidanceState = AvoidanceState.Idle;
    }
    else
    {
        // 4. 寻路失败 → 掉头或随机选新目标
        SelectNewCruiseTarget();
    }
}
```

### 6. 行人避让

| 距离 | 行为 |
|------|------|
| 9~15m | 减速至 50% |
| 4~9m | 减速至 20% |
| < 4m | 停车等待 |
| 行人离开 | 恢复原速 |

```csharp
private float GetPedestrianSpeedModifier(float distToPed)
{
    if (distToPed > _personality.StopDistancePeds * 2.5f) return 1f;
    if (distToPed > _personality.StopDistancePeds) return 0.5f;
    if (distToPed > _personality.StopDistancePeds * 0.5f) return 0.2f;
    return 0f;  // 停车
}
```

### 7. 关键约束（小镇经验）

- **必须过滤对向来车**：`dirDot < 0` 跳过，否则双向道路全部死锁
- **蠕行速度不为 0**：EmergencyBrake 保留 0.5 m/s，防完全停死
- **侧闪需检查车道边界**：防止侧闪到路外或对向车道
- **绕行路径不能太长**：最多比原路径长 50%，否则放弃绕行选新目标
