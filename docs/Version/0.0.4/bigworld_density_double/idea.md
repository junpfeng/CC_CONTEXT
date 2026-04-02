# 大世界 NPC 与车辆分布密度翻倍

## 核心需求
大世界的NPC和车辆的分布密度再增加一倍。

## 调研上下文

### NPC 密度控制（服务端 JSON 配置驱动）

**主配置文件**: `P1GoServer/bin/config/bigworld_npc/bigworld_npc_spawn.json`
（源文件: `freelifeclient/RawTables/_tool/config/server/bigworld_npc/bigworld_npc_spawn.json`）

当前值：
- `max_count`: 50（全局最大 NPC 数）
- `spawn_density`: 5.0（密度乘数）
- `spawn_radius`: 200m（玩家 AOI 生成半径）
- `despawn_radius`: 300m（消失半径）
- `spawn_batch_size`: 3（每 tick 生成数）

**WalkZone 配额系统**: `P1GoServer/bin/config/npc_zone_quota.json`
（源文件: `freelifeclient/RawTables/Json/Server/npc_zone_quota.json`）

当前值（总预算 50，回收滞后 5）：
- zone_0: density_weight=1.0, max_npc=12
- zone_1: density_weight=0.6, max_npc=8
- zone_2: density_weight=0.8, max_npc=10
- zone_3: density_weight=1.2, max_npc=12
- zone_4: density_weight=1.0, max_npc=10

**服务端核心代码**:
- `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_spawner.go`
- `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_config.go`

### 车辆/交通密度控制

**设计文档**: `docs/design/ai/big_world_traffic/density-spawn.md`

当前值：
- AOI 内可见车辆: ~15 辆
- 场景总最大车辆: 50 辆
- 生成半径: 150-250m（屏幕外）
- 消失半径: 300m
- 生成频率: 每 2 秒最多 2 辆
- 清理频率: 每 5 秒
- 车辆间最小距离: 30m

**服务端核心代码**:
- `P1GoServer/servers/scene_server/internal/ecs/system/traffic_vehicle/traffic_vehicle_system.go`

**客户端**: DotsCity ECS 纯客户端渲染（服务端同步已废弃）

### 架构总结
- NPC: 全部服务端控制，JSON 配置驱动，改配置 + 少量代码即可
- 车辆: 服务端控制生成，客户端 DotsCity 渲染，配置 + 代码双改

## 范围边界
- 做：将 NPC 和车辆的数量/密度参数翻倍
- 不做：不改生成逻辑算法、不改客户端渲染管线、不改协议

## 初步理解
核心是修改配置参数：NPC 的 max_count、zone quota、spawn_density 翻倍；车辆的最大数量、AOI 可见数、生成频率翻倍。可能需要调整 spawn_batch_size 以保证生成速率跟上。

## 待确认事项
已全部确认。

## 确认方案

方案摘要：大世界 NPC 与车辆密度翻倍

核心思路：将所有密度/数量相关的配置参数统一翻倍，不改算法、不改协议、不考虑性能。

### 锁定决策

**NPC 侧（服务端 JSON 配置修改）**：

`bigworld_npc_spawn.json`:
- `max_count`: 50 → 100
- `spawn_density`: 5.0 → 10.0
- `spawn_batch_size`: 3 → 6（生成速率跟上翻倍后的总量）
- `spawn_radius`: 200m（不变）
- `despawn_radius`: 300m（不变）
- `despawn_delay`: 3.0（不变）

`npc_zone_quota.json`:
- 总预算: 50 → 100
- zone_0: max_npc 12 → 24
- zone_1: max_npc 8 → 16
- zone_2: max_npc 10 → 20
- zone_3: max_npc 12 → 24
- zone_4: max_npc 10 → 20
- density_weight 各 zone 保持不变
- recycle_hysteresis: 5 → 10（等比放大）

**车辆侧（服务端代码/配置修改）**：
- 场景最大车辆: 50 → 100
- AOI 可见车辆: ~15 → ~30
- 生成频率: 每 2 秒最多 2 辆 → 每 2 秒最多 4 辆
- 车辆间最小距离: 30m（不变）
- 消失半径: 300m（不变）
- 清理频率: 5 秒（不变）

**不改动项**：
- 协议（零新增）
- 客户端渲染管线
- 生成/消失逻辑算法
- spawn/despawn 半径

### 待细化
- 车辆密度参数在代码中的精确位置（常量 or 配置表），由执行引擎定位

### 验收标准
- 服务端编译通过（make build）
- NPC 配置文件参数正确翻倍
- 车辆密度参数正确翻倍
- 登录大世界后 MCP 截图确认 NPC 和车辆数量明显增多
