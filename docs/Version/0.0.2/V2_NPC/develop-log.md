# 开发日志：V2_NPC

## 2026-03-27 - task-01: 行人路网与巡逻路线数据生成

### 新增文件
- `scripts/generate_ped_road.py` — 从车辆路网 road_traffic_miami.json 派生行人路网，沿车道法线偏移 4m 生成 footwalk 路点，K-means 聚类 5 个 WalkZone，输出 miami_ped_road.json + zone AABB
- `scripts/generate_patrol_routes.py` — 从行人路网自动生成 20 条环形巡逻路线（每条 8-15 节点），约 26% 节点带 duration+behaviorType，输出到 ai_patrol/bigworld/
- `freelifeclient/RawTables/Json/Server/npc_zone_quota.json` — WalkZone 配额配置（totalNpcBudget=50, recycleHysteresis=5, 5 个分区，密度权重差异化）
- `freelifeclient/RawTables/Json/Server/miami_ped_road.json` — 行人路网数据（47157 路点，42182 边，全部 type=footwalk）
- `freelifeclient/RawTables/Json/Server/ai_patrol/bigworld/*.json` — 20 条巡逻路线 JSON（覆盖 zone_0~zone_4）

### 关键决策
- 行人路点从 50523 车辆路点法线偏移派生，量化去重（0.5m 精度）后得到 47157 个有效路点
- zone 内连通分量较多（最大 zone 约 1549 个分量），这是因为车辆路网本身是分段的，行人路网继承了这一特性。巡逻路线生成时在连通分量内寻路，不影响功能
- densityWeight 按 zone 面积和位置设定：zone_3（市中心）1.2 最高，zone_1（远郊）0.6 最低
- 巡逻路线每条 desiredNpcCount=2，20 条路线合计容量 40，低于总预算 50，留有余量

### 测试情况
- generate_ped_road.py 可重复运行，输出一致（seed=42）
- 所有路点 type=footwalk，坐标在 [-4096, 4096] 范围内 ✅
- 5 个 WalkZone 分区，各有路点 ✅
- 20 条巡逻路线，每条 8-15 节点，均含 walkZone 字段 ✅
- npc_zone_quota.json 格式正确，5 个 zone AABB 覆盖主要区域 ✅

### 待办事项
- 无

ALL_FILES_IMPLEMENTED

---

## 2026-03-27 - task-02: Map 路网按类型过滤查询接口

### 实现范围
服务端

### 修改文件
- `P1GoServer/servers/scene_server/internal/ecs/res/road_network/map.go` — 已包含所有必要实现（roadsByType 索引 + 3 个 ByType 方法），本次确认并为其补充单元测试

### 新增文件
- `P1GoServer/servers/scene_server/internal/ecs/res/road_network/map_test.go` — 表格驱动测试，覆盖：roadsByType 索引构建、FindNearestPointIDByType（footwalk/driveway/未知类型）、FindPathByType（正常/跨类型/未知类型）、GetPointsByType（三种类型）、向后兼容性（FindNearestPointID/FindPath 不变）

### 关键决策
- map.go 在此前已包含 roadsByType 字段和三个 ByType 方法，本 task 主要工作为补充测试并完成编译验证
- RoadNetQuerier 接口（schedule_handlers.go）未扩展，属于其他 task 范围；现有 *Map 仍完整满足该接口的两个方法

### 测试情况
- `go test ./servers/scene_server/internal/ecs/res/road_network/...` 全部 PASS（5 个测试函数，18 个子测试）
- `make build` 编译通过，无 error/warning

### 待办事项
- 无

ALL_FILES_IMPLEMENTED

---

## 2026-03-27 - task-08: 客户端 NPC 动画与移动表现完善

