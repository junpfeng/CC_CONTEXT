---
name: GTA5动物系统Phase1技术设计审查
description: 0.0.4 GTA5动物系统复刻设计审查（2026-03-31），CRITICAL：syncAnimalStateChange缺Flee/Attack推导、perception plan互斥；HIGH：EventSensor未注册、FieldAccessor遗漏、ThreatSourceID双写
type: project
---

GTA5动物系统Phase1设计审查（2026-03-31），结论 PASS（有条件，需修复 2C+3H）。

**CRITICAL:**
1. syncAnimalStateChange 的 BehaviorState 推导 switch（bt_tick_system.go:611-623）缺少 Flee=6/Attack=7 分支，pipeline tick 后会覆盖回 Idle，新状态永远不会被客户端观测到
2. AnimalPerceptionHandler 作为独立 plan 注册但与 idle plan 互斥，未说明如何从 idle 切换到 perception——建议 perception 替代 idle 作为默认 plan

**HIGH:**
- EventSensor 未注册到动物管线（听觉感知前提缺失）
- 新增 NpcState 字段（GroupID/ThreatSourceID/AttackSubState）未注册到 FieldAccessor（历史重复问题，第3次）
- ThreatSourceID 在 Base 和 Perception 双重存储，一致性风险

**Why:** 在现有 4 种动物 + OrthogonalPipeline 架构上最小改动扩展行为
**How to apply:** 后续 task 实现时注意：(1) syncAnimalStateChange 必须先改推导逻辑再写 Handler；(2) 每次新增 NpcState 字段都检查 FieldAccessor+Snapshot
