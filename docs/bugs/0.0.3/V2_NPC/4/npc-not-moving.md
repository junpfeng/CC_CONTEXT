# Bug 分析：大世界 NPC 坐标从不移动

## Bug 描述

大世界 NPC 出现在场景中，服务端坐标始终不变（TransformComp 位置不更新），NPC 永远停在生成点。客户端收不到有效的移动同步，NPC 视觉上完全静止。

## 代码定位

**直接触发**：`bt_tick_system.go` → `syncNpcMovement` 每帧调用 `MoveEntityViaRoadNet` → `StartMove()` 重置 `LastStamp = now`

**根因**：`bigworld_default_patrol.go` 用 `TargetPos` 作"当前位置"做到达判断，而 `navigation_handlers.go` 的 `navCheckArrival` 每帧把 `TargetPos` 覆写为 `MoveTarget`（目标点），导致 patrol handler 永远认为 NPC 已到达，每帧换新目标，触发每帧重建路径+重置时间戳。

### 涉及文件

| 文件 | 行号 | 作用 |
|------|------|------|
| `handlers/bigworld_default_patrol.go` | L110 | 读 `TargetPos` 作"当前位置"（语义错误） |
| `handlers/navigation_handlers.go` | L61 | `navCheckArrival` 写 `TargetPos = MoveTarget` |
| `system/decision/bt_tick_system.go` | L272-L349 | `syncNpcMovement` → `MoveEntityViaRoadNet` → `StartMove` |
| `ecs/npc/npc_move.go` | L339-343 | `StartMove` 重置 `LastStamp = now` |
| `system/npc/move.go` | L99-106 | `passedTime = now - LastStamp ≤ 0 → return`（零 delta 保护） |
| `scene/scene_impl.go` | L618, L728 | BtTickSystem 先注册，NpcMoveSystem 后注册（同帧顺序） |

### 当前行为

每帧死循环，NPC 坐标永远不更新。

### 预期行为

NPC 每帧沿路网路径推进，TransformComp 更新坐标并同步客户端。

## 全链路断点分析

### idea.md → feature.json
- **是否覆盖**：是（巡逻移动为 P0 需求）
- **idea.md 原文**：大世界 NPC 沿路网巡逻游荡，P0 基础移动功能
- **feature.json 对应**：REQ-001 大世界 NPC 巡逻游荡，NavBt + DefaultPatrol 分离正交管线

### feature.json → plan.json
- **是否覆盖**：部分覆盖
- **feature 需求**：locomotion 维度写 MoveTarget，navigation 维度负责路径执行
- **plan 设计**：设计了双维度分离，但**未明确 `TargetPos` 字段语义**：locomotion 把 `TargetPos` 当"当前位置"，navigation 把 `TargetPos` 当"当前目标副本"
- **关键遗漏**：两个模块对同一字段有冲突语义，plan 未定义字段归属

### plan.json → tasks/
- **是否覆盖**：是（task-03 实现 DefaultPatrol，task-04 实现 NavigationBt）
- **plan 设计点**：两个 handler 独立设计，均已拆 task
- **对应任务**：task-03（patrol）、task-04（navigation）

### tasks/ → 代码实现
- **是否实现**：已实现，但接口契约冲突
- **task-03 实现**：`BigWorldDefaultPatrolHandler` L110 用 `TargetPos` 作当前位置参考点
- **task-04 实现**：`navCheckArrival` L61 每帧写 `TargetPos = MoveTarget`
- **冲突**：两个 task 独立实现时均符合各自逻辑，但组合后语义冲突

### Review 检出
- **是否被 Review 发现**：否
- **Review 原文**：develop-review-task-03 HIGH 仅标记 TurnState 守卫缺失，未审查 TargetPos 字段的跨 handler 语义一致性
- **修复结果**：TurnState 守卫问题已修，TargetPos 冲突未被识别

## 归因结论

**主要原因**：方案遗漏 + Review 盲区

**根因链**：

```
plan 未定义 TargetPos 字段归属
    ↓
task-03 (patrol)  : TargetPos = 实体当前位置  ← 读方
task-04 (nav)     : TargetPos = MoveTarget    ← 每帧覆写
    ↓
每帧执行顺序（维度顺序：locomotion → navigation）：
  1. patrol.OnTick  : pos = TargetPos = MoveTarget（上帧被 nav 写成目标点）
                      distSq = |MoveTarget - MoveTarget| = 0
                      → 误判"已到达" → pickNewTarget
                      → MoveTarget = 随机新目标, IsMoving = true
  2. navCheckArrival: entity 实际距离新目标很远 → RUNNING
                      TargetPos = MoveTarget（新目标）← 再次覆写
  3. syncNpcMovement: IsMoving=true, MoveTarget 变化 → 旧路径末点距新目标 >4m
                      → Clear + MoveEntityViaRoadNet(新目标) → StartMove()
                      → LastStamp = T_now
  4. NpcMoveSystem  : passedTime = T_now - T_now ≈ 0 → return（零 delta 保护）
    ↓
每帧循环，坐标永远不更新
```

**关键放大因素**：`scene_impl.go` 中 BtTickSystem（L618）先于 NpcMoveSystem（L728）注册，同帧内 syncNpcMovement 的 `StartMove` 重置 `LastStamp` 后，NpcMoveSystem 读到的 passedTime 趋近于零。

## 修复方案

### 代码修复

**文件**：`handlers/bigworld_default_patrol.go` L110 附近

将到达判断从读 `TargetPos` 改为读实体真实变换位置：

```go
// 修改前（语义错误：TargetPos 会被 navCheckArrival 每帧覆写为 MoveTarget）
pos := ctx.NpcState.Movement.TargetPos
distSq := distanceXZSquared(pos, ctx.NpcState.Movement.MoveTarget)

// 修改后（读实体真实坐标）
distSq, ok := distanceSqToTarget(ctx.Scene, ctx.EntityID, ctx.NpcState.Movement.MoveTarget)
if !ok {
    return btree.Running
}
```

`distanceSqToTarget` 已在 `navigation_handlers.go` 实现，直接复用即可（或提取到 handlers 公共工具文件）。

**效果**：patrol handler 基于实体真实位置判断到达，navCheckArrival 对 TargetPos 的覆写不再干扰 locomotion 维度，MoveTarget 不再每帧变换，syncNpcMovement 不再每帧重建路径+重置 LastStamp，NpcMoveSystem 获得正常 passedTime，坐标正常推进。

### 工作流优化建议

- **问题**：plan 中两个正交维度 handler 共用 `TargetPos` 字段，但未定义该字段的"写方/读方"归属，导致 task 级别实现各自正确但组合后冲突
- **建议**：plan 设计正交管线时，对每个 NpcState 共享字段必须标注：**唯一写方** 和 **有效读时机**。模板：`字段名: 写方=xxx, 读时机=yyy帧`
- **改哪里**：`docs/version/*/V2_NPC/plan/` 类文件的模板，以及 `skills/feature/plan.md` 中补充"共享状态字段归属声明"规则
