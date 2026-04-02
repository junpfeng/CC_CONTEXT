# 变道系统

## 现状

- **路网数据**：29% 路点有 `OtherLanes` 字段，标记平行车道关系
- **客户端框架**：DrivingAI 有 Overtake 行为概念，但无车道切换执行逻辑
- **缺失**：变道决策 FSM、平滑车道切换执行、变道安全检查

## GTA5 参考

GTA5 变道由人格驱动（`WillChangeLanes`），有冷却时间、转向灯、安全检查（后方来车检测）。变道分主动（超车）和被动（避障）。

## 设计方案

### 1. 变道 FSM

```csharp
public enum LaneChangeState
{
    None,        // 不变道
    Evaluating,  // 评估是否需要变道
    Preparing,   // 准备变道（打灯、检查安全）
    Executing,   // 执行变道（横向移动）
    Cooldown     // 变道冷却（不接受新的变道请求）
}
```

### 2. 变道触发条件

**主动变道（超车）**：
1. 前方同向车辆距离 < 20m 且速度明显低于自己（差 > 3 m/s）
2. 人格允许变道（`personality.WillChangeLanes == true`）
3. 变道冷却已结束
4. 当前节点有平行车道（`OtherLanes` 非空）

**被动变道（避障升级）**：
1. 碰撞闪避 FSM 进入 Reroute 状态
2. 平行车道可用
3. 优先于绕行寻路（更快）

### 3. 安全检查

```csharp
private bool IsLaneChangeSafe(int targetLaneNode)
{
    // 1. 目标车道前方 30m 内无车
    if (HasVehicleAhead(targetLaneNode, 30f))
        return false;

    // 2. 目标车道后方 20m 内无快速接近的车
    if (HasFastApproachingVehicleBehind(targetLaneNode, 20f))
        return false;

    // 3. 目标车道不是对向车道
    // （OtherLanes 可能包含对向车道，需方向检查）
    if (!IsSameDirection(targetLaneNode))
        return false;

    return true;
}
```

### 4. 变道执行

```csharp
private void ExecuteLaneChange(int targetLaneNode)
{
    _laneChangeState = LaneChangeState.Executing;

    // 1. 计算目标位置（目标车道对应节点的世界坐标）
    Vector3 targetPos = _roadGraph.GetNodePosition(targetLaneNode);

    // 2. 在 1.5s 内平滑横移
    _laneChangeTimer = 1.5f;
    _laneChangeStartPos = transform.position;
    _laneChangeTargetPos = targetPos;

    // 3. 更新路径：切换到目标车道的后续节点
    UpdatePathToLane(targetLaneNode);
}

// 每帧更新
private void UpdateLaneChange(float dt)
{
    if (_laneChangeState != LaneChangeState.Executing) return;

    _laneChangeTimer -= dt;
    float t = 1f - (_laneChangeTimer / 1.5f);
    t = Mathf.SmoothStep(0, 1, t);  // 平滑曲线

    // 横向插值（仅 XZ 平面，Y 由贴地处理）
    Vector3 lateralOffset = Vector3.Lerp(Vector3.zero,
        _laneChangeTargetPos - _laneChangeStartPos, t);
    // 仅取横向分量
    lateralOffset = Vector3.ProjectOnPlane(lateralOffset, transform.forward);

    _laneChangeOffset = lateralOffset;

    if (_laneChangeTimer <= 0)
    {
        _laneChangeState = LaneChangeState.Cooldown;
        _cooldownTimer = _personality.LaneChangeCooldownMs / 1000f;
        _laneChangeOffset = Vector3.zero;
    }
}
```

### 5. 路径更新

变道完成后需要将当前路径切换到新车道：

```csharp
private void UpdatePathToLane(int targetLaneNode)
{
    // 1. 从目标车道节点开始，沿 neighbors 方向获取后续 5 个节点
    var laneNodes = _roadGraph.GetForwardNodes(targetLaneNode, 5);

    // 2. 将当前路径的剩余部分替换为新车道节点
    _currentPath.RemoveRange(_currentPathIndex, _currentPath.Count - _currentPathIndex);
    _currentPath.AddRange(laneNodes);

    // 3. 如果新车道节点不足，在末尾追加 A* 寻路到原目标
    if (laneNodes.Count < 5)
    {
        var appendPath = _pathfinder.FindPath(laneNodes.Last(), _targetNode);
        if (appendPath != null)
            _currentPath.AddRange(appendPath);
    }
}
```

### 6. OtherLanes 数据使用

```csharp
// 查询当前节点的平行车道
public int GetBestLaneChangeTarget(int currentNode, Vector3 forward)
{
    var otherLanes = _roadGraph.GetOtherLanes(currentNode);
    if (otherLanes == null || otherLanes.Count == 0)
        return -1;

    // 筛选同向车道（排除对向）
    foreach (int laneNode in otherLanes)
    {
        Vector3 laneDir = _roadGraph.GetNodeDirection(laneNode);
        if (Vector3.Dot(forward, laneDir) > 0.5f)  // 同向
        {
            if (IsLaneChangeSafe(laneNode))
                return laneNode;
        }
    }

    return -1;  // 无安全的平行车道
}
```

### 7. 约束

- 变道期间锁定转向，不响应新的变道请求
- 变道期间碰撞避让仍然生效（如果目标车道突然出现车辆，中止变道）
- 路口范围内（junction_id > 0）禁止变道
- 单次变道最多跨 1 条车道
