# 错误模式库

> 由 `/dev-debug` skill 的 Phase 4 自动维护。每条模式记录一个已知的典型错误，便于后续调试时快速匹配。

## 格式说明

每条模式使用以下结构：

```
## [EP-XXX] 简短标题
- 症状：用户可观察到的现象或日志特征
- 模块：涉及的代码模块/服务
- 根因：导致问题的根本原因
- 解决：修复方案或规避方法
- 日期：首次记录日期 (YYYY-MM-DD)
```

---

<!-- 以下为实际错误模式条目，由 Phase 4 沉淀时追加 -->

## [EP-001] Redis 重连时 "too many colons in address"
- 症状：login server 报 `RedisCon is closed`，日志中出现 `too many colons in address`，服务器无法连接 Redis 导致登录/鉴权全线失败
- 模块：`pkg/gredis/redisConn.go` `resetNet()`
- 根因：`config.toml` 中 `redis_addr = "redis://127.0.0.1:6379"`，`conRedis()` 初始化时做了本地变量的前缀剥离但未回写，`redisCon.server` 保存了原始带 `redis://` 前缀的地址；重连时 `resetNet()` 直接 `net.Dial("tcp", c.server)` → "too many colons in address"
- 解决：在 `NewRedisCon()` 入口处 `svr = strings.TrimPrefix(svr, "redis://")` 统一剥离，确保 `redisCon.server` 存储裸地址
- 日期：2026-03-12

## [EP-002] Unity Play 模式代码变更时 PlayerControls Finalizer 崩溃
- 症状：`PlayerControls.Finalize()` 报 "Xxx.Disable() has not been called"，随后 `gptrarray.c:117` 断言失败崩溃；或 `Native Crash: domain required for stack walk`
- 模块：`freelifeclient/Assets/Scripts/Gameplay/Managers/Input/InputManager.cs`，`Assets/Scripts/Tools/Editor/InputDomainReloadCleanup.cs`
- 根因：`InputManager.OnShutdown()` 为空，`PlayerControls` 从未 Dispose；domain reload 时 GC Finalizer 在 Mono 内部结构已释放后仍尝试访问 gptrarray → 断言崩溃
- 解决：① `InputManager.OnShutdown()` 中 `playerControls.Disable(); playerControls.Dispose(); playerControls = null;` ② Editor 脚本 `InputDomainReloadCleanup.cs` 中 `AssemblyReloadEvents.beforeAssemblyReload` 主动 Disable+Dispose
- 日期：2026-03-12

## [EP-003] Unity Play 模式代码变更时 A* RVO Burst 同步编译崩溃
- 症状：日志出现 `Synchronous compilation was requested for method Pathfinding.RVO.RVOQuadtreeBurst+JobBuild during script compilation. This is not allowed because when done on the main thread it can cause a deadlock`，随后 `Native Crash Reporting`、`domain required for stack walk`
- 模块：`freelifeclient/Packages/com.arongranberg.astar/RVO/RVOSimulator.cs`，`Assets/Scripts/Tools/Editor/InputDomainReloadCleanup.cs`
- 根因：domain reload 前 `RVOSimulator.Update()` 仍在调度 Burst Job，Burst 尝试主线程同步 JIT 编译，与脚本重编译流程冲突 → 死锁 → Native crash
- 解决：`InputDomainReloadCleanup.cs` 中 `beforeAssemblyReload` 时 `FindObjectsOfType<RVOSimulator>()` → `sim.enabled = false`（触发 `OnDisable → SimulatorBurst.OnDestroy`，停止所有 RVO Burst Job）
- 日期：2026-03-12

## [EP-004] NPC 实体销毁后 AI tick 访问空指针
- 症状：scene_server panic: runtime error: nil pointer dereference，堆栈指向 AI tick 相关函数
- 模块：scene_server/internal/common/ai/
- 根因：场景切换时 NPC 实体已从 ECS 移除，但 AI BtTickSystem 仍持有引用并尝试 tick
- 解决：在 AI tick 入口检查实体有效性，无效则跳过并清理引用
- 日期：2026-02-15

## [EP-005] V2 NPC 日程系统完整链路断裂（6 个断点）
- 症状：NPC 停在原地不动，无报错日志，服务端 ScheduleHandler 日志正常
- 模块：scene_server 的 AI execution/handlers、pipeline、bt_tick_system、npc_move
- 根因：V2 日程系统从决策到实际移动的链路存在 6 个断点（按发现顺序）：
  1. **时间源错误**：ScheduleHandler 用系统时间而非 TimeMgr 游戏时间，日程匹配失败
  2. **Handler 未注册**：schedule plan 注册条件同时要求 scheduleQuerier 和 scenarioFinder 非 nil，但 scenarioFinder 传了 nil
  3. **IsMoving 未设置**：MoveTo/Work 行为只设了 MoveTarget，未设 IsMoving=true，Navigation brain 条件不满足
  4. **IsMoving 未同步到 snapshot**：OrthogonalPipeline.ReadLiveState 只同步了 MoveTarget/MoveSource，未同步 IsMoving
  5. **NpcState→NpcMoveComp 桥接缺失**：ScheduleHandler 写 NpcState.MoveTarget，但 NpcMoveSystem 只读 NpcMoveComp.pointList，中间无转换
  6. **eState=Stop 未激活**：写入 pointList 后未调用 StartMove()，NpcMoveComp 始终处于 Paused 状态，NpcMoveSystem 直接跳过
- 解决：
  1. SceneAccessor.GetGameTimeSecond() 从 TimeMgr 获取游戏时间
  2. 注册条件改为只需 scheduleQuerier != nil
  3. MoveTo/Work 分支添加 IsMoving=true
  4. ReadLiveState 刷新时同步 IsMoving
  5. bt_tick_system 新增 syncNpcMovement() 将 MoveTarget 转为 pointList
  6. SetEntityRoadNetPath 和 syncNpcMovement 末尾调用 StartMove()
