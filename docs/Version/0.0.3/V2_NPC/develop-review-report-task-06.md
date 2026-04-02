═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.3
  Task：task-06（REQ-006 Timeline 支持）
  审查文件：3 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端（.cs 文件）

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | BigWorldNpcAnimationComp 有 `using UnityEngine.Timeline`、Vector3/Vector2 alias；ScenarioState/ScheduleIdleState using 齐全 |
| 编译：命名空间 | ✅ | 均在 `FL.Gameplay.Modules.BigWorld` namespace，与目录层级一致 |
| 编译：类型歧义 | ✅ | `using Vector2 = UnityEngine.Vector2; using Vector3 = UnityEngine.Vector3;` 已显式消解歧义 |
| 编译：API 存在性 | ✅ | `PlayTimeline(TimelineAsset)`、`StopTimeline()`、`AnimationManager.*` 均可在基类/框架中确认 |
| 1.1 YAGNI | ✅ | 仅实现 plan 要求的 Timeline 接口，无额外功能 |
| 1.2 框架优先 | ✅ | 复用 LoaderManager.LoadAssetAsync、AnimationManager、base.PlayTimeline(TimelineAsset) |
| 2.x Manager 架构 | ✅ | 本任务无新增 Manager |
| 3.x 事件驱动 | ✅ | OnEnable/OnDisable 中 UnListen+Listen 配对，无泄漏 |
| 4.x 异步编程 | ✅ | 异步加载均通过 LoaderManager 回调，非 async void |
| 5.x 网络通信 | ✅ | 纯动画层，无网络调用 |
| 6.x 内存性能 | ✅ | Timeline 字典复用不重建；UpdateSpeedDrivenAnimation 有阈值保护避免每帧 GC |
| 7.1 日志规范 | ✅ | 所有 MLog 均用 `+` 拼接，无 `$""` 插值（已扫描 3 个文件） |
| 7.2 错误处理 | ✅ | 资源加载失败均有 Warning 日志 + 静默降级，无空 catch |
| 7.3 命名规范 | ✅ | 字段 `_camelCase`，公共方法 PascalCase |
| 8.x 资源加载 | ✅ | LoaderManager.LoadAssetAsync 异步加载，无同步加载 |
| 9.x 状态机 | ✅ | 状态封装于 FsmState 子类 |

### 服务端（.go 文件）
本任务为纯客户端改动，无 Go 文件变更，跳过。

---

## 二、Plan 完整性

### 已实现
- [x] `_replaceTimelines: Dictionary<ConfigEnum.TransitionKey, TimelineAsset>` 字段（AnimationComp.cs:65）
- [x] `ChangeAnimationsByGroup()` 扩展加载 config.timelines（AnimationComp.cs:240-246）
- [x] `PlayTimeline(ConfigEnum.TransitionKey key)` 接口（AnimationComp.cs:492-503）
- [x] `StopTimeline()` 接口（AnimationComp.cs:509-519）
- [x] `OnRemove()` / `OnClear()` 中的 `_replaceTimelines.Clear()`（AnimationComp.cs:717、739）
- [x] BigWorldNpcScenarioState — Scenario(19) 状态实现
- [x] BigWorldNpcScheduleIdleState — ScheduleIdle(20) 状态实现

### 偏差（已记录）
- BigWorldNpcScenarioState:15 — `[偏离 plan]` 注释已说明：plan 要求从 `NpcCfgId` 查配置，实际改用 `NpcCreatorId` 查 `ConfigLoader.NpcMap`，原因是 `HumanBaseData` 无 `NpcCfgId` 字段，且 `NpcCfg` 无 `scenario_default_anim_key` 字段（用 `specialIdle` 替代）。偏离已记录，可接受。

---

## 三、边界情况与问题

### [HIGH-1] BigWorldNpcScenarioState.cs:35 / BigWorldNpcScheduleIdleState.cs:59 — 修改共享 AnimationClip 资源的 wrapMode

