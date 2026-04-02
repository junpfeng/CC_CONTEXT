═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.3
  任务：task-08 — REQ-008 击中反应动画
  审查文件：2 个（BigWorldNpcAnimationComp.cs、BigWorldNpcController.cs）
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | 包含 `UnityEngine`、`FL.NetModule`（HitData 所在包）、Vector2/Vector3 alias 完整 |
| 编译：命名空间 | ✅ | `namespace FL.Gameplay.Modules.BigWorld` 与目录层级一致 |
| 编译：API 存在性 | ✅ | `HitData` 定义于 `scene.pb.cs`（Proto 生成代码），类型合法；`_upperBodyLayer.Play`/`StartFade` 均为合法 Animancer API |
| 编译：类型歧义 | ✅ | `Vector2 = UnityEngine.Vector2`、`Vector3 = UnityEngine.Vector3` 别名已消歧 |
| 1.1 YAGNI | ✅ | 新增字段/方法均为 plan 明确要求，无多余功能 |
| 1.2 框架优先 | ✅ | 使用 `LoaderManager.LoadAssetAsync` 加载资源，符合框架规范 |
| 3.3 订阅配对 | ✅ | `OnEnable` 订阅 `MonsterStateUpdate`，`OnDisable` 取消订阅；`OnEnable` 内先 `UnListen` 再 `Listen` 防止重复订阅 |
| 4.1-4.3 异步编程 | ✅ | 未引入新的异步方法，`LoadHitClip` 使用回调模式（非 async/await），无协程 |
| 6.1-6.3 内存性能 | ✅ | `OnUpdate` 热路径仅含 bool/float 运算，命中才执行恢复；`_hitClip` 预加载缓存，OnHit 零分配 |
| 7.1 日志规范 | ✅ | 所有日志使用 `MLog.Warning?.Log` / `MLog.Error?.Log` + `+` 拼接，无 `$""` 插值（符合 lesson-003）|
| 7.2 错误处理 | ✅ | `LoadHitClip` 加载失败时 `_hitClip` 为 null，`OnHit` 中有 null 检查静默跳过 |
| 7.3 命名规范 | ✅ | 私有字段 `_camelCase`，常量 `PascalCase`，方法 `PascalCase` |
| 8.1-8.2 资源加载 | ✅ | 通过 `LoaderManager.LoadAssetAsync` 异步加载，无同步加载 |

### 服务端

本次 task-08 为纯客户端实现，**无 Go 文件变更**，服务端合宪性审查不适用。

---

## 二、Plan 完整性

### 已实现

- [x] `_isInHitReaction`、`_hitReactionTimer`、`_isDead` 字段 — 符合 plan 字段定义
- [x] `OnHit(HitData hitData)` 公共接口 — 死亡检查、计时器设置均已实现
- [x] `Update()` 击中反应计时器逻辑 — 正确使用 `deltaTime` 参数而非 `Time.deltaTime`
- [x] `RestoreUpperBodyAnim()` 私有方法 — `StartFade(0, CrossFadeDuration)` 归零权重
- [x] `OnNpcStateUpdate` + `OnEnable`/`OnDisable` 订阅机制检测 Death 状态
- [x] `ResetForPool()` 重置 3 个字段（`_isDead`/`_isInHitReaction`/`_hitReactionTimer`），保留资源缓存
- [x] `BigWorldNpcController.ResetForPool()` 调用 `AnimationComp?.ResetForPool()`
- [x] `OnClear()` 清理所有新增字段（含 `_hitClip = null`）
- [x] 资源缺失时静默降级，不影响其他层

### 遗漏 / 偏差

- [ ] **OnHit 中 UpperBody 层权重激活缺失**（见三、HIGH-1）— plan 要求 CrossFade 播放击中 Clip，且 `RestoreUpperBodyAnim` 明确将权重淡出到 0，隐含击中期间权重应为非零，但实现未在 `Play()` 前调用 `StartFade(1f, ...)`

---

## 三、边界情况

