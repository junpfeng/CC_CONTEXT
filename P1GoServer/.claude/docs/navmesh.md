---
name: navmesh
description: NavMesh 寻路系统开发和调试
---

# NavMesh 寻路系统助手

当用户需要使用或调试 NavMesh 寻路时使用。

## NpcMoveComp NavMesh 数据

```go
type NavMeshData struct {
    Agent        *navmesh.Agent // NavMesh 代理
    TargetPos    navmesh.Vec3   // 目标位置
    TargetType   int32          // 目标类型
    TargetEntity uint64         // 目标实体 ID
    IsMoving     bool           // 是否移动中
    Path         []navmesh.Vec3 // 路径点
    PathIndex    int            // 当前路点索引
    Radius       float32        // 代理半径
    Height       float32        // 代理高度
    MaxSpeed     float32        // 最大速度
}

// 目标类型
const (
    NavMeshTargetType_None     = 0
    NavMeshTargetType_Position = 1  // 固定位置
    NavMeshTargetType_Player   = 2  // 跟随玩家
    NavMeshTargetType_WayPoint = 3  // 路点
)
```

## 使用 NavMesh 寻路

### 移动到固定位置
```go
npcMoveComp := getNpcMoveComp(entity)

// 设置寻路类型
npcMoveComp.SetPathFindType(EPathFindType_NavMesh)

// 设置目标位置
npcMoveComp.NavMesh.TargetType = NavMeshTargetType_Position
npcMoveComp.NavMesh.TargetPos = navmesh.Vec3{X: x, Y: y, Z: z}

// 开始移动
npcMoveComp.StartMove()
```

### 追逐玩家
```go
// 设置目标为玩家
npcMoveComp.NavMesh.TargetType = NavMeshTargetType_Player
npcMoveComp.NavMesh.TargetEntity = playerEntityID

// 使用奔跑
npcMoveComp.StartRun()
```

### 停止寻路
```go
npcMoveComp.StopMove()
npcMoveComp.ClearNavPath()
```

## NavMesh 资源

位置：`servers/scene_server/internal/ecs/res/navmesh/`

```go
// 获取 NavMesh 资源
navmeshRes := scene.GetResource(common.ResourceType_NavMesh)

// 查询路径
path, err := navmeshRes.FindPath(startPos, endPos)
```

## 路网寻路（RoadNetWork）

用于小镇 NPC 的路网寻路：

```go
// 设置寻路类型
npcMoveComp.SetPathFindType(EPathFindType_RoadNetWork)

// 使用路网管理器查找路径
roadNetworkMgr := scene.GetResource(common.ResourceType_RoadNetwork)
path := roadNetworkMgr.FindPath(startNodeID, endNodeID)

// 设置路点列表
npcMoveComp.SetPointList(path)
npcMoveComp.StartMove()
```

## 调试技巧

```go
// 打印当前路径
log.Debugf("[NavMesh] NPC %d path: %v", entityID, npcMoveComp.NavMesh.Path)
log.Debugf("[NavMesh] Current index: %d", npcMoveComp.NavMesh.PathIndex)

// 检查是否到达目标
if npcMoveComp.IsFinish {
    log.Debugf("[NavMesh] NPC %d reached destination", entityID)
}
```

## 关键文件

- @servers/scene_server/internal/ecs/com/cnpc/npc_move.go
- @servers/scene_server/internal/ecs/res/navmesh/
- @pkg/navmesh/

## 使用方式

- `/navmesh debug <npc_id>` - 调试 NPC 寻路
- `/navmesh path <start> <end>` - 查询路径
