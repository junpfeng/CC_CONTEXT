# 设计文档：整合 EventSensorSystem 与 SensorFeatureSystem

## 1. 需求回顾

**目标**：将 `EventSensorSystem` 和 `SensorFeatureSystem` 合并为单一系统，确保 tick update 的确定性时序，SensorFeatureSystem 的逻辑先执行。

**动机**：两个系统各自独立 tick，虽然枚举顺序已保证 SensorFeature 先于 EventSensor，但无法保证同一帧内的原子性和数据一致性。

## 2. 当前架构

```
Scene.tick()
  ├── OnBeforeTick (按 SystemType 枚举序)
  ├── Update (按 SystemType 枚举序)
  │     ├── ... 其他系统 ...
  │     ├── SensorFeatureSystem.Update()  [枚举 34, 500ms]  ← 拉模型
  │     ├── EventSensorSystem.Update()    [枚举 35, 100ms]  ← 推模型
  │     └── ... 其他系统 ...
  └── OnAfterTick (按 SystemType 枚举序)
```

### 问题

1. 两个系统独立注册、独立 tick，时序依赖隐含在枚举值顺序中，不够显式
2. 不同的 tick 间隔（500ms vs 100ms）导致数据更新时机不对齐
3. EventSensorSystem 在 `initAllSystems()` 无条件创建，SensorFeatureSystem 在 `initSceneSystems()` 条件创建，生命周期不统一

## 3. 目标架构

```
Scene.tick()
  ├── Update
  │     ├── ... 其他系统 ...
  │     ├── SensorFeatureSystem.Update()  [枚举 34]
  │     │     ├── Step 1: 特征轮询 (500ms)  ← 原 SensorFeatureSystem 逻辑
  │     │     └── Step 2: 事件处理 (100ms)  ← 原 EventSensorSystem 逻辑
  │     └── ... 其他系统 ...
```

### 核心设计

**将 EventSensorSystem 作为 SensorFeatureSystem 的内部组件**，不再独立注册为 System。

- `EventSensorSystem` 保留完整的结构体和方法（Push API、事件队列、processEvent 等）
- 但不再通过 `AddSystem()` 注册，不再被场景 tick 循环独立调用
- `SensorFeatureSystem.Update()` 内部显式调用 `eventSensor.Update()`
- 各自保留独立的 tick 间隔（500ms / 100ms），互不干扰

### 时序保证

```go
func (ds *SensorFeatureSystem) Update() {
    // Step 1: 特征轮询（500ms 自管理）
    ds.updateFeatures()

    // Step 2: 事件处理（100ms 自管理）
    ds.eventSensor.Update()
}
```

每帧调用 `SensorFeatureSystem.Update()` 时：
- 特征轮询先执行（500ms 到才真正工作）
- 事件处理后执行（100ms 到才真正工作）
- **同一帧内，特征轮询一定先于事件处理**

## 4. 详细设计

### 4.1 SensorFeatureSystem 变更 (`sensor_feature.go`)

```go
type SensorFeatureSystem struct {
    *system.SystemBase
    lastUpdateTime        int64
    eventSensorFeature    *EventSensorFeature
    scheduleSensorFeature *ScheduleSensorFeature
    distanceSensor        *DistanceSensor
    visionSensor          *VisionSensor
    stateSensor           *StateSensor
    miscSensor            *MiscSensor
    eventSensor           *EventSensorSystem     // [新增] 事件感知系统（原独立 System）
}
```

**构造函数**：在内部创建 EventSensorSystem
```go
func NewSensorFeatureSystem(scene common.Scene) *SensorFeatureSystem {
    return &SensorFeatureSystem{
        // ... 原有字段 ...
        eventSensor: NewEventSensorSystem(scene), // [新增]
    }
}
```