- 日期：2026-03-16

## [EP-006] NPC 日程移动走直线无视路网（ScenarioSystem 中断）
- 症状：小镇 NPC 从起点到终点走直线，穿墙穿山，无视路网；日志中 ScenarioHandler OnEnter/OnExit 每帧弹跳
- 模块：scene_server `ecs/system/scenario/scenario_system.go` `isNpcFreeForScenario()`
- 根因：`ScenarioSystem` 的 `isNpcFreeForScenario` 空闲判定过于宽松，不检查 `Movement.IsMoving` 和 `Schedule.HasTarget`。NPC 正在执行日程 MoveTo（沿路网行走）时被 ScenarioSystem 认为"空闲"并分配场景点，导致：①`CurrentPlan="scenario"` 触发 Brain plan 切换 → ②ScheduleHandler.OnExit 清理 `HasTarget/CurrentPlan` → ③Brain 立刻切回 schedule → ④ScheduleHandler 重入重置路网路径 → 每帧弹跳
- 解决：`isNpcFreeForScenario` 增加 `!npcState.Movement.IsMoving && !sched.HasTarget` 条件，确保只有真正空闲的 NPC 才被分配场景点
- 日期：2026-03-17

## [EP-007] NPC 初始走路无动画（定身漂移），稍后恢复
- 症状：部分 NPC 生成后走路时无走路动画（站立姿势漂移），过一会切换状态后动画恢复正常
- 模块：freelifeclient `AnimationManager`、`TownNpcMoveState`、`TownNpcIdleState`、`TownNpcAnimationComp`
- 根因：`AnimationManager.OnInit()` 中 `InitAllTransitions()` 和 `InitNpcAnimationConfigMap()` 均为 `async void`（fire-and-forget），`OnInit` 立即返回，Manager 系统认为初始化完成。NPC 创建时动画配置仍在异步加载 → `TryGetAnimationConfig` 返回 false → `_replaceTransitions` 为空 → `Play(BaseMove)` 静默返回 null。状态切换后 OnEnter 重试时配置已加载，动画恢复正常。
- 解决（两轮）：
  1. [v1] OnEnter 重试：`TownNpcMoveState/TownNpcIdleState.OnEnter()` 添加 `ChangeAnimationsByGroup(NpcWpn00)` — 治标，首次进入仍失败
  2. [v2] 根治：`InitAllTransitions` 和 `InitNpcAnimationConfigMap` 改为 `async UniTask`，`OnInit` 中 `await` 两者，确保配置加载完成后才继续
- 日期：2026-03-17

## [EP-008] NPC EnterBuilding 日程条目仅设标记不传送位置
- 症状：V2 NPC（如 Donna）在 EnterBuilding 日程时段（如 19:00-08:00）应在建筑内，但实际停在出生点坐标不动
- 模块：scene_server `ai/execution/handlers/schedule_handlers.go` ScheduleHandler case 6
- 根因：`behaviorType=6` (EnterBuilding) 仅设置 `ScriptOverride=true` 标记，未传送 NPC 到建筑门口坐标、未停止移动、未设置 `HasTarget=true`。NPC 在日程中间时刻生成时保持出生点位置
- 解决：case 6 中增加 `SetEntityPosition` 传送到 `entry.TargetPos`，设置 `IsMoving=false` + `HasTarget=true`；`SceneAccessor` 接口新增 `SetEntityPosition` 方法
- 日期：2026-03-18

## [EP-009] NPC 正常行走播放奔跑动画（FSM 状态索引偏移）
- 症状：所有小镇 NPC 正常行走时播放奔跑动画；停止时播放行走动画；奔跑状态映射到无关状态
- 模块：freelifeclient `TownNpcFsmComp`、`TownNpcStateData`、`TownNpcController`、`TownNpcTurnState`、`TownNpcInDoorState`、`TownNpcTradeEffectState`
- 根因：服务端 `EMoveState` 枚举从 1 开始（Stop=1, Move=2, Run=3），客户端 `_stateTypes` 列表从 0 开始。原设计通过隐式 `-1` 偏移映射，但 `-1` 散落在 6 处代码中（信号发送端 2 处、初始化 1 处、客户端状态回退 3 处），维护中被部分删除导致映射错位
- 解决：
  1. `TownFsmComp`：废弃隐式 -1，改用 `Dictionary<int, int> _serverStateMap` 显式映射，`RegisterServerState<T>(serverStateId)` 注册时自动建立映射
  2. `TownNpcStateData`：`Notify(StateIdUpdate, ...)` 传原始服务端值（删除 -1）
  3. `TownNpcController`：`FsmComp.InitData(StateId)` 传原始服务端值（删除 -1）
  4. `TownNpcTurnState`/`TownNpcInDoorState`/`TownNpcTradeEffectState`：改用 `ChangeStateByServerStateId()` 替代 `ChangeStateById(stateId - 1)`
  5. 新增 `ChangeStateByServerStateId(int)` 公开方法，供需要用服务端枚举值切换状态的代码使用
- 教训：值域转换（如 1-based→0-based）必须集中在一处完成，散落多处的隐式 -1 极易在维护中被遗漏或重复
- 日期：2026-03-18

## [EP-010] NPC 移动插值数据被情绪状态覆盖丢弃
- 症状：NPC 触发情绪后位置不再更新，站立姿态滑行或完全不动
- 模块：freelifeclient `TownNpcStateData`、`TownNpcClientData`
- 根因：`TownNpcStateData.StateId` 同时被 `MoveStateProto.State`(1-3) 和 `NpcEmotionChangeNtf.EmotionState`(12-16) 写入。情绪覆盖 StateId 后，`TryUpdateMoveControlData` 中 `StateId != MOVE_STATE_MOVE(2)` 判断为 true（如 StateId=12），移动插值数据被丢弃
- 解决：新增 `PhysicalMoveState` 字段，仅由 MoveStateProto.State 写入，不被情绪覆盖。`TryUpdateMoveControlData`、`TryUpdateTransformSnapShotData`、`TownNpcInteractableComp` 中的移动判断改用 PhysicalMoveState
- 教训：一个字段承担两个职责（FSM 驱动 + 移动判断）是隐患，状态用途不同时必须分离存储
- 日期：2026-03-18

