# V2 日程配置体系 — 变更清单

> 关联设计文档: [v2-schedule-config.md](v2-schedule-config.md)

## 代码修改（14 个）

路径省略 `P1GoServer/servers/scene_server/internal/`

| 文件 | 说明 |
|------|------|
| `common/ai/schedule/schedule_config.go` | ScheduleEntry 扩展（int64 秒级 + TargetPos/FaceDirection/PointId/BuildingId/DoorId/Duration），新增 Vec3Json |
| `common/ai/schedule/day_schedule_manager.go` | MatchEntry 参数 gameHour→gameSecond，matchTimeRange 改秒级，新增 FindTemplateIdByName |
| `common/ai/execution/plan_handler.go` | SceneAccessor 接口新增 SetEntityRoadNetPath 方法 |
| `common/ai/execution/handlers/schedule_handlers.go` | 新增 RoadNetQuerier 接口；ScheduleEntryResult 扩展 6 字段；ScheduleQuerier/ScenarioFinder 签名改秒级；MoveTo 集成路网寻路 + fallback |
| `common/ai/execution/handlers/schedule_handlers_test.go` | mock 签名同步 + 3 个路网集成测试 |
| `common/ai/execution/handlers/handlers_test.go` | mockScene 新增 SetEntityRoadNetPath stub |
| `common/ai/scenario/scenario_point_manager.go` | FindNearest/IsAvailable 改秒级 |
| `common/ai/scenario/spatial_grid_test.go` | 测试参数同步 |
| `ecs/system/decision/scene_accessor_adapter.go` | 实现 SetEntityRoadNetPath（获取 NpcMoveComp，设置路点列表 + 路网寻路模式） |
| `ecs/res/npc_mgr/locomotion_managers.go` | InitLocomotionManagers 新增第 4 参数 roadNetQuerier |
| `ecs/res/npc_mgr/v2_pipeline_defaults.go` | NewScheduleHandler 传入 roadNetQuerier |
| `ecs/res/npc_mgr/scene_npc_mgr.go` | 用 cfg.GetScheduleV2() 读 templateId，移除 V1 adapter 字段和方法 |
| `ecs/res/npc_mgr/scenario_adapter.go` | FindNearest 签名 gameHour→gameSecond |
| `ecs/scene/scene_impl.go` | V2 独立初始化（DayScheduleManager + V2ScheduleAdapter），从 Scene Resource 获取路网注入，移除 V1ScheduleAdapter 和 confignpcschedule import |

## 新建文件（28 个）

| 文件 | 说明 |
|------|------|
| `freelifeclient/RawTables/Json/Server/V2TownNpcSchedule/*.json`（24 个） | V2 日程模板源文件，从 V1 转换（秒级时间 + 路点 ID + 扁平结构），打表工具自动拷贝到 `P1GoServer/bin/config/V2TownNpcSchedule/` |
| `ecs/res/npc_mgr/v2_schedule_adapter.go` | DayScheduleManager → ScheduleQuerier 适配器，含 nil guard |
| `ecs/res/npc_mgr/v2_schedule_adapter_test.go` | 5 个测试（字段映射、nil 防御、委托查找） |
| `common/ai/schedule/day_schedule_manager_test.go` | 6 个测试（FindTemplateIdByName + 秒级时间边界） |

## 删除文件（1 个）

| 文件 | 说明 |
|------|------|
| `ecs/res/npc_mgr/v1_schedule_adapter.go` | V1→V2 桥接适配器，已被 v2_schedule_adapter.go 替代 |

## 自动生成（2 个）

| 文件 | 说明 |
|------|------|
| `P1GoServer/common/config/cfg_townnpc.go` | 打表生成，新增 scheduleV2 字段和 GetScheduleV2() int32 方法 |
| `P1GoServer/bin/config/cfg_townnpc.bytes` | 打表生成，含 24 行 scheduleV2 数据（templateId 1001-1024） |

## 配置表（1 个）

| 文件 | 说明 |
|------|------|
| `freelifeclient/RawTables/TownNpc/npc.xlsx` | TownNpc sheet M 列新增 ScheduleV2（int, S, "V2日程模板ID"），24 行数据已填入 |

## templateId 分配

| templateId | NPC | V1 Schedule 名 |
|------------|-----|----------------|
| 1001 | Austing | Austing_Schedule |
| 1002 | Benji | Benji_Schedule |
| 1003 | Beth | Beth_Schedule |
| 1004-1011 | Blackman~Blackman8 | Blackman_Schedule~Blackman8_Schedule |
| 1012 | Chloe | Chloe_Schedule |
| 1013 | Dan | Dan_Schedule |
| 1014 | Donna | Donna_Schedule |
| 1015 | Geraldine | Geraldine_Schedule |
| 1016 | Jessi | Jessi_Schedule |
| 1017 | Kathy | Kathy_Schedule |
| 1018 | Kyle | Kyle_Schedule |
| 1019 | Ludwing | Ludwing_Schedule |
| 1020 | Mick | Mick_Schedule |
| 1021 | Ming | Ming_Schedule |
| 1022 | Peggy | Peggy_Schedule |
| 1023 | Peter | Peter_Schedule |
| 1024 | Sam | Sam_Schedule |
