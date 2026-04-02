# Bug 分析：大世界 NPC 走路动画原地踏步 + 部分 NPC 插入地面

## Bug 描述
- **现象 A**：大世界 NPC 播放走路动画，但视觉上原地踏步（位置几乎不变）
- **现象 B**：部分 NPC 仍然插入地面中（与前报告 `npc-stuck-underground.md` 现象相同，本报告补充动画视角）
- **关系**：两个现象是同一根因的不同表现，可能是同一批 NPC

## 代码定位

| 涉及文件 | 行号 | 关键逻辑 |
|---------|------|---------|
| `BigWorldNpcMoveComp.cs` | ~71-96 | CurrentSpeed = XZ 帧间位移 / deltaTime；< 0.001 → Idle |
| `BigWorldNpcAnimationComp.cs` | ~658-701 | UpdateSpeedDrivenAnimation：仅读 MoveComp.CurrentSpeed，无 IsMoving 直接触发 |
| `bigworld_default_patrol.go` | `pickNewTarget` | `target.Y = center.Y`（startPos.Y，来自 spawn，可能偏低） |
| `bigworld_navigation_handler.go` | `correctTargetY` | 修正目标 Y——但路径**中间节点** Y 由 A* 路网决定 |
| `bigworld_npc_spawner.go` | `spawnNpcAt` | spawn 坐标直接用路网节点，无 Raycast 修正 |

**已确认**：走路动画不存在"IsMoving 直接触发"路径，动画 100% 由位置变化驱动。

**当前行为**：
1. NPC spawn 在路网节点位置（Y 可能偏低，在地表以下）
2. Fix D 修复后 patrol handler 正确写 MoveTarget、IsMoving=true
3. syncNpcMovement 调用 A*，找到路网路径
4. 路网路径节点 Y 来自路网数据（同样可能偏低，`feedback_bigworld_y_offset`：路网 Y 不可信）
5. NpcMoveSystem 沿路径节点移动：NPC 在地表以下的 Y 平面上水平移动
6. 客户端收到位置更新：帧间 XZ delta > 0.001 → MoveMode.Walk → 播放走路动画
7. 但 NPC 在地表以下移动 → 从玩家视角（地面上方）看，NPC 像插在地里原地踏步

**预期行为**：NPC 沿地面以上路径移动，走路动画与位置变化视觉一致。

## 全链路断点分析

### idea.md → feature.json
- **是否覆盖**：否
- V2_NPC idea 仅关注客户端动画层（无地形 Y 处理需求）

### feature.json → plan.json
- **是否覆盖**：否（REQ-001~REQ-008 全为客户端动画）

### plan.json → tasks/
- **是否覆盖**：否

### tasks/ → 代码实现
- **是否实现**：否（超出范围）

### Review 检出
- **是否被发现**：否（所有 review 审查客户端动画代码，不覆盖路网 Y 精度）

## 归因结论

**主要原因**：需求遗漏 + 实现缺陷（BigWorld 路网 Y 坐标不可信问题贯穿 spawn 和路径两个环节）

**根因链**：
```
路网节点 Y 坐标精度不足（已知问题，feedback_bigworld_y_offset）
  ├─→ spawn Y 偏低：NPC 出生在地表以下（npc-stuck-underground.md 根因）
  └─→ A* 路径节点 Y 偏低：NPC 沿地下路径移动
       ↓
       NPC 在地下水平移动 → XZ delta > 0 → 走路动画触发（正确行为）
       → 但从地表视角看"原地踏步"
```

**次要因素**：
- 服务端 bwSpeedWalk=1.4 m/s vs 客户端 WalkRefSpeed=1.2 m/s（14% 偏差）→ 动画稍快，视觉上走路步伐与移动速度不完全同步，可能加重"原地踏步"观感

## 修复方案

### 代码修复

**根本修复（与 npc-stuck-underground.md 相同）：在 spawnNpcAt 修正 spawn Y**

```go
// bigworld_npc_spawner.go
if correctedY, ok := s.terrainAccessor.RaycastGroundY(pos.X, pos.Z); ok {
    pos.Y = correctedY
}
```

修复 spawn Y 后，`startPos.Y` 正确，patrol 目标 Y = startPos.Y（正确高度），A* 路径起点 Y 修正，后续路径节点 Y 由 A* 路网决定（路网 Y 依然不可信）。

**A* 路径节点 Y 修正（补充修复）：**

若 A* 路网节点 Y 仍不可信，需在 NavigateBtHandler 接收到路径点列表后，对每个路径节点做 RaycastGroundY 修正。当前 `correctTargetY` 只修正终点 Y，中间节点未修正。

**次要修复：速度对齐**
- 方案 1：`WalkRefSpeed = 1.4f`（客户端对齐服务端）
- 方案 2：`bwSpeedWalk = 1.2f`（服务端对齐客户端 refSpeed）

### 工作流优化建议

- **问题**：BigWorld 路网 Y 精度问题影响多个子系统（spawn、patrol 目标、A* 路径），但在 V2_NPC 等纯功能特性中无法被发现
- **建议**：大世界 NPC 相关特性的验收必须包含运行时可视化验证（MCP 截图），确认 NPC 在地表以上移动且移动轨迹合理
- **改哪里**：`skills/feature/developing.md` 验收清单，新增"大世界 NPC 视觉验证：截图确认 NPC 高于地面且有明显移动轨迹"