## [EP-011] NPC 动画参数设置静默失败（LinearMixer 默认值 1.0）
- 症状：NPC 在 MoveState（正确）但播放奔跑动画而非走路动画；多数 NPC 受影响，少数正常
- 模块：freelifeclient `TownNpcMoveState`、`TownNpcIdleState`、`TownNpcRunState`、`TownNpcAnimationComp`
- 根因：`TownNpcMoveState.OnEnter()` 调用 `SetParameter(BaseMove, 0.3)` 时，动画配置可能未加载完成（`_replaceTransitions` 为空），SetParameter 静默失败（无日志、无异常）。LinearMixer 默认 Parameter=1.0（对应奔跑动画）。后续服务端持续发 State=2 但 stateId 未变化，`OnUpdateStateId` 不重新触发 OnEnter，参数永远停在 1.0
- 运行时证据：6 个 MoveState NPC 中 5 个 param=1.0（奔跑），1 个 param=0.3（正确——该 NPC 后来重新进入了 MoveState）
- 解决：在 MoveState/IdleState/RunState/ScenarioState(走路阶段) 的 `OnUpdate` 中检测参数值，不对时重新设置（防守式修正）。同时修复 `TownNpcScenarioComp` 和 `TownNpcScenarioState` 中 `Vector2.right`(param=1.0) 应为 `0.3f * Vector2.right` 的 2 处错误
- 教训：
  1. 静默失败是最难排查的 bug——SetParameter 找不到 key 时应打 Warning 而非静默返回
  2. OnEnter 只执行一次的设置必须有 OnUpdate 兜底，尤其是依赖异步加载的场景
  3. 排查动画问题时，优先用运行时诊断脚本读取实际参数值，而非只看 FSM 状态
  4. 同一根因影响多个状态——修完 MoveState 后遗漏了 ScenarioState 的走路阶段（phase 1/2/6），诊断数据中的"看似正常"的异常值不能轻易放过
- 日期：2026-03-18

## [EP-008] 交通车辆路线分配与 AOI 不一致导致乱飘
- 症状：小镇交通车辆不按预设路线行驶，飘到其他路线的位置；只能看到少量车辆
- 模块：TownTrafficSpawner / Vehicle.cs / scene_server TrafficVehicleSystem
- 根因：
  1. 路线分配用 `vehicleIndex % routes.Count`（TrafficManager 注册顺序），但 AOI 导致客户端收到的车辆顺序与服务端生成顺序不一致，车辆被分配到错误路线后瞬间飞到该路线起点
  2. 服务端 `NeedAutoVanish=true`，300 秒无交互自动删除交通车辆，而 Spawner 已完成生成不再补充
- 解决：
  1. `AssignWaypointPath` 改为按车辆当前位置匹配最近未分配路线（`FindClosestRoute`）
  2. Town 场景交通车辆设 `NeedAutoVanish=false`
- 教训：
  1. 依赖注册顺序做索引映射在有 AOI 的分布式场景中不可靠，应使用位置匹配或显式传递索引
  2. 自动消失机制对无交互的 NPC 交通车辆不适用，需按场景类型区分
- 日期：2026-03-21

## [EP-009] Catmull-Rom 样条移动路口乱晃+拐弯不自然
- 症状：交通车辆到路口方向乱晃、拐弯僵硬不自然、突然消失
- 模块：TownTrafficMover（客户端直驱移动组件）
- 根因：
  1. 路线路点间距过短（<1m 的极短路段），导致每帧跳几十段，帧位移方向噪声极大
  2. 旋转用帧位移方向 `newPos - lastPos` 而非样条切线 `CatmullRomDerivative`，低速时位移极小方向噪声大
  3. 弯道减速无角度阈值，微小转角（5°-10°）也触发减速，全程锁定最低速
  4. 距离隐藏无滞后带（150m 硬切），边缘闪烁导致"突然消失"
- 解决：
  1. Init 时 `FilterShortSegments` 合并 <1.5m 路段（路点数从 103-132 降至 50-79）
  2. 旋转改用 `CatmullRomDerivative` 样条切线（数学连续无噪声）
  3. 弯道角度阈值 25°，低于不减速；前瞻 2 段预减速；预计算角度数组避免每帧开销
  4. 显示 200m / 隐藏 220m 滞后带；单帧最多跨 3 段防止飞跃
- 教训：
  1. 路网提取的路点间距不均匀，必须在加载时做预处理过滤
  2. Catmull-Rom 样条有现成的切线导数函数，旋转应始终用它而非帧位移差分
  3. 减速系统需要角度阈值 + 前瞻 + 平滑过渡三者配合，单一参数不够
  4. 距离剔除必须有滞后带（hysteresis），否则在边界来回穿越时闪烁
  5. 运行时监测脚本是关键诊断工具：采集 speedFactor/segmentCount/position 对比多帧数据可快速定位根因
- 日期：2026-03-21

## [EP-013] 交通车辆路口乱晃（路线数据 180° 折返）
- 症状：小镇交通车辆在路口处剧烈左右摆动/乱晃，直道正常
- 模块：`traffic_routes.json`（路线数据）、`TownTrafficMover.cs`（Catmull-Rom 插值）
- 根因：路线生成器在双车道路网（有向图，正反车道分开存储为 `neighbors` / `OtherLanes`）上使用无向图最短路径，导致路径在正反车道间来回穿越。相邻点位形成 180° 折返（148 处），Catmull-Rom 样条在折返处产生剧烈振荡曲线
- 数据特征：近重复点（<0.1m）14处、极短段（<2m）28处、尖锐折返（>150°）148处
- 解决：路线生成后处理管线（`scripts/gen_cruise_routes.py`），4 步迭代至收敛：
  1. 移除近重复点（<1m）
  2. 消除锯齿（跳过后距离更短 → 移除中间点）
  3. 移除 >120° 折返点（保留正常直角弯）
  4. 移除极短段（<3m）
