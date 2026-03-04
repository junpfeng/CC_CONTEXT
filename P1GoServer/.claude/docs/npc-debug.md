---
name: npc-debug
description: NPC 调试，查看 NPC 状态和行为
---

# NPC 调试助手

当用户需要调试 NPC 相关问题时使用。

## 调试信息收集

### 1. 基础信息
```go
// 获取 NPC 实体
entity := scene.GetEntity(entityID)

// NPC 组件
npcComp := entity.GetComponent(common.ComponentType_Npc).(*cnpc.NpcComp)
log.Debugf("NPC ID: %d, Name: %s", npcComp.NpcID, npcComp.Name)

// 位置信息
transformComp := entity.GetComponent(common.ComponentType_Transform).(*ctransform.TransformComp)
log.Debugf("Position: %v, Rotation: %v", transformComp.Position, transformComp.Rotation)
```

### 2. 移动状态
```go
moveComp := entity.GetComponent(common.ComponentType_NpcMove).(*cnpc.NpcMoveComp)
log.Debugf("Move State: %d (0=Stop, 1=Move, 2=Run)", moveComp.GetState())
log.Debugf("Speed: %.2f, IsFinish: %v", moveComp.GetSpeed(), moveComp.IsFinish)
log.Debugf("PathFindType: %d (1=RoadNetwork, 2=NavMesh)", moveComp.GetPathFindType())
log.Debugf("Current Point Index: %d / %d", moveComp.GetNowIndex(), len(moveComp.GetPointList()))
```

### 3. 决策状态
```go
decisionComp := entity.GetComponent(common.ComponentType_AIDecision).(*caidecision.DecisionComp)

// 当前计划
plan := decisionComp.CurPlan()
if plan != nil {
    log.Debugf("Current Plan: %s, From: %s", plan.Name, plan.FromPlan)
    for _, task := range plan.Tasks {
        log.Debugf("  Task: %s, Type: %d", task.Name, task.Type)
    }
}

// 关键特征值
features := []string{
    "feature_dialog_req",
    "feature_pursuit_entity_id",
    "feature_visible_players_count",
}
for _, key := range features {
    if val, ok := decisionComp.GetFeatureValue(key); ok {
        log.Debugf("Feature %s = %v", key, val.Value())
    }
}
```

### 4. 视野状态
```go
visionComp := entity.GetComponent(common.ComponentType_Vision).(*cvision.VisionComp)
log.Debugf("Vision Radius: %.2f, Angle: %.2f", visionComp.VisionRadius, visionComp.VisionAngle)
log.Debugf("Enabled: %v, Visible Count: %d", visionComp.IsEnabled(), visionComp.GetVisibleEntityCount())

// 可见实体
for _, visibleID := range visionComp.GetVisibleEntities() {
    record := visionComp.GetVisionRecord(visibleID)
    if record != nil {
        log.Debugf("  Visible: %d, Distance: %.2f, Duration: %dms",
            visibleID, record.Distance, time.Now().UnixMilli()-record.EnterTime)
    }
}
```

## 常见问题排查

### NPC 不移动
1. 检查 `NpcMoveComp.IsFinish` 是否为 true
2. 检查路点列表是否为空
3. 检查移动状态是否为 Stop
4. 检查是否有阻塞的决策

### NPC 决策异常
1. 检查当前计划是否正确
2. 检查特征值是否符合预期
3. 检查转移条件是否满足
4. 查看决策日志 `[VisionComp]`, `[DecisionSystem]`

### NPC 视野异常
1. 检查视野是否启用
2. 检查视野半径和角度
3. 检查 GridMgr AOI 是否正常
4. 检查目标实体是否在同一场景

## 日志过滤

```bash
# 过滤特定 NPC 的日志
grep "entity_id=12345" scene_server.log

# 过滤决策相关日志
grep "\[Decision\]\|\[VisionComp\]\|\[Executor\]" scene_server.log

# 过滤移动相关日志
grep "\[NpcMove\]\|\[NavMesh\]" scene_server.log
```

## 使用方式

- `/npc-debug <entity_id>` - 输出 NPC 完整状态
- `/npc-debug plan <entity_id>` - 查看决策状态
- `/npc-debug move <entity_id>` - 查看移动状态
- `/npc-debug vision <entity_id>` - 查看视野状态
