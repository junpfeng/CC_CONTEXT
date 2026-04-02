# S1Town 交通车辆优化方案

> 日期：2026-03-20
> 关联：[system-design.md](system-design.md)、[road-network.md](road-network.md)

## 1. 现状与目标

### 已有实现

| 文件 | 职责 |
|------|------|
| `TownTrafficSpawner.cs` | 自动生成交通车辆、分配路点路径 |
| `TownTrafficMover.cs` | kinematic 沿轨迹定速巡航 |

已实现：客户端驱动、不依赖服务端同步、环形轨迹循环。

### 优化目标

| # | 优化 | 现状问题 |
|---|------|---------|
| 1 | 真正的循环路线 | `BuildLoopPath` 走到 maxLength 截断，首尾可能大跳跃（瞬移） |
| 2 | 移动平滑度 | 直线 Lerp 逐路点移动，转弯处转折生硬；参考 Town NPC 插值思路 |

### 附带修复（审查发现的 bug）

| # | 问题 | 位置 |
|---|------|------|
| B1 | SpawnLoop 缺少 CancellationToken | TownTrafficSpawner:58 |
| B2 | StopSpawning 无调用者（切场景后协程泄漏） | TownTrafficSpawner:53 |
| B3 | FindNearestWaypoint 采样搜索可能漏过最近点 | TownTrafficSpawner:244 |

## 2. 设计方案

### 2.1 移动平滑：Catmull-Rom 样条插值

**改造 `TownTrafficMover`**，将直线 Lerp 替换为 Catmull-Rom 样条插值。

#### 为什么选 Catmull-Rom

- 经过所有路点（不偏离道路）
- 自动生成平滑曲线（无需手动控制点）
- 一阶导数可直接用于旋转朝向
- 计算开销极低（仅 4 点乘加）

#### 核心改动（TownTrafficMover.cs）

```csharp
// 新增字段
private int _currentSegment;    // 当前路段索引
private float _segmentT;        // 路段进度 [0,1]

// Update 改为 Catmull-Rom 驱动
void Update()
{
    // 1. 推进 _segmentT
    float segLen = XZDistance(_track[_currentSegment], _track[NextIdx(_currentSegment)]);
    _segmentT += (_moveSpeed * dt) / Mathf.Max(segLen, 0.5f);

    // 2. 路段切换
    while (_segmentT >= 1f) { _segmentT -= 1f; _currentSegment = NextIdx(_currentSegment); }

    // 3. 取 4 点做 Catmull-Rom
    Vector3 p0 = _track[PrevIdx(_currentSegment)];
    Vector3 p1 = _track[_currentSegment];
    Vector3 p2 = _track[NextIdx(_currentSegment)];
    Vector3 p3 = _track[NextIdx(NextIdx(_currentSegment))];

    Vector3 pos = CatmullRom(p0, p1, p2, p3, _segmentT);
    pos.y = _currentY; // Y 仍用 Raycast 贴地 + Lerp 平滑

    // 4. 旋转用样条切线
    Vector3 tangent = CatmullRomDerivative(p0, p1, p2, p3, _segmentT);
    tangent.y = 0;
    if (tangent.sqrMagnitude > 0.001f)
        transform.rotation = Quaternion.Slerp(transform.rotation,
            Quaternion.LookRotation(tangent), RotationSmoothSpeed * dt);

    transform.position = pos;
}
```

#### 弯道减速

```csharp
// 根据前方路段转角动态调速
float angle = Vector3.Angle((p2 - p1), (p3 - p2));
float speedFactor = Mathf.Lerp(1f, 0.4f, Mathf.Clamp01(angle / 90f));
float effectiveSpeed = _moveSpeed * speedFactor;
```

### 2.2 真正的循环路线

**改造 `BuildLoopPath`**：走完 maxLength 后追加回起点的路径段。

```
现有流程：startIdx → 沿 neighbors 走 80 步 → 截断（首尾可能跳跃）
优化流程：startIdx → 沿 neighbors 走 60 步 → 从末尾反向搜索回 startIdx 的路径
                                                → 拼接形成闭环
                                                → 搜索失败则插入 startIdx 坐标兜底
```

具体算法：
1. 前半段不变（`BuildLoopPath` 走 60 步）
2. 从末尾路点用 BFS/贪心搜索回 startIdx（最多 40 步）
3. 若搜索成功 → 拼接回路段形成真正闭环
4. 若搜索失败 → 在末尾追加起点坐标（仍有一段直线跳跃，但比瞬移好）

### 2.3 Bug 修复

#### B1: CancellationToken

```csharp
private CancellationTokenSource _cts;

public void StartSpawning()
{
    _cts?.Cancel();
    _cts = new CancellationTokenSource();
    _isSpawning = true;
    _spawnedCount = 0;
    SpawnLoop(_cts.Token).Forget();
}

public void StopSpawning()
{
    _isSpawning = false;
    _cts?.Cancel();
}

private async UniTaskVoid SpawnLoop(CancellationToken ct)
{
    await UniTask.WaitUntil(..., cancellationToken: ct);
    while (_isSpawning && ...)
    {
        await UniTask.Delay(..., cancellationToken: ct);
        ...
    }
}
```

#### B2: StopSpawning 调用点

在离开 Town 场景时调用 `StopSpawning()`。需找到 Town 场景退出的代码路径。

#### B3: FindNearestWaypoint 全量遍历

小镇路点数约 12K，全量遍历开销可接受（一次性操作，每辆车初始化时仅调用一次）。去掉采样优化，改为全量 XZ 距离遍历。

## 3. 服务端

**无需改动**。当前已实现：
- S1Town 交通车辆由客户端请求创建（`OnTrafficVehicleReq`）
- 服务端创建 Entity 后返回 entityId
- 车辆 Transform 虽然有 net_update 同步，但 TownTrafficMover 客户端直驱会覆盖位置

> 服务端 Transform 同步对 S1Town 客户端驱动车辆是冗余的（浪费带宽），但不影响正确性。后续可优化跳过，本次不改。

## 4. 接口契约

无协议变更，无配置表变更。纯客户端代码优化。

## 5. 验收测试方案

### [TC-001] 转弯平滑度

```
前置条件：已登录 S1Town，交通车辆已生成
操作步骤：
  1. [screenshot-game-view] 找到一辆正在转弯的交通车辆
  2. [验证] 车辆沿弧线转弯，非折线转弯
  3. [验证] 车辆转弯时速度降低
```

### [TC-002] 循环连续性

```
前置条件：已登录 S1Town，交通车辆已生成
操作步骤：
  1. [script-execute] 读取某辆车的 TownTrafficMover._track 首尾点距离
  2. [验证] 首尾点距离 < 路点间距中位数（无大跳跃）
  3. [等待 90s] 观察车辆循环
  4. [验证] 车辆经过循环点时无瞬移
```

### [TC-003] 切场景后协程清理

```
前置条件：在 S1Town 中有交通车辆
操作步骤：
  1. 切换到 City 场景
  2. [console-get-logs] 检查日志
  3. [验证] 无 TownTrafficSpawner 相关的错误日志或持续生成日志
```

## 6. 改动文件清单

| 文件 | 改动类型 | 内容 |
|------|---------|------|
| `TownTrafficMover.cs` | 修改 | Catmull-Rom 插值替换直线 Lerp、弯道减速 |
| `TownTrafficSpawner.cs` | 修改 | CancellationToken、全量最近点搜索、闭环路径 |
| 调用 StopSpawning 的位置 | 修改 | 离开 Town 时调用 StopSpawning |