**Update()**：拆分为两步
```go
func (ds *SensorFeatureSystem) Update() {
    // Step 1: 特征轮询（原逻辑，提取为方法）
    ds.updateFeatures()

    // Step 2: 事件处理（委托给内部 eventSensor）
    ds.eventSensor.Update()
}

func (ds *SensorFeatureSystem) updateFeatures() {
    // 原 Update() 的全部逻辑移到这里
    now := mtime.NowMilliTickWithOffset()
    if ds.lastUpdateTime == 0 { ... }
    if now-ds.lastUpdateTime < UpdateInterval { return }
    ds.lastUpdateTime = now
    // 遍历 NPC 更新特征 ...
}
```

**新增 Getter**：
```go
func (ds *SensorFeatureSystem) GetEventSensor() *EventSensorSystem {
    return ds.eventSensor
}
```

### 4.2 EventSensorSystem 变更 (`event_sensor.go`)

**仅修改 accessor**：
```go
func (eventSensorSystemHelper) Get(scene common.Scene) (*EventSensorSystem, bool) {
    // 改为从 SensorFeatureSystem 获取
    sys, ok := scene.GetSystem(common.SystemType_SensorFeature)
    if !ok {
        return nil, false
    }
    sfs, ok := sys.(*SensorFeatureSystem)
    if !ok {
        return nil, false
    }
    return sfs.GetEventSensor(), sfs.GetEventSensor() != nil
}
```

其余代码（Push、processEvent、事件处理器等）**完全不变**。

### 4.3 scene_impl.go 变更

**删除** `initAllSystems()` 中的 EventSensorSystem 创建（lines 450-455）：
```go
// 删除以下代码：
// eventSensorSystem := sensor.NewEventSensorSystem(s)
// err = s.AddSystem(eventSensorSystem)
// ...
```

`initSceneSystems()` 中的 SensorFeatureSystem 创建**不变**（它现在内部自动创建 EventSensorSystem）。

### 4.4 ecs.go 变更

**保留** `SystemType_EventSensor` 枚举值（避免后续枚举值偏移），添加注释：
```go
SystemType_SensorFeature         // 传感器特征系统（含事件感知）
SystemType_EventSensor           // [已废弃] 已整合到 SensorFeatureSystem
```

## 5. 兼容性分析

### 5.1 外部调用方（无需修改）

| 调用方 | 调用方式 | 兼容性 |
|--------|---------|--------|
| PoliceSystem | `sensor.EventSensor.Get(scene)` → `Push()` | 兼容（accessor 更新后自动生效）|
| BeingWantedSystem | `sensor.EventSensor.Get(scene)` → `Push()` | 兼容 |
| DecisionSystem | `sensor.EventSensor.Get(scene)` | 兼容 |
| town_npc handler | `sensor.EventSensor.Get(scene)` | 兼容 |
| sakura_npc handler | `sensor.EventSensor.Get(scene)` | 兼容 |
| trade handler | `sensor.EventSensor.Get(scene)` | 兼容 |
| NpcUpdateSystem | `GetSystem(SystemType_SensorFeature)` | 兼容（SensorFeatureSystem 不变）|
| town_npc/sakura_npc | `GetSystem(SystemType_SensorFeature)` | 兼容 |

### 5.2 创建条件

当前所有启用 NPC AI 的场景（Town/Sakura）都设置 `EnableSensor: true`，合并后 EventSensorSystem 的生命周期与 SensorFeatureSystem 一致，不会丢失事件处理能力。

## 6. 涉及文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `sensor_feature.go` | **修改** | 新增 eventSensor 字段、构造函数、Update 拆分、Getter |
| `event_sensor.go` | **修改** | 更新 EventSensor.Get() accessor |
| `scene_impl.go` | **修改** | 删除 initAllSystems 中的 EventSensorSystem 创建 |
| `ecs.go` | **修改** | 添加废弃注释 |

## 7. 风险评估

| 风险 | 级别 | 缓解 |
|------|------|------|
| 枚举值偏移 | 低 | 保留 SystemType_EventSensor，仅添加注释 |
| 事件延迟增加 | 无 | EventSensorSystem 保留 100ms 独立间隔 |
| 特征轮询无变化 | 无 | SensorFeatureSystem 保留 500ms 独立间隔 |
| 无 EnableSensor 的场景 | 低 | 当前所有场景均为 true，不受影响 |
