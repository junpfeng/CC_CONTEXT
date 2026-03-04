# 剩余11个行为树节点实施计划

## 概述

本文档描述剩余11个未实现节点的详细实施计划。

### 节点清单

| 节点 | 使用的Plan | 依赖组件 | 复杂度 |
|------|-----------|----------|--------|
| ClearDialogEventFeature | dialog | DecisionComp | 低 |
| GetCurrentTime | dialog | 无 | 低 |
| SetDialogPause | dialog | DialogComp | 低 |
| SetDialogPauseTime | dialog | DialogComp | 低 |
| SetDialogState | dialog | DialogComp | 低 |
| SetDialogEventType | dialog | DialogComp | 低 |
| UpdateOutFinishStampAfterDialog | dialog | DialogComp | 中 |
| SetInvestigatePlayer | investigate | PoliceComp | 低 |
| FindNearestRoadPoint | meeting_move | RoadNetworkMgr | 中 |
| SetupNavMeshPathToFeaturePos | investigate | NavMesh, MoveComp | 高 |
| SetSakuraControlEventType | sakura_npc_control | SakuraNpcControlComp | 低 |

---

## 并行Agent分配

```
┌─────────────────────────────────────────────────────────────────┐
│                   并行组（3个Agent同时执行）                      │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Agent A    │  │   Agent B    │  │   Agent C    │          │
│  │  对话节点组   │  │ 导航/路网组   │  │ 特定组件组   │          │
│  │   (7个)      │  │   (2个)      │  │   (2个)      │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                   │
└─────────┼─────────────────┼─────────────────┼───────────────────┘
          │                 │                 │
          └────────────┬────┴────────────────┘
                       ▼
              ┌────────────────┐
              │   Factory注册   │
              │   (合并修改)    │
              └────────────────┘
```

---

## Agent A：对话节点组（7个节点）

**新建文件**：`servers/scene_server/internal/common/ai/bt/nodes/dialog_ext.go`

### 节点详细设计

#### 1. ClearDialogEventFeature
```go
// 清除对话事件相关Feature
// 清除: feature_dialog_req, feature_dialog_finish_req, feature_knock_req
type ClearDialogEventFeatureNode struct {
    BaseLeafNode
}

func (n *ClearDialogEventFeatureNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    decisionComp := ctx.GetDecisionComp()
    if decisionComp == nil {
        return node.BtNodeStatusFailed
    }

    // 清除三个对话相关Feature
    decisionComp.ClearFeature("feature_dialog_req")
    decisionComp.ClearFeature("feature_dialog_finish_req")
    decisionComp.ClearFeature("feature_knock_req")

    return node.BtNodeStatusSuccess
}
```

#### 2. GetCurrentTime
```go
// 获取当前时间戳写入黑板
type GetCurrentTimeNode struct {
    BaseLeafNode
    OutputKey string // 输出到黑板的key
}

// 参数: output_key (string)
func (n *GetCurrentTimeNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    now := time.Now().UnixMilli() // 毫秒时间戳
    ctx.SetBlackboard(n.OutputKey, now)
    return node.BtNodeStatusSuccess
}
```

#### 3. SetDialogPause
```go
// 设置对话暂停状态
type SetDialogPauseNode struct {
    BaseLeafNode
    Paused bool
}

// 参数: paused (bool)
func (n *SetDialogPauseNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    dialogComp := getDialogComp(ctx)
    if dialogComp == nil {
        return node.BtNodeStatusFailed
    }
    dialogComp.SetOutPause(n.Paused)
    return node.BtNodeStatusSuccess
}
```

#### 4. SetDialogPauseTime
```go
// 设置对话暂停时间
type SetDialogPauseTimeNode struct {
    BaseLeafNode
    TimeKey string // 从黑板读取时间的key
}

// 参数: time_key (string)
func (n *SetDialogPauseTimeNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    dialogComp := getDialogComp(ctx)
    if dialogComp == nil {
        return node.BtNodeStatusFailed
    }

    pauseTime, ok := ctx.GetBlackboardInt64(n.TimeKey)
    if !ok {
        return node.BtNodeStatusFailed
    }

    dialogComp.SetOutPauseTime(pauseTime)
    return node.BtNodeStatusSuccess
}
```

#### 5. SetDialogState
```go
// 设置对话状态
type SetDialogStateNode struct {
    BaseLeafNode
    State string // "dialog", "idle" 等
}

// 参数: state (string)
func (n *SetDialogStateNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    dialogComp := getDialogComp(ctx)
    if dialogComp == nil {
        return node.BtNodeStatusFailed
    }
    dialogComp.SetDialogNewState(n.State)
    return node.BtNodeStatusSuccess
}
```

#### 6. SetDialogEventType
```go
// 设置对话事件类型
type SetDialogEventTypeNode struct {
    BaseLeafNode
    EventType string // "none", "dialog", "knock" 等
}

// 参数: event_type (string)
func (n *SetDialogEventTypeNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    dialogComp := getDialogComp(ctx)
    if dialogComp == nil {
        return node.BtNodeStatusFailed
    }
    dialogComp.SetDialogEventType(parseDialogEventType(n.EventType))
    return node.BtNodeStatusSuccess
}
```