- 教训：
  1. 双车道路网做无向寻路必须后处理消除车道穿越，不能直接用原始路径
  2. Catmull-Rom 样条对 >120° 转折极度敏感，会产生远超控制点范围的摆动
  3. 路线数据质量验证必须包含三项：重复点、短段、转角角度
- 日期：2026-03-21

## [EP-014] 大世界场景角色误入游泳状态（服务端位置低于地形 + Crest 海洋）
- 症状：玩家角色在大世界场景刚进入时直接呈现落入水中的状态
- 模块：freelifeclient `LoadScene`、`SwitchUniverseNtf`、`SceneManager`、`MoveState`、`FallingState`
- 根因（两层）：
  1. **主因**：服务端下发的出生坐标 Y 值（47.56）远低于实际地形高度（60.0），且低于 Crest 海洋水面（50.0）。玩家出生在海面以下，直接 SwimmingState
  2. **副因**：CrouchState/JumpLandState 的入水检测只查 IsInWater 不查 IsGrounded；MoveState 的 0.3s grace timer 是一次性的
- 运行时数据：Player Y=44.27, Ground Y=59.98, Ocean Y=50.00, SpawnPos Y=48.06
- 解决：
  1. **LoadScene/SwitchUniverseNtf/SceneManager**：出生位置设置前做射线检测地面高度，若玩家位置低于地面则修正到地面 +1m
  2. **MoveState**：一次性 grace timer 改为持续性"未接地累计时间"防抖（>0.5s 才允许入水）
  3. **FallingState**：增加最短落空时间 0.5s 才检查水
  4. **CrouchState/JumpLandState**：补充 `!IsGrounded` 条件
- 教训：
  1. 服务端坐标不可信——客户端必须在出生时做地面修正（Raycast snap to ground）
  2. Crest 全局海洋 Y=50 覆盖整个大世界，任何低于此高度的位置都会触发 InWater
  3. 入水检测的多个入口点必须保持一致的防护条件
  4. 排查 bug 时先用运行时脚本读取实际数值（PlayerPos/OceanY/GroundY），比读代码推理快 10 倍
- 日期：2026-03-22

## [EP-015] 大世界红绿灯位置不对（悬空 + 堆叠 + 镜像）
- 症状：红绿灯悬空、同方向多个灯堆叠在车道间、左右镜像（在路对面）
- 模块：freelifeclient `GTA5TrafficSystem.SpawnLightsForJunction()`
- 根因（三重叠加）：
  1. **多车道入口未去重**：路网数据中同一道路每条车道都有独立入口节点（cycle>0），代码为每个入口生成一个灯，导致同方向 2-3 个灯堆叠（灯数 1544，实际只需 ~567）
  2. **Y 坐标偏移不当**：Grounds 层 raycast 后加 RoadSurfaceOffset=2m 补偿，但在 Grounds 层与路面齐平的区域导致悬空；用 Grounds+Default 混合 mask 则命中建筑屋顶
  3. **right 向量方向**：outward 顺时针 90° 才是正确的路边方向，逆时针 90° 会导致左右镜像
- 解决：
  1. 新增 `MergeEntrancesByDirection()`：同 cycle phase + 距离<12m 的入口合并，取最靠 right 侧车道放一个灯
  2. `RoadSurfaceOffset = 0`，只用 Grounds 层 raycast 不加偏移
  3. right 向量 = `(outward.z, 0, -outward.x)`（outward 顺时针 90°）
- 教训：
  1. 路网数据是按车道粒度的，放置路边设施前必须按方向去重
  2. 大世界 Y 坐标 raycast 只用 Grounds 层，不要混合 Default（命中建筑）也不要加固定偏移（不同区域差异大）
  3. 方向向量的正确性必须在游戏中目视验证，不能只靠数学推导（坐标系约定可能与预期不同）
- 日期：2026-03-23

## [EP-016] 新实体类型 Prefab 缺失导致场景不可见 + MonsterManager 类型分支空引用
- 症状：大世界动物在小地图能定位但场景中看不到（部分动物类型完全不出现），无明显报错
- 模块：freelifeclient `MonsterManager.SpawnNpc()`、`PackResources/Prefab/Character/Monster/`
- 根因（两层）：
  1. **Prefab 缺失**：服务端新增的动物类型（Crocodile/Chicken）在配置表 MonsterPrefab 中已有条目，但对应的 Prefab 文件未创建。`ObjectPoolUtility.LoadGameObject()` 抛异常被 catch 吞掉，_monsterList 中该 entityId 被 Remove，实体静默消失
  2. **类型分支空引用**：SpawnNpc 第 755 行 post-Init 校验的异常分支中写死 `npcController.Dispose()`，但动物实体走的是 `animalController`（npcController 为 null），一旦触发该分支必定 NullReferenceException，被外层 catch 吞掉
- 解决：
  1. 从已有 FBX 模型资源创建 CrocodilePrefab1/2 + ChickenPrefab1，配置 Animator + Avatar + AnimatorController + CapsuleCollider + Rigidbody + AnimancerComponent + AreaTrigger 子对象
  2. Chicken FBX 单位不一致，模型 localScale 设为 0.1（bounds 从 9x5x6 修正为 0.3x0.5x0.6）
  3. post-Init 校验改为 `if (isAnimal) animalController?.Dispose(); else npcController?.Dispose();`
  4. 为全部 5 种动物创建 AnimatorController 并绑定可用的动画 clip
