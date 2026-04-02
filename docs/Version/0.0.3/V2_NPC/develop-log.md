# 开发日志：V2_NPC

## 2026-03-28 - task-01 REQ-001 性别Prefab选择

### 修改文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs`
  — 新增 `public const NPC_PREFAB_MALE / NPC_PREFAB_FEMALE` 路径常量；新增 `public static SelectPrefabByGender(uint gender)` 方法，Female(2)→女性prefab，其余→男性prefab兜底
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Managers/BigWorldNpcManager.cs`
  — `PrewarmPoolAsync` 改为同时预热男/女两个 prefab 池；`AcquireFromPool` 增加 `prefabPath` 参数；`SpawnNpc` 读取 `npcData.BaseInfo?.Gender` 并调用 `SelectPrefabByGender` 选择正确路径

### 关键决策
- 任务描述为"私有方法"，但 `SelectPrefabByGender` 必须是 `public static`，因为实例化在 `BigWorldNpcManager.SpawnNpc` 中，控制器本身不做实例化；将方法放在 `BigWorldNpcController` 作为统一的语义中心（路径常量+选择逻辑集中）
- `BigWorldNpcAppearanceComp.cs` 已有 `_bodyPartsMap.SetGender()` 处理外观性别，Prefab 引用不在此文件，无需修改
- 女性 prefab 预热数量设为 `PoolSize / 2 = 10`，参考 MonsterManager 模式

### 测试情况
- 编译：类型检查通过（uint Gender、public static方法、同命名空间引用）
- TownNpcController 无任何变动（grep 确认）
- 无 $"" 日志插值（规范合规）

ALL_FILES_IMPLEMENTED

---

## 2026-03-28 - task-05 REQ-005 Face 层 + 面部动画 + EmotionComp 联动

### 修改文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs`
  — 新增 `_faceMask / _faceClips / _isFaceClipsReady / _pendingEmotion` 字段
  — `LoadAvatarMasks()` 中添加 `SingleAssetType.Face` 异步加载并绑定到 `_faceLayer.Mask`
  — 新增 `LoadFaceClips()` 预加载 Angry/Happy/Sad/Idle 四个面部 Clip
  — 新增 `IsFaceClipsReady` 属性
  — 新增 `PlayFaceAnim(EmotionType)` 接口：CrossFade 0.2s 播放，未加载完成时缓存到 `_pendingEmotion`，Clip 缺失时静默跳过
  — `OnClear()` 清理所有新增字段；`OnRemove()` 清理 `_faceClips`
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcEmotionComp.cs`
  — 新增 `EmotionType` 枚举（None/Angry/Happy/Sad/Idle，值 0~4），定义在命名空间级别
  — `OnAdd()` 中获取 `BigWorldNpcAnimationComp` 引用（AnimationComp 先于 EmotionComp 注册，安全）
  — `UpdateEmotion()` 将 `int emotionId` 强转 `EmotionType`，调用 `_animationComp.PlayFaceAnim()`
  — `ResetEmotion()` 调用 `PlayFaceAnim(EmotionType.None)` 恢复 FaceIdle
  — `OnClear()` 清理 `_animationComp` 引用

### 关键决策
- `EmotionType` 枚举定义在 `BigWorldNpcEmotionComp.cs` 文件中（同命名空间，两文件均可访问，无需新建文件）
- `PlayFaceAnim(None)` 内部映射到 `EmotionType.Idle` Clip（Clip_Face_Idle），回归中性面部状态
- 面部 Clip 加载计数器 `_faceClipsLoadedCount`：4 个 Clip 回调均到达后标记 `_isFaceClipsReady`，含失败项也计数（失败静默跳过），保证状态机不卡死
- `capturedEmotion` 局部变量用于 lambda 闭包捕获，虽然 C# 5+ foreach 已按迭代作用域，显式捕获更清晰
- 资源路径与 TownNpcAnimationComp 保持一致：`ArtResources/Animation/Human/Face/Clip_Face_*`

### 测试情况
- 编译自检：EmotionType 同命名空间可访问，所有 API 已在 TownNpcAnimationComp 验证
- 日志全部用 `+` 拼接，无 `$""` 插值（规范合规）
- Face Weight 在 OnAdd 中已设为 1（继承自 task-04），本 task 不修改权重

ALL_FILES_IMPLEMENTED

---

## 2026-03-28 - task-03 REQ-003 ScenarioState + ScheduleIdleState

### 新增文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcScenarioState.cs`
  — 继承 FsmState<BigWorldNpcController>；OnEnter 从 ConfigLoader.NpcMap[MonsterInfo.NpcCreatorId].specialIdle 取动画 Key，Play 失败则降级播放 BaseMove 并打 Warning；OnUpdate 无逻辑；OnExit Stop Base 层
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcScheduleIdleState.cs`
  — 继承 FsmState<BigWorldNpcController>；OnEnter 优先播放 specialIdle，Key 不存在时回退 BaseMove Idle；OnUpdate 无逻辑；OnExit Stop Base 层

### 修改文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs`
  — serverStateMap 中 Scenario=19 改为 BigWorldNpcScenarioState；ScheduleIdle=20 改为 BigWorldNpcScheduleIdleState

### 关键决策（偏离 plan）
- plan 要求从 NpcData.BaseInfo.NpcCfgId 查配置，但 HumanBaseData 无 NpcCfgId 字段；改用 NpcData.MonsterInfo.NpcCreatorId（MonsterAnimationComp 同样使用此字段）
- plan 要求读 scenario_default_anim_key，NpcCfg（Npc 类）无此字段；最接近的是 specialIdle（特殊待机动画），两文件均已在注释中标记偏离
- ScheduleIdleState 复用 specialIdle 作为日程待机动画源，无 Warning 日志（无法获取时静默降级）

### 测试情况
- 编译自检：using 与现有 BigWorldNpcIdleState 对齐；ConfigLoader、LogModule.BigWorldNpc、AnimancerLayers 均在正确命名空间
- 无 $"" 日志插值（规范合规）
- FsmComp 中 Scenario/ScheduleIdle 映射已从 IdleState 切换为专属状态

ALL_FILES_IMPLEMENTED

---

## 2026-03-28 - task-03 fix-round-2 CRITICAL 修复

### 修复内容
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs`
  — MoveMode 守卫条件补充排除 `BigWorldNpcScenarioState` 和 `BigWorldNpcScheduleIdleState`
  — 修复前：NPC 到达目的地时 MoveComp 将 CurrentMode 切为 Idle，守卫仅排除 TurnState，ScenarioState/ScheduleIdleState 会被 IdleState 立即覆盖
  — 修复后：三个状态均受守卫保护，MoveMode 变化不打断 Scenario/ScheduleIdle 动画

### 未修复（MEDIUM，非强制）
- PlayBaseIdle 方法两文件重复（DRY 问题）：当前不影响功能，后续统一时提取
- Clip.wrapMode 修改共享资产：与现有 IdleState 一致，记录为技术债
- 缺少集成测试：后续补充
