═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC — task-07 REQ-007 战斗/警惕/逃跑状态动画表现
  版本：0.0.3
  审查文件：2 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | `Vector2/Vector3 = UnityEngine.*` alias 消解歧义；using 列表覆盖所有引用 |
| 编译：命名空间 | ✅ | `namespace FL.Gameplay.Modules.BigWorld` 与目录层级一致 |
| 编译：API 存在性 | ✅ | `AnimancerLayer.StartFade`、`ConfigEnum.AnimationStatus.NpcWpn01`、`NpcState` 枚举值均确认存在 |
| 编译：类型歧义 | ✅ | Vector2/Vector3 均有 alias，FL.NetModule + UnityEngine 共存无歧义 |
| 1.1 YAGNI | ✅ | 4 个新增公共方法均在 plan REQ-007 范围内；未添加计划外功能 |
| 1.2 框架优先 | ✅ | 使用 `AnimancerLayer.StartFade`、`ChangeAnimationsByGroup` 等已有框架 API |
| 1.4 MonoBehaviour 节制 | ✅ | 无误用 MonoManager |
| 2.x Manager 架构 | ✅ | 非 Manager 类，不涉及 |
| 3.x 事件驱动 | ✅ | `DataSignalType.MonsterStateUpdate` 订阅在 OnEnable/OnDisable 配对 |
| 4.x 异步编程 | ⚠️ | AnimationComp.cs 第 3 行 `using Cysharp.Threading.Tasks` 存在但文件中无 async/UniTask 调用，属未用 using（见 MEDIUM-3） |
| 5.x 网络通信 | ✅ | 无网络调用，状态由服务端驱动，客户端只处理表现 |
| 6.x 内存性能 | ✅ | 无热路径分配；`AnimSpeedChangedThreshold` 阈值避免每帧 SetSpeed 调用 |
| 7.1 日志 | ✅ | 全部使用 MLog；grep 验证 0 处 `$""` 插值，全部使用 `+` 拼接 |
| 7.2 错误处理 | ✅ | 资源加载失败均有 Warning 或静默跳过说明；null 检查完整 |
| 7.3 命名规范 | ✅ | `_hasAnimationGroupOverride`（_camelCase）、`SetAnimationGroup`（PascalCase）等全部合规 |
| 8.x 资源加载 | ✅ | 无新增同步加载；现有 LoaderManager.LoadAssetAsync 调用均有 owner null guard |
| 9.x 状态机 | ✅ | 使用 GuardedFsm 框架，无裸 bool 标记链 |
| 宪法：测试要求 | ❌ | 新增功能未附带单元/集成测试（见 HIGH-2） |

### 服务端

无 Go 文件变更，跳过服务端审查。

---

## 二、Plan 完整性

### 已实现

- [x] `SetAnimationGroup(NpcState.Combat)` → 切换到 NpcWpn01 动画组 ✅
- [x] `SetAdditiveBodyOverlay(Scared/Panicked)` → AdditiveBodyDefault 层权重 1.0 ✅
- [x] `SetAdditiveBodyOverlay(Flee)` → UpperBody 层权重 1.0 ✅
- [x] `SetAdditiveBodyOverlay(Watch/Investigate/Curious/Nervous/Angry)` → AdditiveBodyDefault 层权重 0.5 ✅
- [x] `ClearAdditiveBodyOverlay()` + `ClearAnimationGroupOverride()` 退出覆盖状态时清除 ✅
- [x] `HandleServerState` 在 FsmComp 统一管理状态进出逻辑 ✅
- [x] `_hasAnimationGroupOverride` 防止 PlayMoveWithCrossFade 覆盖 Combat 动画组 ✅
- [x] `ResetForPool` 清理叠加层权重，防止对象池复用残留 ✅

### 偏差

- `BigWorldNpcAnimationComp.cs:410-435` — plan REQ-007 描述"播放对应恐惧/警惕动画"，实际实现仅调整叠加层权重（无 Clip 加载），无实际动画内容。开发日志注明"满足验证标准（Weight > 0）"，属已记录偏差（见 MEDIUM-1）

---

## 三、边界情况