**场景：** NPC 进入 Scenario/ScheduleIdle 状态，animKey 对应的 Clip 非循环时执行：
```csharp
state.Clip.wrapMode = WrapMode.Loop;
```

**影响：** `state.Clip` 是通过 YooAsset 加载的共享 `AnimationClip` 资产。在运行时修改其 `wrapMode` 属性会污染该资产的所有引用方（其他 NPC 实例、其他状态中也使用同一 Clip 的地方）。若 100+ NPC 共用同一 specialIdle Clip，第一个 NPC 的 OnEnter 修改后，后续所有 NPC 和其他动画系统使用该 Clip 时均会受到影响。

**建议：** 将 wrapMode 设置到 Animancer 状态对象上而非 Clip 资产上：`state.WrapMode = WrapMode.Loop`（Animancer `AnimancerState` 支持 WrapMode 设置，不影响原始 Clip）。

---

### [HIGH-2] BigWorldNpcAnimationComp.cs:714 — `OnRemove()` 未调用 `base.OnRemove()`

**场景：** 组件从 Actor 上移除（NPC 死亡、回池等）时调用 `OnRemove()`：
```csharp
public override void OnRemove()
{
    _replaceTransitions.Clear();
    _replaceTimelines.Clear();
    _faceClips.Clear();
    // 缺少：base.OnRemove()
}
```

**影响：** `AnimationComp` 基类的 `OnRemove()` 若负责释放 YooAsset 资产句柄或清理 Animancer 图，则不调用会导致资产引用泄漏或 Animancer 状态残留。对比 `OnClear()` 末行有 `base.OnClear()` 的正确写法，`OnRemove` 明显遗漏。

**建议：** 在末行添加 `base.OnRemove()`。

---

## 四、代码质量

### [MEDIUM-1] BigWorldNpcAnimationComp.cs:509 — `StopTimeline()` 使用 `new` 关键字且含冗余逻辑

```csharp
public new void StopTimeline()
{
    if (_director != null) { _director.Stop(); }
    if (_animancer != null) { _animancer.enabled = true; }  // 冗余
}
```

**分析：** 基类 `StopTimeline()` 非 virtual，子类被迫用 `new` 隐藏，这是已知限制，可接受。但 `_animancer.enabled = true` 存疑：基类 `PlayTimeline(TimelineAsset)` 并未 disable `_animancer`（代码确认），因此该行是无效操作。若未来基类 PlayTimeline 增加 disable 逻辑，子类行为才生效——当前是无害但具误导性的冗余代码。

**建议：** 保留 `new` 关键字（无法改为 override），但添加注释说明为何与基类实现不同，或移除冗余的 `_animancer.enabled = true`（若基类不 disable，子类不需要 enable）。

---

### [MEDIUM-2] BigWorldNpcScenarioState.cs:57 — `OnExit` 中调用 `Stop(int)` 的层含义不明

```csharp
Owner.AnimationComp?.Stop((int)AnimancerLayers.Base);
```

**分析：** `Stop(int)` 是按层号停止，与 `Stop(TransitionKey)` 按动画 Key 停止语义不同。若 Base 层同时还有其他状态在播放（如 IdleState 转入 ScenarioState 后又立即切换），OnExit 强制停止整个 Base 层可能中断后继状态的过渡动画。

**建议：** 考虑改为 `Stop(animKey)` 按具体动画 Key 停止，避免影响 Base 层其他动画。

---

## 五、总结

```
  CRITICAL: 0 个
  HIGH:     2 个（强烈建议修复）
  MEDIUM:   2 个（建议修复，可酌情跳过）

  结论: 需修复后再提交

  重点关注:
  1. [HIGH-1] state.Clip.wrapMode 直接修改共享资产——200 NPC 场景下有潜在动画状态污染风险
  2. [HIGH-2] OnRemove() 缺少 base.OnRemove()——可能导致资产句柄泄漏
```

<!-- counts: critical=0 high=2 medium=2 -->
