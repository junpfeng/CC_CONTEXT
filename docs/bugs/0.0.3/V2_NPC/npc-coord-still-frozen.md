# Bug 分析：大世界 NPC 坐标仍然不变（Fix A/B/C 后持续）

## Bug 描述
- **现象**：大世界 NPC 生成后位置坐标始终停在生成点，经过上次 bug:fix（Fix A/B/C）后仍不更新
- **预期**：NPC 生成后应在生成点附近随机游走（`BigWorldDefaultPatrolHandler`）

## 代码定位

| 文件 | 行号 | 作用 |
|------|------|------|
| `handlers/bigworld_default_patrol.go` | ~89-131 | OnTick 目标选取 + 到达判断（Fix C 已改用 distanceSqToTarget） |
| `ecs/res/npc_mgr/v2_pipeline_defaults.go` | ~150-212 | bigworldDimensionConfigs — locomotion "idle" 注册 BigWorldDefaultPatrolHandler |
| `bin/config/ai_decision_v2/bigworld_locomotion.json` | — | init_plan: "idle" ✓ |
| `bin/config/ai_decision_v2/bigworld_navigation.json` | — | init_plan: "navigate" ✓（Fix B 新建） |
| `ecs/system/decision/bt_tick_system.go` | ~272-346 | syncNpcMovement — 三级寻路 + StartMove 节流 |
| `npc_mgr/move.go` | ~99 | passedTime = nowStamp - LastStamp（零 delta 保护） |

**当前行为**：NPC 生成，BtTickSystem 运行，OnTick 被调用，但坐标不变。

**预期行为**：OnTick 选取随机目标 → syncNpcMovement 建路 → StartMove → NpcMoveSystem 每帧推进坐标。

## 全链路断点分析

### idea.md → feature.json
- **是否覆盖**：否
- **idea 原文**：纯动画对齐（"大世界 NPC 与小镇 V2 NPC 动画层差异"），无服务端移动需求
- **feature.json 对应**：REQ-001~REQ-008 全部为客户端动画，服务端移动未提及

### feature.json → plan.json
- **是否覆盖**：否
- **feature 需求**：8 条全部为客户端动画（TurnState/ScenarioState/动画层/Timeline/击中反应等）
- **plan 设计**：8 个 task 全为客户端，无 NPC 服务端移动任务

### plan.json → tasks/
- **是否覆盖**：否（服务端移动本就不在 plan 内）
- **对应任务**：无，所有 8 个 task 均为客户端

### tasks/ → 代码实现
- **是否实现**：否（服务端移动不在 V2_NPC 任务范围内）
- **说明**：bugfix 流程对 `bigworld_default_patrol.go`/`v2_pipeline_defaults.go`/`bigworld_navigation.json` 的修改是在 V2_NPC 特性任务之外单独修复的

### Review 检出
- **是否被发现**：否（所有 8 个 task 的 develop-review-report 均只审查客户端代码）
- **修复结果**：不适用（Review 不覆盖服务端移动）

---

## Fix A/B/C 之后的残余问题分析

### Fix C 的效果边界

Fix C（distanceSqToTarget）消除了"每帧误判到达→每帧换目标→每帧 StartMove"的死循环。修复后：

- OnTick **不再**每帧写 MoveTarget（仅选新目标时写一次） ✓
- syncNpcMovement 有节流机制（同目标 500ms 内不重建路径） ✓

但以下情况仍可能导致坐标不变：

### 候选根因 1：A* 路网覆盖盲区（最可能）

`syncNpcMovement` 三级寻路流程：
1. `MoveEntityViaRoadNet()` → A* 寻路 → 若无有效路径返回 false
2. `MoveEntityViaNavMesh()` → NavMesh（BigWorld 运行时无 Unity NavMesh，`reference_navmesh_astar_only.md`）→ 大概率也失败
3. `SetEntityDirectPath()` → 直线路径（应可作为兜底）

若三级全部失败，`StartMove()` 永远不被调用，NpcMoveComp 无路径点，NpcMoveSystem 无法推进坐标。

**反馈记忆印证**：`feedback_roadnet_path_gap.md` 明确指出："路网 A* 路径终点≠实际目标，必须追加目标点"。说明大世界路网存在盲区问题。

**待验证**：在 NPC 生成点附近打 A* 查询日志，确认 `MoveEntityViaRoadNet` 返回值。

### 候选根因 2：服务端未重启（低成本先排查）

bug:fix 脚本完成后报告 `[阶段四] 无变更需要提交`，这意味着文件修改可能已写入磁盘但进程仍是老镜像。服务端进程未重启则新代码不生效。

**验证**：查看服务端进程启动时间（`server.ps1 status`），确认是否晚于 Fix A/B/C 的文件修改时间。

### 候选根因 3：NpcMoveComp 未绑定（较低可能）

若大世界 NPC 生成时未创建 `NpcMoveComp`，syncNpcMovement 桥接层找不到 comp，StartMove 无法调用。

---

## 归因结论

**主要原因（流程层）**：需求遗漏 — V2_NPC 特性的 idea/feature/plan/task 全部限定在客户端动画，服务端 NPC 移动系统完全超出范围，bug 无法在正常 develop-review 流程内被发现或修复。

**残余根因（当前最可能）**：A* 路网寻路在 NPC 生成点返回失败，直线兜底路径未正确激活，StartMove 未被调用。

**根因链**：
```
V2_NPC idea 纯动画 → feature/plan 全客户端 → 服务端移动系统无 review 覆盖
  ↓
首次 bug:fix 修复 TargetPos 语义冲突（Fix C）→ 死循环消除
  ↓
但 A* 路网未覆盖生成点 → MoveEntityViaRoadNet 失败 → StartMove 未调用
  ↓
NpcMoveSystem 无路径点 → passedTime 推进但 pointList 空 → 坐标不变
```

## 修复方案

### 优先级 1：重启服务端验证 Fix A/B/C 是否生效
```
bash scripts/server.ps1 restart
```
若重启后 NPC 开始移动，原因是进程未更新，可关闭此 bug。

### 优先级 2：为 BigWorldDefaultPatrolHandler 添加直线兜底日志

在 `bigworld_default_patrol.go` 的 `pickNewTarget` 后，打印 syncNpcMovement 调用链的返回值。若 `MoveEntityViaRoadNet` 持续返回 false，说明路网覆盖问题。

修复：改用直线路径或扩大 A* 搜索半径。

### 工作流优化建议

- **问题**：V2_NPC 特性范围（纯客户端动画）与服务端 NPC 移动系统脱节，bug 无法被任何 review 发现
- **建议**：功能验收阶段（develop 最终 review）增加端到端可观测验收项：对有 NPC 的特性，要求 develop-review 包含"NPC 在大世界是否可见移动"的运行时截图验证
- **改哪里**：`skills/feature/developing.md` 的验收检查清单，新增"涉及大世界 NPC 的特性必须通过 MCP 截图验证 NPC 有实际位移"
