# 开发日志：V2_NPC

## 2026-03-27 - task-05: Client Controller + 基础组件

### 实现范围
客户端（仅客户端，无服务端代码）

### 新增文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs` — 大世界 NPC 主控制器，聚合 TransformComp/MoveComp/AppearanceComp，管理 CancellationTokenSource 生命周期
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcTransformComp.cs` — 位置同步组件，基于 TransformSnapshotQueue 插值，LOD 感知帧间隔控制
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcMoveComp.cs` — 移动驱动组件，维护移动状态（Idle/Walk/Run）供 FSM/Animation 查询
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAppearanceComp.cs` — 外观加载组件，通过 BodyPartsMap 异步加载部件，三级 fallback 确保不隐形

### 修改文件
- `freelifeclient/Assets/Scripts/Gameplay/LogModule.cs` — 新增 `BigWorldNpc` 日志模块

### 关键决策
- Controller 继承 `Controller`（BigWorld 基类），不继承 TownNpcController/MonsterController，完全独立于 S1Town
- TransformComp 缓存 proto 对象复用，避免每次服务端更新堆分配
- AppearanceComp 委托 BodyPartsMap（FL.Gameplay.Modules.UI 命名空间）处理部件加载，而非重新实现
- MoveComp 当前主要维护移动状态元数据，实际位移由 TransformComp 的 SnapshotQueue 插值驱动
- FSM/Animation 组件按 plan 设计留在 task-06 实现，Controller.OnInit 中已预留注释标记

### 合宪性自检
- ✅ YAGNI：仅实现 task-05 范围内的 3 个组件
- ✅ 无 S1Town 命名空间引用
- ✅ 使用 MLog（非 Debug.Log）
- ✅ 使用 UniTask + CancellationToken
- ✅ Vector3 alias 消除歧义
- ✅ 错误处理：catch 块均有 MLog.Error 日志
- ✅ OnClear 正确清理所有引用
- ✅ 热路径无堆分配（TransformComp.OnUpdate 无 new，OnPositionUpdate 复用缓存对象）

### 待办事项
- task-06 补充 BigWorldNpcFsmComp + BigWorldNpcAnimationComp 并在 Controller.OnInit 中 AddComp

## 2026-03-27 - task-05: Review 修复

### 修复问题

**HIGH（3 个）**：
1. **MoveComp.OnUpdate 速度估算逻辑失效** — TransformComp 先于 MoveComp 更新，导致 position 与 CurrentPosition 已同步、delta 始终为零。修复：TransformComp 新增 `_previousPosition` 字段，在插值写入前缓存上一帧位置；MoveComp 改用 `PreviousPosition` 与当前位置比较
2. **AppearanceComp.OnClear 未调用 UnloadAppearance** — OnClear 路径不经过 OnDispose，资源泄漏。修复：OnClear 中调用 `UnloadAppearance()` 释放 BodyPartsMap
3. **Controller.ResetForPool 未 Dispose 旧 CTS** — 对象池回收复用时旧 CTS 句柄泄漏。修复：ResetForPool 开头先 Cancel + Dispose 旧 CTS

**MEDIUM（3 个，顺手修复）**：
1. **MoveComp 魔法数字** — 提取 `RunSpeedThreshold = 2.5f` 和 `StopSqrDistThreshold = 0.001f` 为 const
2. **Controller.OnDispose 清理不一致** — TransformComp/MoveComp/AppearanceComp 统一在 OnDispose 中置 null

### 合宪性自检
- ✅ 无新增 S1Town 引用
- ✅ 错误处理完整，无静默忽略
- ✅ 热路径无新增堆分配（PreviousPosition 是值类型缓存）
- ✅ Vector3 alias 保持不变

## 2026-03-27 - task-06: Client FSM 状态机 + 动画系统

### 实现范围
客户端（仅客户端，无服务端代码）

### 新增文件
- `freelifeclient/.../NPC/Comp/BigWorldNpcAnimationComp.cs` — Animancer 多层动画组件，裁剪版（Base/UpperBody/Arms/Face），支持 HiZ 剔除暂停/恢复，动画速度归一化，TransitionKey API
- `freelifeclient/.../NPC/Comp/BigWorldNpcFsmComp.cs` — 轻量级 FSM，GuardedFsm 驱动，服务器 NpcState 枚举映射本地状态，支持 ForceIdle 用于对象池
- `freelifeclient/.../NPC/State/BigWorldNpcIdleState.cs` — Idle 状态，BaseMove 参数 Vector2.zero，OnExit Stop Base 层
- `freelifeclient/.../NPC/State/BigWorldNpcMoveState.cs` — Move 状态，Walk(0.3f)/Run(0.7f) blend tree 参数，归一化速度 animSpeed=actualSpeed/refSpeed
- `freelifeclient/.../NPC/State/BigWorldNpcTurnState.cs` — Turn 状态，角度阈值 TurnThresholdDeg=30f，显式 Rad2Deg 转换，动画结束回退服务器状态

### 修改文件
- `freelifeclient/.../NPC/BigWorldNpcController.cs` — OnInit 添加 AddComp<AnimationComp>、AddComp<FsmComp>，OnDispose/ResetForPool 补充清理

### 关键决策
- FsmComp 监听 `ServerAnimStateData.MonsterStateUpdate`（NpcState 枚举），而非 TownNpc 的 StateData.StateIdUpdate
- MoveState 复用 Walk/Run（服务端 ID=2 和 ID=3 映射同一个 MoveState），由 MoveComp.CurrentMode 区分参数
- AnimationComp 使用 AnimationManager.TryGetAnimationConfig + ChangeTransitionByKey 模式（与 TownNpcAnimationComp 一致）
- 动画速度归一化：WalkRefSpeed=1.5f, RunRefSpeed=4.0f, animSpeed=Clamp(actual/ref, 0.5, 2.0)
- 角度变量严格标注单位后缀（deltaYawDeg/deltaYawRad），Mathf.Rad2Deg 显式转换

### 合宪性自检
- ✅ 无 S1Town 命名空间引用
- ✅ 每个 State 的 OnExit 都 Stop 使用过的动画层
- ✅ 角度比较两侧单位一致，无弧度/度数混用
- ✅ 播放 clip 前检查 isLooping 设置
- ✅ 动画归一化 refSpeed 匹配实际移速
- ✅ Vector2/Vector3 alias 消除歧义
- ✅ 使用 MLog（非 Debug.Log）
- ✅ OnClear 正确清理所有引用
- ✅ 错误处理完整，null 检查到位

### 待办事项
（无）

---

## 2026-03-27 - task-07: Client BigWorldNpcManager 管理器

### 实现范围
客户端（仅客户端，无服务端代码）

### 新增文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Managers/BigWorldNpcManager.cs` — 大世界 NPC 生命周期 + 对象池管理器，继承 BaseManager，核心职责：对象池预热、Spawn/Despawn 分帧控制、LOD 三档管理、断线重连验证、场景切换清理

