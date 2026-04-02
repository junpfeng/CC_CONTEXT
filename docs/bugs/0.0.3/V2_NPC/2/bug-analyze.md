# Bug 分析：NPC 分布密度低，巡逻路线 NPC 不全局持久化

## Bug 描述

大世界 NPC 分布密度太低，玩家移动到任意位置时，应能看到 NPC 按照预先配置的行人移动巡逻路线（`ai_patrol/bigworld/bigworld_patrol_001~020.json`）持续巡逻。
但当前表现是：仅在玩家附近 200m 内有 NPC，玩家移动到新区域时 NPC 从零开始动态生成，远离玩家的 zone 中巡逻路线始终为空。

## 代码定位

| 文件 | 行号 | 说明 |
|------|------|------|
| `P1GoServer/.../bigworld_npc_spawner.go` | L371-405 | `doSpawn()` 仅在玩家 AOI 内生成，总数上限 50 |
| `P1GoServer/.../bigworld_npc_spawner.go` | L408-426 | `findBestSpawnPosition` 优先从有配额缺口的 zone 选路线节点 |
| `P1GoServer/.../bigworld_walk_zone.go` | L88-111 | `Calculate()` 未被玩家 AOI 覆盖的 zone 配额为 0 |
| `P1GoServer/.../bigworld_npc_config.go` | L21-22 | `DefaultBigWorldSpawnConfig`: MaxCount=50, SpawnRadius=200 |
| `P1GoServer/bin/config/npc_zone_quota.json` | 全文 | totalNpcBudget=50，5个 zone 各自上限 8-12 |
| `P1GoServer/bin/config/ai_patrol/bigworld/*.json` | 全部 20 个 | 20 条巡逻路线，每条 desiredNpcCount=2，共需 40 个 NPC |
| `P1GoServer/.../scene_impl.go` | L227 | 初始化 Spawner 使用 `DefaultBigWorldSpawnConfig()`，未加载外部 JSON 配置 |

**当前行为**：
- SpawnRadius=200m，NPCs 只在玩家 200m 内出现
- `WalkZoneQuotaCalculator.Calculate()` 对未被玩家 AOI 圆覆盖的 zone 强制配额=0，不生成任何 NPC
- 全局上限 50，20条路线分布在5个 zone，玩家只覆盖1-2个 zone 时，其余 zone 的18条路线全空

**预期行为**：
- 所有 20 条巡逻路线在场景加载时预生成 NPC（每条2个，共40个），持久存在于路线位置
- 不依赖玩家是否靠近，全局可见

## 全链路断点分析

### idea.md → feature.json
- **是否覆盖**：N/A（不在 V2_NPC 范围内）
- **idea.md 原文**：提到"NPC 数量 200+"为**性能约束**，不是密度需求。提到"巡逻节点到达行为需要坐下等状态"是关于**动画状态**，不是生成数量。
- **结论**：idea.md 未提出"任何位置可见 NPC"的需求，V2_NPC 定位为"纯客户端动画/FSM 表现升级"。

### feature.json → plan.json
- **是否覆盖**：N/A
- **feature.json 全部8条需求均为 client side**，无一涉及服务端 NPC 生成密度或全局巡逻路线持久化。
- **结论**：方案设计层未涉及此问题，符合需求边界。

### plan.json → tasks/
- **是否覆盖**：N/A
- 8 个 task 全部为客户端实现任务（Prefab/Animation/FSM/Layer），服务端无任务。

### tasks/ → 代码实现
- **是否实现**：V2_NPC 任务均按 plan 实现完成。
- **实际代码**：Spawner 设计为"动态 AOI 生成器"，这是**预先存在的架构决策**，不是 V2_NPC 引入的问题。

### Review 检出
- **是否被 Review 发现**：否
- **原因**：V2_NPC review 聚焦于客户端代码质量，未涉及服务端 NPC 密度系统。此问题不在 review 边界内。

## 归因结论

**主要原因**：**需求遗漏（跨版本需求边界）**

V2_NPC feature 范围定义为"客户端动画/FSM 对齐"，服务端 NPC 生成/密度/持久化不在其内。用户的"任何位置可见 NPC 巡逻"属于一个独立的**服务端生成架构需求**，从未被纳入任何版本的需求文档。

**根因链**：
```
产品期望：全地图持久化巡逻 NPC
↓
V2_NPC 需求文档：仅关注客户端动画质量（"不改变速度驱动架构"、"不改变 Spawner"）
↓
Spawner 架构：动态 AOI 生成（SpawnRadius=200m，MaxCount=50）
↓
WalkZone 配额：未覆盖的 zone 配额=0，无 NPC
↓
结果：玩家移动到任何新区域，巡逻路线都是空的
```

**根本架构冲突**：巡逻路线（20条，静态世界位置）vs. NPC 生成器（动态跟随玩家）。两者目标不一致：
- 巡逻路线系统假设"特定路线上持续有 NPC"
- Spawner 系统假设"NPC 跟随玩家，保证玩家周围有人"

## 修复方案

### 代码修复

**方案：在场景初始化时预生成全部巡逻路线 NPC（静态持久化）**

在 `scene_impl.go` 的 BigWorld 初始化块中，在 Spawner 创建完成后，增加一个"巡逻路线预生成"阶段：

1. **新增 `BigWorldNpcSpawner.PreSpawnPatrolRoutes()` 方法**：
   - 遍历所有已注入的 `patrolMgr.AllRouteIds()`
   - 对每条路线，按 `desiredNpcCount` 数量，在路线节点上生成 NPC
   - 生成的 NPC 打上 `staticPatrol=true` 标记，不纳入 AOI 动态回收逻辑（不进入 `activeNpcs` 的 despawn 判断）

2. **修改 `doDespawn()` 豁免静态巡逻 NPC**：
   - `doDespawn` 中检查 `staticPatrol` 标记，豁免这批 NPC 的距离回收

3. **修改配额计算豁免静态 NPC**：
   - `zoneNpcCount` 中静态 NPC 不计入动态配额（或提高 totalNpcBudget 到 90 以容纳 40 静态 + 50 动态）

4. **`scene_impl.go` 调用点**：
```go
// 在 spawner.SetPatrolMgr(bigWorldPatrolMgr) 之后调用
if bigWorldPatrolMgr != nil {
    spawner.PreSpawnPatrolRoutes()
}
```

**最小改动替代方案（配置调整）**：
- 将 `npc_zone_quota.json` 的 `totalNpcBudget` 改为 200
- 将各 zone 的 `maxNpc` 提高（如各 40）
- 将 `DefaultBigWorldSpawnConfig.SpawnRadius` 改为覆盖整个大世界（约 6000m）
- **代价**：服务器需要维护 200 个 NPC 实体，性能开销大，不推荐

**推荐方案**：方案1（静态预生成）。20 条路线 × 2 = 40 个静态 NPC，固定开销可控，巡逻路线全时可见。

### 工作流优化建议

- **问题**：auto-work 的 feature/plan 阶段只关注当前 task 文档描述的范围，对"产品应有但未明说的背景假设"无感知
- **建议**：在 feature.json 生成阶段，增加一个"已知约束检查"步骤——当 feature 是"对齐成熟功能"类型时，检查目标系统的基础设施（此处为 Spawner）是否满足目标场景（200+ NPC 全局可见）的前提
- **改哪里**：`skills/feature/plan-creator.md` 的 Plan 创建 prompt 中增加："若 feature 依赖已有服务端基础设施，需显式验证该基础设施是否满足产品期望的规模/密度/覆盖范围"
