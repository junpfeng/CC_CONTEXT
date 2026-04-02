═══════════════════════════════════════════════
  Bug Fix Review 报告
  版本：0.0.3
  模块：V2_NPC
  审查文件：6 个
═══════════════════════════════════════════════

## 一、根因修复验证

### 根因对应性
✅ 两个根因均有对应修复：
- **根因 A**（BigWorldDefaultPatrolHandler 未注册）：`bigworldDimensionConfigs()` 重写为显式 4 维度配置，locomotion 维度注册 `"idle" → BigWorldDefaultPatrolHandler`。直接对应分析报告中的根因。
- **根因 B**（bigworld_navigation.json 缺失）：文件已创建，内容为 `init_plan: "navigate"`，navigation 维度可正常加载。直接对应分析报告中的根因。

### 修复完整性
⚠️ 核心路径修复完整，但巡逻 Handler 存在到达判定逻辑缺陷（见问题 HIGH-1）：
- NPC IsMoving 可被正确设置为 true，syncNpcMovement 会触发 A* 寻路 ✅
- NpcMoveComp 路径执行驱动实际移动 ✅
- 但 `BigWorldDefaultPatrolHandler.OnTick` 中的到达判定逻辑错误，导致每帧都误判到达。NPC 实际靠 NpcMoveComp 路径执行在移动，而不是靠巡逻状态机正确驱动。

### 影响范围覆盖
✅ bigworld 场景下所有 V2 NPC 均受益于此修复（dimension 配置是场景级）。无其他同类遗漏。

---

## 二、合宪性审查

### 服务端（.go 文件）

| 条款 | 状态 | 说明 |
|------|------|------|
| 错误处理 | ✅ | `PreSpawnPatrolRoutes` 的 spawnNpcAt 错误走 log.Errorf + continue，符合规范 |
| Actor 独立性 | ✅ | Spawner 数据仅在 scene 初始化路径访问，无跨协程并发风险 |
| 日志格式 | ✅ | 新增日志均使用 `%v`，字段命名使用 `npc_cfg_id=`，符合 logging.md 规范 |
| 日志模块标签 | ✅ | 使用 `[BigWorldNpcSpawner]`、`[BigWorldPatrol]` 方括号格式 ✅ |
| safego | ✅ | 无新 goroutine 引入 |

---

## 三、副作用与回归风险

### [HIGH] handlers/bigworld_default_patrol.go:110 — 到达判定使用 TargetPos 而非实体实际世界坐标

**问题描述**：`BigWorldDefaultPatrolHandler.OnTick` 用 `ctx.NpcState.Movement.TargetPos` 作为 NPC "当前位置" 与 MoveTarget 比较，判断是否到达目标。但 `TargetPos` 并非 NPC 的实际世界位置——它由 navigation 维度的 `navStartMove`/`navCheckArrival` 写入，始终等于 `MoveTarget`（`navigation_handlers.go:38,61`）。

**触发过程**：
```
Tick 1:
  locomotion OnEnter → pickNewTarget → MoveTarget=random, IsMoving=true
  navigation OnEnter → navStartMove → TargetPos = MoveTarget = random
  syncNpcMovement → 路径计算，NpcMoveComp 开始执行移动

Tick 2:
  locomotion OnTick:
    pos = TargetPos = random
    target = MoveTarget = random
    distSq = (pos.X - target.X)² + (pos.Z - target.Z)² ≈ 0 < 9
    → 误判到达！IsMoving = false，进入 3-8 秒等待
  syncNpcMovement: IsMoving=false → 不计算新路径
  但 NpcMoveComp 仍在执行 Tick 1 中的路径段
```

**影响**：NPC 的巡逻到达语义完全失效。NPC 靠 NpcMoveComp 物理移动，而非巡逻状态机的正确到达检测驱动。巡逻 idle 等待由计时器（3-8s）触发，而不是物理到达后触发。原始 bug（NPC 完全静止）已修复，但巡逻行为的状态机驱动不正确。

**建议**：参考 `navCheckArrival` 使用 `distanceSqToTarget(ctx.Scene, ctx.EntityID, target)` 获取实体的真实世界坐标距离：
```go
// 替换
pos := ctx.NpcState.Movement.TargetPos
target := ctx.NpcState.Movement.MoveTarget
dx := pos.X - target.X
dz := pos.Z - target.Z
distSq := dx*dx + dz*dz

// 改为
distSq, ok := distanceSqToTarget(ctx.Scene, ctx.EntityID, ctx.NpcState.Movement.MoveTarget)
if !ok { return }
```

---

### [HIGH] 本次 commit 包含 3 个与 V2_NPC bug 无关的文件变更

**场景**：git diff HEAD~1 中包含：
- `base/gonet/tcpclient.go`：注释代码中的 `%s` → `%v` 日志格式修改
- `common/citem/item.go`：`%d` → `%v` 日志格式修改
- `common/cmd/app.go`：`%s` → `%v` 日志格式修改（2 处）

**影响**：虽然这些改动本身是正确的（符合 logging.md 规范），但违反了 Bug 修复最小化原则（lesson-004）。混入无关变更扩大了 diff 范围，增加 code review 负担，且若此 commit 需要 revert，会一并 revert 本无问题的格式修复。

**建议**：在后续单独的 `<style>` commit 中提交这 3 个文件的格式修改，与 bug fix commit 保持隔离。

---

## 四、最小化修改检查

❌ 存在无关修改：
- 3 个日志格式文件（见 HIGH-2）与 V2_NPC bug 修复无关

✅ 核心修复修改范围合理：
- `v2_pipeline_defaults.go`：重写 `bigworldDimensionConfigs()` 是必要的，因为旧版使用 `buildDimensionConfigs` 代理且不支持独立注册 idle handler
- `bigworld_npc_spawner.go`：`PreSpawnPatrolRoutes` + `staticPatrolCfgIds` 是可选增强（预生成静态巡逻 NPC），但不影响 bug 修复的核心路径。属于超出 bug fix 范围的新功能，可接受。
- `scene_impl.go`：调用 `PreSpawnPatrolRoutes` 是对应的初始化调用，合理
- `bigworld_navigation.json`：新建配置文件，是 Fix B 的直接修复

### 附：activeNpcInfo.StaticPatrol 字段冗余

**MEDIUM** — `bigworld_npc_spawner.go` 中 `activeNpcInfo.StaticPatrol` 字段在 `PreSpawnPatrolRoutes` 中写入，但 `doDespawn` 的豁免逻辑实际检查 `staticPatrolCfgIds` map，该字段从未被读取。存在两套"静态 NPC 标记"（struct 字段 vs map），实际生效的是 map。该字段为死代码，容易造成混淆。建议移除 `activeNpcInfo.StaticPatrol` 字段，以 `staticPatrolCfgIds` map 为唯一 source of truth。

---

## 五、总结

```
  CRITICAL: 0 个（必须修复）
  HIGH:     2 个（强烈建议修复）
  MEDIUM:   1 个（建议修复，可酌情跳过）

  结论: 需修复后再审

  重点关注:
  1. [HIGH-1] bigworld_default_patrol.go:110 — 到达判定必须改用实体真实世界坐标
     (distanceSqToTarget)，否则巡逻状态机驱动失效
  2. [HIGH-2] 3 个无关文件的日志格式修改应从本 commit 中剥离，单独 <style> commit
  3. [MEDIUM] activeNpcInfo.StaticPatrol 字段冗余，应移除避免与 staticPatrolCfgIds 混淆
```

<!-- counts: critical=0 high=2 medium=1 -->