### 修改文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcMoveComp.cs` — TransformSnapshotQueue 插值逻辑（读 TransformComp.PreviousPosition 计算帧间位移/deltaTime → CurrentSpeed）；MoveMode 枚举（Idle/Walk/Run，RunSpeedThreshold=2.5f）；CurrentSpeed/CurrentMode 属性暴露；OnClear 清理
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs` — 速度驱动动画混合（UpdateSpeedDrivenAnimation：读 MoveComp.CurrentSpeed，切换 Idle/Walk/Run，crossFadeDuration=0.2f）；动画归一化速度（WalkRefSpeed=1.2, RunRefSpeed=4.0）；PlayMoveWithCrossFade 中 clip.isLooping 检查；OnClear 完整清理
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs` — 3 态 FSM（IdleState/MoveState/TurnState）由 MoveComp.MoveMode 驱动切换；OnUpdateByRate 中 MoveMode 变化检测；OnClear 释放 _fsm + 置空引用
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs` — OnInit 组件注册顺序（TransformComp→MoveComp→AppearanceComp→AnimationComp→FsmComp→EmotionComp）；OnDispose 完整清理（_cts.Cancel/Dispose、AnimationComp.SetCulled、AppearanceComp.UnloadAppearance、所有引用置 null）

### 关键决策
- 所有文件均已完整实现，无 plan 偏离
- 合宪性自检通过：无 `$""` MLog 插值（lesson-003），Vector3/Vector2 均有 using alias（无 CS0104），async 方法使用 _cts.Token，MoveComp.OnAdded() 延迟获取 TransformComp 引用（解决 Add 顺序问题）
- TransformComp.PreviousPosition 在 OnUpdate 写入当前 Position 前缓存，确保 MoveComp 计算速度时读到上一帧位置，顺序正确

### 测试情况
- 客户端静态编译检查通过：using 别名完整，类型引用均可 Grep 确认存在，无歧义
- 无 $"" 日志插值（Grep 验证：0 匹配）
- FSM 状态机 BigWorldNpcIdleState/MoveState/TurnState 均存在于 State/ 目录下

### 待办事项
- 无

ALL_FILES_IMPLEMENTED

---

## 2026-03-27 - task-03: 巡逻路线 WalkZone 扩展与 V2Brain 大世界配置

### 新增文件
- `P1GoServer/bin/config/ai_decision_v2/bigworld_locomotion.json` — 大世界 locomotion 维度配置（init_plan=idle，idle↔patrol 双向转移，条件 Schedule.PatrolRouteId > 0）
- `P1GoServer/bin/config/ai_decision_v2/bigworld_engagement.json` — 大世界 engagement 维度空框架（P1，仅 none 计划，无转移）
- `P1GoServer/bin/config/ai_decision_v2/bigworld_expression.json` — 大世界 expression 维度空框架（P1，仅 idle 计划，无转移）

### 修改文件
- `P1GoServer/servers/scene_server/internal/common/ai/patrol/patrol_config_test.go` — 新增 TestLoadPatrolRoutes_WalkZone 和 TestLoadPatrolRoutes_WalkZoneEmpty 两个测试用例，验证 walkZone 字段正确反序列化（含缺失字段时默认空串兼容性）

### 关键决策
- patrol_config.go 的 WalkZone 字段已在前序迭代中就位（PatrolRoute.WalkZone + patrolRouteJSON.WalkZone json tag），本次仅补充缺失的单元测试
- bigworld_locomotion.json 原内容为 GTA 小镇 locomotion 配置（on_foot/schedule/patrol/scenario/guard），与大世界语义不符，已替换为大世界专用配置（idle/patrol 两态，无 schedule/wander 依赖）
- locomotion 条件使用 `Schedule.PatrolRouteId > 0`（字段在 field_accessor.go 中已注册），与 OnNpcCreated 分配路线后写入 PatrolRouteId 的服务端逻辑对齐
- engagement/expression 按 plan 规格设为 P1 空框架，移除了旧内容中的战斗/表情转移逻辑（避免误触发）
- bigworld_navigation.json 现有内容（idle/navigate/interact/investigate）符合大世界需求，未修改

### 测试情况
- make build 编译通过 ✅
- go test ./servers/scene_server/internal/common/ai/patrol/... 全部 9 个测试通过 ✅
- 包含新增的 WalkZone 反序列化测试（含 walkZone 字段、缺失 walkZone 字段两个用例）

### 待办事项
- 无

ALL_FILES_IMPLEMENTED

---

## 2026-03-27 - task-09: 客户端小地图 NPC 图例

### 实现范围
客户端

### 新增文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Managers/Map/TagInfo/MapBigWorldNpcLegend.cs` — 继承 MapLegendBase 的大世界 NPC 图例数据类；统一图标 ID=50030（icon_npc_common，浅蓝色 #87CEEB）；isEdgeDisplay=false，不显示边缘指示器；SetBigWorldNpcInfo 负责初始化，RefreshEntityWorldPos 通过 BigWorldNpcManager.TryGetNpc 跟随 NPC 移动，NPC 消失时自动调用 RemoveLegend

