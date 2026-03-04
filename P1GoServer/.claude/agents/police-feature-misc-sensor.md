# Police Feature MiscSensor Agent

## 职责

优化 MiscSensor，使其只处理警察状态特征（跟随 PoliceComp 状态变化）。

## 前置条件

- 阅读计划文件：`.claude/plans/police-feature-refactor-plan.md`
- 阅读感知系统规范：`.claude/rules/sensor-system.md`

---

## 任务 1.1：简化 updatePoliceMiscFeature()

### 目标文件
`servers/scene_server/internal/ecs/system/sensor/misc_sensor.go`

### 修改内容

1. **只保留状态特征的更新逻辑**
2. **移除 `feature_arrested` 相关代码**（改由事件处理）
3. **根据 PoliceComp 状态完整映射**

### 状态特征映射

| PoliceComp.State | feature_state_pursuit | feature_pursuit_entity_id | feature_pursuit_miss |
|------------------|----------------------|--------------------------|---------------------|
| None | false | 0 | false |
| Suspect | false | 0 | false |
| Arresting | true | ArrestingPlayer | false |
| Investigate | false | 0 | true |

### 修改后代码

```go
func (ms *MiscSensor) updatePoliceMiscFeature(entityID uint64, decisionComp *caidecision.DecisionComp) {
    policeComp, ok := common.GetComponentAs[*cpolice.NpcPoliceComp](ms.scene, entityID, common.ComponentType_NpcPolice)
    if !ok {
        return
    }

    state := policeComp.GetState()

    // 状态特征：feature_state_pursuit
    isPursuit := state == int32(cpolice.ESuspicionState_Arresting)
    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     entityID,
        FeatureKey:   "feature_state_pursuit",
        FeatureValue: isPursuit,
    }); err != nil {
        log.Errorf("[MiscSensor] update feature_state_pursuit failed, npc_entity_id=%v, err=%v", entityID, err)
    }

    // 状态特征：feature_pursuit_entity_id
    var pursuitEntityID uint64
    if isPursuit {
        pursuitEntityID = policeComp.GetArrestingPlayer()
    }
    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     entityID,
        FeatureKey:   "feature_pursuit_entity_id",
        FeatureValue: pursuitEntityID,
    }); err != nil {
        log.Errorf("[MiscSensor] update feature_pursuit_entity_id failed, npc_entity_id=%v, err=%v", entityID, err)
    }

    // 状态特征：feature_pursuit_miss
    isMiss := state == int32(cpolice.ESuspicionState_Investigate)
    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     entityID,
        FeatureKey:   "feature_pursuit_miss",
        FeatureValue: isMiss,
    }); err != nil {
        log.Errorf("[MiscSensor] update feature_pursuit_miss failed, npc_entity_id=%v, err=%v", entityID, err)
    }
}
```

### 验证
```bash
go vet ./servers/scene_server/internal/ecs/system/sensor/misc_sensor.go
```

---

## 完成检查

- [ ] 只处理三个状态特征：pursuit、entity_id、miss
- [ ] 移除了 feature_arrested 相关代码
- [ ] 状态映射完整覆盖所有 PoliceComp 状态
- [ ] 日志格式符合规范（`[MiscSensor]` 标签）
- [ ] 编译通过

## 重构注意事项

1. **保持 switch-case 结构** - 不要将 switch-case 改为 if-else，用户偏好 switch-case 表达状态分支
2. **确认感知器被调用** - 检查 `sensor_feature.go` 中 `miscSensor.GetAndUpdateFeature(entityID)` 没有被注释掉
3. **不要注释代码** - 要么删除，要么保留，不要留下注释掉的代码