- 教训：
  1. **配置表有条目 ≠ 资源就绪**：新增实体类型时，配置表、Prefab、动画三件套必须同步完成，不能只建表不建 Prefab
  2. **类型分支的清理/异常代码必须覆盖所有分支**：MonsterManager 新增 isAnimal 分支后，多处 Dispose/cleanup 仍写死 npcController，未跟进修改。新增实体类型时必须 grep 所有 npcController/animalController 使用点
  3. **异常被 catch 吞掉的场景最难排查**：ObjectPoolUtility.LoadGameObject 失败后只打 Error 日志但立即 return，没有在 Unity Console 中留下足够显眼的痕迹。定位时优先检查 _monsterList/_animalList 计数与 DataManager.Npcs 计数是否一致
  4. **FBX 导入单位不统一是常见陷阱**：不同美术来源的 FBX fileScale 可能不同（Dog=0.0254 inch→m，Chicken=1 但实际cm级），创建 Prefab 后必须在场景中对比 bounds 确认比例合理
- 日期：2026-03-24

## [EP-008] 场景加载卡 40% — async void 吞异常
- 症状：客户端登录后加载进度条卡在 40%，不推进；服务器日志显示进入场景成功，网络连接正常
- 模块：`freelifeclient/Gameplay/Modules/UI/Store/Module/Backpack/StoreBackpackOperation.cs`、`freelifeclient/Gameplay/Managers/LaunchManager/State/LoadScene.cs`
- 根因：`LoadScene.ProcessLoadingScene()` 是 `async void` 方法。在 40% 之后调用 `UpdateUserData` 处理背包数据时，`StoreBackpackOperation.SetIsLocked()` 直接用 `_data.Items[index]` 访问字典，当 `IsFull=true` 清空背包后重新添加项但某些 ItemType 未被 AddItem 实际添加时，key 不存在导致 `KeyNotFoundException`。由于 `async void` 的异常不会传播到 caller，整个加载流程静默中断
- 解决：`SetIsLocked` 添加 `ContainsKey` 检查；同时修复服务端 `func_scene.go:TmpFirstEnterScene` 中 `session==nil` 时缺失的 return 语句
- 教训：
  1. `async void` 方法中的异常会被静默吞掉，关键流程应使用 `async UniTask` 并在外层 catch
  2. 字典直接用 `[]` 索引前必须确认 key 存在，或使用 `TryGetValue`
  3. 调试此类问题时优先查 Unity Console 的 Exception 日志，不要只看 Error
- 日期：2026-03-24

## [EP-009] 动物跟随不动 — NpcMoveComp 速度未切换
- 症状：喂食 Dog 后状态正确切换为 Follow（AnimalFollowHandler OnEnter 日志可见），但狗不跟随玩家移动（实际以 1.5m/s 漫步速度在移动，玩家 3+m/s 轻松跑丢）
- 模块：`scene_server/common/ai/execution/handlers/animal_follow.go`、`scene_server/ecs/res/npc_mgr/animal_init.go`
- 根因：
  1. `animal_init.go` 创建 NpcMoveComp 时只设了 BaseSpeed（漫步 1.5m/s），RunSpeed 保持默认 0
  2. `AnimalFollowHandler.OnTick` 设置 MoveTarget 但从未切换 NpcMoveComp 的速度
  3. `syncNpcMovement` → `MoveEntityVia*` → `StartMove()` 始终用 BaseSpeed（1.5m/s），狗永远追不上玩家
- 解决：
  1. `animal_init.go`: 初始化 `npcMoveComp.RunSpeed = meta.MoveSpeed[2]`（Dog=7.0）
  2. `npc_state.go`: MovementState 增加 `SpeedOverride float32`，AnimalBaseState 增加 `FollowSpeed float32`
  3. `animal_follow.go`: OnTick 跟随时设置 `SpeedOverride = FollowSpeed`
  4. `bt_tick_system.go`: `syncNpcMovement` 路径设定后检查 SpeedOverride 覆盖速度
- 教训：
  1. **ECS 组件全字段初始化**：新建 NpcMoveComp 时必须检查 RunSpeed/BaseSpeed 是否都正确设置
  2. **行为切换必须同步速度**：Handler 切换行为状态时，不能只设 MoveTarget，还要设对应的移动速度
  3. **代码审查看不出的 bug 看日志**：本次所有代码路径审查均正确，最终通过日志发现狗确实在移动但速度极慢
- 日期：2026-03-25

## [EP-008] 动物系统客户端数据清零——proto 引用 vs 复制
- 症状：8 只动物仅 1 只生成，动物无动画、无自主行为、无跟随；投喂后仅 ~1 秒动画后静止
- 模块：freelifeclient NpcData.TryUpdateAnimalData、MonsterManager.SpawnNpc
- 根因：`NpcData.TryUpdateAnimalData` 直接存储 proto `AnimalData` 对象引用（`_animalInfo = netData`），但 proto 对象随 `NpcDataUpdate` 消息回收后字段清零。导致：
  1. `AnimalType=0` → `isAnimal=false` → 7/8 动物按普通怪物路径生成失败（无 MonsterPrefab 配置）
  2. `AnimalState=0` → FSM 始终在 None/Idle，即使服务端 AI 在正常 tick
  3. 推送通知 `AnimalStateChangeNtf` 短暂生效后被下一帧帧同步的零值 AnimalData 覆盖
- 解决：`TryUpdateAnimalData` 改用 `CloneFrom` 复制数据（与其他组件 HumanBaseData、BaseStatusData 等一致）
- 附带修复：`AnimalAnimationComp.PlayAnimation` 后缀匹配增加纯后缀兜底（Chicken 的 `Squatidle` 匹配 `idle`）
- 教训：
  1. **proto 对象有生命周期**：自定义 PbObj 系统可能回收 proto 对象，持有引用不等于持有数据
  2. **新增 TryUpdate 方法必须参照现有模式**：NpcData 中其他字段全部用 Create+InitData/UpdateData 复制，唯独 AnimalData 走了捷径
  3. **运行时数据验证**：MCP script-execute 直接读取内存比静态审查更快定位数据归零问题
