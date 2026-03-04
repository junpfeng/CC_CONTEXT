---
name: vision
description: NPC 视野系统开发和调试
---

# NPC 视野系统开发助手

当用户需要开发或调试 NPC 视野相关功能时使用。

## VisionComp 组件

位置：`servers/scene_server/internal/ecs/com/cvision/vision_comp.go`

```go
type VisionComp struct {
    common.ComponentBase
    VisionRadius    float32                   // 视野半径（米）
    VisionAngle     float32                   // 视野角度（360=全向）
    visibleEntities map[uint64]bool           // 可见实体
    visionRecords   map[uint64]*visionRecord  // 视野记录
    isEnabled       bool                      // 是否启用
    AlertEntity     uint64                    // 通缉实体
}

type visionRecord struct {
    EntityID  uint64  // 实体 ID
    Distance  float32 // 距离
    EnterTime int64   // 进入时间（毫秒）
}
```

## 常用方法

```go
// 获取视野组件
visionComp, ok := entity.GetComponent(common.ComponentType_Vision)
vc := visionComp.(*cvision.VisionComp)

// 设置视野参数
vc.SetVisionRadius(10.0)  // 10米
vc.SetVisionAngle(120.0)  // 120度扇形

// 启用/禁用视野
vc.SetEnabled(true)

// 检查实体是否在视野内
if vc.IsEntityInVision(targetID) {
    // 目标在视野内
}

// 获取可见实体列表
entities := vc.GetVisibleEntities()

// 获取实体进入视野的时间
enterTime := vc.GetEntityEnterTime(targetID)

// 获取实体在视野内的持续时间
duration := vc.GetEntityInVisionDuration(targetID)

// 获取完整视野记录
record := vc.GetVisionRecord(targetID)
if record != nil {
    log.Debugf("Entity %d in vision for %dms, distance: %.2f",
        record.EntityID, time.Now().UnixMilli()-record.EnterTime, record.Distance)
}
```

## VisionSystem 系统

位置：`servers/scene_server/internal/ecs/system/vision/vision_system.go`

职责：
1. 每帧更新 NPC 的可见实体列表
2. 基于 GridMgr 进行 AOI 查询
3. 进行视野角度和距离筛选

## VisionSensor 感知器

位置：`servers/scene_server/internal/ecs/system/sensor/vision_sensor.go`

更新的特征：
```go
"feature_vision_radius"          // 视野半径
"feature_vision_angle"           // 视野角度
"feature_vision_enabled"         // 是否启用
"feature_visible_entities_count" // 可见实体数
"feature_visible_players_count"  // 可见玩家数
"feature_visible_npcs_count"     // 可见 NPC 数
```

## 视野检测逻辑

```go
// 检查目标是否在视野内
func IsInVision(npcPos, npcForward, targetPos Vec3, radius, angle float32) bool {
    // 1. 距离检测
    distance := npcPos.DistanceTo(targetPos)
    if distance > radius {
        return false
    }

    // 2. 角度检测（如果不是全向视野）
    if angle < 360 {
        direction := targetPos.Sub(npcPos).Normalize()
        dot := npcForward.Dot(direction)
        halfAngle := angle / 2
        if math.Acos(dot) > halfAngle * math.Pi / 180 {
            return false
        }
    }

    // 3. 可选：射线检测（障碍物遮挡）

    return true
}
```

## 关键文件

- @servers/scene_server/internal/ecs/com/cvision/vision_comp.go
- @servers/scene_server/internal/ecs/system/vision/vision_system.go
- @servers/scene_server/internal/ecs/system/sensor/vision_sensor.go

## 使用方式

- `/vision config <npc_id>` - 查看 NPC 视野配置
- `/vision debug <npc_id>` - 调试视野检测
- `/vision add-feature` - 添加新的视野特征
