# 根因分析报告 - NPC 坐标不变，未发生移动

> 版本：0.0.3 / 功能模块：V2_NPC
> 完整原始分析：[npc-no-movement.md](V2_NPC/npc-no-movement.md)

## Bug 描述

大世界 NPC 生成后停留在初始位置，坐标始终不变，未按巡逻路线移动。

## 直接原因

`P1GoServer/bin/config/ai_decision_v2/bigworld_navigation.json` 文件缺失。

`buildDimensionConfigs("bigworld_", ...)` 构建 4 个正交维度，每个维度需要对应的 `bigworld_*.json`（`v2_pipeline_defaults.go:164-166`）：

| 配置文件 | 状态 |
|---------|------|
| `bigworld_engagement.json` | ✓ 存在 |
| `bigworld_expression.json` | ✓ 存在 |
| `bigworld_locomotion.json` | ✓ 存在 |
| `bigworld_navigation.json` | ✗ **缺失** |

断链路径：
navigation 维度加载配置失败 → `OrthogonalPipeline.Tick()` navigation 维度跳过 → `PatrolHandler` 未被调用 → `mv.IsMoving=false` → `syncNpcMovement`（`bt_tick_system.go:274`）在 `IsMoving` 检查处提前返回 → `MoveEntityViaRoadNet` / `NpcMoveComp.StartMove()` 从不调用 → `NpcMoveSystem` 因 `IsPaused=true` 跳过 → NPC 坐标永远不变。

## 根本原因分类

**任务遗漏（配置文件）** — 添加 BigWorld V2 管线时创建了 engagement / expression / locomotion 三个 JSON，遗漏了 navigation 维度所需的 `bigworld_navigation.json`。Review 阶段不检查配置文件存在性，因此漏网。

## 影响范围

- BigWorld 场景下所有 V2 NPC 全部静止，无一例外
- `NpcMoveSystem` 下游逻辑（碰撞推开、路径跟随）不触发
- GTA / Animal 场景不受影响（各自 navigation.json 均存在）

## 修复方案

创建 `P1GoServer/bin/config/ai_decision_v2/bigworld_navigation.json`，内容与 `gta_navigation.json` 相同（两者 navigation 维度 handler 注册相同，见 `v2_pipeline_defaults.go:204-216`）：

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
    {"from": "idle", "to": "navigate", "priority": 1, "probability": 100, "condition": "Movement.IsMoving == true"},
    {"from": "idle", "to": "interact", "priority": 2, "probability": 100, "condition": "Social.InDialog == true"},
    {"from": "navigate", "to": "idle", "priority": 1, "probability": 100, "condition": "Movement.IsMoving == false"},
    {"from": "interact", "to": "idle", "priority": 1, "probability": 100, "condition": "Social.InDialog == false"}
  ]
}
```

修复后重启 scene_server，验证 NPC 开始沿巡逻路线移动。

## 是否需要固化防护

**是** — 在 `.claude/rules/auto-work-lesson-005.md` 编码后自查清单末尾增加：

> Go 文件（新增场景 V2 管线）：grep `buildDimensionConfigs` 调用的 prefix，检查 `bin/config/ai_decision_v2/{prefix}*.json` 是否覆盖全部 4 个维度（engagement / expression / locomotion / navigation）。

## 修复风险评估

**低** — 仅新增配置文件，不修改任何代码。最坏情况是 navigation 计划转移不符合预期，不会引发新崩溃。GTA / Animal 场景不受影响。