- 日期：2026-03-25

## [EP-009] 动物走路动画冻结——FBX clip 未勾选 Loop
- 症状：狗移动时全身静止不动（idle 状态有动画），Animancer 报告 Clip 在播放但视觉无变化
- 模块：freelifeclient AnimalAnimationComp、动物 Prefab AnimatorController
- 根因：`Mod_Animal_Dog_walk` 等动画 clip 的 FBX 导入设置未勾选 Loop Time（`isLooping=false`），clip 长度仅 0.58s，播放一次后冻结在末帧。Walk 状态 OnEnter 仅调用一次 `PlayAnimation`，不像 Idle 有每帧重播兜底
- 解决：`AnimalAnimationComp.PlayAnimation` 播放前检测 `targetClip.isLooping`，非循环 clip 强制 `targetClip.wrapMode = WrapMode.Loop`
- 附带修复：
  1. 客户端根据 XZ 位移方向推算朝向（服务端旋转未同步到大世界动物）
  2. 漫游概率从 30% 提高到 60%，Rest 时间从 5-15s 缩短到 3-8s
- 教训：
  1. **动画 clip 属性必须运行时验证**：FBX 导入的 Loop 设置容易遗漏，运行时 `clip.isLooping` + `clip.length` 检查比靠美术规范可靠
  2. **MCP 强制播放诊断法**：直接 `anc.Layers[0].Play(clip)` 强制播放 clip 后检查 `Time` 递增情况，精确定位"播放但不动"
  3. **服务端移动≠客户端旋转**：NpcMoveSystem 计算了旋转但不一定同步到所有实体类型，客户端需速度方向推算朝向兜底
- 日期：2026-03-25

## [EP-010] 动物漫游数分钟后永久停止——正交维度竞态清零 WanderTarget
- 症状：鳄鱼有爬行动画但不移动，狗完全静止。动物生成后最初几分钟正常漫游，之后永久卡在 Wander 子状态
- 模块：`scene_server/common/ai/execution/handlers/animal_idle.go`、`animal_navigate.go`
- 根因：正交管线 Engagement→Navigation 维度执行顺序导致竞态：
  1. Navigation 维度 `animalNavCheckArrival` 检测到到达后设 `WanderTarget=(0,0,0)` + `IsMoving=false`
  2. 下一帧 Engagement 维度先 tick，发现 `WanderTarget=(0,0,0)` 但误以为是有效远距离目标（距离>>阈值）
  3. 设 `MoveTarget=(0,0,0)` + `IsMoving=true`
  4. `syncNpcMovement` 有零值守卫 `if X==0 && Y==0 && Z==0 { return }` → 移动永远不执行
  5. 动物卡死在 Wander 子状态，永不切回 Rest
- 解决：`AnimalIdleHandler.OnTick` Wander 分支入口增加零值检查：`WanderTarget` 为零时立即切回 Rest 并清除 `IsMoving`
- 教训：
  1. **正交维度间的写入顺序是隐含契约**：下游维度（Navigation）清除上游维度（Engagement）写入的字段时，上游必须有防御性零值检查
  2. **"偶尔失败"比"总是失败"更难定位**：竞态只在 Navigation 的 `animalNavCheckArrival` 先于下一帧 Engagement 检测到到达时触发，初始几分钟正常运行掩盖了问题
  3. **诊断关键线索**：服务端日志有活跃的 navigation 条目→突然消失→之后永远为零。客户端 `AnimalState=Walk` 但位置不变
- 日期：2026-03-25

## [EP-011] 动物播放 walk 动画但不移动——路网路径终点偏移引发每帧重建路径
- 症状：所有漫游中的动物（Dog/Crocodile/Bird）播放 walk 动画，`BehaviorState=Walk` 正确广播到客户端，但服务端位置完全不变
- 模块：`scene_server/ecs/system/decision/scene_accessor_adapter.go`、`bt_tick_system.go`
- 根因：`syncNpcMovement` 路径有效性检查与路网 A* 路径终点不匹配导致死循环：
  1. `MoveEntityViaRoadNet` 返回的路径终点是最近路网节点，不是实际 `MoveTarget`（漫游目标点）
  2. `syncNpcMovement` 检查 `GetLastPoint()` 到 `MoveTarget` 的 XZ 距离是否 ≤ 4m，路网节点偏差 > 4m 时判定"目标显著变化"
  3. 每帧 `Clear()` 清除路径 → 重新寻路 → `StartMove()` 重置 `LastStamp` 为当前时间
  4. `NpcMoveSystem.updateNpcMove` 在同帧执行时 `passedTime = nowStamp - LastStamp ≈ 0` → 跳过移动
  5. 动物永远不移动，但 BehaviorState 始终为 Walk → 客户端播放 walk 动画
- 解决：`MoveEntityViaRoadNet` 中，当路网路径终点距实际目标 > 4m 时，追加实际目标点作为路径最后一个点，确保路径终点等于 `MoveTarget`
- 教训：
  1. **路网寻路结果与实际目标存在固有偏差**：路网 A* 只到达最近节点，不到实际目标。所有依赖路网路径终点的比较逻辑都必须考虑这个偏差
  2. **每帧重置时间戳是移动系统的致命模式**：`StartMove()` 重置 `LastStamp`，如果在同一帧内 `syncNpcMovement` 和 `NpcMoveSystem` 先后执行，`passedTime=0` 导致实体完全不移动
  3. **诊断关键线索**：服务端日志 `MoveEntityViaRoadNet` 每 30ms 重复调用相同 start/end 节点 + `updateNpcMove` 每帧 `arrived=true` 但位置不变 + 客户端两次位置采样完全一致
