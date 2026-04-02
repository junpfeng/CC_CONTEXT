# Bug 分析：大世界 NPC 原地踏步 + 密密麻麻聚堆

## Bug 描述

**现象**：大世界满大街都是原地踏步的 NPC，且密密麻麻聚集成堆。
- NPC 播放行走动画，但实际位移为零或极小（视觉上"原地踏步"）
- 大量 NPC 聚集在同一区域，密度异常高

**复现**：进入大世界后观察街道，可见成堆 NPC 聚集且集体原地踏步。

---

## 代码定位

### 问题一：原地踏步（Walk 动画播放但无位移）

- **涉及文件**：
  - `freelifeclient/.../BigWorld/Entity/NPC/Comp/BigWorldNpcTransformComp.cs:92-116`（LOD 帧间隔更新）
  - `freelifeclient/.../BigWorld/Entity/NPC/Comp/BigWorldNpcMoveComp.cs:71-96`（帧间速度计算）
  - `freelifeclient/.../BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs:658-701`（UpdateSpeedDrivenAnimation）

- **当前行为**：
  - TransformComp 在 LOD REDUCED/MINIMAL 模式下每 3-6 帧才更新一次 Transform 和 `_previousPosition`
  - 但 `_snapshotQueue.Update()` 每帧都在推进时间线（位置内插在 SnapshotQueue 中前进）
  - MoveComp 每帧读取 `PreviousPosition` 计算速度：`speed = |currentPos - previousPos| / deltaTime`
  - LOD 跳帧期间，`_previousPosition` 停留在数帧前，`currentPos` 也停留在数帧前（未应用新快照），速度计算结果为 0
  - AnimationComp 读到 `speed=0 → mode=Idle`，播放 Idle 动画——但服务端状态是 Walk
  - **结果**：服务端推送 walk 状态，客户端 FSM 进入 WalkState；但速度驱动层判定 speed=0，实际播放的是 Idle 动画；NPC 看上去"原地踏步"

- **预期行为**：TransformComp 每帧推进 SnapshotQueue 后，MoveComp 应能正确感知位移，speed > 0 → 播放 Walk 动画且 NPC 向前移动

### 问题二：密密麻麻聚堆（Spawn 无 NPC 间距保护）

- **涉及文件**：
  - `P1GoServer/.../npc_mgr/bigworld_npc_spawner.go:626-663`（`findSpawnPosition`）
  - `P1GoServer/.../npc_mgr/bigworld_npc_spawner.go:267-330`（`initSpawnPoints`）

- **当前行为**：
  - `findSpawnPosition` 只检查候选点与**玩家**的最小距离（`minSpawnDistSqXZ=100`，即 10m²=3.16m）
  - **不检查候选点与已有 NPC 的距离**
  - `spawnPoints` 直接使用路网 footwalk 节点，节点间距可低至 0.5-1m
  - 多个 NPC 可以 spawn 在相邻节点（间距 < 1m），形成堆聚

- **预期行为**：候选 spawn 点距离现有 NPC 应不小于最小安全间距（建议 5m）

---

## 全链路断点分析

### idea.md → feature.json

- **是否覆盖**：
  - 原地踏步（动画/位移同步）：部分覆盖
  - 密集聚堆（spawn 间距）：**未覆盖**

- **idea.md 原文**（移动动画）：
  > 动画驱动方式 | FSM 状态机直接控制播放 | 自动速度驱动（UpdateSpeedDrivenAnimation）| 大世界更流畅但缺少精细控制
  > 不改变大世界的速度驱动动画系统（比小镇的 FSM 驱动更适合大量 NPC）

- **feature.json 对应**：REQ-001~REQ-008 全部聚焦于动画状态（TurnState、ScenarioState、RightArm 层等），无关于 LOD 与速度驱动的交互约束，无关于 spawn 间距。

### feature.json → plan.json

- **是否覆盖**：
  - 动画速度驱动：plan 描述了 UpdateSpeedDrivenAnimation 的实现路径，但未设计 LOD 帧间隔与速度计算的兼容性
  - spawn 间距：**plan.json 无任何 spawn 相关设计**（V2_NPC 的 plan 范围仅限于客户端动画表现）

- **plan.json 原文**（动画层）：
  > Layer 0: Base — 速度驱动Walk/Run混合；性能约束：单帧200 NPC动画系统总CPU开销增量不超过0.5ms

### plan.json → tasks/

- **是否覆盖**：
  - tasks/README.md：task-01~08 全部为客户端动画相关（性别Prefab/TurnState/ScenarioState/动画层/Timeline等）
  - **无任何 spawn 相关 task**
  - **无 LOD 与速度驱动兼容性 task**

### tasks/ → 代码实现

