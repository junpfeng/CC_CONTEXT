# 物理与导航架构

> PhysX 物理引擎（CGO）、NavMesh 导航（Recast/Detour）、路网 A* 寻路、Grid 空间划分，三层导航体系。

## 三层导航体系

```
全局导航层    路点网络 A* 寻路 → 路点序列（NPC 日常移动）
局部导航层    NavMesh 寻路 + Crowd 避障 → 平滑路径（NPC 追击）
运动控制层    NPC 移动组件 + Grid 空间管理 → 实时位置更新
```

## PhysX 物理引擎

### CGO 集成

```
pkg/physics/
├── type.go              Go 类型（Vec3f, Actor, Trigger, RaycastResult）
├── physx_linux.go       Linux: 全部空存根
├── physx_windows.go     Windows: 完整 C 调用
├── loader_linux.go      场景序列化（存根）
└── loader_windows.go    场景序列化（完整）
```

**当前状态**：仅 Windows 有完整实现，Linux 全部为空存根。

### 核心接口

```go
// 场景管理
Init() / CreateScene() / DestroyScene() / Cleanup()

// 物理对象
CreateSphere() / CreateBox() / CreateCapsule() / CreateGround()

// 角色控制器
CreateCharacterController(pos, radius, height, stepOffset)
MoveCharacterController(id, displacement, dt)

// 触发器
CreateTrigger(pos, size)
SetTriggerCallback(id, handler)

// 射线检测
Raycast(origin, dir, maxDistance) → RaycastResult{Hit, HitXYZ, NormalXYZ, Distance}

// 场景序列化
LoadSceneFromXml() / LoadSceneFromBinary()
```

### Resource 层

```go
// ecs/res/physx.go
type Physx struct {
    common.ResourceBase
    physx *physics.Physx
}
```

## NavMesh 导航系统

### 技术栈

Recast（网格生成）+ Detour（寻路）+ DetourCrowd（人群避障），通过 C++ 包装层 CGO 调用。

### 目录结构

```
pkg/navmesh/
├── includes/
│   ├── Recast/Include/              网格生成库
│   ├── Detour/Include/              寻路库
│   └── DetourCrowd/Include/         人群管理库
├── c_wrapper/
│   ├── navmesh_wrapper.h            C 接口定义
│   ├── navmesh_common.h             内部结构体
│   ├── navmesh_scene_wrapper.cpp    场景加载/销毁
│   ├── navmesh_agent_wrapper.cpp    Agent 管理
│   ├── navmesh_pathfind_wrapper.cpp 路径查询
│   └── navmesh_build_wrapper.cpp    网格构建
├── types.go                         Go 类型定义
├── scene_linux.go / scene_windows.go
└── agent_linux.go / agent_windows.go
```

### C 核心结构体

```c
NavMeshScene {
    dtNavMesh* navMesh;       // 导航网格
    dtNavMeshQuery* query;    // 查询器
}

NavMeshAgent {
    NavMeshScene* scene;
    dtCrowd* crowd;           // 人群管理器（2048 容量）
    int agentIdx;             // Agent 在 crowd 中的索引
}

NavMeshAgentState {
    float pos[3], vel[3];     // 位置、速度
    int state;                // INVALID / WALKING / OFFMESH
    int ncorners;             // 路径角点数量
    float corners[12];        // 路径角点（max 4 个）
}
```

### Go Agent 参数

```go
AgentParams {
    Radius, Height, MaxSpeed    float32
    MaxAcceleration             float32   // 默认 8.0
    CollisionQueryRange         float32   // radius × 8
    PathOptimizationRange       float32   // radius × 30
    SeparationWeight            float32   // 默认 2.0
    UpdateFlags                 uint8     // ANTICIPATE_TURNS | OBSTACLE_AVOIDANCE | SEPARATION | OPTIMIZE_VIS
}
```

### 两种路径查询

| 方法 | 特点 | 场景 |
|------|------|------|
| `FindPathQuery` | 详细路径点较多 | 精确导航 |
| `FindPathCrowd` | 含避障，路径点较少 | 实时追击 |

### 使用流程

```go
// 1. 创建场景（全局缓存，同一地图只加载一次）
scene := navmesh.NewScene()
scene.Load("navmesh.bin")

// 2. 创建 Agent（指定位置，自动找最近 NavMesh 点）
agent := scene.CreateAgentAtPosition(radius, height, maxSpeed, posX, posY, posZ)

// 3. 路径查询
path := agent.FindPathCrowd(startX, startY, startZ, endX, endY, endZ)

// 4. 运动控制（每帧）
agent.SetMoveTarget(targetX, targetY, targetZ)
agent.Update(deltaTime)
pos := agent.GetPosition()
```

### Resource 管理（NavMeshMgr）

```go
type NavMeshMgr struct {
    common.ResourceBase
    sceneMgr *navmesh.Scene
    mapName  string
}

// 全局缓存（单例，避免重复加载同一地图）
var globalNavMeshCache = &navMeshCache{
    scenes: map[string]*navmesh.Scene
}
```

**坐标转换**：Unity 左手坐标系 ↔ NavMesh 右手坐标系（Z 轴取反）。

## 路网系统（Road Network）

### 数据结构

```go
Point {
    Index       int
    ID          int
    Edges       []*Edge       // 邻接边
    TotalWeight int64         // 所有边权重之和（用于随机选择）
    Position    Vec3I         // 整数坐标
}

Edge {
    To     *Point
    Weight int64
}

RoadNetwork {
    points   []*Point
    pointMap map[int]*Point   // ID → Point
}
```

### A* 寻路算法

