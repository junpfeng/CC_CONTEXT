# 场景点系统集成正交决策管线

> ⚠️ **状态：未实施** — ScenarioSystem 仍采用外部分配模式，本方案尚未落地。当前系统参见 `schedule/scenario-p0-design.md`。
>
> **目标**：将 ScenarioSystem（外部 ECS System）的场景点分配逻辑下沉到正交管线 locomotion 维度，实现单一决策源。
>
> 生成日期：2026-03-18

---

## 目录

1. [现状与问题](#1-现状与问题)
2. [改造目标](#2-改造目标)
3. [方案设计](#3-方案设计)
4. [详细改动清单](#4-详细改动清单)
5. [Brain JSON 配置](#5-brain-json-配置)
6. [风险与注意事项](#6-风险与注意事项)

---

## 1. 现状与问题

### 1.1 当前架构（双轨驱动）

```
ScenarioSystem (ECS System, 管线外部)
  │  每60帧扫描空闲NPC → 搜索附近场景点 → 概率选中 → 占用 → 写 NpcState
  ↓
locomotion Brain (管线内部)
  │  看到 ScenarioPointId != 0 → 输出 plan="scenario"
  ↓
ScenarioHandler (locomotion 维度 PlanExecutor)
  │  7阶段状态机：Init → WalkToNearNode → WalkToPoint → Enter → Loop → Leave → WalkBack
  ↓
ScenarioHandler.OnExit → 释放占用 → 设置冷却
```

### 1.2 问题

| 问题 | 说明 |
|------|------|
| 双决策源 | ScenarioSystem 在管线外做"谁去哪个点"的决策，Brain 只是被动转发 |
| 响应延迟 | ScenarioSystem 分帧扫描（60帧间隔 × 5NPC批次），NPC 可能等 1~N 秒才被分配 |
| 优先级孤立 | 场景点与日程/巡逻/驻守的优先级关系无法在 Brain JSON 中统一配置 |
| 生命周期分散 | NPC 销毁时的占用清理分布在 ScenarioSystem.OnDestroy 和 ScenarioHandler.OnExit 两处 |
| 空闲判定重复 | ScenarioSystem.isNpcFreeForScenario 与 Brain 条件评估存在逻辑重叠 |

### 1.3 涉及文件

| 文件 | 角色 | 改造后 |
|------|------|--------|
| `ecs/system/scenario/scenario_system.go` | 外部分配系统 | **删除** |
| `ecs/scene/scene_impl.go` | 注册 ScenarioSystem | 移除注册代码 |
| `ai/execution/handlers/schedule_handlers.go` | ScenarioHandler 执行 | 增加自主搜点逻辑 + 扩展 ScenarioFinder 接口 |
| `ecs/res/npc_mgr/scenario_adapter.go` | ScenarioFinder 适配器 | 实现 FindCandidates |
| `ecs/res/npc_mgr/scene_npc_mgr.go` | NPC 生命周期管理 | DestroyNpc 增加占用释放兜底 |
| `bin/config/ai_decision_v2/gta_locomotion.json` | Brain 决策配置 | 修改 schedule→scenario 转移条件 |
| `ai/state/npc_state.go` | NPC 状态 | SelfState 增加 `NowMs` 字段 |
| `ai/decision/v2brain/expr/field_accessor.go` | Brain 字段解析 | resolveSelf 增加 `NowMs` case |
| `ecs/system/decision/bt_tick_system.go` | 决策帧驱动 | Snapshot 前设置 `npcState.Self.NowMs` |
| `ai/pipeline/orthogonal_pipeline.go` | 正交管线 | 不变 |
| `ecs/res/npc_mgr/v2_pipeline_defaults.go` | 维度配置 | 不变（Handler 已注册） |

---

## 2. 改造目标

1. **单一决策源**：locomotion Brain 统一控制所有运动行为（日程、巡逻、场景点、驻守）的优先级和转移条件
2. **删除 ScenarioSystem**：不再需要外部 ECS System 做场景点分配
3. **Handler 自治**：ScenarioHandler.OnEnter 自主完成搜点 + 占用，OnExit 释放 + 冷却
4. **配置驱动**：场景点触发条件、概率、与其他行为的互斥关系全部在 JSON 中调整

---

## 3. 方案设计

### 3.1 改造后架构

```
locomotion Brain (管线内部, schedule hub 模式不变)
  │  schedule → scenario 转移条件：无冷却(Self.NowMs) + 非脚本 + 非移动中
  ↓
ScenarioHandler.OnEnter (locomotion 维度 PlanExecutor)
  │  调用 ScenarioFinder.FindCandidates → 逐点概率过滤 → Occupy
  │  成功 → 写入 NpcState 全部字段，进入状态机
  │  失败 → 设短冷却(5s) + CurrentPlan=""，Brain 下帧回 schedule
  ↓
ScenarioHandler.OnTick
  │  7阶段状态机不变（已有 ScenarioPointId==0 兜底守卫）
  ↓
ScenarioHandler.OnExit
  │  ScenarioPointId > 0 时：Release + 30s 冷却 + 清理
  │  ScenarioPointId == 0 时：仅清理字段（不覆写短冷却）
```

**关键变更**：
1. 保持 `schedule` 作为中枢的转移拓扑不变（`on_foot → schedule → scenario → schedule`），
   仅将 `schedule → scenario` 的转移条件从"外部系统预设 CurrentPlan"改为"Brain 自主评估场景点条件"
2. Brain 冷却条件需要时间比较，新增 `Self.NowMs` Snapshot 字段（见 4.4）

### 3.2 Brain.curPlan 与 NpcState.CurrentPlan 双轨状态

Brain 内部的 `curPlan` 和 `NpcState.Schedule.CurrentPlan` 是**独立的两层状态**，理解它们的关系是本设计的关键：

| 状态 | 归属 | 设置方 | 用途 |
|------|------|--------|------|
| `Brain.curPlan` | Brain 内部字段 | Brain.Tick() 在转移时更新 | 决定下帧从哪个 plan 评估转移（`from` 匹配） |
| `Schedule.CurrentPlan` | NpcState | Handler.OnEnter/OnExit 主动设置 | Brain 转移条件表达式中读取 |

**OnEnter 失败时的完整时序**：

```
Frame N:
  Brain.Tick(): curPlan="schedule" → 条件满足 → curPlan="scenario"
  PlanExecutor: ScheduleHandler.OnExit() → ScenarioHandler.OnEnter()
  OnEnter: 搜点失败 → failWithCooldown(5s) → CurrentPlan=""
  OnTick: ScenarioPointId==0 → return（已有兜底守卫，安全）

Frame N+1:
  Brain.Tick(): curPlan="scenario" → 评估 from:"scenario" 的转移
    → 条件 "Schedule.CurrentPlan == ''" 满足 → curPlan="schedule"
  PlanExecutor: ScenarioHandler.OnExit() → ScheduleHandler.OnEnter()
  OnExit: ScenarioPointId==0 → 跳过 Release 和 30s 冷却 → 仅清理字段
  （5s 短冷却不被覆写 ✓）
```

### 3.3 对比

| 维度 | 改造前 | 改造后 |
|------|--------|--------|
| 决策在哪 | ScenarioSystem（外部） | locomotion Brain（内部） |
| 搜点在哪 | ScenarioSystem.tryAssignScenario | ScenarioHandler.OnEnter |
| 搜点方法 | mgr.FindNearestFiltered（Flag 过滤+优先级排序） | adapter.FindCandidates（同等能力） |
| 逐点概率 | ScenarioSystem 循环 rand < probability | ScenarioHandler.OnEnter 同样逻辑 |
| 响应延迟 | 60帧轮询 | 每帧 Brain 评估 |
| 优先级控制 | 硬编码 isNpcFreeForScenario | Brain JSON 转移条件 |
| 占用清理 | ScenarioSystem.OnDestroy + Handler.OnExit | Handler.OnExit + SceneNpcMgr.DestroyNpc 兜底 |

### 3.4 ScenarioHandler.OnEnter 改造伪代码

```go
const scenarioSearchRadius = 12.0 // 与 ScenarioSystem 一致

func (h *ScenarioHandler) OnEnter(ctx *execution.PlanContext) {
    sched := &ctx.NpcState.Schedule
    nowMs := mtime.NowTimeWithOffset().UnixMilli()

    // 情况1：外部预分配（兼容期保留，后续可删）
    if sched.ScenarioPointId != 0 {
        sched.ScenarioPhase = ScenarioPhase_Init
        sched.CurrentPlan = "scenario" // ScheduleHandler.OnExit 已清空，必须重设
        return
    }

    // 情况2：Brain 触发，自主搜点
    x, y, z, ok := ctx.Scene.GetEntityPos(ctx.EntityID)
    if !ok {
        h.failWithCooldown(sched, nowMs, 5000)
        return
    }
    npcPos := transform.Vec3{X: x, Y: y, Z: z}
    gameSecond := ctx.Scene.GetGameTimeSecond()

    // 使用 FindCandidates 替代 FindNearest，保留 Flag 过滤 + 优先级排序
    // 接口接收 gameSecond，adapter 内部转换为 hour 传给 mgr.FindNearestFiltered
    candidates := h.scenarioMgr.FindCandidates(npcPos, scenarioSearchRadius, gameSecond)
    if len(candidates) == 0 {
        h.failWithCooldown(sched, nowMs, 5000) // 5秒短冷却
        return
    }

    // 逐点概率过滤（与 ScenarioSystem.tryAssignScenario 一致）
    var chosen *ScenarioPointResult
    for _, c := range candidates {
        if rand.Intn(100) < int(c.Probability) {
            chosen = c
            break
        }
    }
    if chosen == nil {
        h.failWithCooldown(sched, nowMs, 5000)
        return
    }

    // 占用
    if !h.scenarioMgr.Occupy(chosen.PointId, int64(ctx.EntityID)) {
        h.failWithCooldown(sched, nowMs, 5000) // 竞争失败也设冷却
        return
    }

    // 写入 NpcState 全部字段（必须与 Handler 读取列表完全对应）
    sched.ScenarioPointId = chosen.PointId
    sched.ScenarioTypeId = chosen.ScenarioType
    sched.ScenarioDirection = chosen.Direction
    sched.ScenarioDuration = chosen.Duration
    sched.TargetPos = chosen.Position
    sched.HasTarget = true
    sched.ScenarioPhase = ScenarioPhase_Init
    sched.CurrentPlan = "scenario" // 必须设置！ScheduleHandler.OnExit 已清空，不设则下帧立刻退出
}

// failWithCooldown 搜点失败时设短冷却并退出，防止 Brain 每帧重试
// 注意：不缩短已有的更长冷却（如正常完成的 30s 冷却）
func (h *ScenarioHandler) failWithCooldown(sched *ScheduleState, nowMs int64, cooldownMs int64) {
    newCooldown := nowMs + cooldownMs
    if newCooldown > sched.ScenarioCooldownUntil {
        sched.ScenarioCooldownUntil = newCooldown
    }
    sched.CurrentPlan = ""
}
```

### 3.5 ScenarioHandler.OnExit 改造伪代码

OnExit 需增加条件守卫：仅在实际执行了场景点（ScenarioPointId > 0）时才 Release 和设 30s 冷却，
避免覆写 OnEnter 失败时设置的 5s 短冷却。

```go
func (h *ScenarioHandler) OnExit(ctx *execution.PlanContext) {
    sched := &ctx.NpcState.Schedule
    nowMs := mtime.NowTimeWithOffset().UnixMilli()

    // 仅在实际占用了场景点时释放和设 30s 冷却
    if sched.ScenarioPointId > 0 {
        h.scenarioMgr.Release(sched.ScenarioPointId, int64(ctx.EntityID))
        sched.ScenarioCooldownUntil = nowMs + scenarioCooldownMs // 30s
    }
    // 注意：ScenarioPointId == 0 时（OnEnter 搜点失败），不覆写短冷却

    // 字段清零始终执行（10 个字段，与现有 OnExit/abortScenario 完全一致）
    sched.ScenarioPointId = 0
    sched.ScenarioPhase = 0
    sched.ScenarioTypeId = 0
    sched.ScenarioDirection = 0
    sched.ScenarioDuration = 0
    sched.ScenarioNearNodeId = 0
    sched.ScenarioNearNodePos = transform.Vec3{}
    sched.HasTarget = false
    sched.NextNodeTime = 0
    sched.CurrentPlan = ""
}
```

**abortScenario 不受影响**：abort 仅在状态机执行过程中调用（ScenarioPointId 必定 > 0），
其 Release + 30s 冷却逻辑保持不变。

### 3.6 与 ScenarioSystem.tryAssignScenario 的完整对应关系

| ScenarioSystem | ScenarioHandler.OnEnter | 说明 |
|----------------|------------------------|------|
| `mgr.FindNearestFiltered(pos, 12m, gameTimeHour)` | `scenarioMgr.FindCandidates(pos, 12m, gameSecond)` | 接口用 gameSecond，adapter 内部转 hour |
| `rand.Intn(100) < GetProbability(point)` 循环 | 同样循环 | 逐点概率，非 Brain 转移概率 |
| `mgr.Occupy(pointId, entityId)` | `scenarioMgr.Occupy(pointId, entityId)` | 相同 |
| `assignScenarioToNpc` 写 7 个字段 | 写相同 7 个字段 | 含 TargetPos、HasTarget |
| 失败直接 return（外部系统无冷却） | 失败设 5s 短冷却 | 防止 Brain 每帧重试 |

---

## 4. 详细改动清单

### 4.1 总览

| # | 文件 | 操作 | 说明 |
|---|------|------|------|
| D1 | `ecs/system/scenario/scenario_system.go` | **删除** | 外部分配系统 |
| D2 | `ecs/system/scenario/scenario_system_test.go` | **删除** | 对应测试 |
| D3 | `ecs/scene/scene_impl.go` | **移除** ScenarioSystem 注册代码 | |
| M1 | `ai/execution/handlers/schedule_handlers.go` — ScenarioFinder 接口 | **新增** `FindCandidates(pos Vec3, radius float32, gameSecond int64) []*ScenarioPointResult` | 保留原有方法 |
| M2 | `ai/execution/handlers/schedule_handlers.go` — ScenarioPointResult | **增加** `Probability int32` 字段 | |
| M3 | `ai/execution/handlers/schedule_handlers.go` — OnEnter | **增加** 自主搜点逻辑（见 3.4） | |
| M4 | `ai/execution/handlers/schedule_handlers.go` — OnExit | **增加** `ScenarioPointId > 0` 冷却守卫（见 3.5） | |
| M5 | `ecs/res/npc_mgr/scenario_adapter.go` | **实现** `FindCandidates`（gameSecond/3600→hour，调用 FindNearestFiltered + GetDuration + GetProbability） | |
| M6 | `ecs/res/npc_mgr/scene_npc_mgr.go` — DestroyNpc | **增加** `scenarioNpcCleaner.ReleaseByNpc` 兜底调用 | |
| M7 | `bin/config/ai_decision_v2/gta_locomotion.json` | **修改** schedule→scenario 转移条件（见第 5 节） | |
| M8 | `ai/state/npc_state.go` — SelfState | **增加** `NowMs int64` 字段 | Brain 时间比较 |
| M9 | `ecs/system/decision/bt_tick_system.go` — Update() | **增加** Snapshot 前设置 `npcState.Self.NowMs` | `mtime.NowTimeWithOffset().UnixMilli()` |
| M10 | `ai/decision/v2brain/expr/field_accessor.go` — resolveSelf() | **增加** `case "NowMs"` | |
| T1 | `ai/execution/handlers/schedule_handlers_test.go` — mockScenarioFinder | **增加** `FindCandidates` mock 方法 | |
| T2 | `ai/execution/handlers/schedule_handlers_test.go` — TestScenarioHandler_OnEnter_NoPreAssign | **更新** PointId==0 走自主搜点路径 | |
| T3 | `ai/execution/handlers/schedule_handlers_test.go` | **新增** OnEnter 搜点成功/失败/Occupy 失败测试 | |
| T4 | `ai/execution/handlers/schedule_handlers_test.go` | **新增** OnExit PointId==0 不覆写冷却测试 | |

### 4.2 备注

- **不变的文件**：`orthogonal_pipeline.go`、`v2_pipeline_defaults.go`
- **已就绪无需改动**：`ScenarioCooldownUntil` 已在 Snapshot（ScheduleState 整体拷贝）和 FieldAccessor（`resolveSchedule` case）中
- **不需修改的方法**：`abortScenario`（仅在 ScenarioPointId > 0 时被调用，冷却逻辑不受影响）
- **已有接口复用**：`ReleaseByNpc` 在 `ScenarioNpcCleaner` 接口上，adapter 已实现，`scenarioNpcCleaner` 包变量已在 `locomotion_managers.go` 初始化
- **配置文件范围**：仅改 `gta_locomotion.json`（`locomotion.json` 不存在，非 GTA NPC 未启用正交管线）

### 4.3 NowMs 设计说明

Brain 表达式系统不支持时间变量，冷却比较 `Schedule.ScenarioCooldownUntil < Self.NowMs` 需新增 `NowMs`。

**注入方式**：BtTickSystem.Update() 在 `npcState.Snapshot()` 前写入 `npcState.Self.NowMs = mtime.NowTimeWithOffset().UnixMilli()`，Snapshot 自然拷贝。无需改 `Snapshot()` 签名。

**精度安全**：表达式求值器内部用 float64 比较 int64。毫秒时间戳 ~1.7×10¹²，float64 精度覆盖到 2⁵³ ≈ 9×10¹⁵，无损失。

**通用能力**：`Self.NowMs` 放入 SelfState（与 NpcID、IsDead 同组），未来其他维度的时间条件可复用。

**精度安全**：表达式求值器内部用 float64 比较 int64。毫秒时间戳当前 ~1.7×10¹²，
float64 精度覆盖到 2⁵³ ≈ 9×10¹⁵，精度损失为零。

---

## 5. Brain JSON 配置

### 5.1 转移拓扑（保持 schedule hub 模式）

当前 gta_locomotion.json 使用 `schedule` 作为中枢：

```
on_foot ←→ schedule ←→ scenario / patrol / guard
```

本次改造**不改变拓扑**，仅修改 `schedule → scenario` 的转移条件。

### 5.2 修改 schedule → scenario 转移条件

**改造前**（被动，依赖 ScenarioSystem 预设 CurrentPlan）：
```json
{
  "from": "schedule",
  "to": "scenario",
  "priority": 3,
  "probability": 100,
  "condition": "Schedule.CurrentPlan == \"scenario\""
}
```

**改造后**（主动，Brain 自主评估场景点条件）：
```json
{
  "from": "schedule",
  "to": "scenario",
  "priority": 3,
  "probability": 100,
  "condition": "Schedule.ScenarioPointId == 0 && Schedule.ScenarioCooldownUntil < Self.NowMs && Movement.IsMoving == false && External.ScriptOverride == false"
}
```

- **priority 3**：与现有一致，低于 schedule→patrol（priority 2）
- **probability 100**：Brain 的 probability 仅用于同优先级多转移的加权选择，单转移时直接命中。
  频率控制由冷却机制（5s/30s）和逐点概率（OnEnter 内）承担，不在 Brain 层做概率门控
- `Self.NowMs` 为 Snapshot 中新增的时间字段（见 4.4），取当前毫秒时间戳
- 移除 `CurrentPlan == "scenario"` 条件（不再需要外部系统预设）
- **注意**：`condition` 是单个字符串（非数组），多条件用 `&&` 连接

### 5.3 scenario → schedule 退出转移（不变）

```json
{
  "from": "scenario",
  "to": "schedule",
  "priority": 1,
  "probability": 100,
  "condition": "Schedule.CurrentPlan == \"\""
}
```

ScenarioHandler 完成或失败时设置 `CurrentPlan = ""`，Brain 下帧检测到后切回 schedule（非 on_foot）。

---

## 6. 风险与注意事项

### 6.1 性能

- ScenarioHandler.OnEnter 中调用 `FindCandidates` 是同步操作（与原 ScenarioSystem 调用 FindNearestFiltered 等价）
- ScenarioPointManager 使用空间网格索引（SpatialGrid），单次查询 O(1) 网格单元
- 频率控制由冷却机制 + 逐点概率两层保证：正常完成 30s 冷却、搜点失败 5s 冷却、逐点概率过滤
- Brain probability 不做门控（单转移时 probability 被忽略），避免依赖不可靠的概率机制

### 6.2 Brain 不会死循环

- OnEnter 搜点失败 → 设 5s 短冷却 + `CurrentPlan = ""` → Brain 回 schedule
- Brain 下帧评估时 `ScenarioCooldownUntil < Self.NowMs` 不满足 → 5s 内不会再进入 scenario
- 冷却覆盖所有失败路径：无候选点、概率未命中、Occupy 竞争失败

**冷却分层机制**（三道防线）：

| 层级 | 触发点 | 冷却时长 | 说明 |
|------|--------|---------|------|
| Brain 转移条件 | `ScenarioCooldownUntil < Self.NowMs` | — | 冷却期内条件不满足，根本不会转移（第一道防线） |
| OnEnter failWithCooldown | 搜点/概率/占用失败 | 5s | 不缩短已有的更长冷却（第二道防线） |
| OnExit | 正常完成/abort | 30s | 仅在 ScenarioPointId > 0 时设置（第三道防线） |
| 逐点概率 | OnEnter 概率循环 | — | 每个场景点按配置概率独立决定是否选中 |

### 6.3 NPC 销毁清理

改造前 ScenarioSystem.OnDestroy 遍历所有 NPC 释放占用。改造后：

- 正常流程：ScenarioHandler.OnExit 释放
- 异常销毁：SceneNpcMgr.DestroyNpc → Pipeline.RemoveEntity 触发各 Handler OnExit → 释放
- 兜底：SceneNpcMgr.DestroyNpc 额外调用 `scenarioNpcCleaner.ReleaseByNpc`（接口和实现已存在）

### 6.4 兼容过渡

可分两步执行：
1. **第一步**：ScenarioHandler.OnEnter 支持自主搜点（ScenarioPointId==0 时），ScenarioSystem 保留但降低扫描频率
2. **第二步**：验证稳定后删除 ScenarioSystem

### 6.5 测试要点

| 场景 | 验证内容 |
|------|----------|
| 空闲 NPC 自动做场景点 | Brain 条件满足 → OnEnter 搜点成功 → 状态机正常执行 |
| 附近无场景点 | OnEnter 搜点失败 → 设 5s 短冷却 → Brain 回 schedule |
| 逐点概率全未命中 | OnEnter 概率循环无命中 → 设 5s 短冷却 → Brain 回 schedule |
| 日程打断场景点 | Loop 阶段 shouldLeaveForSchedule → Leave → WalkBack → Brain 切 schedule |
| NPC 销毁时占用释放 | DestroyNpc → OnExit → Release + scenarioNpcCleaner.ReleaseByNpc 兜底 |
| 冷却期内不重复尝试 | ScenarioCooldownUntil 未到期 → Brain 条件不满足 → 不进入 scenario |
| 多 NPC 竞争同一场景点 | Occupy 失败 → OnEnter 退出 → 不死锁 |
| OnEnter 失败后 OnExit 不覆写冷却 | 搜点失败(5s冷却) → 下帧 OnExit → ScenarioPointId==0 → 不设 30s 冷却 |
| Self.NowMs 表达式求值 | Brain 条件 `Schedule.ScenarioCooldownUntil < Self.NowMs` 正确求值 |
