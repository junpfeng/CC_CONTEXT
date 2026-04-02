# Design Reviewer Memory

## 项目审查记录
- [project_schedule_system_review.md](project_schedule_system_review.md) - NPC 日程系统技术设计审查（2026-03-13），关键问题：CurrentPlan 路由一帧延迟、FieldAccessor 字段未注册
- [project_schedule_moveto_review.md](project_schedule_moveto_review.md) - MoveTo 两段式移动设计审查（2026-03-18），关键问题：ScenarioPhase 复用残留值风险、GetPointPos 坐标单位
- [project_town_vehicle_client_drive_review.md](project_town_vehicle_client_drive_review.md) - Town 交通车辆客户端驱动设计审查（2026-03-20），核心问题：未基于已有 TownTrafficMover 实现，架构不一致
- [project_big_world_traffic_review.md](project_big_world_traffic_review.md) - 大世界交通系统GTA5复刻设计审查（2026-03-22），关键问题：协议文档与proto不一致、信号灯缺初始同步、无灯路口死锁、服务端无路网空间查询
- [project_animal_system_review.md](project_animal_system_review.md) - 动物系统技术设计审查（2026-03-23），严重问题：BtTickSystem单管线无法路由Animal/NPC共存、客户端模块路径矛盾
- [project_npc_v2_bigworld_review.md](project_npc_v2_bigworld_review.md) - NPC V2 大世界迁移设计审查（2026-03-25），严重问题：NpcV2Info缺朝向字段、缺LOD性能设计、DataManager分流缺服务端约束
- [project_vehicle_driving_review.md](project_vehicle_driving_review.md) - 玩家自由驾驶车辆设计审查（2026-03-30），CRITICAL：征用非原子竞态、10秒自动消失冲突；HIGH：控制权切换链路不明
- [project_animal_system_phase2_design.md](project_animal_system_phase2_design.md) - GTA5动物系统Phase1设计审查（2026-03-31），CRITICAL：syncAnimalStateChange缺Flee/Attack、perception plan互斥；FieldAccessor遗漏第3次
- [project_summon_wheel_review.md](project_summon_wheel_review.md) - 召唤轮盘UI设计审查（2026-03-31），HIGH：缺InputMode/光标管理；MEDIUM：PanelEnum路径错误
- [project_vehicle_gta5_review.md](project_vehicle_gta5_review.md) - 载具GTA5级提升设计审查（2026-04-01），CRITICAL：损伤上报链路不存在、VehicleDataUpdate缺损伤快照字段
- [project_parallel_workspace_review.md](project_parallel_workspace_review.md) - 多窗口并行隔离方案v1-v5审查（2026-04-01），v5通过0C/0H/3M可进入实现
- [project_weapon_system_review.md](project_weapon_system_review.md) - 武器系统设计审查（2026-04-02），CRITICAL：禁枪区服务端无实现基础；HIGH：DrawWeaponReq缺广播
