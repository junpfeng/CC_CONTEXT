---
name: BigWorldExtHandler 完善与 scene_impl 初始化接入
status: completed
---

## 范围
- 修改: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_ext_handler.go — OnNpcDestroyed 补充 patrolNpcCleaner.Clean 和 scenarioNpcCleaner.Clean 资源释放；OnNpcCreated 接入巡逻路线分配（从 NPC 配置读 patrolRouteIds → PatrolRouteManager.AssignNpc）；新增 patrolNpcCleaner/scenarioNpcCleaner 字段
- 修改: P1GoServer/servers/scene_server/internal/ecs/scene/scene_impl.go — BigWorld 初始化分支中创建 PatrolRouteManager 并加载 bigworld/ 路线；InitLocomotionManagers 的 patrolQuerier 参数从 nil 改为有效的 PatrolRouteManager；加载 npc_zone_quota.json 并注入 BigWorldNpcSpawner

## 验证标准
- 服务端 make build 编译通过
- scene_impl.go 大世界初始化时 patrolQuerier 不再为 nil
- BigWorldExtHandler.OnNpcDestroyed 正确释放巡逻路线和场景点占用
- BigWorldExtHandler.OnNpcCreated 正确分配巡逻路线
- 不影响小镇/樱花场景的初始化流程

## 依赖
- 依赖 task-02（Map 路网扩展，scene_impl 中路网初始化依赖）
- 依赖 task-03（PatrolRoute WalkZone 字段 + V2Brain 配置）
- 依赖 task-04（WalkZone 配额配置加载）
