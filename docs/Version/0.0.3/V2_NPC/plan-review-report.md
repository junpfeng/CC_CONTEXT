# Plan Review 报告

**功能**: 大世界 V2 NPC 表现力对齐 (V2_NPC)
**版本**: 0.0.3
**Review 日期**: 2026-03-28

---

## 📊 总评

| 维度 | 评级 | 问题数 |
|------|------|--------|
| 需求覆盖度 | ⚠️ 有遗漏 | 2 |
| 边界条件 | ⚠️ 有遗漏 | 3 |
| 协议设计 | ✅ 完善 | 0 |
| 服务端设计 | ✅ 完善 | 0 |
| 客户端设计 | ❌ 严重缺失 | 3 |
| 安全防滥用 | ✅ 完善 | 0 |
| 可测试性 | ⚠️ 有遗漏 | 2 |

**总体评价**：plan 整体结构清晰，协议和服务端无变动的决策正确；但存在一个根本性的 Critical 错误——plan 中的动画层索引表与代码中的 AnimancerLayers 枚举实际定义完全不一致，实现者若按 plan 的层号表操作将产生错误的层初始化代码。此外 ScenarioState 的动画 Key 数据来源、对象池状态重置两项实现阻塞点也未解决。

---

## 🔴 必须修复（Critical）

### C1: AnimancerLayers 枚举实际值与 plan 层级表完全不符

- **位置**: `plan/client.json` → `animancer_layers_after` 表格
- **问题**: plan 的层级表显示 RightArm=7、AdditiveBodyExtra=8，但代码中 `AnimancerLayers` 枚举实际定义为：
  ```
  Base=0, RightArm=1, UpperBody=2, Arms=3,
  AdditiveBodyDefault=4, AdditiveBodyExtra=5,
  AdditiveUpperBody=6, AdditiveArms=7, Face=8
  ```
  （定义位置：`Assets/Scripts/Tools/MEditor/MEditorCore/Runtime/Character/HoldItemData.cs`）

  plan 中 "原7层+新2层=9层" 的假设也是错误的：枚举已有 9 个值（0-8），RightArm(1) 和 Face(8) 本就在枚举中。

- **影响**: 实现者按 plan 的层号表初始化动画层会产生完全错误的层顺序，导致 RightArm 层（实际=1）和 AdditiveBodyExtra 层（实际=5）挂载到错误的索引位置，动画叠加逻辑全部失效。测试用例 "确认初始化后 ≥ 9 层" 也因基数假设错误而无法正确验证。

- **建议**: 将 `animancer_layers_after` 表格替换为以下正确内容，并以此为实现基准：

  | 枚举值 | Index | Name | BlendMode | InitWeight | 说明 |
  |--------|-------|------|-----------|------------|------|
  | AnimancerLayers.Base | 0 | Base | Override | 1 | 速度驱动 Walk/Run 混合 |
  | AnimancerLayers.RightArm | **1** | RightArm | Override | 0 | 右手持物（REQ-004 确认已在枚举中）|
  | AnimancerLayers.UpperBody | 2 | UpperBody | Override | 0 | 上半身/击中反应 |
  | AnimancerLayers.Arms | 3 | Arms | Override | 0 | 手臂 |
  | AnimancerLayers.AdditiveBodyDefault | 4 | AdditiveBodyDefault | Additive | 0 | 全身叠加（恐惧/恐慌）|
  | AnimancerLayers.AdditiveBodyExtra | **5** | AdditiveBodyExtra | Additive | 0 | 额外全身叠加（REQ-004）|
  | AnimancerLayers.AdditiveUpperBody | 6 | AdditiveUpperBody | Additive | 0 | 上半身叠加 |
  | AnimancerLayers.AdditiveArms | 7 | AdditiveArms | Additive | 0 | 手臂叠加 |
  | AnimancerLayers.Face | **8** | Face | Override | 1 | 面部表情（REQ-005）|

  实现任务应改为：确认 BigWorldNpcAnimationComp 已初始化上述哪些层，对缺失层调用 `animancer.Layers[AnimancerLayers.XXX].SetMask()` 补齐，不需要"新增两层"。测试用例也应改为验证具体层的 BlendMode 和初始 Weight，而非层数。

---

### C2: ScenarioState 动画 Key 数据来源在实现层面是阻塞点

- **位置**: `plan/flow.json` → 场景点行为流程；`plan/client.json` → `BigWorldNpcScenarioState` 实现
- **问题**: NpcState 枚举仅携带状态值（Scenario=19），不携带任何额外数据。plan 说 Key "从 _controller.NpcData 或 _fsmComp.ScenarioConfig 读取"，且 feature.json 明确标注 "[待确认]" 但 plan 没有给出明确答案。服务端 server.json 中的帧同步字段列表也没有动画 Key 字段。若 NpcData 中无此字段，ScenarioState 将没有任何动画 Key 可读，只能永远回退 Idle——功能实质失效。

