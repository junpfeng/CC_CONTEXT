# 路人 AI 情绪系统 — Bug 修复设计方案

> **日期**: 2026-03-13
> **状态**: 已完成（commit daca59f6）
> **输入**: ped-ai-emotion-review.md（代码审查报告）
> **范围**: P1GoServer

## 1. Bug 状态总览

| Bug | 描述 | 当前状态 | 需修复 |
|-----|------|---------|--------|
| S1 | 传播系统硬编码枚举值 `< 3` | ✅ 已用 `proto.NpcState_Scared` | 否 |
| S2 | 距离衰减 `actualMood` 被丢弃 | ✅ 已通过 `moodToImpactLevel(actualMood)` 使用 | 否 |
| S3 | DecayTimer 多用途复用 | ✅ 已拆分为 DecayTimer/WatchElapsed/PhoneElapsed/PhoneDuration | 否 |
| S4 | UniTaskVoid 无 CancellationToken | ✅ 已有 `_tripFallCts` + OnClear Cancel | 否 |
| S5 | 摔倒随机每帧触发 | ✅ 已移至 OnEnter 一次性决定 | **部分**（见 F1） |
| G1 | 曼哈顿距离 | ✅ 已用 `dx*dx + dz*dz` 平方距离 | 否 |
| G2 | Scared 无条件触发 PhoneReport | ✅ 已改为 `return false`（待接入 WantedSystem） | 否 |
| G3 | OnExit 完成判断永假 | ❌ 逻辑缺陷 | **是**（见 F2） |
| G4 | SpreadEmotionSystem 紧耦合 Default | ⚠️ 设计问题 | 延后 |
| G5 | pendingSpread 无硬上限 | ❌ 未修复 | **是**（见 F3） |
| G6 | 客户端 EmotionState 无边界检查 | ✅ 已有 `if > 0` 守卫 | 否 |
| G7 | broadcastNpcEmotionChangeNtf 未实现 | ❌ 仅 Debug 日志 | **是**（见 F4） |
| G8 | 日志语言不统一 | ✅ 已统一 | 否 |

**结论：13 个问题中 8 个已修复，需要处理 4 个（F1-F4）。**

---

## 2. 修复方案

### F1: trip_fall 动画无自动过渡（S5 残留）

**文件**: `expression_handlers.go` ThreatReactHandler

**问题**: OnEnter 一次性决定 trip_fall（ReactAnimID=3），但 OnTick 在 Panicked 状态下永远保持 ReactAnimID=3，客户端可能循环播放摔倒动画。

**方案**: 在 EmotionState 中新增 `TripFallTimer float32` 字段，OnEnter 设置初值 2.0s（摔倒+爬起时长），OnTick 递减至 0 后自动切换到 `ReactAnimID=1`（flee_run）。

**修改点**:
1. `state/npc_state.go`: EmotionState 新增 `TripFallTimer float32`
2. `state/npc_state_snapshot.go`: Snapshot 同步新字段
3. `expression_handlers.go`: OnEnter 设 TripFallTimer=2.0; OnTick 递减并判断

---

### F2: PhoneReportHandler OnExit 完成判断永假（G3）

**文件**: `phone_report_handler.go:70-81`

**问题**: OnTick 完成时已清零 PhoneElapsed 和 PhoneDuration，OnExit 中 `completed` 判断条件恒为 false，日志总是输出"被打断"。

**方案**: 在 EmotionState 新增 `PhoneCompleted bool` 标志。OnTick 完成时设为 true，OnExit 读取后重置。

**修改点**:
1. `state/npc_state.go`: EmotionState 新增 `PhoneCompleted bool`
2. `phone_report_handler.go`: OnTick 完成时设 `em.PhoneCompleted = true`; OnExit 用 `em.PhoneCompleted` 判断

---

### F3: pendingSpread 队列无硬上限（G5）

**文件**: `emotion_spread_system.go:90`

**问题**: 极端场景（爆炸）可能导致 pendingSpread 无限增长。

**方案**: 添加 200 项硬上限，超出时丢弃新项。

**修改点**:
1. `emotion_spread_system.go`: 在 append 前检查 `len(sys.pendingSpread) >= 200`，超出时跳过并打 Warning 日志

---

### F4: broadcastNpcEmotionChangeNtf 实现（G7）

**文件**: `bt_tick_system.go`

**问题**: 当前仅打 Debug 日志，客户端收不到情绪变化通知。

**方案**: 通过 AOI 系统获取视野内玩家，构建 NpcEmotionChangeNtf 并广播。需要对齐现有 NPC 状态同步的广播模式。

**修改点**:
1. `bt_tick_system.go`: 实现 broadcastNpcEmotionChangeNtf，遍历 AOI 内玩家发送 RPC
2. `global_guard.go`: 死亡重置时同步推送 Calm 状态

> **注意**: 此项依赖现有广播基础设施，需先确认 AOI + RPC 接入方式。

---

## 3. 修改影响范围

| 文件 | 修改类型 | 风险 |
|------|---------|------|
| `state/npc_state.go` | 新增 2 个字段 | 低（向后兼容） |
| `state/npc_state_snapshot.go` | 同步新字段 | 低 |
| `expression_handlers.go` | 修改 OnEnter/OnTick | 中（行为变化） |
| `phone_report_handler.go` | 修改 OnTick/OnExit | 低（逻辑修正） |
| `emotion_spread_system.go` | 添加上限检查 | 低 |
| `bt_tick_system.go` | 实现广播 | 高（需确认接入方式） |

## 4. 执行顺序

```
F1（trip_fall 过渡） → F2（Phone 完成标志） → F3（pending 上限） → F4（广播实现）
```

F1-F3 无依赖可并行，F4 需要先确认广播接入方式。
