---
name: sensor
description: 感知系统开发，创建新感知器
---

# 感知系统开发助手

当用户需要开发感知相关功能时使用。

## 创建新感知器

### 1. 感知器模板

```go
// servers/scene_server/internal/ecs/system/sensor/my_sensor.go
package sensor

import (
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/common/ai/decision"
)

type MySensor struct {
    scene common.Scene
}

func NewMySensor(scene common.Scene) *MySensor {
    return &MySensor{scene: scene}
}

// Update 更新指定实体的特征
func (s *MySensor) Update(entityID uint64) {
    entity := s.scene.GetEntity(entityID)
    if entity == nil {
        return
    }

    // 获取决策组件
    decisionComp, ok := entity.GetComponent(common.ComponentType_AIDecision)
    if !ok {
        return
    }
    aiDecision := decisionComp.(*caidecision.DecisionComp)

    // 计算特征值
    value := s.calculate(entity)

    // 更新特征
    aiDecision.UpdateFeature(decision.UpdateFeatureReq{
        Key:   "feature_my_sensor_value",
        Value: value,
    })
}

func (s *MySensor) calculate(entity common.Entity) interface{} {
    // 实现计算逻辑
    return nil
}
```

### 2. 注册到 SensorFeatureSystem

```go
// sensor_feature.go
type SensorFeatureSystem struct {
    *system.SystemBase
    // ... 其他感知器
    mySensor *MySensor  // 添加新感知器
}

func New(scene common.Scene) common.System {
    return &SensorFeatureSystem{
        // ...
        mySensor: NewMySensor(scene),
    }
}

func (s *SensorFeatureSystem) updateNpcFeatures(entityID uint64) {
    // ... 其他感知器更新
    s.mySensor.Update(entityID)
}
```

## 已有感知器

| 感知器 | 更新的特征 |
|--------|-----------|
| VisionSensor | vision_radius, visible_players_count |
| DistanceSensor | 玩家距离 |
| StateSensor | NPC 状态 |
| EventSensorFeature | 事件触发的特征 |
| ScheduleSensorFeature | 日程相关特征 |
| MiscSensor | 警察状态特征（pursuit, entity_id, miss） |

## 警察状态与特征

### 状态定义（优先级：Arresting > Investigate > Suspect > None）

| 状态 | 触发条件 | 对应特征 |
|------|----------|----------|
| None (0) | 无警戒目标 | pursuit=false, miss=false |
| Suspect (1) | 有玩家在警戒列表 | pursuit=false, miss=false |
| Arresting (2) | 警戒值达阈值 | pursuit=true, entity_id=玩家ID |
| Investigate (3) | 追捕目标失去视野 | pursuit=false, miss=true |

**状态由 `PoliceComp.updatePoliceState()` 自动计算**，MiscSensor 根据状态更新特征。

### 特征值分类

| 特征 | 类型 | 处理位置 |
|------|------|----------|
| `feature_state_pursuit` | 状态 | MiscSensor |
| `feature_pursuit_entity_id` | 状态 | MiscSensor |
| `feature_pursuit_miss` | 状态 | MiscSensor |
| `feature_arrested` | 事件 | EventSensorSystem |
| `feature_release_wanted` | 事件 | EventSensorSystem |

## 事件系统使用

```go
// 定义新事件类型（在 event_sensor.go 中）
const (
    EventType_MyEvent EventType = "my_event"
)

// 获取事件系统并推送事件
eventSystem, ok := sensor.EventSensor.Get(scene)
if ok {
    eventSystem.Push(sensor.EventType_MyEvent, sourceID,
        sensor.WithTarget(targetID),
        sensor.WithData(myData),
        sensor.WithPriority(sensor.EventPriority_High))
}

// 在 EventSensorSystem.processEvent() 中注册处理
case EventType_MyEvent:
    es.processMyEvent(event)
```

## 关键文件

- @servers/scene_server/internal/ecs/system/sensor/sensor_feature.go
- @servers/scene_server/internal/ecs/system/sensor/vision_sensor.go
- @servers/scene_server/internal/ecs/system/sensor/event.go
- @servers/scene_server/internal/ecs/system/sensor/distance_sensor.go

## 使用方式

- `/sensor create <name>` - 创建新感知器
- `/sensor event <type>` - 添加新事件类型
- `/sensor feature <name>` - 添加新特征