- 日期：2026-03-26

## [EP-012] 动物跟随时无动画（视觉冻结）——动画速度归一化与服务端 MoveSpeed 不匹配
- 症状：喂食 Dog 后狗跟随移动，但身体完全静止（无跑步/行走动画），模型在贴近玩家时抖动
- 模块：`AnimalFollowState.cs`（客户端）、`animal_follow.go`（服务端）
- 根因（三层叠加）：
  1. `AnimalFollowState.OnEnter()` 播放 "run" 动画，`OnUpdate` 用 `SetAnimSpeed(MoveSpeed, 7.0)` 归一化。但服务端 `AnimalStateChangeNtf.MoveSpeed` 取自 `Animal.Base.MoveSpeed`（初始化=baseSpeed=1.5），只在追赶时（distSq>4）才更新为 followSpeed（7.0）
  2. 结果：客户端动画倍率 = 1.5 / 7.0 = 0.21x，视觉上等同冻结
  3. run clip（`Mod_Animal_Dog_run`）是非循环的（loop=False, 0.88s），`OnUpdate` 缺少 `TickLoopNonLoopingClip()` 兜底，0.88s 后彻底冻结
  4. 狗贴近玩家停步时，服务端位置同步的微小抖动（~0.3-0.5 m/s）导致模型晃动
- 解决：
  1. 不依赖服务端 MoveSpeed 字段，改为客户端每帧计算实际位移速度（XZ delta + Lerp 平滑）
  2. 两档切换：实际速度 < 0.8 → idle（过滤位置抖动），≥ 0.8 → run
  3. 添加 `TickLoopNonLoopingClip()` 兜底非循环 clip
  4. 服务端跟随超时后设 `IdleSubState=Wander` 直接恢复漫步，跳过 Rest 等待
- 教训：
  1. **服务端同步字段 ≠ 实时状态**：`Animal.Base.MoveSpeed` 只在特定条件下更新，客户端不能盲目依赖
  2. **动画归一化必须匹配实际速度量级**：refSpeed=7 配 moveSpeed=1.5 → 0.21x 冻结
  3. **位置同步微抖需要足够高的 idle 阈值**：0.3 不够，0.8 才能覆盖
  4. **GM 命令前缀是 `/ke* gm`**（字面星号），不是 `/ke66 gm`
- 日期：2026-03-26

## [EP-013] 大世界 NPC 插入地面——NavMesh 未加载导致 spawn Y 和路径节点 Y 修正静默失效
- 症状：大世界 NPC 半截插入地面，路径移动时 Y 值剧烈跳变（视觉抖动）
- 模块：`bigworld_npc_spawner.go`（服务端 spawn）、`scene_accessor_adapter.go`（路径 Y 修正）、`initialize.go`（NavMesh 加载）
- 根因：
  1. `MoveEntityViaRoadNet` 已实现对每个 A* 路径节点的 NavMesh Y 投影修正，但大世界 NavMesh（`WorldNavBake_20241218.bin`）从未预加载，`nmMgr.FindPath` 静默失败，修正不执行
  2. `spawnNpcAt` 直接使用路网节点 Y 坐标，路网节点 Y 由离线工具生成精度不足（系统性偏低）
  3. `CitySceneInfo.GetNpcAIConfig()` 缺少 `NavMeshName: "bigworld"`，场景初始化不加载 NavMesh
- 解决：
  1. `initialize.go` preloadNavMeshes 追加 bigworld NavMesh 预加载（`.bin` 格式用 `nil` config 触发二进制加载）
  2. `CitySceneInfo.GetNpcAIConfig()` 增加 `NavMeshName: "bigworld"`
  3. `spawnNpcAt` 用 `NavMeshMgr.FindPath` 投影 spawn 点，修正出生 Y
- 教训：
  1. **NavMesh 预加载 vs 按需加载**：`.bin` 二进制格式须用 `PreloadNavMesh(name, file, nil)` 预加载（nil=Load()），不走场景配置表路径；`GetNpcAIConfig().NavMeshName` 是场景实例化时加载 NavMesh 的入口，两处都要设置
  2. **路网节点 Y 不可信**：大世界路网 Y 坐标系统性偏低，spawn 和路径规划都必须走 NavMesh Y 修正
  3. **静默失败排查**：`NavMeshMgr.FindPath` 无 NavMesh 时返回 error 但代码用 `if err == nil` 短路，日志中不会有明显报错，需主动验证 NavMesh 是否加载成功
- 日期：2026-03-29

## [EP-014] 大世界 NPC 幽灵 controller 累积（DestroyNpc 缺少 scene.RemoveEntity）
- 症状：客户端 BigWorldNpcController 从 ~50 随时间线性膨胀到数千（60 分钟内达 8K+）；所有 controller speed=0，全部处于 MoveState 播放行走动画但位置不变（"满街原地踏步密密麻麻"）
- 模块：`scene_server/ecs/res/npc_mgr/scene_npc_mgr.go` → `DestroyNpc()`
- 根因：
  1. `SceneNpcMgr.DestroyNpc()` 清理 NpcState、管线状态、调用 `m.RemoveNpc(cfgId)` 删除内部映射，但**从不调用 `scene.RemoveEntity(entity.ID())`**
  2. GridManager 不感知实体删除 → `net_update/update.go` 的 `GetRemoveEntityByGrid()` 永远不返回该实体 → 客户端 frame sync `RemoveEntity` 列表永不含该 ID → `DataManager.Npcs` 永不删除 → `BigWorldNpcManager.SyncWithDataManager()` 检测不到移除 → controller 永久驻留
  3. 服务端 spawn/despawn 循环（~3/s × 3600s = ~10K 次），每次 despawn 都泄漏一个 controller