#### 7. UpdateOutFinishStampAfterDialog
```go
// 对话结束后更新外出结束时间戳
// 计算: dialogDuration = nowTime - pauseTime; finishStamp += dialogDuration
type UpdateOutFinishStampAfterDialogNode struct {
    BaseLeafNode
}

func (n *UpdateOutFinishStampAfterDialogNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    dialogComp := getDialogComp(ctx)
    if dialogComp == nil {
        return node.BtNodeStatusFailed
    }

    // 获取暂停时间和当前结束时间戳
    pauseTime := dialogComp.GetOutPauseTime()
    finishStamp := dialogComp.GetOutFinishStamp()

    if pauseTime > 0 && finishStamp > 0 {
        nowTime := time.Now().UnixMilli()
        dialogDuration := nowTime - pauseTime
        newFinishStamp := finishStamp + dialogDuration
        dialogComp.SetOutFinishStamp(newFinishStamp)
    }

    return node.BtNodeStatusSuccess
}
```

### 依赖检查
需要先查看 DialogComp 的接口：
- `SetOutPause(bool)`
- `SetOutPauseTime(int64)`
- `GetOutPauseTime() int64`
- `SetDialogNewState(string)`
- `SetDialogEventType(type)`
- `GetOutFinishStamp() int64`
- `SetOutFinishStamp(int64)`

---

## Agent B：导航/路网节点组（2个节点）

**新建文件**：`servers/scene_server/internal/common/ai/bt/nodes/navigation.go`

### 节点详细设计

#### 1. FindNearestRoadPoint
```go
// 查找距离当前位置最近的路点
type FindNearestRoadPointNode struct {
    BaseLeafNode
    OutputKey string // 输出路点ID到黑板
}

// 参数: output_key (string)
func (n *FindNearestRoadPointNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 获取当前位置
    transformComp := ctx.GetTransformComp()
    if transformComp == nil {
        return node.BtNodeStatusFailed
    }
    currentPos := transformComp.GetPosition()

    // 获取路网管理器
    roadNetMgr, ok := common.GetResourceAs[*roadnetwork.MapRoadNetworkMgr](
        ctx.Scene, common.ResourceType_RoadNetworkMgr)
    if !ok {
        return node.BtNodeStatusFailed
    }

    // 查找最近路点
    nearestPointID := roadNetMgr.MapInfo.FindNearestPoint(currentPos)
    if nearestPointID <= 0 {
        return node.BtNodeStatusFailed
    }

    ctx.SetBlackboard(n.OutputKey, int64(nearestPointID))
    return node.BtNodeStatusSuccess
}
```

#### 2. SetupNavMeshPathToFeaturePos
```go
// 从Feature获取目标位置，使用NavMesh寻路
type SetupNavMeshPathToFeatureNode struct {
    BaseLeafNode
    PosKeys       []string // 位置Feature keys: [posx, posy, posz]
    RotKeys       []string // 旋转Feature keys: [rotx, roty, rotz]
    OutputPathKey string   // 输出路径到黑板
}

// 参数: pos_keys, rot_keys, output_path_key
func (n *SetupNavMeshPathToFeatureNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 获取目标位置从Feature
    decisionComp := ctx.GetDecisionComp()
    if decisionComp == nil {
        return node.BtNodeStatusFailed
    }

    // 读取目标位置
    posX := getFeatureFloat32(decisionComp, n.PosKeys[0])
    posY := getFeatureFloat32(decisionComp, n.PosKeys[1])
    posZ := getFeatureFloat32(decisionComp, n.PosKeys[2])
    targetPos := transform.Vec3{X: posX, Y: posY, Z: posZ}

    // 读取目标旋转
    rotX := getFeatureFloat32(decisionComp, n.RotKeys[0])
    rotY := getFeatureFloat32(decisionComp, n.RotKeys[1])
    rotZ := getFeatureFloat32(decisionComp, n.RotKeys[2])
    targetRot := transform.Vec3{X: rotX, Y: rotY, Z: rotZ}

    // 获取当前位置
    transformComp := ctx.GetTransformComp()
    if transformComp == nil {
        return node.BtNodeStatusFailed
    }
    currentPos := transformComp.GetPosition()

    // 获取NavMesh并寻路
    navMesh, ok := common.GetResourceAs[*navmesh.NavMeshMgr](
        ctx.Scene, common.ResourceType_NavMesh)
    if !ok {
        return node.BtNodeStatusFailed
    }

    pathList := navMesh.FindPath(currentPos, targetPos)
    if pathList == nil {
        return node.BtNodeStatusFailed
    }

    // 设置到移动组件
    moveComp := ctx.GetMoveComp()
    if moveComp != nil {
        moveComp.SetNavMeshPath(pathList, targetRot)
    }

    // 输出到黑板
    ctx.SetBlackboard(n.OutputPathKey, pathList)
    return node.BtNodeStatusSuccess
}
```

