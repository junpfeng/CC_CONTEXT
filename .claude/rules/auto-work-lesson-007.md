---
description: 多个系统写同一 Animancer 层时，必须实现层优先级保护，防止低优先级系统覆盖高优先级表现
globs:
alwaysApply: true
---

# Animancer 共享层优先级保护

## 触发条件
当编写或修改以下代码时触发：
- 调用 `_upperBodyLayer`、`_additiveBodyLayer` 或 `BigWorldNpcAnimationComp` 中任何命名 Animancer 层的 `StartFade` / `Stop` / `Play`
- 新增使用某 Animancer 层的功能（HitReaction、情绪叠加、武器动画等）
- 编写层权重归零（`StartFade(0)`）的"恢复"逻辑

## 规则内容
1. **层所有权声明**：编码前确认目标层的当前使用方清单（grep `_upperBodyLayer\|_additiveBodyLayer` 等）。若已有其他系统使用同一层，必须实现优先级机制
2. **条件恢复**：任何将层权重归零的"还原"方法（`RestoreUpperBodyAnim` 等）在执行前必须检查：高优先级系统是否仍处于激活状态，若是则跳过归零，避免清除高优先级效果
3. **最小实现方式**（无需复杂架构）：
   - 在 AnimationComp 中为每个共享层维护一个 `int _layerOwnerPriority` 或 `bool _hasHighPriorityOverride` 字段
   - 激活时写入优先级，归零前比较优先级
4. **编码完成后验证**：grep 该层所有调用点，逐一检查"激活"与"归零"是否都考虑了并发使用方的状态

## 来源
auto-work meta-review #6，基于 0.0.3/V2_NPC task-07、task-08 的工作数据。
task-07 引入 HitReaction 与 Flee Overlay 共用 UpperBody 层但无协调机制（HIGH）；
task-08 因相同根因出现 2 个问题：OnHit 未激活层权重（HIGH）+ RestoreUpperBodyAnim 无条件清层破坏 Flee 表现（MEDIUM），同一根因跨 2 个连续任务重复出现。
