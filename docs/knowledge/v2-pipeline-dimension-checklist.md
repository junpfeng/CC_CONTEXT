# V2 正交管线维度注册 Checklist

> **来源**：0.0.3/V2_NPC Bug #1（NPC 坐标不变，未发生移动，2026-03-29）
> **严重性**：P0 — 静默失效，服务器无任何报错，NPC 完全静止

## 问题描述

V2 正交管线新增维度时，三件套缺任何一项都会导致 NPC 完全静止，且全链路无报错：

```
setupOrthogonalPipeline 加载 JSON 失败 → continue（跳过，零报错）
PlanExecutor.OnTick() 找不到 plan handler → 什么都不做（零报错）
孤立的 Handler 文件 → 永远不被调用（零报错）
```

## 三件套 Checklist

| # | 必须完成 | 缺失后果 |
|---|---------|---------|
| 1 | `bin/config/ai_decision_v2/<prefix>_<dimension>.json` 文件存在 | setupOrthogonalPipeline `continue` 跳过该维度 |
| 2 | JSON `init_plan` 的值在代码中有对应 `RegisterHandler("<plan>", ...)` | OnTick 无操作，IsMoving 永远 false |
| 3 | Handler 在 `bigworldDimensionConfigs()` 等入口处显式注册 | Handler 文件孤立，永远不被执行 |

## 验证命令

```bash
# 列出所有 plan name
grep -h '"name"' bin/config/ai_decision_v2/bigworld_*.json

# 确认每个 plan name 都有 RegisterHandler 调用
grep -rn 'RegisterHandler' servers/scene_server/internal/ecs/res/npc_mgr/
```

## 典型失效示例

```
bigworld_locomotion.json:  "init_plan": "idle"
代码：handlers.RegisterHandler("patrol", handlers.NewOnFootHandler())
     // BigWorldDefaultPatrolHandler 文件存在但从未 RegisterHandler("idle", ...)
bigworld_navigation.json:  文件不存在

结果：
- locomotion 维度 OnTick 无操作 → IsMoving = false
- navigation 维度被 continue 跳过
- syncNpcMovement 提前 return → Transform 永远不 dirty → 客户端坐标不更新
- 全程无任何 error log
```
