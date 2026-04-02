# Bug 分析：大世界 NPC 坐标不变，未发生移动

## Bug 描述

大世界 NPC 被创建（客户端可见），但坐标始终不变，NPC 停留在初始生成位置，未按巡逻路线移动。
服务端 AI 管线正确运行时，NPC 应在 PatrolHandler.OnTick() 驱动下通过 syncNpcMovement → MoveEntityViaRoadNet → NpcMoveComp.StartMove() 实现移动。

## 代码定位

| 文件 | 行号 | 说明 |
|------|------|------|
| `P1GoServer/bin/config/ai_decision_v2/` | 全目录 | **缺少 `bigworld_navigation.json`**（animal/gta 均有，bigworld 独缺） |
| `v2_pipeline_defaults.go` | L153-158 | `bigworldDimensionConfigs()` 调用 `buildDimensionConfigs("bigworld_", ...)` |
| `v2_pipeline_defaults.go` | L204-217 | navigation 维度 ConfigPath = `"config/ai_decision_v2/bigworld_navigation.json"` |
| `bt_tick_system.go` | L117, L120 | `activePipeline.Tick()` 后调用 `syncNpcMovement()` |
| `bt_tick_system.go` | L272-346 | `syncNpcMovement`: 检查 `mv.IsMoving && mv.MoveTarget` 非零，再调用 `MoveEntityViaRoadNet` |
| `scene_accessor_adapter.go` | L268 | `MoveEntityViaRoadNet` 末尾调用 `moveComp.StartMove()` ✓ |
| `bigworld_locomotion.json` | 全文 | `idle → patrol` 当 `Schedule.PatrolRouteId > 0` ✓ |

**当前行为**：
navigation 维度加载 `bigworld_navigation.json` 失败 → 维度执行器无法初始化计划列表 → 管线 Tick 异常（或 navigation 维度静默忽略跳过）。
即便 locomotion PatrolHandler 设置了 `mv.IsMoving=true`，如果整个 `activePipeline.Tick()` 因 navigation 维度错误提前退出，`mv.IsMoving` 永远不会被设置，`syncNpcMovement` 在第一个检查（line 274）就返回 → `MoveEntityViaRoadNet` 从不调用 → `StartMove` 从不调用 → NPC 停留原地。

**预期行为**：
`bigworld_navigation.json` 存在 → navigation 维度正确初始化 → 管线完整 Tick → PatrolHandler 设置 MoveTarget → syncNpcMovement → MoveEntityViaRoadNet → StartMove → NPC 沿巡逻路线移动。

## 全链路断点分析

### idea.md → feature.json
- **是否覆盖**：N/A（V2_NPC 为纯客户端动画任务，不涉及 AI 管线配置）

### feature.json → plan.json
- **是否覆盖**：N/A

### plan.json → tasks/
- **是否覆盖**：N/A（8 个任务全为客户端 C# 实现）

### tasks/ → 代码实现
- **是否实现**：**部分** —— 配置文件遗漏
- **分析**：BigWorld V2 管线代码完整（BtTickSystem、PatrolHandler、locomotion config），但 `bigworld_navigation.json` 从未被创建。对比其他场景：
  - `gta_navigation.json` ✓ 存在
  - `animal_navigation.json` ✓ 存在
  - `bigworld_navigation.json` ✗ **缺失**
- **原因推断**：BigWorld V2 管线作为 auto-work 新增功能，在添加 `bigworld_locomotion.json`/`bigworld_engagement.json`/`bigworld_expression.json` 时，**遗漏了 `bigworld_navigation.json`**

### Review 检出
- **是否被 Review 发现**：否
- **原因**：Review 检查代码逻辑，配置文件存在性通常不在 review scope 内

## 归因结论

**主要原因**：**任务遗漏（配置文件）** + **Review 盲区** — 添加 BigWorld V2 管线时创建了 engagement/expression/locomotion 三个 JSON，遗漏了 navigation 维度所需的 `bigworld_navigation.json`

**根因链**：
```
BigWorld V2 管线注册 bigworldDimensionConfigs() 共4个维度
↓
4个维度都需要对应的 JSON 配置文件（bigworld_*.json）
↓
engagement/expression/locomotion 三个已创建
↓
bigworld_navigation.json 遗漏未创建
↓
navigation 维度 Executor 加载配置失败
↓
OrthogonalPipeline.Tick() 对 BigWorld NPC 异常（部分或全部维度跳过）
↓
PatrolHandler 未被调用 → mv.IsMoving=false → syncNpcMovement 提前返回
↓
MoveEntityViaRoadNet 未调用 → NpcMoveComp.StartMove() 未调用
↓
NpcMoveSystem 跳过（IsPaused=true）→ NPC 坐标不变
```

## 修复方案

### 代码修复

**创建 `P1GoServer/bin/config/ai_decision_v2/bigworld_navigation.json`**，内容与 `gta_navigation.json` 相同：

```json
{
  "system": "navigation",
  "init_plan": "idle",
  "plan_interval": 0,
  "plans": [
    {"name": "idle"},
    {"name": "navigate"},
    {"name": "interact"},
    {"name": "investigate"}
  ],
  "transitions": [
    {
      "from": "idle",
      "to": "navigate",
      "priority": 1,
      "probability": 100,
      "condition": "Movement.IsMoving == true"
    },
    {
      "from": "idle",
      "to": "interact",
      "priority": 2,
      "probability": 100,
      "condition": "Social.InDialog == true"
    },
    {
      "from": "navigate",
      "to": "idle",
      "priority": 1,
      "probability": 100,
      "condition": "Movement.IsMoving == false"
    },
    {
      "from": "interact",
      "to": "idle",
      "priority": 1,
      "probability": 100,
      "condition": "Social.InDialog == false"
    }
  ]
}
```

修复后预期：BtTickSystem 完整 Tick → navigation 维度正确选 navigate/idle 计划 → locomotion 的 PatrolHandler 设置 MoveTarget → syncNpcMovement 驱动 MoveEntityViaRoadNet → NPC 开始移动。

### 工作流优化建议

- **问题**：添加新场景 V2 管线时，`buildDimensionConfigs` 需要 N 个配置文件，但没有检查点验证所有配置文件是否存在
- **建议**：在 `auto-work-lesson-005.md` 的编码后自查清单中增加：新增场景类型管线时，grep `buildDimensionConfigs` 调用的 prefix，检查 `bin/config/ai_decision_v2/{prefix}*.json` 是否覆盖所有维度（engagement/expression/locomotion/navigation）
- **改哪里**：`.claude/rules/auto-work-lesson-005.md` 已有规则扫描项列表末尾
