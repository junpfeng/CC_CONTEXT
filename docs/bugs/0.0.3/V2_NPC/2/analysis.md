# 根因分析报告 - NPC 分布密度低，巡逻路线不全局持久化

> 版本：0.0.3 / 功能模块：V2_NPC
> 完整原始分析：[npc-density-patrol-everywhere.md](V2_NPC/npc-density-patrol-everywhere.md)

## Bug 描述

大世界 NPC 分布密度低，20 条预配置巡逻路线（`ai_patrol/bigworld/*.json`）无法全局持久化：NPC 仅出现在玩家 200m AOI 范围内，玩家离开后 NPC 随即被回收，远端路线始终空无一人。

## 直接原因

三处代码共同导致：

| 文件 | 行号 | 问题说明 |
|------|------|---------|
| `servers/scene_server/internal/ecs/res/npc_mgr/bigworld_walk_zone.go` | L85-93 | `WalkZoneQuotaCalculator.Calculate()` 仅对被玩家 AOI 圆（SpawnRadius=200m）覆盖的 zone 分配配额，未覆盖 zone 的配额强制为 0，远端路线无 NPC 生成权利 |
| `servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_spawner.go` | L372-406 | `doSpawn()` 总上限 MaxCount=50，所有 NPC 挂靠最近玩家（OwnerPlayer），随玩家移动触发 `despawnNpc()` 距离回收，静态路线 NPC 无豁免机制 |
| `servers/scene_server/internal/ecs/scene/scene_impl.go` | L227-228 | 初始化使用 `DefaultBigWorldSpawnConfig()`（SpawnRadius=200，MaxCount=50），场景启动后无"预生成巡逻路线 NPC"阶段 |

**根因链**：
```
产品预期：20 条巡逻路线全时可见 NPC（共 40 个静态 NPC）
       ↓
scene_impl.go 初始化：仅创建动态 AOI Spawner，无预生成阶段
       ↓
WalkZone 配额计算：未被玩家 AOI 覆盖的 zone → 配额 = 0
       ↓
doSpawn：总预算 50 个，仅在玩家附近生成，随玩家移动动态换位
       ↓
结果：玩家离开后路线 NPC 被距离回收，任何无人区路线始终为空
```

## 根本原因分类

**需求理解偏差 + 架构设计冲突**

V2_NPC feature.json 明确定义为"纯客户端动画/FSM 对齐，零服务端变动"，Spawner 的"动态 AOI 跟随"架构是预先存在的设计，从未被评估是否满足"巡逻路线全局持久化"的产品期望：

- **Spawner 设计假设**：NPC 紧跟玩家，保证玩家身边有人，节省服务器实体开销
- **巡逻路线设计假设**：特定路线上持续存在 NPC，不依赖玩家位置

两套假设在任何需求文档层面均未被对齐，属于跨架构约束的需求遗漏。

## 影响范围

| 影响点 | 说明 |
|--------|------|
| 全部 20 条大世界巡逻路线 | 玩家不在附近时路线完全为空 |
| `bigworld_npc_spawner.go` 的 `doDespawn()` | 若修复时新增静态 NPC，现有距离回收逻辑会误回收 |
| `bigworld_walk_zone.go` 的 `Calculate()` | 静态 NPC 若不豁免配额，会挤占动态 NPC 的 50 个预算 |
| `npc_zone_quota.json` 的 `totalNpcBudget=50` | 静态路线 40 个 + 动态 50 个 = 需上调至 90 |

## 修复方案

**推荐：静态预生成方案**（40 个固定开销，可控）

**Step 1 — 新增 `PreSpawnPatrolRoutes()` 方法**（`bigworld_npc_spawner.go`）：
- 遍历 `patrolMgr.AllRoutes()`，对每条路线按 `DesiredNpcCount` 在路线节点上生成 NPC
- `activeNpcInfo` 新增 `staticPatrol bool` 字段，标记这批 NPC

**Step 2 — `doDespawn()` 豁免静态 NPC**（`bigworld_npc_spawner.go`）：
- 检查 `activeNpcInfo.staticPatrol == true` 时跳过距离回收

**Step 3 — 配额豁免**（`bigworld_walk_zone.go` 或 `npc_zone_quota.json`）：
- 方案 A：静态 NPC 不计入 `currentNpcCounts`（代码改动）
- 方案 B：`npc_zone_quota.json` 的 `totalNpcBudget` 提高至 90（配置改动，更简单）

**Step 4 — `scene_impl.go` 调用点**：
```go
// 在 spawner.SetPatrolMgr(bigWorldPatrolMgr) 之后添加
if bigWorldPatrolMgr != nil {
    spawner.PreSpawnPatrolRoutes()
}
```

注意：调用时序需确保 `patrolMgr` 已完成路线加载（`LoadPatrolRoutes()` 已执行）。

**备选：配置调整方案**（不推荐）：
- SpawnRadius 扩至 6000m + totalNpcBudget 扩至 200
- 代价：服务器持续维护 200 个实体，性能开销不可控

## 是否需要固化防护

**是** — 建议在 `skills/feature/plan-creator.md` 的 Plan 创建 prompt 中增加：

> 若 feature 依赖已有服务端基础设施（Spawner / AOI / 配额系统），需显式验证该基础设施的规模/密度/覆盖范围是否满足产品期望。"纯客户端 feature"不代表可以忽略服务端基础设施约束。

## 修复风险评估

**低** — `staticPatrol` 标记位仅影响新增路径，不修改已有动态 NPC 的生成/回收主流程；修改局部在 `BigWorldNpcSpawner` 内部，不涉及协议和 TownNPC 系统。

回归验证重点：
- 场景启动后 20 条路线上各有 NPC（静态预生成生效）
- 玩家远离路线后，路线 NPC 不被回收（豁免生效）
- 动态 AOI NPC 正常生成/回收不受影响
