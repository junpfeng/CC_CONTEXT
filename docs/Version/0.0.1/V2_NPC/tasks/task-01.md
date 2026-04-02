---
name: Server Pipeline 注册与数据结构基础
status: completed
---

## 范围
- 修改: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/v2_pipeline_factory.go — 注册 BigWorld 场景类型的 V2Pipeline，添加 RegisterV2Pipeline(SceneType_BigWorld, ...) 调用
- 修改: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/v2_pipeline_defaults.go — 新增 BigWorld 默认维度配置（engagement/expression/locomotion/navigation 四维度参数）
- 新增: P1GoServer/servers/scene_server/internal/ecs/com/cnpc/bigworld_npc.go — BigWorldSceneNpcExt 实现 SceneNpcExt 接口，承载大世界 NPC 扩展数据（SpawnConfig、ScheduleState、AppearanceId 等）
- 修改: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/scene_npc_mgr.go — createExt 工厂方法添加 BigWorld 分支，根据 sceneType 创建 BigWorldSceneNpcExt

## 验证标准
- `cd P1GoServer && make build` 编译通过
- SetupV2Pipeline 传入 BigWorld sceneType 能正确创建 Pipeline 实例（可通过 GM 或单测验证）
- BigWorld 维度配置独立于 Town/Sakura/Animal，修改 BigWorld 配置不影响其他场景

## 依赖
- 无
