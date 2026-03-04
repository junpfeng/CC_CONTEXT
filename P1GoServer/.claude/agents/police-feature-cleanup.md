# Police Feature Cleanup Agent

## 职责

移除 PoliceSystem 和 BeingWantedSystem 中分散的特征值更新代码，改为推送事件。

## 前置条件

- 阅读计划文件：`.claude/plans/police-feature-refactor-plan.md`
- 确保 Phase 2（EventSensorSystem 事件处理）已完成

---

## 任务 3.1：修改 PoliceSystem

### 目标文件
`servers/scene_server/internal/ecs/system/police/police_system.go`

### 修改内容

在 `clearPoliceDataForPlayer()` 方法中：

1. **移除**直接的特征值更新代码
2. **改为**推送 `EventType_Arrested` 事件

### 修改前（约第 448-492 行）

```go
func (p *NpcPoliceSystem) clearPoliceDataForPlayer(playerEntityID uint64) {
    // ... 遍历警察 ...

    // 直接更新特征值（需要移除）
    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     policeEntityID,
        FeatureKey:   "feature_state_pursuit",
        FeatureValue: false,
    }); err != nil {
        // ...
    }

    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     policeEntityID,
        FeatureKey:   "feature_pursuit_entity_id",
        FeatureValue: 0,
    }); err != nil {
        // ...
    }

    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     policeEntityID,
        FeatureKey:   "feature_arrested",
        FeatureValue: true,
    }); err != nil {
        // ...
    }
}
```

### 修改后

```go
func (p *NpcPoliceSystem) clearPoliceDataForPlayer(playerEntityID uint64) {
    // ... 遍历警察 ...

    // 推送逮捕完成事件，由 EventSensorSystem 处理特征更新
    p.pushArrestedEvent(policeEntityID, playerEntityID)

    // 注意：状态特征（pursuit、entity_id）由 MiscSensor 根据 PoliceComp 状态自动更新
    // 只需要确保 PoliceComp 状态已正确设置
}

func (p *NpcPoliceSystem) pushArrestedEvent(policeEntityID, playerEntityID uint64) {
    eventSystem, ok := common.GetSystemAs[*sensor.EventSensorSystem](
        p.Scene(), common.SystemType_EventSensor)
    if !ok {
        log.Warningf("[PoliceSystem] EventSensorSystem not found")
        return
    }

    eventSystem.PushEvent(&sensor.EventInfo{
        Type:         sensor.EventType_Arrested,
        SourceEntity: policeEntityID,
        TargetEntity: playerEntityID,
        Priority:     sensor.EventPriority_High,
    })
}
```

### 验证
```bash
go vet ./servers/scene_server/internal/ecs/system/police/police_system.go
```

---

## 任务 3.2：修改 BeingWantedSystem

### 目标文件
`servers/scene_server/internal/ecs/system/police/being_wanted_system.go`

### 修改内容

在 `NotifyReleaseWanted()` 方法中：

1. **移除**直接的 `feature_release_wanted` 更新代码
2. **改为**推送 `EventType_ReleaseWanted` 事件

### 修改前（约第 195-238 行）

```go
func (bws *BeingWantedSystem) NotifyReleaseWanted(playerEntityID uint64) {
    // ... 遍历警察 ...

    // 直接更新特征值（需要移除）
    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     policeEntityID,
        FeatureKey:   "feature_release_wanted",
        FeatureValue: true,
    }); err != nil {
        // ...
    }
}
```

### 修改后

```go
func (bws *BeingWantedSystem) NotifyReleaseWanted(playerEntityID uint64) {
    // ... 遍历警察 ...

    // 推送结束通缉事件，由 EventSensorSystem 处理特征更新
    bws.pushReleaseWantedEvent(policeEntityID)
}

func (bws *BeingWantedSystem) pushReleaseWantedEvent(policeEntityID uint64) {
    eventSystem, ok := sensor.EventSensor.Get(bws.Scene())
    if !ok {
        log.Warningf("[BeingWantedSystem] EventSensorSystem not found")
        return
    }

    eventSystem.Push(sensor.EventType_ReleaseWanted, policeEntityID,
        sensor.WithPriority(sensor.EventPriority_Normal))
}
```

### 验证
```bash
go vet ./servers/scene_server/internal/ecs/system/police/being_wanted_system.go
```

---

## 任务 3.3：全局搜索确认

### 搜索命令

确保没有遗漏其他直接更新警察特征值的地方：

```bash
# 搜索 feature_arrested
grep -r "feature_arrested" servers/scene_server/

# 搜索 feature_release_wanted
grep -r "feature_release_wanted" servers/scene_server/

# 搜索 feature_state_pursuit（应该只在 MiscSensor 中）
grep -r "feature_state_pursuit" servers/scene_server/

# 搜索 feature_pursuit_entity_id（应该只在 MiscSensor 中）
grep -r "feature_pursuit_entity_id" servers/scene_server/

# 搜索 feature_pursuit_miss（应该只在 MiscSensor 中）
grep -r "feature_pursuit_miss" servers/scene_server/
```

### 期望结果

| 特征值 | 预期出现位置 |
|--------|-------------|
| feature_arrested | event_sensor.go |
| feature_release_wanted | event_sensor.go |
| feature_state_pursuit | misc_sensor.go |
| feature_pursuit_entity_id | misc_sensor.go |
| feature_pursuit_miss | misc_sensor.go |

---

## 任务 3.4：最终编译验证

```bash
make build APPS='scene_server'
```

---

## 完成检查

- [ ] PoliceSystem 不再直接更新特征值
- [ ] BeingWantedSystem 不再直接更新特征值
- [ ] 事件推送方法已添加
- [ ] 全局搜索确认无遗漏
- [ ] 编译通过
- [ ] 日志格式符合规范

## 重构注意事项

1. **使用正确的 API 获取 EventSensorSystem**
   ```go
   // 正确方式
   eventSystem, ok := sensor.EventSensor.Get(scene)

   // 错误方式（不存在）
   // common.GetSystemAs[*sensor.EventSensorSystem](scene, ...)
   ```

2. **确认 MiscSensor 被调用** - 移除业务系统中的特征更新代码前，确认 `sensor_feature.go` 中调用了 `miscSensor.GetAndUpdateFeature(entityID)`

3. **不要注释掉关键代码** - 如果要移除代码，直接删除，不要留下注释

4. **功能测试** - 编译通过不等于功能正常，需要实际测试：
   - 警察警戒值满后是否追击玩家
   - 逮捕完成后特征是否正确更新
   - 调查超时后特征是否正确更新
