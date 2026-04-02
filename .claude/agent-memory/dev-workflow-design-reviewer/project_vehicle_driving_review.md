---
name: vehicle_driving_review
description: 玩家自由驾驶车辆（GTA5风格）技术设计审查（第二轮 2026-03-30），CONDITIONAL PASS：上轮2个CRITICAL已修复，残留3个HIGH（节流逻辑错误、征用竞态、空车分支缺失）
type: project
---

## 审查结果: CONDITIONAL PASS (第二轮)

### 上轮 CRITICAL 修复确认
1. NeedAutoVanish=false 阻止10秒自动消失 — 已修复，ShouldVanish() 正确短路
2. 复用 TrafficVehicleSystem.Update() 而非新建 System — 已修复

### HIGH (本轮)
1. 回收节流逻辑有误：`currentTime - AbandonedAt < 5` 不是5秒间隔轮询，而是5秒延迟后每帧检查。需独立 LastRecycleCheckAt 字段
2. PullFromVehicle + OnVehicle 两步竞态仍未解决，多人场景有确定性 bug（两人同时征用同一车）
3. 空车（无NPC）征用分支缺失，只描述了 Pull+OnVehicle 链路

### MEDIUM
1. SwitchToPlayerControl 直接调用 vs 信号驱动冲突未澄清
2. OwnerPlayerEntityID 跨场景失效在代码中有覆盖（nil检查立即回收）但设计未显式说明
3. 重新上车状态清理不完整（缺状态转换表）
4. IsPlayerCommandeered 缺网络同步说明

**Why:** 第一轮两个 CRITICAL 修复方向正确，但竞态和空车等上轮 HIGH 未完全回应。节流伪代码有逻辑错误。

**How to apply:** 征用原子性是多人车辆交互的通用问题，后续载具设计审查需持续关注。