```go
GetRoadList(startID, endID int) ([]int, error)
```

1. 初始化 gScore / fScore / prev / visited 数组
2. 最小堆优先队列
3. 启发式：曼哈顿距离 `|ax-bx| + |ay-by| + |az-bz|`
4. 回溯：终点反向追踪到起点

### 辅助方法

| 方法 | 功能 |
|------|------|
| `PathIDToVec3List()` | 路点 ID 序列 → 坐标序列 |
| `FindNearestPointID()` | 坐标 → 最近路点 ID |
| `GetNextPoint()` | 按权重随机选择下一个路点 |

### Resource 层

```go
type MapRoadNetworkMgr struct {
    common.ResourceBase
    MapInfo *Map    // map[线路名] → RoadNetwork
}
```

## Grid 空间划分

### 数据结构

```go
GridMgr {
    gridCountX, gridCountY  int
    cellSizeX, cellSizeY    float32    // 单元格大小（默认 128.0）
    grids                   []*Grid    // 线性数组
    entityMap               map[uint64]*GridEntityInfo
    dirtyGridIds            []int      // 本帧有变化的网格 ID
}

Grid {
    entities  map[uint64]*GridEntityInfo   // 已确认实体
    enterMap  map[uint64]*GridEntityInfo   // 即将进入
    leaveMap  map[uint64]*GridEntityInfo   // 即将离开
    removeMap map[uint64]*GridEntityInfo   // 即将移除
    // 帧内缓存
    entitiesCache []*GridEntityInfo
    isDirty       bool
}
```

### 核心操作

```go
GetGridIdByPosition(x, y)     → gridId = i * gridCountY + j
GetNineGridListByCentral()    → 3×3 九宫格

UpdateEntityPosition(entity, x, y)
├─ 计算新格子 ID
├─ 旧格子 → leaveMap
└─ 新格子 → enterMap

Clear()  // 帧结束：enterMap → entities，清理临时 map
```

### 脏标记与缓存

- `dirtyGridIds`：帧更新时累积，帧结束时提交
- `entitiesCache`：帧内缓存实体列表，数据变化时 `invalidateCache()`

## NPC 移动组件集成

### 双寻路引擎

```go
NpcMoveComp {
    // 路点寻路
    pointList     []*Vec3
    nowIndex      int
    ePathFindType int32    // RoadNetWork(1) / NavMesh(2)

    // NavMesh 寻路
    NavMesh NavMeshData {
        Agent        *navmesh.Agent
        TargetPos    Vec3
        TargetType   int32    // Player / WayPoint
        TargetEntity uint64
        IsMoving     bool
        Path         []Vec3
        PathIndex    int
    }

    // 速度与状态
    speed, RunSpeed, BaseSpeed  float32
    eState     int32   // Stop(0) / Move(1) / Run(2)
    prevEState int32   // 暂停前状态（用于 Resume）
}
```

### 移动生命周期

```
SetNavAgent() → 初始化
SetNavMoveTarget() / SetNavPath() → 设置目标
    ↓
UpdateNavAgent()            每帧推进
AdvanceNavPathPoint()       完成路点
    ↓
IsNavPathComplete()         检查完成
StopNavMove()               停止
DestroyNavAgent()           销毁
```

### 暂停/恢复

- `PauseState()`：Move/Run → Stop，保存 `prevEState`
- `ResumeState()`：Stop → 恢复 `prevEState`
- 用于对话、逮捕等中断场景

## 场景初始化顺序

```
scene_impl.go:
1. NewPlayerManager()
2. NewGridMgr(cellSize=128.0)
3. NewSubTransformMgr()
4. NewInitObjectManager()
5. NewSpawnPointManager()
6. NewNavMeshMgr(s)              ← NavMesh 管理
7. initNpcAISystemsFromConfig()
8. 按场景类型初始化（Town / Sakura / ...）
```

## 关键设计决策

| 方面 | 设计 | 原因 |
|------|------|------|
| 双寻路 | NavMesh + 路点网络 | NavMesh 用局部移动，路点用全局导航 |
| 全局缓存 | NavMesh Scene 单例 | 避免重复加载同一地图网格数据 |
| 坐标转换 | Z 轴取反 | Unity(左手) ↔ NavMesh(右手) 适配 |
| Grid 缓存 | 帧内缓存 + 脏标记 | 减少频繁 map 遍历分配 |
| 路径方法 | Query vs Crowd | Query 详细，Crowd 含避障更快 |
| 物理引擎 | Linux 空实现 | 仅 Windows 有完整 PhysX 实现 |

## 关键文件路径

| 文件 | 内容 |
|------|------|
| `pkg/physics/type.go` | PhysX 类型定义 |
| `pkg/physics/physx_linux.go` | PhysX Linux 存根 |
| `pkg/navmesh/types.go` | NavMesh Go 类型 |
| `pkg/navmesh/c_wrapper/navmesh_wrapper.h` | NavMesh C 接口 |
| `pkg/navmesh/scene_linux.go` | NavMesh 场景 CGO |
| `pkg/navmesh/agent_linux.go` | NavMesh Agent CGO |
| `common/pathfind/navmesh/scene.go` | NavMesh 高层包装 |
| `common/pathfind/road_network/network.go` | 路网 A* 核心 |
| `ecs/res/navmesh/navmesh_mgr.go` | NavMeshMgr Resource |
| `ecs/res/road_network/map.go` | 路网 Resource |
| `ecs/res/grid.go` | Grid 空间划分 |
| `ecs/com/cnpc/npc_move.go` | NPC 移动组件 |
| `ecs/system/npc/move.go` | NPC 移动系统 |