### 修改文件
（无）

### 关键决策
- 对象池委托 ObjectPoolUtility 管理（PrewarmGameObject/LoadGameObject/Free），不自行维护 Queue<GameObject>，与 MonsterManager 使用模式一致
- NPC 数据源通过 DataManager.Npcs diff 驱动（poll 模式），过滤条件为 ServerAnimStateData != null 以区分 V2 管线 NPC
- 分帧 despawn 最多每帧 5 个，避免突刺
- LOD 使用平方距离（sqrMagnitude）避免 sqrt 开销，每秒更新一次
- 断线重连：pendingValidation 标记 + ProcessFullSync 全量 diff + 5 秒超时自动清除
- Dispose 后调用 ReturnToPool（Free 回 ObjectPoolUtility），不 Destroy

### 合宪性自检
- ✅ YAGNI：仅实现 task-07 范围
- ✅ 无 S1Town 命名空间引用
- ✅ EntityId 使用 ulong（非 int）
- ✅ 使用 MLog + `+` 拼接（非 $"" 插值）
- ✅ 使用 UniTask（非 System.Threading.Tasks）
- ✅ OnInit/OnShutdown 配对完整
- ✅ _isReady=false 期间消息排入 _pendingSpawnQueue 不丢弃
- ✅ 对象池复用时调用 ResetForPool()
- ✅ 热路径（OnUpdate）无堆分配（使用预分配 List）
- ✅ 错误处理完整，catch 块有 MLog.Error 日志
- ✅ Vector3 alias 消除歧义

### 待办事项
（无）

## 2026-03-27 - task-07: Review 修复

### 修复问题

**CRITICAL（1 个）**：
1. **ProcessPendingSpawnQueue 缺少 CancellationToken** — async UniTaskVoid fire-and-forget 无法取消，Manager 销毁后继续执行导致 NullReferenceException。修复：新增 `_cts` 字段，OnInit 创建、OnShutdown Cancel+Dispose，ProcessPendingSpawnQueue 接收 token 并在循环中检查取消