[HIGH] `BigWorldNpcAnimationComp.cs:340-344` — `OnHit()` 未激活 UpperBody 层权重，击中动画实际不可见

  场景：NPC 处于 Idle / Walk / Combat 等非 Flee 状态时（即所有非 Flee 状态），UpperBody 层初始化权重为 0（OnAdd:117 行），`OnHit` 仅调用 `_upperBodyLayer.Play(_hitClip, CrossFadeDuration)` 而未调用 `_upperBodyLayer.StartFade(1f, CrossFadeDuration)` 激活层权重

  影响：击中动画在视觉上完全不可见（权重=0，Animancer 不将该层混入最终姿态）；功能验收标准"截图确认 UpperBody 层播放击中动画"无法通过

  佐证：`SetAdditiveBodyOverlay(NpcState.Flee)` 在激活 UpperBody 前显式调用 `_upperBodyLayer.StartFade(1f, ...)`；`RestoreUpperBodyAnim()` 调用 `StartFade(0, ...)` 归零，明确暗示击中期间权重应为非零

  建议：在 `_upperBodyLayer.Play(_hitClip, CrossFadeDuration)` 之前添加 `_upperBodyLayer.StartFade(1f, CrossFadeDuration)`

[MEDIUM] `BigWorldNpcAnimationComp.cs:350-354` — `RestoreUpperBodyAnim()` 与 Flee 状态 UpperBody overlay 共享同一层

  场景：NPC 处于 Flee 状态（`SetAdditiveBodyOverlay(Flee)` 已将 UpperBody 权重设为 1），此时触发 OnHit，约 1s 后 `RestoreUpperBodyAnim()` 将 UpperBody 权重归零，导致 Flee 状态的上半身叠加动画被意外移除

  影响：Flee 状态下被击中后，上半身慌张姿态消失，与逃跑状态不符；视觉表现异常

  建议：`RestoreUpperBodyAnim` 中记录 _upperBodyLayer 击中前的权重值，恢复时还原（或与 task-07 协商 UpperBody 层使用规范）

[MEDIUM] `BigWorldNpcAnimationComp.cs:335` — `OnHit(HitData hitData)` 参数 `hitData` 完全未使用

  场景：任何时候调用 OnHit

  影响：方法签名接受的数据（伤害值、击中位置、身体部位等）未用于区分不同击中效果，不满足 plan 中 `IsStrongHit` / `BodyPart` 等字段的潜在扩展需求；代码可读性略低

  建议：若当前无差异化需求，可将参数改为 `_`（弃用标记）或添加 `// 预留参数，后续用于差异化击中效果` 注释；或在 `IsStrongHit` 为 true 时使用更长的 timer

[MEDIUM] `BigWorldNpcAnimationComp.cs:360-365` — `ResetForPool()` 未重置 `_pendingEmotion`

  场景：NPC 对象池复用时，若上一生命周期中 `_pendingEmotion != EmotionType.None`（面部 Clip 加载中途被回收），`_pendingEmotion` 值会保留到下一个 NPC

  影响：由于 `_isFaceClipsReady` 在对象池复用时为 true（面部 Clip 保留），`_pendingEmotion` 不会被自动触发播放，实际无功能性影响；但属于不完整的状态清理，增加维护成本

  建议：在 `ResetForPool()` 中添加 `_pendingEmotion = EmotionType.None;`

---

## 四、代码质量

安全检查：无 CRITICAL 安全问题，无硬编码密钥/Token，无客户端直接修改游戏状态

[HIGH] 同上（三、HIGH-1，击中动画不可见属功能性缺陷）

质量检查：
- 函数长度：所有新增方法均在 20 行以内 ✅
- 嵌套深度：最深 3 层（`if _isDead + if _hitClip null + 逻辑`）✅
- 魔法数字：`_hitReactionTimer = 1f` 无命名常量 — 可接受（plan 明确为 1s，且只有一处）

可维护性：
- 新增字段和方法均有 XML 注释 ✅
- `OnEnable`/`OnDisable` 模式与现有代码风格一致 ✅

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     1 个（必须修复）
  MEDIUM:   3 个（建议修复）

  结论: **需修复后再提交**（HIGH-1 导致核心功能不可见，无法通过视觉验收）

  重点关注：
  1. [HIGH] `OnHit()` 缺少 `_upperBodyLayer.StartFade(1f, CrossFadeDuration)` — 击中动画在 99% 场景下不可见
  2. [MEDIUM] `RestoreUpperBodyAnim` 与 Flee overlay 共享 UpperBody 层，恢复时会清除 Flee 状态表现
  3. [MEDIUM] `hitData` 参数未使用，建议添加注释或处理 `IsStrongHit` 差异化

<!-- counts: critical=0 high=1 medium=3 -->
