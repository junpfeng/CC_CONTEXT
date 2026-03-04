# NPC System Refactor Agent

## 职责

重构感知系统、视野系统、警察系统，消除 TownNpcMgr 硬编码依赖。

## 前置条件

- 阅读计划文件：`.claude/plans/npc-ai-refactor-plan.md`
- 阅读 ECS 规范：`.claude/rules/ecs-architecture.md`
- 阅读日志规范：`.claude/rules/logging.md`

---

## 任务 1.1：sensor_feature.go 通用化

### 目标文件
`servers/scene_server/internal/ecs/system/sensor/sensor_feature.go`

### 修改内容

1. **移除 town 包依赖**（如果不再需要）
2. **修改 Update() 方法**，使用 EntityListByType 替代 TownNpcMgr

### 修改前
```go
// 从小镇管理器中获取NPC
townMgr, ok := common.GetResourceAs[*town.TownNpcMgr](ds.Scene(), common.ResourceType_TownNpcMgr)
if !ok {
    ds.Scene().Warning("[SensorFeatureSystem] townNpcMgr not found")
    return
}

// 遍历小镇管理器中的所有NPC
for _, townNpc := range townMgr.NpcMap {
    if townNpc.Entity == nil {
        continue
    }
    ds.eventSensorFeature.GetAndUpdateFeature(townNpc.Entity.ID())
    ds.scheduleSensorFeature.TimeTick(townNpc.Entity.ID())
}
```

### 修改后
```go
// 遍历所有 NPC 实体（通用）
npcEntities := ds.Scene().EntityListByType(common.EntityType_Npc)
for _, entity := range npcEntities {
    if entity == nil {
        continue
    }

    // 更新事件感知特征
    ds.eventSensorFeature.GetAndUpdateFeature(entity.ID())

    // 如果有日程组件，更新日程感知特征
    if _, ok := common.GetComponentAs[*cnpc.NpcScheduleComp](
        ds.Scene(), entity.ID(), common.ComponentType_NpcSchedule); ok {
        ds.scheduleSensorFeature.TimeTick(entity.ID())
    }
}
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 1.2：vision_system.go 通用化

### 目标文件
`servers/scene_server/internal/ecs/system/vision/vision_system.go`

### 修改内容

1. **移除 town 包依赖**（如果不再需要）
2. **修改 Update() 方法**
3. **修改 UpdateVisionByProto() 方法**

### 修改示例

```go
// 修改 Update() 方法
func (v *VisionSystem) Update() {
    // ... 时间检查 ...

    // 遍历所有 NPC 实体（通用）
    npcEntities := v.Scene().EntityListByType(common.EntityType_Npc)
    for _, entity := range npcEntities {
        if entity == nil {
            continue
        }
        v.updateNpcVision(entity)
    }
}

// 修改 UpdateVisionByProto() 方法中的 NPC 遍历
func (v *VisionSystem) UpdateVisionByProto(playerEntityID uint64, npcEntityIDs []uint64) {
    // ... 现有逻辑 ...

    // 如果需要遍历所有 NPC，使用 EntityListByType
    npcEntities := v.Scene().EntityListByType(common.EntityType_Npc)
    for _, entity := range npcEntities {
        // ...
    }
}
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 1.3：police_system.go 通用化

### 目标文件
`servers/scene_server/internal/ecs/system/police/police_system.go`

### 修改内容

1. **移除 town 包依赖**（如果不再需要）
2. **修改 Update() 方法**，使用 IsNpcPolice() 判断

### 修改前
```go
townMgr, ok := common.GetResourceAs[*town.TownNpcMgr](p.Scene(), common.ResourceType_TownNpcMgr)
if !ok {
    return
}

policeNpcs := townMgr.GetPoliceNpcs()
for _, townNpc := range policeNpcs {
    p.updatePoliceLogic(townNpc.Entity)
}
```

### 修改后
```go
// 遍历所有 NPC，筛选警察
npcEntities := p.Scene().EntityListByType(common.EntityType_Npc)
for _, entity := range npcEntities {
    if entity == nil {
        continue
    }

    // 使用通用判断函数
    if IsNpcPolice(p.Scene(), entity) {
        p.updatePoliceLogic(entity)
    }
}
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 1.4：新增 IsNpcPolice() 函数

### 目标文件
`servers/scene_server/internal/ecs/system/police/police_utils.go`（新建）

### 创建内容

```go
package police

import (
    "common/config"
    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/ecs/com/cnpc"
    "mp/servers/scene_server/internal/ecs/com/cpolice"
)

// IsNpcPolice 判断 NPC 是否为警察
// 优先检查警察组件的 IsPolice 字段，其次检查场景特定配置
func IsNpcPolice(scene common.Scene, entity common.Entity) bool {
    if entity == nil {
        return false
    }

    entityID := entity.ID()

    // 方式1：检查警察组件的 IsPolice 标志
    policeComp, ok := common.GetComponentAs[*cpolice.NpcPoliceComp](
        scene, entityID, common.ComponentType_NpcPolice)
    if ok && policeComp.IsPolice {
        return true
    }

    // 方式2：检查小镇 NPC 配置
    townNpcComp, ok := common.GetComponentAs[*cnpc.TownNpcComp](
        scene, entityID, common.ComponentType_TownNpc)
    if ok && townNpcComp.Cfg != nil {
        return townNpcComp.Cfg.GetOccupation() == config.PoliceTownNpcOccupationType
    }

    // 方式3：检查樱校 NPC 配置（如果樱校有警察职业配置）
    // sakuraNpcComp, ok := common.GetComponentAs[*cnpc.SakuraNpcComp](
    //     scene, entityID, common.ComponentType_SakuraNpc)
    // if ok && sakuraNpcComp.Cfg != nil {
    //     return sakuraNpcComp.Cfg.GetOccupation() == config.PoliceOccupationType
    // }

    return false
}
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 完成检查

- [ ] sensor_feature.go 不再依赖 TownNpcMgr
- [ ] vision_system.go 不再依赖 TownNpcMgr
- [ ] police_system.go 不再依赖 TownNpcMgr
- [ ] IsNpcPolice() 函数已创建
- [ ] 所有文件编译通过
- [ ] 日志符合规范（使用 `[ModuleName]` 标签，`%v` 格式）
