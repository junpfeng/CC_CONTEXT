---
name: GM 命令（bw_npc spawn/clear/info）
status: pending
---

## 范围
- 新增: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_gm.go — 实现三个 GM 命令：
  - `/ke* gm bw_npc spawn {cfgId}` — 校验 cfgId → FindNearestPointIDByType(footwalk) 查找玩家附近路点 → GMSpawnAt 生成 NPC
  - `/ke* gm bw_npc clear` — 清除所有大世界 NPC，返回清除数量
  - `/ke* gm bw_npc info` — 返回当前 NPC 数量、各 WalkZone 配额状态、巡逻路线占用情况
- 修改: GM 命令注册入口（需注册到已有 GM 框架中）

## 验证标准
- 服务端 make build 编译通过
- GM 命令注册到框架，可被 `/ke* gm` 路由
- spawn 命令 cfgId 无效时返回错误提示不崩溃
- spawn 生成的 NPC 纳入 AOI 管理
- info 命令返回完整的调试信息
- clear 命令正确清除并释放所有资源

## 依赖
- 依赖 task-05（BigWorldNpcSpawner.GMSpawnAt 方法）
- 依赖 task-06（scene_impl 初始化完成后 Spawner 可用）
