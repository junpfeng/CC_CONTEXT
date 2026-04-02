---
name: BigWorldNpcSpawner 改造（footwalk + 配额 + 巡逻路线生成）
status: completed
---

## 范围
- 修改: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_spawner.go — initSpawnPoints 改为从 footwalk 子路网获取候选点（调用 Map.GetPointsByType 替换 GetAllPointPositions）；新增 walkZoneConfig/patrolMgr/zoneNpcCount/quotaTimer 字段；新增 TickQuota 方法（每 5s 调用 WalkZoneQuotaCalculator 计算配额）；spawnOne 改为从 PatrolRouteManager 选负载最低路线的节点作为生成位置；新增 GMSpawnAt 方法供 GM 调用

## 验证标准
- 服务端 make build 编译通过
- initSpawnPoints 仅使用 footwalk 类型路点
- TickQuota 正确驱动生成/回收决策
- spawnOne 从巡逻路线节点生成 NPC
- 每帧生成数不超过 SpawnBatchSize
- NPC 总数不超过 MaxCount 上限
- 不影响小镇/樱花场景的 Spawner 逻辑

## 依赖
- 依赖 task-02（Map 路网按类型查询接口）
- 依赖 task-03（PatrolRoute WalkZone 字段）
- 依赖 task-04（WalkZone 配额计算器）
