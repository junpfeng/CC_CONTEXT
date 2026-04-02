═══════════════════════════════════════════════
  Bug Fix Review 报告
  版本：0.0.3
  模块：V2_NPC
  审查文件：10 个
═══════════════════════════════════════════════

## 一、根因修复验证

### 根因对应性

✅ **Fix 1（客户端 spawn Y 修正）**：`BigWorldNpcTransformComp.cs` 在 `InitFromSnapshot()` 中调用 `CorrectYToGround()`，从 Y=200 向下 Raycast Grounds 层修正初始位置，与分析报告根因 A 完全对应。`_groundsLayerMask` 使用延迟初始化，符合 `feedback_static_field_layer_mask` 约束。

✅ **Fix 3（WalkRefSpeed 统一）**：`BigWorldNpcAnimationComp.cs` 1.2f→1.4f，`BigWorldNpcMoveState.cs` 1.5f→1.4f，两处均对齐服务端 `defaultBigWorldWalkSpeed=1.4`。`OnUpdate` 中的 `SetSpeed` 调用已移除，AnimationComp 成为唯一写入方，双写问题消除。

⚠️ **Fix 2（服务端路径节点 Y 修正）**：分析报告指定修改 `bigworld_navigation_handler.go correctTargetY`，实际修复在 `scene_accessor_adapter.go MoveEntityViaRoadNet` 中实现，位置偏差但功能覆盖（对所有 pathPoints 应用修正）。然而实现方式存在问题，见 HIGH-1。

### 修复完整性

✅ Fix 1 仅在 `InitFromSnapshot()` 中修正初始帧，后续帧通过 SnapshotQueue 插值，不涉及 Raycast，逻辑独立。Raycast 未命中时回退原始坐标，不会 panic。

✅ Fix 3 修复了 `OnUpdate` 的双写；`OnEnter` 仍保留一次 `SetSpeed` 用于进入状态时初始化，这是合理的一次性赋值，不产生持续双写。

⚠️ Fix 2 使用 `NavMeshMgr.FindPath` 进行 Y 投影，存在语义和性能问题，见 HIGH-1。

### 影响范围覆盖

✅ 分析报告影响范围（"所有大世界 V2 NPC"）已被 Fix 1+2+3 覆盖。客户端 Y 修正对所有新 spawn NPC 生效，服务端路径 Y 修正对所有 `MoveEntityViaRoadNet` 调用生效。

---

## 二、合宪性审查

### 客户端（.cs 文件）

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译正确性 | ✅ | using 完整；`UnityEngine.Physics.Raycast` 显式命名空间，消除歧义 |
| 日志规范（MLog/+拼接） | ✅ | 变更文件无新增日志 |
| 事件配对 | ✅ | 无新增事件订阅 |
| async UniTask | ✅ | 无新增 async 方法 |
| 热路径 GC | ✅ | `CorrectYToGround` 仅在 spawn 时调用（一次性），非 Tick；MoveState OnUpdate 中移除了 new 调用 |
| LayerMask 延迟初始化 | ✅ | `_groundsLayerMask = -1` 实例字段，首次使用时赋值，符合规范 |

### 服务端（.go 文件）

| 条款 | 状态 | 说明 |
|------|------|------|
| 错误处理 | ✅ | `spawnNpcAt` 失败有 `log.Errorf` + continue；`FindPath` 失败静默保留原 Y（设计为降级，可接受） |
| 日志格式（%v） | ✅ | 所有新增日志使用 `%v`，无 `%d`/`%s` |
| 日志模块标签 | ✅ | `[BigWorldNpcSpawner]`、`[BigWorldPatrol]` 方括号格式一致 |
| goroutine 安全 | ✅ | 无新增 goroutine |
| error 向上传播 | ✅ | `PreSpawnPatrolRoutes` 内部错误已 log，不上报（spawner 不应因单个 NPC 失败中断） |

---

## 三、副作用与回归风险

### [HIGH-1] scene_accessor_adapter.go — 使用 FindPath API 进行 Y 坐标投影

**位置**：`servers/scene_server/internal/ecs/system/decision/scene_accessor_adapter.go`，新增的路径节点 Y 修正循环

**问题**：使用 `nmMgr.FindPath(start, dest)` 进行单点 Y 投影语义错误：
1. `FindPath` 是 A* 寻路算法，设计用于路径规划，而非坐标投影
2. 当 start/dest 处于不同 NavMesh 多边形时，`projPath[0]` 返回的是 A* 路径起点投影，而非输入 XZ 处的精确地表 Y
3. 性能：对每个 path node 调用一次 A* 查询，N 个节点 = N 次 A* overhead；`MoveEntityViaRoadNet` 是高频调用路径
4. 分析报告明确指定使用 `terrainAccessor.RaycastGroundY`，该接口语义正确（直接 Raycast 返回地表 Y）