- **影响**: REQ-003 核心功能（播放场景点指定动画）无法实现，ScenarioState 与 IdleState 行为一致，需求失效。

- **建议**:
  1. 实现前先用 Grep 搜索现有 NpcData / NpcSyncData 数据结构，确认是否有 `ScenarioAnimKey`、`animKey` 或类似字段
  2. 若无：方案A——ScenarioState 固定播放配置表中 `NpcScenarioConfig` 的默认 Key（按 NPC 的 scenario_point_id 查表）；方案B——使用已有字段（如 BehaviorState/ExtraInfo）携带 Key
  3. 在 plan 中明确指定数据来源和读取路径（具体字段名），消除 "或" 的歧义

---

### C3: 对象池复用时新增字段未在 ResetForPool 中重置

- **位置**: `plan/client.json` → `BigWorldNpcAnimationComp` 变更列表
- **问题**: plan 为 AnimationComp 新增了 `_isDead`、`_isInHitReaction`、`_hitReactionTimer` 等字段，但未在 ResetForPool 中重置这些字段。现有代码的 ResetForPool 存在于多个 Comp 中（BigWorldNpcAnimationComp、FsmComp、MoveComp 等），但 plan 没有指定新字段的清理逻辑。

- **影响**:
  - 死亡 NPC 归还对象池后复用：`_isDead=true` 持久，该 NPC 永久不触发击中反应（REQ-008 失效）
  - `_isInHitReaction=true` 若在归还时未重置，复用的 NPC 会进入击中冻结状态
  - `_faceClips` 字典在复用时是否需要清空并重新加载？plan 未说明

- **建议**: 在 `BigWorldNpcAnimationComp` 的 ResetForPool 方法中（或由 Controller.ResetForPool 触发的清理链）添加以下重置：
  ```csharp
  _isDead = false;
  _isInHitReaction = false;
  _hitReactionTimer = 0f;
  // _faceClips 保留（资源不重复加载，复用缓存）
  // _replaceTimelines 保留（同上）
  ```
  同时确认 FsmComp.ResetForPool 会清除 `_prevStateType`（TurnState 的前序状态记录）。

---

## 🟡 建议修复（Important）

### I1: TurnState 阈值已为 30f，plan 要求 45f，决策未明确

- **位置**: `BigWorldNpcTurnState.cs` 已有实现；`plan/client.json` turn_state_logic 章节
- **问题**: 代码中 `TurnThresholdDeg = 30f` 已存在，plan 要求 "确认并完善 TurnThresholdDeg = 45f"，会改变现有行为。feature.json 验收标准说 "建议 45f"，非强制。改 30f→45f 会使转身触发更迟钝，视觉上 NPC 朝向错位更明显。
- **建议**: plan 中明确指定保留 30f 或改为 45f，附上选择理由（45f 减少不必要的转身动画；30f 过渡更自然），避免实现者自行决定。

---

### I2: TurnState 触发检测位置描述矛盾

- **位置**: `plan/flow.json` Step2 vs `plan/client.json` turn_state_logic.detection
- **问题**: flow.json 说 "每帧 BigWorldNpcFsmComp.Update() 计算"，client.json 说 "MoveComp 回调" 两种方案。两处选一但 plan 没有明确选择。放错位置可能导致：放在 FsmComp.Update 则每帧轮询；放在 MoveComp 回调则只有移动时才检测（静止 NPC 不会触发转身）。
- **建议**: 明确指定在 FsmComp.Update() 中轮询（适用于静止 NPC 改变朝向的场景），删除 MoveComp 回调的表述。

---

### I3: TurnState 期间再次到来的新朝向指令行为未定义

- **位置**: `plan/flow.json` → 转身过渡流程
- **问题**: 如果 NPC 正在执行 TurnState（2s 窗口内），服务端又推送了新的目标朝向（与当前朝向差仍 >=TurnThreshold），应该：重置计时器+更新转身方向？还是忽略新朝向直到当前 TurnState 结束？不定义会导致实现者自行选择。
- **建议**: 在 flow.json 中补充：TurnState 期间忽略新的朝向差触发（简单方案），TurnState 结束后若朝向差仍大则再次触发新的 TurnState。

---

### I4: 面部 Clip 预加载完成前 EmotionComp 触发时静默丢弃，无 retry

- **位置**: `plan/client.json` → AnimationComp changes_req005
- **问题**: plan 指定 "OnInit() 后异步预加载4个面部Clip"，但如果 NPC 生成后立刻推送情绪数据，而预加载尚未完成，PlayFaceAnim 会因 `_faceClips` 为空而静默跳过。对于初始情绪非 Neutral 的 NPC，面部动画永久缺失。
- **建议**: 在 `EmotionComp` 中缓存最后一次情绪请求（`_pendingEmotion`），预加载完成回调中若 `_pendingEmotion != None` 则补调 PlayFaceAnim。或改为按需加载（首次请求时加载对应 Clip）。