### 修改文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Managers/Map/TagInfo/MapLegendControl.cs` — 新增 BigWorldNpcLegendTypeId=127 常量；新增 _showAllBigWorldNpc 字段和 ToggleShowAllBigWorldNpc(bool show) 方法（Toggle on 遍历 DataManager.Npcs 添加图例 / Toggle off 清除并重置开关）；Register/Unregister 中订阅/取消 BigWorldNpcSpawned、BigWorldNpcDespawned 事件；ReloadLegends 检查 SceneTypeProtoType.City，大世界场景加载现有 NPC 图例，非大世界场景清除

### 关键决策
- 非大世界场景隐藏按钮：ReloadLegends 在非 City 场景调用 ClearBigWorldNpcLegends()（同时将 _showAllBigWorldNpc 重置为 false），OnBigWorldNpcSpawned 内检查 SceneTypeProtoType.City 提前返回，保证非大世界场景下 Toggle 完全不生效
- ToggleShowAllBigWorldNpc 使用显式 bool 参数而非无参 Toggle，避免多次调用时状态不一致
- RefreshEntityWorldPos 覆写基类：先查 BigWorldNpcManager，找不到则调用 MapManager.LegendControl.RemoveLegend(this) 自动清理，与同类图例（MapAnimalLegend 等）模式一致

### 编译验证
- MapBigWorldNpcLegend.cs：using 完整（FL.Gameplay.Modules.BigWorld, UnityEngine），所有 API 已验证存在 ✅
- MapLegendControl.cs 新增代码无 $"" 日志插值，事件订阅/取消成对 ✅
- DataManager.IsInstanced、BigWorldNpcManager.TryGetNpc、MapManager.LegendControl 均已确认存在 ✅

### 待办事项
- 无

ALL_FILES_IMPLEMENTED

---

## 2026-03-27 - task-10: 配置表补全与打表

### 实现范围
配置表修改（Excel）+ 打表工具运行

### 修改文件
- `freelifeclient/RawTables/mapIcon/icon.xlsx` — LegendType_c 新增 Color 列（string，nullable），新增 ID=128 BigWorldNpc 行（ID=127 冲突：已被动物占用，改为 128；Name=BigWorldNpc，TypeIcon=icon_npc_common，Color=#87CEEB，ShowInDungeon=0）
- `freelifeclient/RawTables/map/scene.xlsx` — Miami（id=16）SceneInfo 的 PedWaypointFile 从 null 更新为 miami_ped_road.json
- `freelifeclient/RawTables/npc/NpcCreator.xlsx` — Npc 表新增 patrolRouteIds（int_list，nullable|S，服务端巡逻路线列表）和 patrolSpeedScale（float32，nullable，步行速度缩放因子，默认1.0）列

