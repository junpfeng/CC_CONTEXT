---
name: Server GM 命令 + JSON 配置文件
status: completed
---

## 范围
- 修改: P1GoServer 中 GM 命令注册文件 — 新增 4 个 GM 命令：
  - `/ke* gm bigworld_npc_spawn <count>` — 强制生成指定数量 NPC（忽略密度但受 max_count 约束）
  - `/ke* gm bigworld_npc_clear` — 清除所有大世界 NPC
  - `/ke* gm bigworld_npc_info <npcId>` — 查看单个 NPC 状态详情（Pipeline 维度、日程、位置、AOI 归属）
  - `/ke* gm bigworld_npc_schedule <npcId> <scheduleId>` — 强制切换 NPC 日程
  - `/ke* gm bigworld_npc_lod` — 输出 LOD 级别分布统计
- 新增: 大世界 NPC 生成配置 JSON（BigWorldNpcConfig：max_count=50, spawn_density, spawn_radius, despawn_radius, spawn_batch_size）
- 新增: 大世界 NPC 日程配置 JSON（V2_BigWorld 前缀，P0 仅 default_behavior=patrol）
- 新增: 大世界 NPC 外观配置 JSON（bigworld_npc_appearance.json，5-8 套固定外观组合 + 权重）

## 验证标准
- `cd P1GoServer && make build` 编译通过
- GM 命令均以 `/ke* gm` 前缀开头
- 配置文件走 JSON 加载，不 hardcode 在代码中
- 日程配置使用 V2_BigWorld 前缀，与小镇日程不冲突
- 配置文件加载失败有 log.Errorf，不静默忽略

## 依赖
- 依赖 task-03（GM 命令需调用 Spawner 和 ExtHandler 方法）