---

### I5: PlayFaceAnim 参数类型在 plan 中不一致

- **位置**: `plan/client.json` → `new_public_interfaces`（用 `EmotionType`）vs `feature.json` 验收标准（用 `ConfigEnum.TransitionKey key`）
- **问题**: 两处描述使用不同类型参数，实现者无法确定应该用哪个。
- **建议**: 统一为 `EmotionType`（与 EmotionComp 的情绪类型保持一致，内部再映射到 Clip Key）；或统一为 `ConfigEnum.TransitionKey`（直接传 Clip Key，EmotionComp 负责转换）。在 plan 中选一并删除矛盾项。

---

### I6: RestoreUpperBodyAnim() 行为规格缺失

- **位置**: `plan/client.json` → changes_req008
- **问题**: plan 提到 "RestoreUpperBodyAnim()：UpperBody层恢复上一个播放状态" 但未指定实现：
  - 方案A：Weight→0（UpperBody 层停止，不播放任何内容）
  - 方案B：CrossFade 到击中前缓存的 Clip
  - 方案C：CrossFade 到当前 FSM 状态对应的 UpperBody 默认 Clip

  三种方案在视觉上有明显差异，且方案B/C需要额外的 "击中前状态缓存" 逻辑，plan 未提及。
- **建议**: 指定采用方案A（Weight 淡出到 0），并注明这是与 TownNpcAnimationComp 一致的实现（如果小镇如此）；或指定方案并补充所需的状态缓存字段。

---

## 🟢 可选优化（Nice to have）

### N1: 明确 BigWorldNpcAnimationComp 当前已初始化的层

- **建议**: 在实现前先读取 BigWorldNpcAnimationComp.cs 的 `OnInit()` 或 `CreateLayers()` 方法，列出当前实际初始化的层（不是枚举中定义的层），更新 plan 中 "原X层" 的描述，使测试用例的验证数字准确。

### N2: REQ-007 战斗状态 ClearAdditiveBodyOverlay 触发条件未说明

- **建议**: 在 plan 中指定 HandleServerState() 的清理策略：每次状态变更时先 Clear 所有叠加层，再按新状态设置——避免旧状态叠加残留。

### N3: 补充 TurnState 日志以提升可观测性

- **建议**: 在 TurnState.OnEnter/OnExit 添加 `MLog.Info?.Log("TurnState enter/exit, delta=" + deltaAngleDeg)` 用于运行时调试，特别是超时强制退出时需要 Warning 日志。

### N4: 明确 TurnState 期间服务端推送新状态的优先级

- **建议**: 指定若 TurnState 执行期间服务端推送 Scenario/Move/Idle，是立即退出 TurnState 响应，还是等转身完成。推荐立即响应（服务端权威），在 flow.json 中补充该边界场景。

---

## 📝 遗漏场景清单

1. **NPC 生成到外观加载完成期间的状态** — ScenarioState 若在 AppearanceComp 加载完成前触发，动画 Rig 可能未就绪，需在 flow.json 中补充加载完成前的状态处理
2. **TurnState + ScenarioState 的交互** — TurnState 是客户端自主状态，若 NPC 在 ScenarioState 期间目标朝向差 >=TurnThreshold，是否触发 TurnState？触发后 _prevStateType 保存 ScenarioState，退出后能否正确恢复？需在 client.json 中说明
3. **多次快速情绪变化时 Face 层的 CrossFade 堆叠** — 100ms 内连续3次 PlayFaceAnim，Animancer CrossFade 是否能正确处理（通常可以），但 plan 没有说明
4. **_faceClips 字典已有实现的确认** — plan 说 "新增 Dictionary<ConfigEnum.TransitionKey, AnimationClip> _faceClips"，但未确认 BigWorldNpcAnimationComp 中是否已有该字段（搜索结果显示未找到，确认需要新增）

---

## ✅ 做得好的地方

1. **lesson 规则的前置集成**：plan/client.json 中的 `coding_checklist` 完整列出了 lesson-002/003/005 等规则的逐项自查要求，且每项都具体可执行（如 grep 命令格式），大幅降低了实现后才发现规范违规的风险。

2. **异常降级策略完整**：plan.json 和 flow.json 中对每种资源加载失败场景（AvatarMask、FaceClip、Timeline、Prefab）都有明确的降级策略（静默跳过 / 回退 Idle / 回退男性 Prefab），没有遗漏。每个异常都有对应的日志级别（Warning/静默），符合宪法要求。

3. **零协议变更的架构决策**：严格遵守 "不新增 NpcState 枚举值" 约束，所有新状态复用已有枚举值，TurnState 纯客户端处理，既满足需求又保持协议稳定性。protocol.json 对此有清晰文档说明，是本次 plan 设计最合理的部分。

---

<!-- counts: critical=3 important=6 nice=4 -->