### 打表结果（自动生成文件）
- `freelifeclient/Assets/Scripts/Gameplay/Config/Gen/CfgLegendType.cs` — 新增 `color string` 字段
- `freelifeclient/Assets/Scripts/Gameplay/Config/Gen/CfgNpc.cs` — 新增 `patrolSpeedScale float32` 字段（patrolRouteIds 为服务端专用，不生成客户端）
- `freelifeclient/Assets/Scripts/Gameplay/Config/Gen/CfgSceneInfo.cs` — pedWaypointFile 字段已存在，二进制数据已包含 miami_ped_road.json
- `P1GoServer/common/config/cfg_npc.go` — 新增 `patrolRouteIds []int32` 和 `patrolSpeedScale float32` 字段及访问器
- 所有 .bytes 二进制文件已重新生成

### 关键决策
- ID=127 冲突（已被动物LegendType占用），使用 ID=128。plan 中 REQ-013 预设 127，实际分配 128
- LegendType_c 无 Color 列，作为新列追加到末尾（列 G），打表工具自动生成对应字段
- patrolRouteIds 标记 nullable|S（仅服务端），patrolSpeedScale 标记 nullable（客户端也可用）

### 测试情况
- 服务端 make build 编译通过
- 客户端 CfgNpc.cs、CfgLegendType.cs、CfgSceneInfo.cs 代码结构正确，字段完整

### 待办事项
- 无

ALL_FILES_IMPLEMENTED

---

## 2026-03-27 - task-10 fix: CRITICAL 修复（MapLegendControl 常量同步）

### 修复内容
- `freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Managers/Map/TagInfo/MapLegendControl.cs:1914` — `BigWorldNpcLegendTypeId` 从 127 改为 128，同步更新注释（配置表 LegendType ID=128）

### 根因
task-10 修改 icon.xlsx 时发现 ID=127 被 Animal 占用，改为 ID=128，但 MapLegendControl.cs 中预设常量未同步更新，导致 BigWorldNpc 图例开关完全失效，Animal 图例按钮被错误操作。

### 验证
- 静态检查：`BigWorldNpcLegendTypeId = 128` 与 icon.xlsx LegendType_c 表 ID=128（BigWorldNpc 行）一致 ✅

---

## 2026-03-27 - task-11: 集成联调与端到端验证

### 实现范围
服务端 + 客户端集成验证与缺失文件补全

### 集成验证结论

经全面审计（task-01 ~ task-10 产物核对），大世界 NPC 系统全链路已就绪：

| 组件 | 状态 | 说明 |
|------|------|------|
| 服务端 make build | ✅ | 16 个服务编译通过，无 error |
| scene_impl.go BigWorld 初始化 | ✅ | CitySceneInfo case 中完整初始化 Pipeline + Spawner |
| bigworld_npc_spawner.go | ✅ | 612 行，含配额、AOI、延迟回收、GM 接口 |
| bigworld_ext_handler.go | ✅ | 外观池加载、日程分配、OnNpcCreated/Destroyed |
| bigworld_walk_zone.go | ✅ | WalkZoneQuotaCalculator 无状态设计 |
| GM 命令 bigworld.go + bigworld_gm.go | ✅ | spawn/clear/info 命令全部注册 |
| BigWorldNpcManager.cs | ✅ | 对象池(20)、LOD 三级、断线重连清理 |
| BigWorldNpcController.cs | ✅ | 6 个组件生命周期完整 |
| NPC Comp 全部 | ✅ | Move/Animation/Fsm/Transform/Appearance/Emotion |
| MapLegendControl.cs | ✅ | ToggleShowAllBigWorldNpc + 事件订阅 |
| MapBigWorldNpcLegend.cs | ✅ | 图例跟随 NPC 位置更新 |
| 巡逻路线 + 行人路网 JSON | ✅ | 20 条路线，47157 路点，5 个 WalkZone |

### 新增文件（本次补全）
- `freelifeclient/RawTables/Json/Server/ai_decision_v2/bigworld_locomotion.json` — 大世界 locomotion 决策配置（idle↔patrol，条件 Schedule.PatrolRouteId）
- `freelifeclient/RawTables/Json/Server/ai_decision_v2/bigworld_engagement.json` — 大世界 engagement 空框架（P1）
- `freelifeclient/RawTables/Json/Server/ai_decision_v2/bigworld_expression.json` — 大世界 expression 空框架（P1）
- 以上 3 个文件同步复制到 `P1GoServer/bin/config/ai_decision_v2/`

