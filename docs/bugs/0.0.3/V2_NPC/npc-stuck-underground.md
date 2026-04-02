# Bug 分析：大世界部分 NPC 插入地面无法动弹

## Bug 描述
- **现象**：大世界场景中小部分 NPC 生成后视觉上插入地面，且无法动弹
- **"小部分"说明**：大多数 NPC 表现正常，仅路网节点 Y 坐标偏低的区域受影响
- **复现**：进入大世界，观察 NPC，部分 NPC 身体下半截嵌入地面，静止不动

## 代码定位

| 涉及文件 | 行号 | 作用 |
|---------|------|------|
| `bigworld_npc_spawner.go` | ~282-307 | spawn 时直接用路网节点 3D 坐标（含 Y），无 Raycast 修正 |
| `bigworld_default_patrol.go` | `OnEnter` ~82-86 | 记录 `startPos` = `GetEntityPos`（Y 来自 spawn，可能偏低） |
| `bigworld_default_patrol.go` | `pickNewTarget` ~147-148 | `target.Y = center.Y`（复用 startPos.Y，同样偏低） |
| `bigworld_navigation_handler.go` | `correctTargetY` ~258-282 | 三级 Raycast 修正——仅对**移动目标**生效，不对 spawn 点修正 |
| `BigWorldNpcTransformComp.cs` | ~60-98 | 客户端直接使用服务端下发 Y，无地面 Raycast |

**当前行为**：
1. NPC 在 `spawnNpcAt` 时用路网节点原始 Y → 实体建立在偏低位置
2. `BigWorldDefaultPatrolHandler.OnEnter` 记录 startPos.Y = 偏低 Y
3. `pickNewTarget` 生成的 patrol 目标 Y = center.Y（同样偏低）
4. navigation handler `correctTargetY` 修正移动**目标** Y，但 NPC **自身起点** Y 未修正
5. 客户端渲染位置 = 服务端实体 Y → NPC 视觉上插入地面

**预期行为**：NPC 生成时 spawn 坐标 Y 应经过 Raycast 修正（从 Y=200 向下打 Grounds 层），确保在地面以上正确高度。

## 全链路断点分析

### idea.md → feature.json
- **是否覆盖**：否
- **idea 原文**：V2_NPC idea 关注"动画层对齐"，无地面修正需求
- **feature.json 对应**：未提及 Y 坐标或地面修正

### feature.json → plan.json
- **是否覆盖**：否
- **feature 需求**：REQ-001~REQ-008 全为客户端动画
- **plan 设计**：所有任务纯客户端，无服务端 spawn Y 处理

### plan.json → tasks/
- **是否覆盖**：否（服务端 spawn Y 不在 V2_NPC 任务范围内）
- **对应任务**：无

### tasks/ → 代码实现
- **是否实现**：否（超出 V2_NPC 任务范围）
- **说明**：`bigworld_npc_spawner.go` 的 spawn Y 问题早于 V2_NPC 特性存在，不由任何 V2_NPC task 负责

### Review 检出
- **是否被发现**：否（所有 develop-review-report 均审查客户端动画代码，不覆盖服务端 spawn 逻辑）

## 归因结论

**主要原因**：需求遗漏 + 实现缺陷（两层）

**根因链**：
```
BigWorld 路网节点 Y 坐标不可信（路网生成时 Y 精度不足）
  ↓
bigworld_npc_spawner.go：spawn 时直接用路网节点 Y，无 Raycast 修正
  ↓
NPC 实体建立在偏低 Y → GetEntityPos 返回偏低 Y
  ↓
BigWorldDefaultPatrolHandler.OnEnter：startPos.Y = 偏低 Y
  ↓
pickNewTarget：target.Y = center.Y（继承偏低 Y）
  ↓
correctTargetY 修正了移动目标 Y（navigation handler），但实体自身 Y 未被"拉起"
  ↓
NpcMoveSystem 沿路网路点移动时 Y 逐渐修正，但 spawn 瞬间 ~ 移动前 NPC 在偏低位
  ↓
客户端直接用服务端 Y → 视觉上插入地面
```

**"无法动弹"原因**（次生）：
- 若 Fix D 未生效（服务端未重启），patrol handler 仍有移动问题
- 或：NPC 处于 spawn 后首帧，navigation handler 尚未完成第一次 correctTargetY，导致初始几帧视觉卡在地下

## 修复方案

### 代码修复

**方案 A（推荐）：spawn 时做 Raycast Y 修正**

在 `bigworld_npc_spawner.go` 的 `spawnNpcAt` 中，调用 Raycast 修正 spawn 坐标 Y：

```go
func (s *BigWorldNpcSpawner) spawnNpcAt(cfgId int32, pos transform.Vec3) error {
    // 修正 spawn 坐标 Y：从高度 200 向下 Raycast Grounds 层
    if correctedY, ok := s.terrainAccessor.RaycastGroundY(pos.X, pos.Z); ok {
        pos.Y = correctedY
    }
    // 其余逻辑不变...
}
```

同时 `bigworld_default_patrol.go` 的 `OnEnter` 使用 `GetEntityPos` 已能读到修正后的 Y（因为 spawn 已修正），startPos.Y 自然正确。

**方案 B（轻量）：patrol OnEnter 修正 startPos.Y**

若不改 spawner，在 `BigWorldDefaultPatrolHandler.OnEnter` 中对 startPos.Y 单独修正：

```go
if sx, _, sz, ok := ctx.Scene.GetEntityPos(ctx.EntityID); ok {
    if y, hit := ctx.Scene.RaycastGroundY(sx, sz); hit {
        ps.startPos = transform.Vec3{X: sx, Y: y, Z: sz}
    } else {
        ps.startPos = transform.Vec3{X: sx, Y: sy, Z: sz}
    }
}
```

**优先方案 A**：从根本上修复，避免所有依赖 spawn 坐标的代码都要各自修正 Y。

### 工作流优化建议

- **问题**：BigWorld 基础设施 bug（spawn Y 修正缺失）无法被 V2_NPC 纯客户端任务的 develop-review 发现
- **建议**：在 `feature:plan-creator` 生成 plan 时，若涉及大世界 NPC 生成，自动检查是否包含"Y 坐标地面修正"验收项
- **改哪里**：`skills/feature/plan-creator.md` 的验收检查清单，新增"大世界 NPC spawn 必须验证 Y 坐标在地面以上"
