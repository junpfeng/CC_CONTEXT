# 路人 AI 情绪系统 — 代码审查报告

> ✅ **审查结论**：13 个问题中 8 个已修复（S1-S5, G1, G6, G8），4 个待修复（G2-G5）。详见 `ped-ai-emotion-bugfix-design.md`。

**日期**：2026-03-13
**审查范围**：服务端 Go（emotion_system/spread/handlers）+ 客户端 C#（State/Comp/Data）+ 协议

---

## 必须修复（严重问题）

### [S1] 传播系统魔数硬编码枚举值
**文件**：`emotion_spread_system.go:98`
**问题**：`em.EmotionState < 3` 硬编码数字而非 `proto.NpcState_Scared`，枚举值变动后静默失效。
**修复**：改为 `em.EmotionState < proto.NpcState_Scared`。

### [S2] 距离衰减结果被丢弃（功能 Bug）
**文件**：`emotion_spread_system.go:161`
**问题**：`_ = actualMood` 丢弃了按距离衰减后的情绪强度，远近 NPC 接收相同冲击级别，设计意图失效。
**修复**：根据 `actualMood` 重新计算 `impactLevel`，或将 `actualMood` 传入 `TriggerEvent`。

### [S3] DecayTimer 多用途复用导致计时冲突
**文件**：`expression_handlers.go`，`phone_report_handler.go`
**问题**：`EmotionState.DecayTimer` 被三处同时使用（衰减冷却 / 围观计时 / 通话计时），同帧递减与累加互相干扰。
**修复**：新增独立字段 `WatchElapsed float32`，PhoneHandler 使用 `PhoneElapsed float32`。

### [S4] TriggerTripFallDelayed 无取消机制（内存/逻辑泄漏）
**文件**：`TownNpcFleeComp.cs:130`
**问题**：UniTaskVoid 在 await 期间 NPC 被回收再复用，`_npcOwner` 会指向新 NPC 对象，触发错误的跌倒动画。
**修复**：使用 `CancellationTokenSource`，在 `OnClear` 中 Cancel。

### [S5] 摔倒随机判断每帧触发导致动画闪烁
**文件**：`expression_handlers.go:52`
**问题**：每帧 5% 随机触发 `is_trip_fall`，同一 NPC 会在多帧间反复切换摔倒状态。
**修复**：在 `ThreatReactHandler.OnEnter` 时一次性决定（已在服务端设计中，但实现时放在了 OnTick）。

---

## 建议修复（一般问题）

### [G1] 传播范围使用曼哈顿距离误差大
**文件**：`emotion_spread_system.go:192`
对角方向误差 41%。改用 `dx*dx + dz*dz < radius*radius`（无 sqrt，精确）。

### [G2] Scared 状态无条件触发 PhoneReport
**文件**：`phone_report_handler.go:119`
`case NpcState_Scared` TODO 直接 `return true`，配合传播放大会导致大量 NPC 同时举报。WantedSystem 接入前改为 `return false` 或添加概率门槛。

### [G3] PhoneReport 使用 FleeAttrFlags 存通话时长，语义矛盾
**文件**：`phone_report_handler.go:51`
`FleeAttrFlags` 原义是逃跑属性位掩码，不应复用存通话时长。新增 `PhoneElapsed float32` 字段后自然解决。

### [G4] SpreadEmotionSystem 有状态，多场景不安全
`DefaultSpread` 包含可变 `pendingSpread` 切片，多场景并行时需改为 per-scene 实例。

### [G5] pendingSpread 队列无硬上限
极端场景（爆炸引发数百 NPC 同时恐慌）可能导致队列无限增长。建议添加 200 项上限，超出时丢弃。

### [G6] 客户端 EmotionState 无边界检查直接用作 FSM 索引
**文件**：`TownNpcStateData.cs:87`
`ntf.EmotionState - 1` 直接作为 `_stateTypes` 数组索引，未来扩展枚举值会导致 `IndexOutOfRangeException`。

### [G7] 广播接入时必须过 AOI 过滤
**文件**：`bt_tick_system.go broadcastNpcEmotionChangeNtf`
TODO 接入时必须限制为视野内玩家，否则泄露视野外 NPC 状态。

### [G8] 客户端日志语言不统一
CuriousState/AngryState 使用英文，其余使用中文。建议统一为中文。

---

## 通过项

- Handler 共享单例无状态字段，符合 ECS 规范 ✅
- 所有 Handler OnExit 正确清理 Expression 字段 ✅
- NpcState.Reset() 正确清零 Emotion 结构体 ✅
- Snapshot 同步已就位 ✅
- 客户端 Comp 生命周期（OnAdd/OnClear）正确实现 ✅
- null 检查统一使用 early return / `?.` ✅
- MoodLevel [0,3] 上限 clamp 无溢出 ✅
- 无硬编码密钥/凭证 ✅
- 并发安全：单线程 ECS Tick，无跨线程风险 ✅

---

## 测试覆盖

### 现有状态
- `emotion/emotion_system_test.go`：新增 10 个单元测试，全部通过 ✅
- `handlers/handlers_test.go`：ThreatReact/SocialReact 基础测试，SocialReact.OnTick 未覆盖

### 已补充测试（emotion_system_test.go）
| 测试函数 | 覆盖逻辑 |
|---------|---------|
| TestTick_ExponentialDecay_NormalPersonality | 指数衰减公式正确性 |
| TestTick_CowardDecayFaster | 个性差异衰减速度 |
| TestTick_LOD2_ResetsToCalm | LOD2 直接清零 |
| TestTick_LOD1_DecaysOnly_NoStateTransition | LOD1 不触发状态归 Calm |
| TestTick_MoodDropBelowThreshold_BecomesCalm | 阈值归 Calm |
| TestTriggerEvent_Level1_CalmToCurious | 跃迁 Calm→Curious |
| TestTriggerEvent_Level1_CuriousToNervous | 跃迁 Curious→Nervous |
| TestTriggerEvent_DedupeWindow_OnlyAddsSmallMood | 去重窗口内不跃迁 |
| TestTriggerEvent_Level3_AnyStateBecomePanicked | Level3 直接 Panicked |
| TestApplyAngry_FearPriority | 恐惧优先于愤怒 |
| TestTick_PinnedSkipsDecay | Pinned 跳过衰减 |

### 建议后续补充
- `SpreadEmotions` 帧限额积压测试
- `SocialReactHandler.OnTick` WatchElapsed 超时路径

