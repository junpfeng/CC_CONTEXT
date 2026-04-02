# 设计：behaviorType=1 路网移动后对齐 TargetPos

## 问题

`schedule_handlers.go` 的 `behaviorType=1`（MoveTo）在有显式路点（`startPointId/endPointId`）时，走路网 A* 路径，走完后停在 `endPointId` 路点坐标，**不会再移动到 `entry.TargetPos`**。

**实测偏差**（Donna_Schedule.json，templateId=1014）：
- `endPointId=225` 路点坐标：(56.74, 0.14, -96.62)
- 对应 `targetPos`：(60.0, 0.0, -95.0)
- 偏差：**~3.6m**

## 根本原因

```go
// 当前代码（有 bug）：只设路网路径，走完后不做任何事
ctx.Scene.SetEntityRoadNetPath(ctx.EntityID, vecList, entry.FaceDirection)
sched.HasTarget = true
sched.TargetPos = entry.TargetPos  // 记录了但从未消费
ctx.NpcState.Movement.IsMoving = true
break  // 之后每帧 HasTarget==true，直接跳过所有逻辑
```

## 修复方案：两段式移动（参考 ScenarioHandler）

ScenarioHandler 已有成熟模式：路网走到最近节点 → 检测到达 → NavMesh/直线走到精确目标。

### 状态字段

**必须新增独立字段** `MoveToPhase int32`（不复用 `ScenarioPhase`），原因：`ScenarioPhase` 被 ScenarioHandler 使用，OnExit 中没有清零，复用会导致 ScenarioHandler 读到残留值后跳入错误阶段。

在 `ScheduleState`（`npc_state.go`）新增：

```go
MoveToPhase int32 // MoveTo 两段式移动阶段（0=未开始 1=路网行走中 2=对齐移动中）
```

| 值 | 含义 |
|----|------|
| `0` | 未开始 |
| `1` | 路网行走中（road net phase） |
| `2` | 对齐移动中（align to targetPos phase） |

### 到达检测信号

**优先检测 `IsMoving==false`**（移动组件已自动停止）作为主信号，距离检测作为辅助（防止因速度/帧间距导致漏检）：

```go
// 到达判定（两种信号取 OR）
arrived := !ctx.NpcState.Movement.IsMoving ||
           distanceSqXZ(npcPos, targetPos) <= threshold
```

### 新增接口

`RoadNetQuerier` 接口新增 `GetPointPos`，`MapRoadNetworkMgr` 实现：

```go
// RoadNetQuerier 扩展
GetPointPos(pointId int) (transform.Vec3, bool)

// 实现在 *Map（scene_impl.go 注入的是 roadNetMgr.MapInfo，即 *Map）
// Point.Position 已是 transform.Vec3（float32），无需类型转换
func (m *Map) GetPointPos(pointId int) (transform.Vec3, bool) {
    for _, net := range m.roads {
        if p, ok := net.GetPointByID(pointId); ok {
            return p.Position, true
        }
    }
    return transform.Vec3{}, false
}
```

### case 1 新逻辑（伪代码）

phase 1 检测移入 switch 内部，避免 case 0 设置 MoveToPhase=1 后同帧立即触发到达检测。

```go
case 1: // MoveTo
    npcPos := ctx.NpcState.Movement.Position

    if h.roadNetMgr != nil && entry.StartPointId > 0 && entry.EndPointId > 0 {
        switch sched.MoveToPhase {

        case 0: // 启动路网寻路（每个条目只执行一次）
            sched.TargetPos = entry.TargetPos   // 先写，fallback 也能用
            sched.HasTarget = true
            pathPoints, err := h.roadNetMgr.FindPathToVec3List(int(entry.StartPointId), int(entry.EndPointId))
            if err == nil && len(pathPoints) > 0 {
                // faceDirection 在路网段结束时应用；phase 2 朝向由移动方向决定（接口无独立朝向方法）
                ctx.Scene.SetEntityRoadNetPath(ctx.EntityID, toVecList(pathPoints), entry.FaceDirection)
                sched.MoveToPhase = 1
                ctx.NpcState.Movement.IsMoving = true
                break // 本帧结束，下帧进入 case 1
            }
            // 路网失败：直接发出 NavMesh 指令跳到 phase 2
            if !ctx.Scene.MoveEntityViaNavMesh(ctx.EntityID, sched.TargetPos) {
                ctx.Scene.SetEntityDirectPath(ctx.EntityID, sched.TargetPos)
            }
            sched.MoveToPhase = 2
            ctx.NpcState.Movement.IsMoving = true

        case 1: // 路网行走中 → 检测是否到达 endPoint
            if endPos, ok := h.roadNetMgr.GetPointPos(int(entry.EndPointId)); ok {
                distSq := distanceSqXZ(npcPos, endPos)
                if !ctx.NpcState.Movement.IsMoving || distSq <= moveToNodeArrivalDistSq {
                    // 到达路网终点，发出 NavMesh 指令对齐到 targetPos
                    if !ctx.Scene.MoveEntityViaNavMesh(ctx.EntityID, sched.TargetPos) {
                        ctx.Scene.SetEntityDirectPath(ctx.EntityID, sched.TargetPos)
                    }
                    sched.MoveToPhase = 2
                    ctx.NpcState.Movement.IsMoving = true
                }
            }

        case 2: // 对齐移动中 → 检测是否到达 targetPos
            distSq := distanceSqXZ(npcPos, sched.TargetPos)
            if !ctx.NpcState.Movement.IsMoving || distSq <= moveToPointArrivalDistSq {
                ctx.NpcState.Movement.IsMoving = false
                sched.MoveToPhase = 0
            }
        }
        break
    }
    // 无显式路点 → NavMesh/直线直接走到 targetPos（现有逻辑不变）
```

### 重置点（必须）

以下位置必须同步重置 `MoveToPhase = 0`：

| 位置 | 代码行（约） | 说明 |
|------|-------------|------|
| 条目切换检测处 | ~148 | `sched.HasTarget = false` 旁边 |
| `ScheduleHandler.OnExit` | ~251 | 防止切换 Handler 时残留 |

### 新增常量

```go
const (
    moveToNodeArrivalDistSq  = float32(25.0) // 路网终点到达判定 5m²（与 scenarioNodeArrivalDistSq 一致）
    moveToPointArrivalDistSq = float32(0.25) // targetPos 最终到达判定 0.5m²（与 scenarioPointArrivalDistSq 一致）
)
```

## 影响范围

| 文件 | 改动 |
|------|------|
| `common/ai/state/npc_state.go` | `ScheduleState` 新增 `MoveToPhase int32` |
| `execution/handlers/schedule_handlers.go` | case 1 重构为 3 阶段；OnExit 和条目切换处补 `MoveToPhase=0`；`RoadNetQuerier` 接口新增 `GetPointPos`；新增 2 个常量 |
| `common/pathfind/road_network/`（MapRoadNetworkMgr） | 实现 `GetPointPos` |

**不影响**：无路点的 NavMesh fallback、`NpcMoveComp`、协议同步、`ScenarioPhase` 字段。

## 验证

1. 启动服务器，Donna NPC（templateId=1014）在 08:00 走路网 27→225 后，最终停在 `targetPos=(60.0, 0.0, -95.0)` 附近（误差 <0.5m）
2. 检查日志：`[ScheduleHandler] MoveTo phase1→phase2` 和 `phase2 arrived`
3. 确认 endPointId=27 的条目（偏差仅 0.08m）行为无回归
