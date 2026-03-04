# 警察系统特征值优化计划

## 背景

当前警察系统的特征值更新逻辑分散在多个位置（MiscSensor、PoliceSystem、EventSensorSystem、BeingWantedSystem），导致：
- 代码难以维护
- 更新时机不一致
- 可能产生状态不同步问题

## 目标

按职责分离特征值更新逻辑：
- **事件特征** → EventSensorSystem 处理（一次性触发的特征）
- **状态特征** → MiscSensor 处理（跟随组件状态变化的特征）

## 特征值分类

| 特征值 | 类型 | 处理位置 | 说明 |
|--------|------|----------|------|
| `feature_state_pursuit` | 状态 | MiscSensor | 是否处于追捕状态，跟随 PoliceComp.State |
| `feature_pursuit_entity_id` | 状态 | MiscSensor | 追捕目标玩家ID，跟随 PoliceComp.ArrestingPlayer |
| `feature_pursuit_miss` | 状态 | MiscSensor | 追捕丢失（进入调查），跟随 State == Investigate |
| `feature_arrested` | 事件 | EventSensorSystem | 逮捕完成事件，一次性触发 |
| `feature_release_wanted` | 事件 | EventSensorSystem | 调查超时事件，一次性触发 |

## 实现计划

### Phase 1: MiscSensor 状态特征优化

#### 1.1 简化 MiscSensor.updatePoliceMiscFeature()

**文件**: `servers/scene_server/internal/ecs/system/sensor/misc_sensor.go`

**改动**:
- 只保留状态特征的更新逻辑
- 移除 `feature_arrested` 相关代码（改由事件处理）
- 根据 PoliceComp 状态映射更新：
  - `None` → pursuit=false, entity_id=0, miss=false
  - `Arresting` → pursuit=true, entity_id=玩家ID, miss=false
  - `Investigate` → pursuit=false, entity_id=0, miss=true
  - `Suspect` → pursuit=false, entity_id=0, miss=false

### Phase 2: EventSensorSystem 事件特征处理

#### 2.1 确认/添加事件类型

**文件**: `servers/scene_server/internal/ecs/system/sensor/event.go`

**检查事件类型**:
- `EventType_Arrested` - 逮捕完成事件
- `EventType_ReleaseWanted` - 结束通缉事件

#### 2.2 完善事件处理逻辑

**文件**: `servers/scene_server/internal/ecs/system/sensor/event_sensor.go`

**改动**:
- 确保 `processArrestedEvent()` 正确处理 `feature_arrested`
- 添加 `processReleaseWantedEvent()` 处理 `feature_release_wanted`

### Phase 3: 移除分散的特征更新代码

#### 3.1 修改 PoliceSystem

**文件**: `servers/scene_server/internal/ecs/system/police/police_system.go`

**改动**:
- 移除 `clearPoliceDataForPlayer()` 中的特征值更新代码
- 改为推送 `EventType_Arrested` 事件

#### 3.2 修改 BeingWantedSystem

**文件**: `servers/scene_server/internal/ecs/system/police/being_wanted_system.go`

**改动**:
- 移除 `NotifyReleaseWanted()` 中的 `feature_release_wanted` 更新
- 改为推送 `EventType_ReleaseWanted` 事件

### Phase 4: 验证与测试

#### 4.1 编译验证
- 确保所有文件编译通过
- 检查无未使用的导入

#### 4.2 逻辑验证
- 状态特征跟随 PoliceComp 状态正确更新
- 事件特征在正确时机触发

## 文件改动清单

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `sensor/misc_sensor.go` | 修改 | 简化，只处理状态特征 |
| `sensor/event.go` | 可能修改 | 确认/添加事件类型 |
| `sensor/event_sensor.go` | 修改 | 添加事件处理逻辑 |
| `police/police_system.go` | 修改 | 移除特征更新，改为推送事件 |
| `police/being_wanted_system.go` | 修改 | 移除特征更新，改为推送事件 |

## 风险评估

| 风险 | 级别 | 缓解措施 |
|------|------|----------|
| 状态特征更新延迟（最多500ms） | 低 | 可接受，感知系统更新周期 |
| 事件丢失导致特征未更新 | 中 | 事件系统已有可靠性保证 |
| 遗漏其他调用点 | 中 | 全局搜索确认所有调用点 |

## 时间线

- Phase 1: MiscSensor 优化
- Phase 2: EventSensorSystem 事件处理
- Phase 3: 移除分散代码
- Phase 4: 验证测试

---

## 执行记录与经验总结

### 执行状态：已完成

### 遇到的问题

#### 问题 1：MiscSensor 未被调用
- **现象**：警察警戒值满后不追击玩家
- **原因**：`sensor_feature.go` 中 `miscSensor.GetAndUpdateFeature(entityID)` 被注释掉
- **修复**：取消注释，确保 MiscSensor 在每 500ms 更新周期被调用

#### 问题 2：Agent 改变代码风格
- **现象**：Phase 1 Agent 将 switch-case 改为 if-else 布尔计算
- **原因**：Agent 认为 if-else 更简洁
- **修复**：改回 switch-case 结构，用户偏好 switch-case 表达状态分支

#### 问题 3：Agent 使用不存在的 API
- **现象**：Phase 3 Agent 使用 `common.GetSystemAs[T]()` 获取系统
- **原因**：Agent 猜测 API 而非检查实际存在的方法
- **修复**：使用正确的 `sensor.EventSensor.Get(scene)` helper 方法

### 经验教训

1. **不要注释代码** - 要删除就彻底删除，不要留下注释掉的代码
2. **保持代码风格** - 不要将 switch-case 改为 if-else（或反之）
3. **确认调用链完整** - 移除代码前，确认替代逻辑已正确启用
4. **使用正确的 API** - 先检查目标包中实际存在的方法
5. **功能测试** - 编译通过不等于功能正常，需要实际测试
6. **逐步验证** - 每个 Phase 完成后立即编译和功能验证

### 更新的文档

- `.claude/rules/sensor-system.md` - 警察状态系统和特征值说明
- `.claude/skills/refactor.md` - 重构禁忌和经验教训
- `.claude/skills/sensor.md` - 警察状态与特征说明

---

## 后续修复：警察状态系统

### 问题描述

`updatePoliceState()` 不支持 Investigate 状态，导致：
- 进入调查状态时，`GetState()` 返回错误的值（Suspect 而非 Investigate）
- 特征值更新与实际状态不匹配

### 修复内容

1. **修复 `updatePoliceState()`** - 添加 Investigate 状态支持
   ```go
   // 状态优先级：Arresting > Investigate > Suspect > None
   if p.arrestingPlayer != nil {
       newState = ESuspicionState_Arresting
   } else if p.investigatePlayerEntityID != 0 {
       newState = ESuspicionState_Investigate  // 新增
   } else if p.getSuspicionMapSize() > 0 {
       newState = ESuspicionState_Suspect
   }
   ```

2. **修复 `SetInvestigatePlayer()`** - 添加 `updatePoliceState()` 调用

3. **修复 `StopInvestigatePlayer()`** - 添加清除字段和状态更新

### 修改的文件

- `servers/scene_server/internal/ecs/com/cpolice/police_comp.go`
