---
description: Unity C# 中涉及角度/旋转的代码，必须在每个变量和阈值处标注单位（弧度/度数），转换必须显式调用 Mathf.Deg2Rad / Rad2Deg
globs:
alwaysApply: true
---

# 角度单位一致性（弧度 vs 度数）

## 触发条件
当编写或修改以下代码时触发：
- 涉及 `heading`、`rotation`、`angle`、`yaw`、`pitch`、`turn` 等角度相关变量
- 使用 `Mathf.Atan2`、`Vector3.Angle`、`Quaternion.Euler` 等返回/接受角度的 API
- FSM 状态切换条件中包含角度阈值判断

## 规则内容
1. **每个角度变量命名或注释必须标明单位**：`headingRad`（弧度）或 `headingDeg`（度数），不得使用无后缀的 `heading`
2. **角度比较时，两侧必须是同一单位**。阈值常量必须标注单位：`const float TurnThresholdDeg = 5f;` 或 `const float TurnThresholdRad = 0.087f;`
3. **单位转换必须显式调用**：`Mathf.Deg2Rad` / `Mathf.Rad2Deg`，禁止手动乘除 `57.295f` 或 `0.01745f` 等魔法数字
4. **Unity API 约定**：
   - `Quaternion.Euler()` / `Transform.eulerAngles` → 度数
   - `Mathf.Atan2()` / `Mathf.Acos()` → 弧度
   - `Vector3.Angle()` → 度数
   混用这些 API 的返回值进行比较时，必须先统一单位

## 来源
auto-work meta-review #5，基于 0.0.1/NPC_refactor_to_big_world task-09 的工作数据。
task-09 经历 6 轮迭代未收敛（Critical 从 1→1→2），核心原因是 NpcMoveState/NpcTurnState 中 heading 弧度与度数阈值混用，导致 FSM 状态切换完全失效。develop 循环 3 轮修复均未能根治，每轮修复反而引入新的不一致。
