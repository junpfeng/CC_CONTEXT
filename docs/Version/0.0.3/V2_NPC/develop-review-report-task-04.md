═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.3
  审查文件：1 个（BigWorldNpcAnimationComp.cs）
  审查任务：task-04 · REQ-004 RightArm + AdditiveBodyExtra 层初始化
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ⚠️ | Line 3 `using Cysharp.Threading.Tasks` 已导入但整个文件未使用 UniTask/await，为无效导入 |
| 编译：命名空间 | ✅ | `FL.Gameplay.Modules.BigWorld` 与目录层级一致 |
| 编译：API 存在性 | ✅ | 所有 Animancer API、LoaderManager、ConfigLoader 调用符合项目既有模式 |
| 编译：类型歧义 | ✅ | Line 11-12 显式别名 `Vector2 = UnityEngine.Vector2`、`Vector3 = UnityEngine.Vector3`，无歧义 |
| 7.1 日志规范 | ✅ | 全部 MLog 调用使用 `?.Log()` + 字符串 `+` 拼接，无 `$""` 插值 |
| 7.2 错误处理 | ✅ | RightArm 回调显式检查 `obj == null` 并打印 Warning，`animancer == null` 时打印 Error 并提前返回 |
| 6.1 热路径零分配 | ✅ | `UpdateSpeedDrivenAnimation()` 使用阈值门控（AnimSpeedChangedThreshold），仅在变化超阈值时调用 SetSpeed |
| 4.1 异步编程 | ✅ | 使用 `LoaderManager.LoadAssetAsync` 回调模式，无裸 Thread 或 Unity 协程 |
| 1.1 YAGNI | ✅ | 仅实现 plan 要求的层初始化与 AvatarMask 加载，无多余功能 |
| OnClear 资源清理 | ✅ | `_rightArmMask`、`_rightArmLayer`、`_additiveBodyExtraLayer` 均在 OnClear 置 null |

### 服务端

本任务（task-04）仅涉及客户端文件，无服务端变更，跳过服务端审查。

---

## 二、Plan 完整性

### 已实现

- [x] `AnimancerLayers.RightArm`（index=1）层引用初始化（Line 70）
- [x] RightArm 初始 Weight=0（Line 81）
- [x] RightArm IsAdditive=false（Override 模式，默认值，符合 plan 要求）
- [x] `AnimancerLayers.AdditiveBodyExtra`（index=5）引用初始化（Line 75）
- [x] AdditiveBodyExtra IsAdditive=true（Line 76）
- [x] AdditiveBodyExtra 初始 Weight=0（Line 85）
- [x] Face 层初始 Weight=1（Line 86）
- [x] `LoadAvatarMasks()` 扩展：异步加载 RightArm AvatarMask，失败时降级无 Mask 运行（Lines 115-133）
- [x] Owner null 守卫（回调内 `if (Owner == null) return`）

### 遗漏

无。所有 plan 要求项均已实现。

### 偏差

- **Lines 116**：plan 任务描述使用 "RightArmAvatarMask" 作为 config key，代码使用 `ConfigEnum.SingleAssetType.RightArm`。
  - develop-log 已记录：开发者发现 `SingleAssetType.RightArm`（enum=4）已存在于 HoldItemData.cs，与项目其他动画组件（MonsterAnimationComp 等）模式一致。
  - 影响：低。代码有 else 分支 + Warning 日志降级，即使 config key 不存在也不会崩溃。
  - 结论：可接受的技术选择，建议确认配置表中该 key 对应资源路径正确。

---

## 三、边界情况

[MEDIUM] BigWorldNpcAnimationComp.cs:3 - 无效 using 导入
  场景: 全文件无 UniTask/async/await 用法，`using Cysharp.Threading.Tasks` 不被使用
  影响: 无编译错误，但引入无谓的命名空间污染，可能误导维护者认为此处有异步逻辑
  建议: 删除 Line 3 的 `using Cysharp.Threading.Tasks;`

---

## 四、代码质量

无 CRITICAL 安全问题。

**预存问题（task-04 未引入，记录供后续跟进）：**

[HIGH-预存] BigWorldNpcAnimationComp.cs:377 - 运行时修改 Unity 资产属性
  `state.Clip.wrapMode = WrapMode.Loop;` 直接修改 `AnimationClip` 资产实例的 wrapMode 属性。
  Unity 中 AnimationClip 为共享引用，此修改对所有使用该 Clip 的动画状态机均生效。
  该行为在 Editor 模式下会持久化（直到域重载），在构建中影响所有共享此 Clip 的 NPC。
  **注意：此为 task-04 之前的预存代码（PlayMoveWithCrossFade 方法），不计入本次 task-04 review 评分。**

[MEDIUM-预存] BigWorldNpcAnimationComp.cs:99-112 - Arms/UpperBody 回调缺少 null 检查
  Arms 和 UpperBody 的 `LoaderManager.LoadAssetAsync` 回调未检查 `obj == null`，
  与 task-04 新增的 RightArm 回调（有完整 null 检查）形成不一致。
  **注意：此为预存代码，task-04 引入了更严格的 RightArm 模式，暴露了既有不一致。**

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     0 个
  MEDIUM:   1 个（无效 using 导入，单行删除即可修复）

  结论: 通过（可提交，MEDIUM 问题可酌情修复）

  重点关注:
  1. 删除 Line 3 的 `using Cysharp.Threading.Tasks;`（1分钟内可修复）
  2. 确认配置表中 `SingleAssetType.RightArm` 对应的资源路径已填写正确
  3. 后续跟进 Line 377 的 `state.Clip.wrapMode` 预存问题（建议改用 AnimancerState 层级控制循环）
<!-- counts: critical=0 high=0 medium=1 -->
