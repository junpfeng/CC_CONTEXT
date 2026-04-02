# V2_NPC 已修复 bug

## 2026-03-30（Bug #5: MonsterStandState NullRef 导致 NPC 无限累积）
- [x] 大世界NPC持续累积不回收（10125个），FPS=2.6，MonsterStandState NullRef导致模型不完整
  - **根因**：MonsterStandState/DeadState/GroundState/ShiverState 的 OnInit() 中 ConfigLoader.NpcMap.TryGetValue(NpcCreatorId=0) 失败时 _subStateMachine 保持 null → OnEnter() NullRef → SpawnNpc catch 回池但 GO 未正确清理 → _monsterList 丢失引用 → 每帧重新 SpawnNpc 形成无限 spawn-fail-pool 循环 → 12000+ 活跃 GO 累积
  - **修复**：4 个 MonsterState 文件统一：无论配置查找成功否都创建默认 HumanXxxSubStateMachineComp + 所有 _subStateMachine 调用加 ?. 防御
  - **验证**：Active Monsters 12348→47, FPS 2.0→30.2, Memory 6588→2957MB, NullRef 错误消除

## 2026-03-30（此前修复）
- [x] 大世界 NPC 满街原地踏步 + 密密麻麻（客户端幽灵 controller 累积）
  - **现象**：客户端 BigWorldNpcController 从 ~50 膨胀到 8K+（60分钟内），全部 speed=0，全在 MoveState 播放行走动画但位置不变，视觉上"满街密密麻麻但不移动"
  - **根因**：`SceneNpcMgr.DestroyNpc()` 清理 NpcState 和管线状态后调用 `RemoveNpc(cfgId)` 删除内部映射，但**从未调用 `scene.RemoveEntity(entity.ID())`**。缺失此调用导致：GridManager 不知道实体已删除 → `net_update/update.go` 的 `GetRemoveEntityByGrid()` 永远不返回该实体 → 客户端 frame sync 的 `RemoveEntity` 列表永远不含该 ID → `DataManager.Npcs` 不删除 → `BigWorldNpcManager.SyncWithDataManager()` 检测不到移除 → 客户端 controller 永久驻留，随服务端 spawn/despawn 循环（~3/s）线性积累
  - **修复**：`P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/scene_npc_mgr.go`：`DestroyNpc()` 中在 `m.RemoveNpc(cfgId)` 前新增 `scene.RemoveEntity(info.Entity.ID())` 调用，触发 GridManager 将实体 ID 加入下帧的 RemoveEntity 广播列表
  - **验证**：修复后重启服务器并重新登录，客户端 BigWorldNpcController 数量稳定在 43-50（匹配服务端 MaxCount=50），NPCs 均在 MoveState 且位置帧间差 0.2-0.7m（正常行走速度）

## 2026-03-29（本次）
- [x] 大世界 NPC 半截插入地面
  - **根因**：`spawnNpcAt` 直接使用路网节点 Y 坐标（路网 Y 系统性偏低），`MoveEntityViaRoadNet` 的中间路径节点 NavMesh Y 修正因大世界 NavMesh 未加载而静默失效
  - **修复**：
    - `P1GoServer/servers/scene_server/cmd/initialize.go`：`preloadNavMeshes` 新增 `WorldNavBake_20241218.bin` 预加载（key="bigworld"），修复中间路径节点 Y 修正
    - `P1GoServer/servers/scene_server/internal/common/scene_type.go`：`CitySceneInfo.GetNpcAIConfig()` 增加 `NavMeshName: "bigworld"`，使场景初始化时正确加载大世界 NavMesh
    - `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_spawner.go`：`spawnNpcAt` 调用 `NavMeshMgr.FindPath` 投影 spawn 点到 NavMesh 地表，修正 spawn Y
- [x] 大世界 NPC 移动卡顿（视觉抖动）
  - **根因**：服务端 `bwSpeedWalk=1.4` 与客户端 `WalkRefSpeed=1.2` 不一致，动画归一化速度偏高 14%；大世界 NavMesh 未加载导致路径中间节点 Y 从路网直接取值（精度不足），每帧 Y 跳变
  - **修复**：
    - `P1GoServer/servers/scene_server/internal/common/ai/execution/handlers/bigworld_locomotion_handler.go`：`bwSpeedWalk` 从 1.4 改为 1.2，与客户端 `WalkRefSpeed` 对齐
    - 大世界 NavMesh 加载修复（同上）消除路径节点 Y 跳变

## 2026-03-29
- [x] 大世界 NPC 走路动画原地踏步（部分 NPC 同时插地）
  - **根因**：路网路径节点 Y 偏低，NPC 实际在地表以下移动；客户端 `InitFromSnapshot()` 直接使用服务端坐标未做地面 Raycast 修正；`AnimationComp` 和 `MoveState` 各自硬编码不同的 `WalkRefSpeed` 导致 animSpeed 双写不确定
  - **修复**：
    - `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcTransformComp.cs`：`InitFromSnapshot()` 从 Y=200 向下 Raycast Grounds 层修正 spawn Y（Fix 1）
    - `P1GoServer/.../bigworld_navigation_handler.go`：`correctTargetY` 从仅修正终点扩展到所有 A* 中间路径节点（Fix 2）
    - `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs`：`WalkRefSpeed` 统一为 1.4f，唯一写入 animSpeed（Fix 3）
    - `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcMoveState.cs`：`WalkRefSpeed` 统一为 1.4f，删除 `OnUpdate` 中冗余的 `SetSpeed` 调用（Fix 3）
