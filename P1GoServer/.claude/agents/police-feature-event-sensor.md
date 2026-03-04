# Police Feature EventSensor Agent

## 职责

完善 EventSensorSystem，处理警察事件特征（一次性触发的特征）。

## 前置条件

- 阅读计划文件：`.claude/plans/police-feature-refactor-plan.md`
- 阅读感知系统规范：`.claude/rules/sensor-system.md`
- 阅读现有事件定义：`servers/scene_server/internal/ecs/system/sensor/event.go`

---

## 任务 2.1：确认/添加事件类型

### 目标文件
`servers/scene_server/internal/ecs/system/sensor/event.go`

### 检查内容

确认以下事件类型存在，如不存在则添加：

```go
const (
    // ... 现有事件类型 ...

    EventType_Arrested      // 逮捕完成事件
    EventType_ReleaseWanted // 结束通缉事件
)
```

### 事件结构

确认 EventInfo 结构支持：
- SourceEntity（警察实体ID）
- TargetEntity（玩家实体ID，可选）
- Priority（事件优先级）

---

## 任务 2.2：处理逮捕完成事件

### 目标文件
`servers/scene_server/internal/ecs/system/sensor/event_sensor.go`

### 检查/完善 processArrestedEvent()

```go
func (es *EventSensorSystem) processArrestedEvent(event *EventInfo) {
    policeEntityID := event.SourceEntity

    decisionComp, ok := common.GetComponentAs[*caidecision.DecisionComp](
        es.Scene(), policeEntityID, common.ComponentType_AIDecision)
    if !ok {
        return
    }

    // 事件特征：feature_arrested（带 TTL）
    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     policeEntityID,
        FeatureKey:   "feature_arrested",
        FeatureValue: true,
        TTL:          1000, // 1秒后自动清理
    }); err != nil {
        log.Errorf("[EventSensor] update feature_arrested failed, npc_entity_id=%v, err=%v", policeEntityID, err)
    }
}
```

---

## 任务 2.3：处理结束通缉事件

### 目标文件
`servers/scene_server/internal/ecs/system/sensor/event_sensor.go`

### 添加 processReleaseWantedEvent()

```go
func (es *EventSensorSystem) processReleaseWantedEvent(event *EventInfo) {
    policeEntityID := event.SourceEntity

    decisionComp, ok := common.GetComponentAs[*caidecision.DecisionComp](
        es.Scene(), policeEntityID, common.ComponentType_AIDecision)
    if !ok {
        return
    }

    // 事件特征：feature_release_wanted（带 TTL）
    if err := decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     policeEntityID,
        FeatureKey:   "feature_release_wanted",
        FeatureValue: true,
        TTL:          1000, // 1秒后自动清理
    }); err != nil {
        log.Errorf("[EventSensor] update feature_release_wanted failed, npc_entity_id=%v, err=%v", policeEntityID, err)
    }
}
```

### 在事件分发中注册

```go
func (es *EventSensorSystem) processEvent(event *EventInfo) {
    switch event.Type {
    // ... 现有事件处理 ...

    case EventType_Arrested:
        es.processArrestedEvent(event)
    case EventType_ReleaseWanted:
        es.processReleaseWantedEvent(event)
    }
}
```

---

## 任务 2.4：验证事件推送接口

### 确认推送方法

确保其他系统可以推送事件：

```go
// 推送逮捕完成事件
eventSystem.PushEvent(&EventInfo{
    Type:         EventType_Arrested,
    SourceEntity: policeEntityID,
    TargetEntity: playerEntityID,
    Priority:     EventPriority_High,
})

// 推送结束通缉事件
eventSystem.PushEvent(&EventInfo{
    Type:         EventType_ReleaseWanted,
    SourceEntity: policeEntityID,
    Priority:     EventPriority_Normal,
})
```

### 验证
```bash
go vet ./servers/scene_server/internal/ecs/system/sensor/...
```

---

## 完成检查

- [ ] 事件类型已定义（Arrested、ReleaseWanted）
- [ ] processArrestedEvent() 正确处理 feature_arrested
- [ ] processReleaseWantedEvent() 正确处理 feature_release_wanted
- [ ] 事件分发逻辑已注册
- [ ] 事件特征带 TTL 自动清理
- [ ] 日志格式符合规范（`[EventSensor]` 标签）
- [ ] 编译通过
