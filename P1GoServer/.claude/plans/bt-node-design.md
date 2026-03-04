# 行为树新增节点详细设计

## 一、概述

本文档详细描述行为树驱动重构所需新增的 10 个叶子节点的设计。

### 节点清单

| 序号 | 节点名称 | 功能 | 优先级 |
|------|----------|------|--------|
| 1 | SetTransform | 设置 NPC 位置和朝向 | P0 |
| 2 | ClearFeature | 清除特定 Feature | P0 |
| 3 | StartRun | 开始奔跑 | P0 |
| 4 | SetPathFindType | 设置寻路类型 | P0 |
| 5 | SetTargetType | 设置目标类型 | P0 |
| 6 | QueryPath | 查询路网路径 | P1 |
| 7 | SetDialogPause | 设置对话暂停状态 | P1 |
| 8 | GetScheduleData | 从日程读取数据到黑板 | P1 |
| 9 | SyncFeatureToBlackboard | Feature 同步到黑板 | P1 |
| 10 | SyncBlackboardToFeature | 黑板同步到 Feature | P1 |

---

## 二、节点详细设计

### 2.1 SetTransform - 设置位置和朝向

#### 功能描述

从 DecisionComp 的 Feature 中读取位置和朝向信息，设置 NPC 的 Transform。

#### 接口定义

```go
// SetTransformNode 设置 NPC 位置和朝向
type SetTransformNode struct {
    BaseLeafNode

    // 参数：Feature Key 前缀（可选，默认使用标准 key）
    FeaturePrefix string  // 默认为空，使用 feature_pos_x/y/z, feature_rot_x/y/z

    // 或直接从黑板读取
    PositionKey   string  // 黑板中位置数据的 key
    RotationKey   string  // 黑板中朝向数据的 key
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `feature_prefix` | string | 否 | "" | Feature key 前缀 |
| `position_key` | string | 否 | "" | 从黑板读取位置的 key |
| `rotation_key` | string | 否 | "" | 从黑板读取朝向的 key |

#### 实现伪代码

```go
func (n *SetTransformNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 获取组件
    transformComp := ctx.GetTransformComp()
    if transformComp == nil {
        return node.BtNodeStatusFailed
    }

    var pos, rot *transform.Vec3

    // 优先从黑板读取
    if n.PositionKey != "" {
        pos = ctx.GetBlackboardVec3(n.PositionKey)
    }
    if n.RotationKey != "" {
        rot = ctx.GetBlackboardVec3(n.RotationKey)
    }

    // 否则从 Feature 读取
    if pos == nil {
        decisionComp := ctx.GetDecisionComp()
        if decisionComp == nil {
            return node.BtNodeStatusFailed
        }
        pos, rot = getTransformFromFeatures(decisionComp, n.FeaturePrefix)
    }

    if pos == nil {
        return node.BtNodeStatusFailed
    }

    // 设置位置和朝向
    transformComp.SetPosition(*pos)
    if rot != nil {
        transformComp.SetRotation(*rot)
    }

    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "SetTransform",
  "params": {
    "position_key": "target_position",
    "rotation_key": "target_rotation"
  }
}
```

```json
{
  "type": "SetTransform",
  "params": {
    "feature_prefix": ""
  }
}
```

---

### 2.2 ClearFeature - 清除 Feature

#### 功能描述

将指定的 Feature 设置为其类型的零值或指定值。

#### 接口定义

```go
// ClearFeatureNode 清除 Feature
type ClearFeatureNode struct {
    BaseLeafNode

    FeatureKey   string  // 要清除的 Feature key
    ClearValue   any     // 清除后的值（可选，默认为类型零值）
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `feature_key` | string | 是 | - | 要清除的 Feature key |
| `clear_value` | any | 否 | false/0/"" | 清除后的值 |

#### 实现伪代码

```go
func (n *ClearFeatureNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    decisionComp := ctx.GetDecisionComp()
    if decisionComp == nil {
        return node.BtNodeStatusFailed
    }

    // 确定清除值
    clearValue := n.ClearValue
    if clearValue == nil {
        // 根据现有值类型推断零值
        if existingVal, ok := decisionComp.GetFeatureValue(n.FeatureKey); ok {
            clearValue = getZeroValue(existingVal)
        } else {
            clearValue = false  // 默认 bool 类型
        }
    }

    decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     ctx.EntityID,
        FeatureKey:   n.FeatureKey,
        FeatureValue: clearValue,
    })

    return node.BtNodeStatusSuccess
}

func getZeroValue(val any) any {
    switch val.(type) {
    case bool:
        return false
    case int, int32, int64:
        return 0
    case uint64:
        return uint64(0)
    case string:
        return ""
    case float32, float64:
        return 0.0
    default:
        return nil
    }
}
```

#### 使用示例

```json
{
  "type": "ClearFeature",
  "params": {
    "feature_key": "feature_knock_req"
  }
}
```

```json
{
  "type": "ClearFeature",
  "params": {
    "feature_key": "feature_args1",
    "clear_value": ""
  }
}
```

---

### 2.3 StartRun - 开始奔跑

#### 功能描述

设置 NPC 进入奔跑状态，同时可选清除当前路径。

#### 接口定义

```go
// StartRunNode 开始奔跑
type StartRunNode struct {
    BaseLeafNode

    ClearPath bool  // 是否先清除路径
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `clear_path` | bool | 否 | false | 是否先清除当前路径 |

#### 实现伪代码

```go
func (n *StartRunNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }

    if n.ClearPath {
        moveComp.Clear()
    }

    moveComp.StartRun()

    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "StartRun",
  "params": {
    "clear_path": true
  }
}
```

---

### 2.4 SetPathFindType - 设置寻路类型

#### 功能描述

设置 NPC 的寻路类型（RoadNetwork、NavMesh、None）。

#### 接口定义

```go
// SetPathFindTypeNode 设置寻路类型
type SetPathFindTypeNode struct {
    BaseLeafNode

    PathFindType string  // "road_network", "nav_mesh", "none"
}