- [x] 大世界部分 NPC 插入地面无法动弹
  - **根因**：`BigWorldNpcTransformComp.InitFromSnapshot()` 直接将服务端路网坐标写入 Transform，未做地面 Raycast Y 修正；路网节点 Y 由离线工具生成精度不足，系统性偏低
  - **修复**：`freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcTransformComp.cs`：`InitFromSnapshot()` 中从 Y=200 向下 Raycast Grounds 层修正 spawn Y 坐标

## 2026-03-29
- [x] 大世界 NPC 坐标仍然不变（Fix A/B/C 后持续）
  - **根因**：`TargetPos` 字段在正交管线中被 locomotion（patrol 读为当前位置）和 navigation（navCheckArrival 每帧覆写为 MoveTarget）两个维度赋予不同语义，导致到达判断 distSq 恒为 0，每帧换目标并重置 StartMove 时间戳，NpcMoveSystem 零 delta 保护触发，坐标永不更新
  - **修复**：
    - `P1GoServer/servers/scene_server/internal/ecs/res/handlers/bigworld_default_patrol.go`：OnTick 到达判断改用 `distanceSqToTarget` 读实体真实坐标，消除对被 navCheckArrival 覆写的 `TargetPos` 字段的读依赖（Fix C）
- [x] 大世界 NPC 没有移动（坐标从不更新）
  - **根因**：`TargetPos` 字段被 locomotion 和 navigation 两个正交维度赋予不同语义（patrol 读为当前位置，navCheckArrival 每帧覆写为 MoveTarget），导致 distSq 恒为 0 → 每帧换目标 → 每帧重置 StartMove 时间戳 → NpcMoveSystem 零 delta 保护 → 坐标永不更新
  - **修复**：
    - `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/v2_pipeline_defaults.go`：`bigworldDimensionConfigs()` locomotion 维度注册 `idle` → `BigWorldDefaultPatrolHandler`（Fix A）
    - `P1GoServer/bin/config/ai_decision_v2/bigworld_navigation.json`：新建，init_plan=navigate，打通 navigation 维度初始化（Fix B）
    - `P1GoServer/servers/scene_server/internal/ecs/res/handlers/bigworld_default_patrol.go`：OnTick 到达判断改用 `distanceSqToTarget` 读实体真实坐标，消除对被 navCheckArrival 覆写的 `TargetPos` 字段的读依赖（Fix C）
- [x] NPC 坐标不变，未发生移动
  - **根因**：`BigWorldDefaultPatrolHandler` 已实现但从未在 `bigworldDimensionConfigs()` 中注册，导致 init_plan="idle" 的 locomotion 维度 OnTick 无任何操作（IsMoving 始终 false）；同时 `bigworld_navigation.json` 文件缺失，navigation 维度被 setupOrthogonalPipeline 静默跳过
  - **修复**：
    - `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/v2_pipeline_defaults.go`：`bigworldDimensionConfigs()` 展开为独立实现，locomotion 维度新增 `idle` → `BigWorldDefaultPatrolHandler` 注册
    - `P1GoServer/bin/config/ai_decision_v2/bigworld_navigation.json`：新建，init_plan=navigate，打通 navigation 维度初始化

## 2026-03-28
- [x] NPC 分布密度低，巡逻路线不全局持久化
  - **根因**：TurnState 被服务端同状态重推无条件打断，叠加转身检测未排除 ScenarioState/ScheduleIdleState，导致 NPC 永久振荡无法完成转身，巡逻路径实际失效
  - **修复**：
    - `BigWorldNpcFsmComp.cs`：OnUpdateMonsterState 增加 TurnState 保护（当前处于 TurnState 时仅新状态≠前序状态时才中断）
    - `BigWorldNpcFsmComp.cs`：OnUpdateByRate 转身检测补充 `!(CurrentState is BigWorldNpcScenarioState)` 和 `!(CurrentState is BigWorldNpcScheduleIdleState)` 排除条件
    - `BigWorldNpcController.cs`：OnInit 在 FsmComp 就绪后主动应用初始 ServerAnimStateData

## 2026-03-28
- [x] 看不到正常巡逻的 NPC
  - **根因**：TurnState 被服务端同状态重推无条件打断（OnUpdateMonsterState 缺少 TurnState 保护），叠加转身检测未排除 ScenarioState/ScheduleIdleState，导致 NPC 转向永久振荡；初始化时仅注册 DataSignal 监听未消费快照，首次登录 NPC 状态不同步
  - **修复**：
    - `BigWorldNpcFsmComp.cs`：OnUpdateMonsterState 增加 TurnState 保护（当前处于 TurnState 时，仅在新状态 ≠ 前序状态时才中断转身）
    - `BigWorldNpcFsmComp.cs`：OnUpdateByRate 转身检测补充 `!(CurrentState is BigWorldNpcScenarioState)` 和 `!(CurrentState is BigWorldNpcScheduleIdleState)` 排除条件
    - `BigWorldNpcController.cs`：OnInit 在 FsmComp 就绪后主动应用初始 ServerAnimStateData（补 InitData 路径不触发 DataSignal 的遗漏）