**HIGH（2 个）**：
1. **Tick 循环 foreach 字典修改风险** — Tick 中可能间接触发字典修改导致 InvalidOperationException。修复：Tick 前用 `_tempTickKeys` 快照 key 列表，循环中 TryGetValue 安全访问
2. **ProcessFullSync 每次 new List 分配** — 断线重连时产生不必要 GC。修复：复用类级 `_tempRemoveList` 字段

**MEDIUM（2 个，顺手修复）**：
1. **常量命名 UPPER_SNAKE_CASE → PascalCase** — 统一为项目规范（PoolSize, MaxDespawnPerFrame, LodFullDistSqr 等）
2. **ProcessPendingSpawnQueue 异常保护** — 整个 while 循环包裹 try-catch，OperationCanceledException 静默处理，其他异常 MLog.Error 记录

### 合宪性自检
- ✅ CancellationToken 配对完整（OnInit 创建 → OnShutdown Cancel+Dispose）
- ✅ 热路径无新增堆分配（_tempTickKeys/\_tempRemoveList 均为预分配 List）
- ✅ 常量命名符合 PascalCase 规范
- ✅ 错误处理完整，无静默忽略

---

## 2026-03-27 - task-04: Server GM 命令 + JSON 配置文件

### 实现范围
服务端（仅服务端，无客户端代码）

### 新增文件
- `P1GoServer/servers/scene_server/internal/net_func/gm/bigworld.go` — 5 个大世界 NPC GM 命令处理器（spawn/clear/info/schedule/lod）
- `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_config.go` — 大世界 NPC 配置 JSON 加载（spawn 配置 + 外观配置）
- `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_config_test.go` — 配置加载单元测试（表格驱动，12 个用例）
- `P1GoServer/bin/config/bigworld_npc/bigworld_npc_spawn.json` — 生成配置（max_count=50, spawn_radius=200, despawn_radius=300）
- `P1GoServer/bin/config/bigworld_npc/bigworld_npc_appearance.json` — 外观配置（6 套市民外观，权重分配）
- `P1GoServer/bin/config/ai_schedule/bigworld/V2_BigWorld_default.json` — 默认日程（P0 全天 patrol）

### 修改文件
- `P1GoServer/servers/scene_server/internal/net_func/gm/gm.go` — switch 新增 5 个 bigworld_npc_* 命令分支
- `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_ext_handler.go` — 外观池从硬编码改为 JSON 配置加载（loadAppearanceConfig），加载失败有 fallback
- `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_npc_spawner.go` — 新增 GM 公开方法（GMSpawn/GMClearAll/GMGetActiveNpcInfo/GMGetActiveCount/GMGetConfig）

### 关键决策
- 外观配置 6 套（plan 要求 5-8 套），权重非均等（常见外观 20，稀有 10-15），符合 GTA5 路人多样性设计
- BigWorldExtHandler 的 initDefaultAppearancePool 改为 loadAppearanceConfig，从 JSON 加载，加载失败 fallback 到 5 套默认外观（保持向后兼容）
- GM 命令中 bigworld_npc_info 同时输出 NpcMap 层和 Spawner 层信息，便于调试时对照两层状态
- LOD 统计使用 plan.json 中 server_lod 阈值（HIGH 0-100m, MEDIUM 100-200m, LOW 200-300m）

### 测试情况
- `make build` 编译通过（15 个微服务全量编译）
- 配置加载单元测试 12/12 通过（正常路径 + 边界值 + 错误路径 + 文件不存在）

### 合宪性自检
- ✅ YAGNI：仅实现 plan 要求的 GM 命令和配置加载
- ✅ 标准库优先：仅用 encoding/json、os 等标准库
- ✅ 错误处理：所有 error 显式处理，有 log.Errorf
- ✅ 无全局变量
- ✅ GM 前缀：通过 gm.go 分发，/ke* gm 前缀已验证
- ✅ 配置不 hardcode：从 JSON 加载
- ✅ V2_BigWorld 前缀：日程配置与小镇隔离

### 待办事项
（无）

## 2026-03-27 - task-04: Review 修复

### 修复问题

