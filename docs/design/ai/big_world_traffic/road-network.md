# 路网系统

## 现状

大世界路网数据已由 Gley 编辑器生成，存储在 `road_traffic_client.json`（51MB）/ `road_traffic.json`（105MB）。

### 数据规模

| 指标 | 值 |
|------|------|
| 路点总数 | 50,523 |
| 路口数 | 295（junction_id 1-294） |
| 有车道关联的路点 | 14,779（29%） |
| 道路类型 | road_type 1/2 |
| 信号灯相位 | cycle 0-3 |
| 覆盖面积 | ~5400 万 m²（Miami） |

### 路点数据格式

```json
{
  "listIndex": 0,
  "position": {"x": 36.19, "y": 12.5, "z": -165.82},
  "neighbors": [2, 4],
  "prev": [3],
  "OtherLanes": [1],
  "junction_id": 0,
  "cycle": 0,
  "road_type": 1
}
```

- `neighbors`：有向前进方向邻居（用于寻路）
- `prev`：反向边（用于构建双向邻接表）
- `OtherLanes`：平行车道的路点索引（用于变道）
- `junction_id`：0 表示非路口，>0 为路口编号
- `cycle`：信号灯相位编号（0 表示无信号灯）
- `road_type`：道路类型（关联限速配置）

### 现有加载架构

```
road_traffic_client.json (51MB)
    → GleyNav / WaypointManager 加载
    → RoadPoint[] 数组 (50,523 元素)
    → CustomWaypoint 邻接表 + Octree 空间索引
    → DotsCity ECS 物理车道使用
```

## 设计方案

### 1. 路网图数据结构

复用现有 GleyNav 加载链路，不重复解析 JSON。在 WaypointManager 加载完成后，构建交通专用的图索引：

```csharp
// 交通系统路网图视图（不持有路点数据，引用 WaypointManager）
public class TrafficRoadGraph
{
    // 快速查询
    private Dictionary<int, List<int>> _adjacencyList;  // nodeId → neighbors
    private Dictionary<int, JunctionData> _junctions;   // junctionId → 路口数据
    private Dictionary<int, int> _nodeToJunction;       // nodeId → junctionId
    private Dictionary<int, List<int>> _otherLanes;     // nodeId → 平行车道节点

    // 空间索引（复用 WaypointManager 的 Octree）
    public int FindNearestNode(Vector3 position);
    public List<int> FindNodesInRadius(Vector3 center, float radius);

    // 路口查询
    public bool IsJunctionNode(int nodeId);
    public JunctionData GetJunction(int junctionId);
    public int GetCyclePhase(int nodeId);

    // 车道查询
    public List<int> GetOtherLanes(int nodeId);
    public bool HasParallelLane(int nodeId);
}
```

### 2. 路口数据结构

```csharp
public struct JunctionData
{
    public int JunctionId;
    public Vector3 Center;                    // 路口中心（所有入口节点平均值）
    public List<JunctionEntrance> Entrances;  // 入口列表
    public int PhaseCount;                    // 相位数（通常 2-4）
    public bool HasTrafficLight;              // 是否有信号灯
}

public struct JunctionEntrance
{
    public int NodeId;           // 入口路点 ID
    public Vector3 Direction;    // 进入方向
    public int CyclePhase;       // 信号灯相位编号
    public float StopDistance;   // 停车线距离（默认 3m）
}
```

**路口数据生成**：离线工具分析路网拓扑，自动检测 junction_id > 0 的节点簇，计算入口方向和中心点。输出 `big_world_junctions.json`，运行时与路网一起加载。

### 3. A* 寻路

**规模适配**：50K 节点比小镇 484 节点大 100 倍，需要优化：

| 优化 | 方案 |
|------|------|
| 开放列表 | 二叉堆（BinaryHeap），O(log n) 插入/弹出 |
| 启发式 | XZ 平面欧几里得距离（忽略 Y） |
| 搜索上限 | 最多展开 5000 节点，超出返回失败 |
| 路径缓存 | LRU 缓存最近 50 条路径，相同起终点直接返回 |
| 分帧计算 | 单帧最多展开 500 节点，超出延续到下一帧 |

```csharp
public class TrafficPathfinder
{
    private const int MAX_EXPAND_PER_FRAME = 500;
    private const int MAX_TOTAL_EXPAND = 5000;
    private const int PATH_CACHE_SIZE = 50;

    // 同步寻路（短距离，< 100 节点展开）
    public List<int> FindPath(int startNode, int endNode);

    // 异步寻路（长距离，分帧）
    public UniTask<List<int>> FindPathAsync(int startNode, int endNode, CancellationToken ct);

    // 支持节点屏蔽（用于绕行）
    public void BlockNode(int nodeId, float duration);
    public void UnblockNode(int nodeId);
}
```

### 4. 巡航目标选择

```
生成时：
  1. 在 100~300m 范围内随机选目标节点
  2. A* 寻路获取路径
  3. 开始路径跟随

到达目标后：
  1. 在当前位置 100~300m 范围内随机选新目标
  2. 排除与上一目标同方向的节点（防折返）
  3. 优先选择同 road_type 的节点（防止主干道车跑到小路）
  4. A* 寻路 → 路径跟随
```

### 5. 贴地处理

- 大世界地形起伏大于小镇，Y 坐标更不可靠
- 每 5 帧一次 Raycast（layer 6 = Terrain）
- Lerp 平滑插值避免跳变
- 复用小镇 TownVehicleDriver 的贴地逻辑

### 6. 与小镇路网的差异

| 差异 | 小镇 | 大世界 |
|------|------|--------|
| 节点数 | 484 | 50,523 |
| 数据格式 | nodes+links 图 | RoadPoint 平面数组 |
| 加载方式 | 独立 JSON 解析 | GleyNav 统一加载 |
| 路口数据 | 无 | 295 个路口+相位 |
| 车道关联 | 无 | 29% 路点有 OtherLanes |
| 寻路优化 | 全量 A* | 分帧+缓存+节点上限 |
| 空间索引 | 无 | Octree（复用 WaypointManager） |
