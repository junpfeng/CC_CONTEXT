# Bug 修复日志 #1

- **版本**: 0.0.3
- **模块**: V2_NPC
- **Bug**: 大世界 NPC 走路动画原地踏步（部分 NPC 同时插地）
- **启动时间**: 2026-03-29 20:59:22

| 轮次 | 操作 | Critical | High | Medium | 状态 |
|------|------|----------|------|--------|------|
| 0 | 根因分析 | - | - | - | done (208s) |

## 修复记录

### Fix 1：客户端 spawn Y 修正（BigWorldNpcTransformComp.cs）
- **状态**：已完成（此前已实现）
- `InitFromSnapshot` 已调用 `CorrectYToGround`，从 Y=200 向下 Raycast 修正到 Grounds 层
- 延迟初始化 `_groundsLayerMask`，符合 `feedback_static_field_layer_mask.md` 规范

### Fix 2：服务端 A* 路径节点 Y 修正（scene_accessor_adapter.go）
- **修改文件**：`servers/scene_server/internal/ecs/system/decision/scene_accessor_adapter.go`
- 在 `MoveEntityViaRoadNet` 中，获取路网 A* 路径节点后，用 NavMesh `FindPath` 将每个节点投影到 NavMesh 表面，修正 Y 坐标
- NavMesh 内部 `findNearestPoly` 会将起点吸附到最近多边形表面，`path[0].Y` 即为该 XZ 处地表高度
- 未命中时（节点超出 NavMesh 覆盖范围）静默保留原始 Y，不影响路径可用性
- 注意：分析报告指向 `bigworld_navigation_handler.go`，实际路径节点变量在 `scene_accessor_adapter.go`，修复位置更准确

### Fix 3：统一 WalkRefSpeed 常量（BigWorldNpcAnimationComp.cs + BigWorldNpcMoveState.cs）
- **BigWorldNpcAnimationComp.cs**：`WalkRefSpeed 1.2f → 1.4f`（对齐服务端 `defaultBigWorldWalkSpeed=1.4`）
- **BigWorldNpcMoveState.cs**：`WalkRefSpeed 1.5f → 1.4f`，删除 `OnUpdate` 中两处 `SetSpeed` 调用（含防守分支中的调用），移除相关 `refSpeed`/`actualSpeed`/`animSpeed` 计算（仅 `AnimationComp.UpdateSpeedDrivenAnimation` 作为唯一 animSpeed 写入方）

## 编译验证

- Go 服务端：`make build` 通过（0 错误）
- Unity 客户端：`Editor.log` 无 `error CS`

ALL_FILES_FIXED
| 1 | 修复 | - | - | - | done |
| 1.c | 编译验证 | - | - | - | 通过 |
| 2 | Review | 0 | 2 | 1 | done |

## 总结
- **总轮次**：2
- **终止原因**：质量达标
- **最终质量**：Critical=0, High=2, Medium=1
- **完成时间**：2026-03-29 21:33:26