**CRITICAL（2 个）**：
1. **spawnNpcAt 未创建实体和写入位置** — spawnNpcAt 仅创建 SceneNpcInfo 注册到 NpcMap，未创建实体，所有动态 NPC 无实体无位置。修复：SceneNpcMgr 新增 `CreateDynamicBigWorldNpc` 方法，使用 `CreateSimpleNpc` 创建完整实体（含 Transform/NpcComp 等），挂载 SceneNpcComp（V2 大世界扩展），spawnNpcAt 改为调用此方法
2. **配置文件绕过打表流程** — 3 个 JSON 直接放在 `bin/config/` 下，打表工具会递归清空。修复：源文件迁移到 `freelifeclient/RawTables/Json/Server/bigworld_npc/` 和 `freelifeclient/RawTables/Json/Server/ai_schedule/bigworld/`，由打表工具自动拷贝

**HIGH（7 个）**：
1. **动态 CfgId 起始值 10000 无边界保护** — 提取为 `const dynamicCfgIdBase = 10000`，添加范围分区注释
2. **魔法数字 100.0（最小玩家距离平方）** — 提取为 `const minSpawnDistSqXZ float32 = 100.0`
3. **魔法数字 50（海洋高度阈值）** — 提取为 `const oceanHeightY float32 = 50.0`，注释引用 reference_bigworld_ocean_height
4. **LOD 阈值硬编码** — 改为 `highDistSq/mediumDistSq/lowDistSq` 平方距离常量，移除 math.Sqrt 调用
5. **body_parts 数据解析后丢弃** — BigWorldAppearanceEntry 新增 `BodyParts map[string]string` 字段，LoadBigWorldAppearanceConfig 传递 body_parts
6. **weight 字段注释矛盾** — 注释从 "0~1 范围" 修正为 "整数权重，值越大被选中概率越高"
7. **NpcMap 直接遍历** — LOD 统计改为通过 GetNpc 方法访问

**MEDIUM（5 个，顺手修复）**：
1. **math.Sqrt 改平方距离** — LOD 分级使用 distSq 对比 highDistSq/mediumDistSq/lowDistSq
2. **采样比例魔法数字 5** — 提取为 `const spawnPointSampleRatio = 5`
3. **配置路径字符串硬编码** — 提取为包级 const `bigWorldAppearanceConfigPath` 和 `bigWorldScheduleConfigDir`
4. **allocCfgId 无溢出保护** — 超出 int32 范围时回绕到 dynamicCfgIdBase
5. **移除未使用的 math 导入** — bigworld.go 不再需要 math.Sqrt

### 合宪性自检
- ✅ 未触碰禁编辑区域
- ✅ 错误处理完整（CreateDynamicBigWorldNpc 所有 error 显式返回）
- ✅ 无新增全局变量
- ✅ 配置走打表流程（源文件在 RawTables/Json/Server/）
- ✅ 单元测试 12/12 通过
- ✅ `make build` 编译通过

## 2026-03-27 - task-04: Review 修复（第 2 轮）

### 修复问题

**CRITICAL（1 个）**：
1. **CreateDynamicBigWorldNpc 错误路径 entity 泄漏** — AddNpc/OnNpcCreated 失败时 entity 已创建但未清理。修复：AddNpc 失败时调用 `scene.RemoveEntity(entity.ID())`；OnNpcCreated 失败时先 `RemoveNpc` 再 `scene.RemoveEntity`

**HIGH（3 个）**：
1. **findSpawnPosition 安全生成点降级跳过有效性检查** — safeSpawnPoints 降级路径不检查水下和贴脸玩家。修复：遍历 safeSpawnPoints 时同样执行 oceanHeightY 过滤和 minPlayerDistSq 检查
2. **allocCfgId 回绕后可能与活跃 NPC 冲突** — nextCfgId 溢出回绕后分配到已占用 ID。修复：回绕后循环跳过 activeNpcs 中已占用的 ID
3. **findSpawnPosition 重试次数硬编码魔法数字 10** — 提取为 `const maxSpawnAttempts = 10`

### 合宪性自检
- ✅ 未触碰禁编辑区域
- ✅ 错误处理完整（entity 泄漏路径已修补 RemoveEntity）
- ✅ 无新增全局变量
- ✅ 单元测试全部通过
- ✅ `make build` 编译通过

## 2026-03-27 - task-04: Review 修复（第 3 轮）

### 修复问题

**HIGH（3 个）**：
1. **rand.Rand 线程安全注释** — `bigworld_ext_handler.go` 和 `bigworld_npc_spawner.go` 的 `rng` 字段添加注释"仅在 Scene goroutine 内使用，非并发安全"，防止未来维护者误用
2. **DespawnRadius 溢出防护** — `bigworld_npc_config.go` 新增 `DespawnRadius <= 10000` 上限校验，防止平方计算 float32 精度丢失
3. **测试断言不充分** — `bigworld_npc_config_test.go` 增加内容断言（AppearanceId/Weight/BodyParts/DespawnRadius/SpawnDensity/SpawnBatchSize/DespawnDelay），新增 4 个边界用例（despawn_radius 等值、spawn_density 为 0、despawn_delay 负数、despawn_radius 超上限）