// 寻路类型常量
const (
    PathFindTypeNone        = "none"
    PathFindTypeRoadNetwork = "road_network"
    PathFindTypeNavMesh     = "nav_mesh"
)
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `path_find_type` | string | 是 | - | 寻路类型 |

#### 实现伪代码

```go
func (n *SetPathFindTypeNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }

    var pathFindType int32
    switch n.PathFindType {
    case PathFindTypeNone:
        pathFindType = int32(cnpc.EPathFindType_None)
    case PathFindTypeRoadNetwork:
        pathFindType = int32(cnpc.EPathFindType_RoadNetWork)
    case PathFindTypeNavMesh:
        pathFindType = int32(cnpc.EPathFindType_NavMesh)
    default:
        return node.BtNodeStatusFailed
    }

    moveComp.SetPathFindType(pathFindType)
    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "SetPathFindType",
  "params": {
    "path_find_type": "nav_mesh"
  }
}
```

---

### 2.5 SetTargetType - 设置目标类型

#### 功能描述

设置 NPC 的移动目标类型和目标实体。

#### 接口定义

```go
// SetTargetTypeNode 设置目标类型
type SetTargetTypeNode struct {
    BaseLeafNode

    TargetType     string  // "none", "waypoint", "player"
    TargetEntityKey string  // 黑板中目标实体 ID 的 key
    TargetEntityID  uint64  // 直接指定目标实体 ID
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `target_type` | string | 是 | - | 目标类型 |
| `target_entity_key` | string | 否 | "" | 从黑板读取目标实体 ID |
| `target_entity_id` | uint64 | 否 | 0 | 直接指定目标实体 ID |

#### 实现伪代码

```go
func (n *SetTargetTypeNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }

    // 获取目标实体 ID
    var targetEntityID uint64
    if n.TargetEntityKey != "" {
        targetEntityID, _ = ctx.GetBlackboardUint64(n.TargetEntityKey)
    } else {
        targetEntityID = n.TargetEntityID
    }

    // 设置目标实体
    moveComp.SetTargetEntity(targetEntityID)

    // 设置目标类型
    var targetType cnpc.ETargetType
    switch n.TargetType {
    case "none":
        targetType = cnpc.ETargetType_None
    case "waypoint":
        targetType = cnpc.ETargetType_WayPoint
    case "player":
        targetType = cnpc.ETargetType_Player
    default:
        return node.BtNodeStatusFailed
    }

    moveComp.SetTargetType(targetType)
    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "SetTargetType",
  "params": {
    "target_type": "player",
    "target_entity_key": "pursuit_target_id"
  }
}
```

---

### 2.6 QueryPath - 查询路网路径

#### 功能描述

从路网系统查询路径，并设置到移动组件。

#### 接口定义

```go
// QueryPathNode 查询路网路径
type QueryPathNode struct {
    BaseLeafNode

    // 起点配置（三选一）
    StartPointKey      string  // 从黑板读取
    StartPointFeature  string  // 从 Feature 读取
    UseCurrentPosition bool    // 使用当前位置

    // 终点配置（二选一）
    EndPointKey     string  // 从黑板读取
    EndPointFeature string  // 从 Feature 读取

    // 朝向配置
    RotationKey     string  // 从黑板读取目标朝向
    RotationFeature string  // 从 Feature 读取目标朝向

    // 路径标识
    PathKey string  // 路径的标识 key（如 "gotoMeeting"）
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `start_point_key` | string | 否 | "" | 从黑板读取起点 |
| `start_point_feature` | string | 否 | "" | 从 Feature 读取起点 |
| `use_current_position` | bool | 否 | false | 使用当前位置作为起点 |
| `end_point_key` | string | 否 | "" | 从黑板读取终点 |
| `end_point_feature` | string | 否 | "" | 从 Feature 读取终点 |
| `rotation_key` | string | 否 | "" | 从黑板读取朝向 |
| `rotation_feature` | string | 否 | "" | 从 Feature 读取朝向 |
| `path_key` | string | 否 | "" | 路径标识 |

#### 实现伪代码

```go
func (n *QueryPathNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 获取组件
    moveComp := ctx.GetMoveComp()
    if moveComp == nil {
        return node.BtNodeStatusFailed
    }

    // 获取路网管理器
    roadNetworkMgr, ok := common.GetResourceAs[*roadnetwork.MapRoadNetworkMgr](
        ctx.Scene, common.ResourceType_RoadNetworkMgr)
    if !ok {
        return node.BtNodeStatusFailed
    }

    // 获取起点
    var startPoint int
    if n.UseCurrentPosition {
        transformComp := ctx.GetTransformComp()
        if transformComp == nil {
            return node.BtNodeStatusFailed
        }
        curPos := transformComp.Position()
        startPoint, _, _ = roadNetworkMgr.MapInfo.FindNearestPointID(&curPos)
    } else if n.StartPointKey != "" {
        startPoint, _ = ctx.GetBlackboardInt(n.StartPointKey)
    } else if n.StartPointFeature != "" {
        startPoint = getFeatureInt(ctx, n.StartPointFeature)
    }

    // 获取终点
    var endPoint int
    if n.EndPointKey != "" {
        endPoint, _ = ctx.GetBlackboardInt(n.EndPointKey)
    } else if n.EndPointFeature != "" {
        endPoint = getFeatureInt(ctx, n.EndPointFeature)
    }

    // 查询路径
    pathList, err := roadNetworkMgr.MapInfo.FindPathToVec3List(startPoint, endPoint)
    if err != nil {
        return node.BtNodeStatusFailed
    }

    // 获取目标朝向
    var rotation *transform.Vec3
    if n.RotationKey != "" {
        rotation = ctx.GetBlackboardVec3(n.RotationKey)
    } else if n.RotationFeature != "" {
        rotation = getFeatureVec3(ctx, n.RotationFeature)
    }

    // 设置路径
    moveComp.SetPointList(n.PathKey, pathList, rotation)

    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "QueryPath",
  "params": {
    "start_point_feature": "feature_start_point",
    "end_point_feature": "feature_end_point",
    "rotation_feature": "feature_rotation",
    "path_key": "schedule_path"
  }
}
```

```json
{
  "type": "QueryPath",
  "params": {
    "use_current_position": true,
    "end_point_key": "meeting_end_point",
    "path_key": "gotoMeeting"
  }
}
```

---

### 2.7 SetDialogPause - 设置对话暂停状态

#### 功能描述

设置对话组件的暂停状态，并记录暂停时间。

#### 接口定义

```go
// SetDialogPauseNode 设置对话暂停状态
type SetDialogPauseNode struct {
    BaseLeafNode

    Pause bool  // true=暂停, false=恢复
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `pause` | bool | 是 | - | 是否暂停 |

#### 实现伪代码

```go
func (n *SetDialogPauseNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    dialogComp, ok := common.GetComponentAs[*cdialog.DialogComp](
        ctx.Scene, ctx.EntityID, common.ComponentType_Dialog)
    if !ok {
        return node.BtNodeStatusFailed
    }

    nowTime := mtime.NowSecondTickWithOffset()

    if n.Pause {
        // 进入暂停状态
        dialogComp.SetOutPause(true)
        dialogComp.SetOutPauseTime(nowTime)
        dialogComp.SetDialogNewState("dialog")
        dialogComp.SetDialogEventType(cdialog.Dialog_EventType_None)
    } else {
        // 恢复状态
        dialogComp.SetOutPause(false)

        // 计算对话时长，更新超时时间
        pauseTime := dialogComp.GetOutPauseTime()
        finishTime := dialogComp.GetOutFinishStamp()
        dialogDuration := nowTime - pauseTime
        dialogComp.SetOutFinishStamp(finishTime + dialogDuration)

        dialogComp.SetDialogNewState("idle")
        dialogComp.SetDialogEventType(cdialog.Dialog_EventType_None)
    }

    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "SetDialogPause",
  "params": {
    "pause": true
  }
}
```

---

### 2.8 GetScheduleData - 从日程读取数据到黑板

#### 功能描述

从 NPC 日程组件读取当前日程数据，存入黑板供后续节点使用。

#### 接口定义

```go
// GetScheduleDataNode 从日程读取数据到黑板
type GetScheduleDataNode struct {
    BaseLeafNode

    // 输出到黑板的 key
    StartPointKey    string  // 起点路点 ID
    EndPointKey      string  // 终点路点 ID
    PositionKey      string  // 目标位置
    RotationKey      string  // 目标朝向
    ScheduleKeyKey   string  // 日程 Key
    ServerTimeoutKey string  // 服务器超时时间
    ClientTimeoutKey string  // 客户端超时时间
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `start_point_key` | string | 否 | "schedule_start_point" | 起点输出 key |
| `end_point_key` | string | 否 | "schedule_end_point" | 终点输出 key |
| `position_key` | string | 否 | "schedule_position" | 位置输出 key |
| `rotation_key` | string | 否 | "schedule_rotation" | 朝向输出 key |
| `schedule_key_key` | string | 否 | "schedule_key" | 日程 Key 输出 |
| `server_timeout_key` | string | 否 | "server_timeout" | 服务器超时输出 |
| `client_timeout_key` | string | 否 | "client_timeout" | 客户端超时输出 |

#### 实现伪代码

```go
func (n *GetScheduleDataNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 获取日程组件
    scheduleComp, ok := common.GetComponentAs[*cnpc.NpcScheduleComp](
        ctx.Scene, ctx.EntityID, common.ComponentType_NpcSchedule)
    if !ok {
        return node.BtNodeStatusFailed
    }

    // 获取时间管理器
    timeMgr, ok := common.GetResourceAs[*time_mgr.TimeMgr](
        ctx.Scene, common.ResourceType_TimeMgr)
    if !ok {
        return node.BtNodeStatusFailed
    }

    // 获取当前日程
    nowTime := timeMgr.GetNowTimeInScene()
    nowSchedule := scheduleComp.GetNowSchedule(nowTime)
    if nowSchedule == nil {
        return node.BtNodeStatusFailed
    }

    // 写入黑板
    if n.StartPointKey != "" {
        ctx.SetBlackboard(n.StartPointKey, nowSchedule.Action.GetStartPoint())
    }
    if n.EndPointKey != "" {
        ctx.SetBlackboard(n.EndPointKey, nowSchedule.Action.GetEndPoint())
    }
    if n.PositionKey != "" {
        pos := nowSchedule.Action.GetPosition()
        ctx.SetBlackboard(n.PositionKey, &transform.Vec3{
            X: pos.GetX(), Y: pos.GetY(), Z: pos.GetZ()})
    }
    if n.RotationKey != "" {
        rot := nowSchedule.Action.GetRotation()
        ctx.SetBlackboard(n.RotationKey, &transform.Vec3{
            X: rot.GetX(), Y: rot.GetY(), Z: rot.GetZ()})
    }
    if n.ScheduleKeyKey != "" {
        ctx.SetBlackboard(n.ScheduleKeyKey, nowSchedule.Key)
    }
    if n.ServerTimeoutKey != "" {
        ctx.SetBlackboard(n.ServerTimeoutKey, nowSchedule.Action.GetServerTimeout())
    }
    if n.ClientTimeoutKey != "" {
        ctx.SetBlackboard(n.ClientTimeoutKey, nowSchedule.Action.GetClientTimeout())
    }

    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "GetScheduleData",
  "params": {
    "start_point_key": "path_start",
    "end_point_key": "path_end",
    "rotation_key": "target_rotation",
    "schedule_key_key": "current_schedule_key"
  }
}
```

---

### 2.9 SyncFeatureToBlackboard - Feature 同步到黑板

#### 功能描述

将 DecisionComp 中的 Feature 值同步到 BtContext 的黑板中。

#### 接口定义

```go
// SyncFeatureToBlackboardNode Feature 同步到黑板
type SyncFeatureToBlackboardNode struct {
    BaseLeafNode

    // 同步映射：Feature Key -> Blackboard Key
    // 如果 BlackboardKey 为空，则使用 FeatureKey 作为 BlackboardKey
    Mappings []FeatureMapping
}

type FeatureMapping struct {
    FeatureKey    string
    BlackboardKey string  // 可选，默认与 FeatureKey 相同
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `mappings` | array | 是 | - | Feature 到黑板的映射列表 |
| `mappings[].feature_key` | string | 是 | - | Feature key |
| `mappings[].blackboard_key` | string | 否 | feature_key | 黑板 key |

#### 实现伪代码

```go
func (n *SyncFeatureToBlackboardNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    decisionComp := ctx.GetDecisionComp()
    if decisionComp == nil {
        return node.BtNodeStatusFailed
    }

    for _, mapping := range n.Mappings {
        val, ok := decisionComp.GetFeatureValue(mapping.FeatureKey)
        if !ok {
            continue  // 跳过不存在的 Feature
        }

        bbKey := mapping.BlackboardKey
        if bbKey == "" {
            bbKey = mapping.FeatureKey
        }

        ctx.SetBlackboard(bbKey, val)
    }

    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "SyncFeatureToBlackboard",
  "params": {
    "mappings": [
      {"feature_key": "feature_pursuit_entity_id", "blackboard_key": "target_id"},
      {"feature_key": "feature_start_point"},
      {"feature_key": "feature_end_point"}
    ]
  }
}
```

---

### 2.10 SyncBlackboardToFeature - 黑板同步到 Feature

#### 功能描述

将 BtContext 黑板中的值同步到 DecisionComp 的 Feature 中。

#### 接口定义

```go
// SyncBlackboardToFeatureNode 黑板同步到 Feature
type SyncBlackboardToFeatureNode struct {
    BaseLeafNode

    // 同步映射：Blackboard Key -> Feature Key
    Mappings []BlackboardMapping

    // 可选：TTL（毫秒）
    TTLMs int64
}

type BlackboardMapping struct {
    BlackboardKey string
    FeatureKey    string  // 可选，默认与 BlackboardKey 相同
}
```

#### 参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `mappings` | array | 是 | - | 黑板到 Feature 的映射列表 |
| `mappings[].blackboard_key` | string | 是 | - | 黑板 key |
| `mappings[].feature_key` | string | 否 | blackboard_key | Feature key |
| `ttl_ms` | int64 | 否 | 0 | Feature TTL |

#### 实现伪代码

```go
func (n *SyncBlackboardToFeatureNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    decisionComp := ctx.GetDecisionComp()
    if decisionComp == nil {
        return node.BtNodeStatusFailed
    }

    for _, mapping := range n.Mappings {
        val, ok := ctx.GetBlackboard(mapping.BlackboardKey)
        if !ok {
            continue  // 跳过不存在的黑板值
        }

        featureKey := mapping.FeatureKey
        if featureKey == "" {
            featureKey = mapping.BlackboardKey
        }

        decisionComp.UpdateFeature(decision.UpdateFeatureReq{
            EntityID:     ctx.EntityID,
            FeatureKey:   featureKey,
            FeatureValue: val,
            TTLMs:        n.TTLMs,
        })
    }

    return node.BtNodeStatusSuccess
}
```

#### 使用示例

```json
{
  "type": "SyncBlackboardToFeature",
  "params": {
    "mappings": [
      {"blackboard_key": "computed_path_completed", "feature_key": "feature_args1"},
      {"blackboard_key": "target_id", "feature_key": "feature_pursuit_entity_id"}
    ],
    "ttl_ms": 0
  }
}
```

---

## 三、节点工厂注册

### 3.1 工厂注册代码

```go
// factory.go 新增注册

func NewNodeFactory() *NodeFactory {
    f := &NodeFactory{
        creators: make(map[string]NodeCreator),
    }

    // ... 现有节点 ...

    // 新增节点
    f.Register("SetTransform", createSetTransformNode)
    f.Register("ClearFeature", createClearFeatureNode)
    f.Register("StartRun", createStartRunNode)
    f.Register("SetPathFindType", createSetPathFindTypeNode)
    f.Register("SetTargetType", createSetTargetTypeNode)
    f.Register("QueryPath", createQueryPathNode)
    f.Register("SetDialogPause", createSetDialogPauseNode)
    f.Register("GetScheduleData", createGetScheduleDataNode)
    f.Register("SyncFeatureToBlackboard", createSyncFeatureToBlackboardNode)
    f.Register("SyncBlackboardToFeature", createSyncBlackboardToFeatureNode)

    return f
}
```

### 3.2 创建函数示例

```go
func createSetTransformNode(cfg *config.NodeConfig) (node.IBtNode, error) {
    n := NewSetTransformNode()

    if featurePrefix, ok := cfg.GetParamString("feature_prefix"); ok {
        n.FeaturePrefix = featurePrefix
    }
    if positionKey, ok := cfg.GetParamString("position_key"); ok {
        n.PositionKey = positionKey
    }
    if rotationKey, ok := cfg.GetParamString("rotation_key"); ok {
        n.RotationKey = rotationKey
    }

    return n, nil
}

func createClearFeatureNode(cfg *config.NodeConfig) (node.IBtNode, error) {
    featureKey, ok := cfg.GetParamString("feature_key")
    if !ok {
        return nil, fmt.Errorf("ClearFeature node requires 'feature_key' param")
    }

    clearValue, _ := cfg.GetParamAny("clear_value")

    return NewClearFeatureNode(featureKey, clearValue), nil
}

// ... 其他创建函数 ...
```

---

## 四、使用场景示例

### 4.1 home_idle 行为树

```json
{
  "name": "bt_home_idle",
  "description": "在家空闲状态",
  "root": {
    "type": "Sequence",
    "children": [
      {
        "type": "SetFeature",
        "params": {
          "feature_key": "feature_out_timeout",
          "feature_value": true
        }
      },
      {
        "type": "SetTransform",
        "params": {}
      }
    ]
  }
}
```

### 4.2 pursuit 行为树

```json
{
  "name": "bt_pursuit",
  "description": "追逐玩家",
  "root": {
    "type": "Sequence",
    "children": [
      {
        "type": "SyncFeatureToBlackboard",
        "params": {
          "mappings": [
            {"feature_key": "feature_pursuit_entity_id", "blackboard_key": "target_id"}
          ]
        }
      },
      {
        "type": "StartRun",
        "params": {
          "clear_path": true
        }
      },
      {
        "type": "SetPathFindType",
        "params": {
          "path_find_type": "nav_mesh"
        }
      },
      {
        "type": "SetTargetType",
        "params": {
          "target_type": "player",
          "target_entity_key": "target_id"
        }
      }
    ]
  }
}
```

### 4.3 move 行为树

```json
{
  "name": "bt_move",
  "description": "路网移动",
  "root": {
    "type": "Sequence",
    "children": [
      {
        "type": "CheckCondition",
        "params": {
          "feature_key": "feature_args1",
          "operator": "==",
          "value": "pathfind_completed"
        }
      },
      {
        "type": "Selector",
        "children": [
          {
            "type": "Sequence",
            "comment": "如果已完成寻路，直接清除标记",
            "children": [
              {
                "type": "ClearFeature",
                "params": {
                  "feature_key": "feature_args1",
                  "clear_value": ""
                }
              }
            ]
          },
          {
            "type": "Sequence",
            "comment": "否则执行寻路",
            "children": [
              {
                "type": "GetScheduleData",
                "params": {
                  "start_point_key": "start_point",
                  "end_point_key": "end_point",
                  "rotation_key": "target_rotation",
                  "schedule_key_key": "path_key"
                }
              },
              {
                "type": "SyncFeatureToBlackboard",
                "params": {
                  "mappings": [
                    {"feature_key": "feature_start_point", "blackboard_key": "start_point"},
                    {"feature_key": "feature_end_point", "blackboard_key": "end_point"}
                  ]
                }
              },
              {
                "type": "QueryPath",
                "params": {
                  "start_point_key": "start_point",
                  "end_point_key": "end_point",
                  "rotation_key": "target_rotation",
                  "path_key_key": "path_key"
                }
              },
              {
                "type": "SetPathFindType",
                "params": {
                  "path_find_type": "road_network"
                }
              },
              {
                "type": "SetTargetType",
                "params": {
                  "target_type": "waypoint"
                }
              },
              {
                "type": "StartMove",
                "params": {}
              }
            ]
          }
        ]
      }
    ]
  }
}
```

---

## 五、测试计划

### 5.1 单元测试

每个新节点需要以下测试：

1. **正常流程测试**：验证节点正确执行
2. **组件缺失测试**：验证组件不存在时返回 Failed
3. **参数边界测试**：验证参数边界情况

### 5.2 测试文件结构

```
bt/nodes/
├── set_transform.go
├── set_transform_test.go
├── clear_feature.go
├── clear_feature_test.go
├── start_run.go
├── start_run_test.go
├── set_pathfind_type.go
├── set_pathfind_type_test.go
├── set_target_type.go
├── set_target_type_test.go
├── query_path.go
├── query_path_test.go
├── set_dialog_pause.go
├── set_dialog_pause_test.go
├── get_schedule_data.go
├── get_schedule_data_test.go
├── sync_feature_bb.go
├── sync_feature_bb_test.go
├── sync_bb_feature.go
└── sync_bb_feature_test.go
```
