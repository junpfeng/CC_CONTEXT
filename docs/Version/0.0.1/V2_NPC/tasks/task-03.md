---
name: Server ExtHandler + Spawner + Update System
status: completed
---

## 范围
- 新增: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_ext_handler.go — 大世界 NPC 扩展处理器。OnNpcCreated：注入感知插件（StateSensor/EventSensor/DistanceSensor/TrafficLightSensor）、加载 V2_BigWorld 日程配置（失败时 fallback 到 patrol + log.Errorf）、按权重随机分配外观 ID。OnNpcDestroyed：清理资源
- 新增: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_spawner.go — 大世界 NPC AOI 动态生成器。包含：初始化路网校验（disabled 状态）、多玩家配额分配（player_quotas + 轮询）、分帧 Spawn/Despawn（batch_size）、orphaned NPC 转移与延迟回收、dormant 休眠机制、密度控制与上限管理
- 新增: P1GoServer/servers/scene_server/internal/ecs/system/npc/bigworld_npc_update.go — 大世界 NPC 更新 System，在 ECS Tick 中驱动 Spawner.TickSpawn（每 500ms）和 Pipeline.Tick

## 验证标准
- `cd P1GoServer && make build` 编译通过
- Spawner 路网加载失败时 disabled=true，不 panic
- ExtHandler 不 import town_ext_handler 或 sakura 扩展处理器代码
- 多玩家配额计算正确（max_count / onlinePlayerCount）
- orphaned NPC 转移逻辑：玩家离开 → 标记 orphaned → 按距离转移给最近玩家 → 超额延迟 despawn

## 依赖
- 依赖 task-01（SceneNpcExt、Pipeline 工厂）
- 依赖 task-02（四维度 Handler 需已注册，ExtHandler 初始化 Pipeline 时引用）