[HIGH] BigWorldNpcAnimationComp.cs:353-356 — UpperBody 层在 Flee 与 HitReaction 之间存在状态冲突
  场景: NPC 处于 Flee 状态时（SetAdditiveBodyOverlay 将 UpperBody 权重设为 1.0），同时收到 OnHit 事件
  流程: OnHit → _upperBodyLayer.Play(_hitClip) → 1 秒后 RestoreUpperBodyAnim() → _upperBodyLayer.StartFade(0) → UpperBody 权重归零
  影响: NPC 在 Flee 状态下被击中后，约 1 秒内 Flee 的 UpperBody 叠加效果消失，视觉上 Flee 动画表现丢失，直到下一次服务端状态切换才能恢复。RestoreUpperBodyAnim 不感知当前覆盖状态，无条件将 UpperBody 权重归零；SetAdditiveBodyOverlay(Flee) 与 HitReaction 共用同一层未做冲突检测。

---

## 四、代码质量

[HIGH] 无测试覆盖（宪法违规）
  说明: 工作空间宪法要求"新增功能必须附带对应的单元测试或集成测试"。task-07 新增 4 个公共接口（SetAnimationGroup/ClearAnimationGroupOverride/SetAdditiveBodyOverlay/ClearAdditiveBodyOverlay）和 FsmComp 的 HandleServerState 逻辑，均无测试。
  开发日志注明为已知缺陷（BigWorld 模块无 NUnit 测试程序集，Animancer 运行时依赖难以在无 MonoBehaviour 环境中 mock），但违规事实存在。
  影响: 宪法违规；回归行为无自动验证保障。

[MEDIUM-1] BigWorldNpcAnimationComp.cs:410-435 — SetAdditiveBodyOverlay 激活层权重但无 Clip 内容
  问题: Scared/Panicked/Watch 等状态仅调用 `_additiveBodyLayer.StartFade(1f/0.5f)`，但 AdditiveBodyDefault 层无 Clip 加载，权重淡入后无实际动画混合效果，对 200 NPC 而言 CPU 执行层混合计算但视觉无输出。
  建议: 属已记录 plan 偏差，建议在 plan 中正式标记并纳入后续 Clip 资源规划；或在代码注释中明确说明"此版本为权重占位，等待美术提供 Clip 后激活"

[MEDIUM-2] BigWorldNpcAnimationComp.cs:363-371 — ResetForPool 未调用 ClearAnimationGroupOverride，动画组单帧残留
  问题: ResetForPool 将 `_hasAnimationGroupOverride = false`，但未调用 `ChangeAnimationsByGroup(NpcWpn00)` 重置转换表。若上一 NPC 处于 Combat 状态，`_replaceTransitions` 中仍保留 NpcWpn01 的转换配置，直到首帧 PlayMoveWithCrossFade 执行后才被修正。
  影响: 池化复用后单帧窗口内 NPC 持有 NpcWpn01 动画映射，视觉上极难察觉，但逻辑上存在状态泄漏。

[MEDIUM-3] BigWorldNpcAnimationComp.cs:3 — 未使用的 using 指令
  问题: `using Cysharp.Threading.Tasks;` 存在但文件中无任何 async/await/UniTask 调用。
  影响: 代码整洁度问题，不影响编译，但增加阅读者误判（误以为存在异步逻辑）。

---

## 五、总结

  CRITICAL: 0 个（必须修复）
  HIGH:     2 个（强烈建议修复）
  MEDIUM:   3 个（建议修复，可酌情跳过）

  结论: 需修复后再提交

  重点关注:
  1. [HIGH] UpperBody 层 Flee/HitReaction 冲突：Flee 状态下被击中后 Flee 动画叠加丢失，是 task-07 引入的可见视觉 bug
  2. [HIGH] 宪法要求新增功能必须有测试，当前 4 个公共接口均无测试覆盖
  3. [MEDIUM] AdditiveBodyOverlay 无 Clip 内容：权重 > 0 但无实际动画混合效果，属 plan 偏差，建议在 plan 中显式标记

<!-- counts: critical=0 high=2 medium=3 -->