**MEDIUM（3 个，顺手修复）**：
1. **SpawnDensity 未校验** — 新增 `SpawnDensity > 0` 校验
2. **DespawnDelay 未校验** — 新增 `DespawnDelay >= 0` 校验
3. **匿名函数可读性** — `bigworld.go` 中 `Infof` 参数的立即执行匿名函数提取为局部变量 `entityId`

### 合宪性自检
- ✅ 未触碰禁编辑区域
- ✅ 错误处理完整
- ✅ 无新增全局变量
- ✅ 单元测试 16/16 通过（含 4 个新增用例）
- ✅ `make build` 编译通过

ALL_FILES_IMPLEMENTED

---

## 2026-03-27 - task-08: 端到端集成联调

### 实现范围
两端（服务端 + 客户端）

### 新增文件
- `freelifeclient/.../NPC/Comp/BigWorldNpcEmotionComp.cs` — 情绪表现组件骨架（P0 空实现，缓存 emotionId，P1 接入表情动画）

### 修改文件
- `P1GoServer/servers/scene_server/internal/ecs/scene/scene_impl.go` — 新增 `case *common.CitySceneInfo` 分支：初始化 V2 NPC 管线 + BigWorldNpcSpawner + BigWorldNpcUpdateSystem
- `P1GoServer/servers/scene_server/internal/common/scene_type.go` — CitySceneInfo.GetNpcAIConfig 启用 EnableSensor（大世界 NPC 感知插件需要 SensorFeatureSystem）
- `P1GoServer/servers/scene_server/internal/ecs/system/traffic_vehicle/traffic_light_system.go` — 新增 GetJunctionState/GetTrafficLightSystem/GetJunctionTrafficLightState 便捷查询函数
- `freelifeclient/.../NPC/BigWorldNpcController.cs` — OnInit 添加 AddComp<EmotionComp>，OnDispose/ResetForPool 补充清理
- `freelifeclient/.../LaunchManager/State/GameInitialize.cs` — 注册 BigWorldNpcManager.CreateInstance()

### 关键决策
- 未创建 SceneImplI 接口（项目中不存在分离的场景实现类），改为在 TrafficLightSystem 上添加静态便捷函数 GetTrafficLightSystem/GetJunctionTrafficLightState，NavigationHandler 通过 Scene 参数直接查询
- CitySceneInfo.GetNpcAIConfig 同时启用 EnableSensor 和 EnableDecision，确保大世界 NPC 的 SensorFeatureSystem 也能注册
- NpcDataUpdate 路由无需修改——BigWorldNpcManager 已通过 DataManager.Npcs 轮询模式自动同步
- BigWorldNpcManager 注册在 GameInitialize 末尾（与 TownManagerOfManagers/SakuraManagerOfManagers 同级），DataManager 已先于其创建

### 测试情况
- `make build` 编译通过（15 个微服务全量编译）
- 客户端 using/类型/API 签名验证通过

### 合宪性自检
- ✅ YAGNI：仅实现 task-08 范围
- ✅ 未触碰禁编辑区域（proto 生成代码、配置生成代码）
- ✅ 服务端错误处理完整（log.Errorf/Warningf）
- ✅ 无新增全局变量
- ✅ Go 日志格式符统一 %v（修正了 %+v → 拆分字段）
- ✅ C# 日志无 $"" 插值（EmotionComp 用 + 拼接）
- ✅ C# EmotionComp 使用 MLog（非 Debug.Log）
- ✅ OnClear 正确清理引用
- ✅ Vector2/Vector3 alias 不需要（EmotionComp 未引用 FL.NetModule）
- ✅ CancellationToken 不需要（EmotionComp 无异步操作）

### 待办事项
（无）

## 2026-03-27 - task-08: Review 修复

### 修复问题

**CRITICAL（1 个）**：
1. **BigWorldNpcEmotionComp.OnClear 访问修饰符错误** — `public override void OnClear()` 与基类 `Comp` 的 `protected abstract void OnClear()` 不匹配，导致 CS0507 编译失败。修复：改为 `protected override void OnClear()`

### 合宪性自检
- ✅ 未触碰禁编辑区域
- ✅ 访问修饰符与基类一致
- ✅ `make build` 编译通过

ALL_FILES_IMPLEMENTED