### 依赖检查
需要先查看：
- `RoadNetworkMgr.MapInfo.FindNearestPoint(pos)`
- `NavMeshMgr.FindPath(from, to)`
- `NpcMoveComp.SetNavMeshPath(path, rot)`

---

## Agent C：特定组件节点组（2个节点）

**新建文件**：`servers/scene_server/internal/common/ai/bt/nodes/specific_comp.go`

### 节点详细设计

#### 1. SetInvestigatePlayer
```go
// 设置调查玩家（用于警察NPC）
type SetInvestigatePlayerNode struct {
    BaseLeafNode
    PlayerID int64 // 玩家ID，0表示清除
}

// 参数: player_id (int64)
func (n *SetInvestigatePlayerNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 获取警察组件
    policeComp, ok := common.GetEntityComponentAs[*cpolice.NpcPoliceComp](
        ctx.Scene, ctx.EntityID, common.ComponentType_NpcPolice)
    if !ok {
        return node.BtNodeStatusFailed
    }

    policeComp.SetInvestigatePlayer(n.PlayerID)
    return node.BtNodeStatusSuccess
}
```

#### 2. SetSakuraControlEventType
```go
// 设置樱校NPC控制事件类型
type SetSakuraControlEventTypeNode struct {
    BaseLeafNode
    EventType string // "none", "control_start", "control_end" 等
}

// 参数: event_type (string)
func (n *SetSakuraControlEventTypeNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
    // 获取樱校NPC控制组件
    controlComp, ok := common.GetEntityComponentAs[*csakura.SakuraNpcControlComp](
        ctx.Scene, ctx.EntityID, common.ComponentType_SakuraNpcControl)
    if !ok {
        return node.BtNodeStatusFailed
    }

    controlComp.SetEventType(parseSakuraEventType(n.EventType))
    return node.BtNodeStatusSuccess
}
```

### 依赖检查
需要先查看：
- `NpcPoliceComp.SetInvestigatePlayer(playerID)`
- `SakuraNpcControlComp.SetEventType(type)`

---

## Factory注册（合并到factory.go）

所有Agent完成后，在 `factory.go` 中添加：

```go
// 对话扩展节点
f.Register("ClearDialogEventFeature", createClearDialogEventFeatureNode)
f.Register("GetCurrentTime", createGetCurrentTimeNode)
f.Register("SetDialogPause", createSetDialogPauseNode)
f.Register("SetDialogPauseTime", createSetDialogPauseTimeNode)
f.Register("SetDialogState", createSetDialogStateNode)
f.Register("SetDialogEventType", createSetDialogEventTypeNode)
f.Register("UpdateOutFinishStampAfterDialog", createUpdateOutFinishStampAfterDialogNode)

// 导航节点
f.Register("FindNearestRoadPoint", createFindNearestRoadPointNode)
f.Register("SetupNavMeshPathToFeaturePos", createSetupNavMeshPathToFeatureNode)

// 特定组件节点
f.Register("SetInvestigatePlayer", createSetInvestigatePlayerNode)
f.Register("SetSakuraControlEventType", createSetSakuraControlEventTypeNode)
```

---

## 任务清单

### Agent A - 对话节点组
- [ ] 阅读 DialogComp 接口了解可用方法
- [ ] 实现 ClearDialogEventFeatureNode
- [ ] 实现 GetCurrentTimeNode
- [ ] 实现 SetDialogPauseNode
- [ ] 实现 SetDialogPauseTimeNode
- [ ] 实现 SetDialogStateNode
- [ ] 实现 SetDialogEventTypeNode
- [ ] 实现 UpdateOutFinishStampAfterDialogNode
- [ ] 编译验证

### Agent B - 导航节点组
- [ ] 阅读 RoadNetworkMgr 和 NavMeshMgr 接口
- [ ] 实现 FindNearestRoadPointNode
- [ ] 实现 SetupNavMeshPathToFeatureNode
- [ ] 编译验证

### Agent C - 特定组件节点组
- [ ] 阅读 NpcPoliceComp 接口
- [ ] 阅读 SakuraNpcControlComp 接口
- [ ] 实现 SetInvestigatePlayerNode
- [ ] 实现 SetSakuraControlEventTypeNode
- [ ] 编译验证

### 合并阶段
- [ ] 在 factory.go 中注册所有11个新节点
- [ ] 运行完整测试
- [ ] 验证所有9个Plan能正确加载

---

## 时间估算

| Agent | 节点数 | 预计耗时 |
|-------|--------|----------|
| Agent A | 7 | 1-2小时 |
| Agent B | 2 | 1小时 |
| Agent C | 2 | 30分钟 |
| 合并 | - | 30分钟 |
| **总计** | **11** | **2-3小时** |

---

## 验收标准

- [ ] 所有11个节点实现完成
- [ ] 编译通过：`make build APPS='scene_server'`
- [ ] 所有行为树测试通过
- [ ] 9个Plan配置都能正确加载（无unknown node type错误）