- **原地踏步**：
  - 任务要求（plan）：使用速度驱动动画，200 NPC 性能预算 0.5ms
  - 实际代码：TransformComp 实现了 LOD 跳帧（合理的性能优化），但 MoveComp 的速度计算未适配 LOD 跳帧场景，导致跳帧期间 speed=0
  - **归因：实现缺陷**（LOD 与速度驱动的兼容性未被设计和测试）

- **聚堆**：
  - 无对应 task（spawn 系统不在 V2_NPC 的范围内）
  - **归因：需求遗漏**（V2_NPC feature 范围从未涵盖 spawn 密度控制）

### Review 检出

- **原地踏步**：
  - develop-review-report-task-01~08 均未提及 LOD 跳帧导致速度计算异常
  - **未被 Review 发现**（Review 只看 task 范围内的代码，LOD 交互属于非 task 范围的集成问题）

- **聚堆**：
  - spawn 系统不在 V2_NPC feature 范围，所有 task 的 Review 均未涉及
  - **未被 Review 发现**（超出 Review 范围）

---

## 归因结论

**主要原因**：

| 问题 | 归因类别 | 说明 |
|------|----------|------|
| 原地踏步 | **实现缺陷** | LOD 跳帧期间 `_previousPosition` 未与 SnapshotQueue 同步，导致 MoveComp 速度计算归零，速度驱动动画回退到 Idle |
| 密密麻麻 | **需求遗漏** | V2_NPC feature 范围仅覆盖动画表现，从未设计 spawn 间距约束；spawn 系统中仅有玩家距离保护，无 NPC 间距保护 |

**根因链**：

```
原地踏步链：
  idea.md 指定"速度驱动"动画 →
  plan 设计 MoveComp 帧间位移计算速度 →
  实现时 TransformComp 加入 LOD 跳帧优化（合理）→
  MoveComp.OnUpdate 在跳帧期间 currentPos == previousPos → speed=0 →
  AnimationComp 进入 Idle → 客户端显示原地踏步

聚堆链：
  V2_NPC feature 范围限定为"动画表现改进" →
  spawn 系统（BigWorldNpcSpawner）不在 V2_NPC 范围 →
  spawn 系统从路网 footwalk 节点随机选点，节点间距 0.5-1m →
  findSpawnPosition 无 NPC 间距检查 →
  多 NPC 同时 spawn 在相邻节点 → 聚堆
```

---

## 修复方案

### 代码修复（原地踏步）

**`BigWorldNpcTransformComp.cs`** LOD 跳帧时同步 PreviousPosition：

```csharp
// OnUpdate 中，不论是否触发 Transform 更新，都要在 SnapshotQueue 位置有效时更新 previousPosition
_snapshotQueue.Update();  // 每帧推进

// 始终同步 previousPosition（不受 LOD 间隔限制）
if (_snapshotQueue.SnapshotCount > 0)
{
    _previousPosition = _controller.GetTransform().position;  // 缓存应用前的位置
    // ... LOD 间隔控制 transform 写入 ...
}
```

或更直接：在 TransformComp 上暴露 `SnapshotVelocity`（SnapshotQueue 内部速度），MoveComp 直接读取，绕过帧间差分。

### 代码修复（聚堆）

**`bigworld_npc_spawner.go` `findSpawnPosition`** 增加 NPC 间距检查：

```go
const minNpcSpawnDistSqXZ float32 = 25.0  // 5m 最小间距

func (s *BigWorldNpcSpawner) findSpawnPosition(...) (transform.Vec3, bool) {
    for attempt := 0; attempt < maxSpawnAttempts; attempt++ {
        candidate := ...
        // 现有的玩家距离检查 ...

        // 新增：检查与已有 NPC 的距离
        tooCloseToNpc := false
        s.scene.ForEachNpc(func(npcPos transform.Vec3) bool {
            if distanceSqXZ(candidate, npcPos) < minNpcSpawnDistSqXZ {
                tooCloseToNpc = true
                return false
            }
            return true
        })
        if tooCloseToNpc { continue }

        return candidate, true
    }
}
```

或在 `initSpawnPoints` 阶段对路网节点做稀疏化（按 3-5m 间隔过滤相邻点），从源头减少候选点密度。

### 工作流优化建议

- **问题**：V2_NPC feature 范围设定为"动画表现"，但大世界 NPC 的表现质量依赖 spawn 分布，两个子系统未被联合设计
- **建议**：大世界场景类 feature（涉及 spawn + 表现）需在 feature.json 阶段声明依赖的相邻系统，plan 阶段产出跨系统集成验收条件（如"不能出现 5m 内 NPC 聚堆"）
- **改哪里**：`.claude/skills/dev-workflow/phases/p1-requirements.md` 增加"跨系统表现依赖检查"提示；plan 审查时增加"空间分布"验收指标

---

*生成时间：2026-03-30*