**场景**：NPC 开始移动，`MoveEntityViaRoadNet` 被调用，对 20 节点路径执行 20 次 A* 查询
**影响**：Y 修正结果在边缘地形（NavMesh 多边形边界附近）可能不准确；持续高 CPU 占用
**建议**：改用 `scene_accessor_adapter` 已有的 `terrainAccessor.RaycastGroundY` 接口，或将 NavMesh 的 `NearestPoint`/`ProjectPoint` API 暴露到 TerrainAccessor 接口

---

### [HIGH-2] 变更包含与 Bug #1 无关的代码修改

**位置**：以下文件的变更与 Bug #1（NPC Y 坐标 + animSpeed）无关：
- `AvoidanceUpgradeChain.cs`：新增 `ObstacleType.Player` 特殊处理（载具避让逻辑）
- `GTA5VehicleAI.cs`：区分玩家和车辆障碍物类型
- `JunctionDecisionFSM.cs`：路口交叉交通过滤停止车辆
- `BigWorldNpcFsmComp.cs`：新增 `_prevStateId` 字段修复 TurnState 恢复逻辑；新增 `BigWorldNpcScenarioState`/`BigWorldNpcScheduleIdleState` TurnState 排除
- `BigWorldNpcController.cs`：新增 `FsmComp.InitData()` 初始服务端状态同步
- `bigworld_npc_spawner.go`：`PreSpawnPatrolRoutes` 静态巡逻 NPC 预生成（新功能）
- `v2_pipeline_defaults.go`：`bigworldDimensionConfigs` 完整 handler 注册（功能扩展）

**场景**：以上变更在未经单独分析和 Review 的情况下混入 Bug Fix，增加回归风险
**影响**：违反 auto-work-lesson-004（只改标记问题）；任何一处引入的回归难以定位到具体变更
**建议**：将车辆避让、FsmComp TurnState 修复、`PreSpawnPatrolRoutes` 拆分为独立提交，分别分析和 Review

---

### [MEDIUM-1] bigworld_default_patrol.go OnEnter — GetEntityPos 失败时 startPos 静默为零向量

**位置**：`bigworld_default_patrol.go:OnEnter`

```go
if sx, sy, sz, ok := ctx.Scene.GetEntityPos(ctx.EntityID); ok {
    ps.startPos = transform.Vec3{X: sx, Y: sy, Z: sz}
}
// ok=false 时 startPos 保持零值，无日志
```

**问题**：若实体在 Handler OnEnter 时尚未完全注册到 Scene（entity 初始化时序问题），`GetEntityPos` 返回 `ok=false`，`startPos` 为零向量 `{0,0,0}`，NPC 后续游荡范围以世界原点为中心，视觉上瞬移到地图原点附近巡逻，且无任何警告日志
**场景**：场景初始化时 `PreSpawnPatrolRoutes` 立即触发 OnEnter，若 entity 创建和 Scene 注册之间有时序间隔
**影响**：NPC 在错误位置巡逻；Bug 无日志，排查困难
**建议**：
```go
if sx, sy, sz, ok := ctx.Scene.GetEntityPos(ctx.EntityID); ok {
    ps.startPos = transform.Vec3{X: sx, Y: sy, Z: sz}
} else {
    log.Warningf("[BigWorldPatrol] OnEnter: GetEntityPos 失败 npc_entity_id=%v，startPos 回退到 TargetPos", ctx.EntityID)
    ps.startPos = ctx.NpcState.Movement.TargetPos
}
```

---

## 四、最小化修改检查

❌ 存在超出 Bug #1 修复范围的无关变更（详见 HIGH-2）

- Fix 1、Fix 3 修改范围合理，改动最小
- Fix 2 实现位置（scene_accessor_adapter.go）比分析报告指定位置更上层，引入了 N×A* 性能问题
- 车辆避让、FsmComp、PreSpawnPatrolRoutes 等属于独立改动，应分离

---

## 五、总结

```
  CRITICAL: 0 个
  HIGH:     2 个（强烈建议修复）
  MEDIUM:   1 个（建议修复）

  结论: 需修复后再审

  重点关注:
  1. [HIGH-1] scene_accessor_adapter.go FindPath 误用为 Y 投影——改用 RaycastGroundY 接口
  2. [HIGH-2] 无关变更混入（车辆避让+FsmComp TurnState+PreSpawnPatrolRoutes）——拆分提交
  3. [MEDIUM-1] BigWorldPatrol OnEnter GetEntityPos 失败无日志无回退——补充 Warning 和 TargetPos 回退
```

<!-- counts: critical=0 high=2 medium=1 -->