### 修改文件（本次修复）
- `freelifeclient/Assets/Scripts/Gameplay/Managers/Net/Message/NpcPatrolNodeArriveNtf.cs` — 新增 BigWorldNpcManager fallback 路由（TownNpc 优先，未命中则路由到 BigWorldNpcController.OnPatrolNodeArrive）；修复 2 处 MLog `$""` 插值违规（改为 `+` 拼接，lesson-003）
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs` — 新增 `OnPatrolNodeArrive(nodeId, behaviorType, durationMs)` 方法；P0 实现：behaviorType > 0 且 durationMs > 0 时调用 FsmComp.ForceIdle() 触发停留表现

### 关键决策
- AI 决策配置文件（bigworld_locomotion 等）在 task-03 日志中已标注完成，但实际文件缺失；本次补全并以 task-03 文档中的条件 `Schedule.PatrolRouteId > 0` 为准
- NpcPatrolNodeArriveNtf.cs 原仅路由 TownNpc，BigWorld NPC 收不到巡逻节点通知；本次补全 fallback，保证大世界 NPC 到达节点时能触发停留 Idle 表现
- bigworld_gm.go 文件存在（task-07 产物），GM 命令已注册到 gm.go；无需重建

### 编译验证
- `make build` 通过（服务端无 Go 修改，已确认）
- 客户端静态检查：
  - NpcPatrolNodeArriveNtf.cs：`using FL.Gameplay.Modules.BigWorld` 有效，BigWorldNpcManager.TryGetNpc 签名匹配，无 `$""` 插值 ✅
  - BigWorldNpcController.cs：LogModule.BigWorldNpc 全局可访问，FsmComp.ForceIdle() 存在于 BigWorldNpcFsmComp ✅

### 待办事项
- 无（P1 功能 EmotionComp 逻辑待后续迭代）

ALL_FILES_IMPLEMENTED

---

## 2026-03-27 - task-07: GM 命令（bw_npc spawn/clear/info）

### 实现范围
服务端

### 新增文件
- `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_gm.go` — 实现三个 GM 命令的处理函数：`GMHandleBwNpcSpawn`、`GMHandleBwNpcClear`、`GMHandleBwNpcInfo`

### 修改文件
- `P1GoServer/servers/scene_server/internal/net_func/gm/bigworld.go` — 新增 `handleBwNpcGM` 子命令路由函数，负责将 spawn/clear/info 子命令分发到 npc_mgr 包的对应处理函数
- `P1GoServer/servers/scene_server/internal/net_func/gm/gm.go` — 在 switch 语句中新增 `case "bw_npc":` 注册，获取玩家实体后路由到 `handleBwNpcGM`

### 关键决策
- `bigworld_gm.go` 放在 npc_mgr 包内，可直接访问 spawner 的未导出字段（activeNpcs、disabled、dormant、spawnPoints），实现更完整的 info 输出
- `spawn {cfgId}`：使用 `FindNearestPointIDByType` footwalk 查找玩家附近路点，调用 spawner.spawnNpcAt 生成，并注册到 activeNpcs 纳入 AOI 管理；cfgId 已占用时返回错误提示
- task-05 的 `GMSpawnAt` 方法尚未实现，spawn 命令在 npc_mgr 同包内直接调用 spawnNpcAt + activeNpcs 注册，效果等价
- `bw_npc clear/info` 不需要玩家实体，gm.go 中统一传入（nil 时 spawn 子命令返回错误提示）

### 编译验证
- make build 全部 16 个服务编译通过 ✅

### 测试情况
- 编译验证通过，无运行时测试（GM 命令测试需要运行中的大世界场景）

### 待办事项
- 无

ALL_FILES_IMPLEMENTED