- 解决：`DestroyNpc()` 的 `m.RemoveNpc(cfgId)` 前追加 `scene.RemoveEntity(info.Entity.ID())`（已有 guard: `if info.Entity != nil`）
- 教训：
  1. **ECS 实体删除双路径**：① `m.RemoveNpc` 删内部映射（服务端状态）② `scene.RemoveEntity` 通知 GridManager（客户端同步）。两个必须都执行，任一缺失都会导致客户端/服务端状态发散
  2. **排查幽灵 controller 的诊断脚本**：`BigWorldNpcManager.Instance._entityDict.Count` vs `DataManager.Npcs.Count`；差值即为积压幽灵数量
  3. **速度永远为 0 的幽灵 controller**：生成时 snapshot 坐标 = spawn 点，此后永远不变，`BigWorldNpcMoveComp` XZ delta = 0 → speed = 0。是判断"缺少 RemoveEntity"根因的特征信号
  4. **错误恢复路径已正确**：scene_npc_mgr.go 的错误分支（行 380、389）已有 `scene.RemoveEntity`；遗漏只在正常 destroy 路径
- 日期：2026-03-30

## [EP-015] 大世界近距离 NPC 突然消失——zone quota surplus 无距离保护
- 症状：大世界移动时，距玩家 20-50m 的可见 NPC 突然消失
- 模块：scene_server/ecs/res/npc_mgr/bigworld_npc_spawner.go
- 根因：`doDespawn()` 的 quota surplus 分支无距离保护。当 zone NPC 数量超过 `quota + recycleHysteresis` 时，zone 内所有 NPC（含近距离）都被标记待回收。Go map 随机迭代导致近距离 NPC 可能先于远距离 NPC 被回收。`lastQuotaResults` 每 5s 才刷新，stale surplus 导致过度回收
- 解决：在 quota surplus 分支添加 `minDistSq > quotaSafeRadiusSq`（SpawnRadius²）距离保护，安全半径内 NPC 免于配额回收。同时将 pendingDespawn 处理改为按距离降序排列（最远优先回收）
- 教训：任何限额/配额回收系统都应有"最小安全距离"保护——不应回收用户视野内的实体。回收优先级应基于距离而非随机
- 日期：2026-03-30

## [EP-016] UI 面板未在场景初始化中打开——事件无订阅者
- 症状：靠近狗时投喂交互 UI 不出现，AnimalInteractComp 正常触发 EShowNpcInteractUI 事件但无响应
- 模块：freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Tools/MuiPanelOpenTool.cs
- 根因：`OpenPanelWhenEnterScene()` 打开了 `InteractionHintPanel` 但遗漏了 `InteractionPanel`。后者是监听 EShowNpcInteractUI 事件并显示头顶交互提示的面板，从未被 `UIManager.Open` 调用，导致事件发送后无订阅者
- 解决：在 `OpenPanelWhenEnterScene()` 的 `await UniTask.WhenAll(tasks)` 前添加 `tasks.Add(UIManager.Open<InteractionPanel>())`
- 教训：新增依赖事件订阅的 UI 面板时，必须确认该面板在 `MuiPanelOpenTool.OpenPanelWhenEnterScene()` 中被打开。事件发布-订阅模式的隐患：发布方不报错，订阅方缺失时静默失败
- 日期：2026-03-31

## [EP-017] DisableAllPickingEvent 未保留按钮——UI 按钮可见但不可点击
- 症状：交互提示按钮（"投喂"）可见但点击完全无反应，UI 不消失，无任何回调触发
- 模块：freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/InteractionHintPanel.cs
- 根因：`OnOpen()` 调用 `MuiUtil.DisableAllPickingEvent(_view.hintContainerGroup)` 缺少 `exceptButton=true` 参数。默认 `false` 导致所有 MButton 的 `pickingMode` 被设为 `Ignore`，按钮在视觉上正常显示但无法接收指针事件。PC 面板 (`InteractionHintPCPanel`) 已正确传入 `true`，Mobile 面板遗漏
- 解决：改为 `MuiUtil.DisableAllPickingEvent(_view.hintContainerGroup, true)` 保留 MButton 的 pickingMode
- 教训：调用 `DisableAllPickingEvent` 时，若容器内包含需要交互的按钮，必须传入 `exceptButton=true`。新增面板使用此方法时，检查是否与同功能的其他平台面板参数一致（PC vs Mobile）
- 日期：2026-03-31

## [EP-018] 客户端/服务端距离判定不一致——位置插值延迟导致交互失败
- 症状：靠近狗后"投喂"按钮出现，点击后无任何反应（无日志、无动画、无跟随）。Gateway 日志显示 `call failed: cmd=3200, err={7 14002}`（距离过远）
- 模块：`scene_server/net_func/npc/animal_feed.go`、`freelifeclient AnimalInteractComp.cs`
- 根因：
  1. 客户端用 `gameObject.transform.position`（TransformComp 插值后的渲染位置）判断 3m 范围显示按钮
  2. 服务端用实体原始坐标判断 3m 距离
  3. 狗在漫游中，服务端位置超前于客户端插值位置，服务端判定距离 > 3m 返回 14002
  4. 附带问题：RPC 错误响应未回传客户端，UniTask 永远 Pending，客户端无任何反馈
- 解决：
  1. 服务端将喂食距离从 3m（9m²）放宽到 5m（25m²），补偿位置同步延迟
  2. 客户端 `SendFeedRequest` 添加 5s 超时兜底，防止 UniTask 永远 Pending
- 教训：
  1. **客户端/服务端距离校验必须留余量**：客户端用插值位置做 UI 显示判断，服务端用原始位置做逻辑校验。服务端校验距离应比客户端宽松 50-100%，补偿同步延迟
  2. **RPC 请求必须有超时兜底**：不能假设所有 RPC 请求都会收到响应。async UniTaskVoid + .Forget() 模式下异常被吞，应使用 CancellationTokenSource.CancelAfter() 添加超时
- 日期：2026-04-01
