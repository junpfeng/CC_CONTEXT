---
name: REQ-007 战斗/警惕/逃跑状态动画表现
status: completed
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs
  — 新增接口：`public void SetAnimationGroup(NpcState state)` — 对 Combat 等状态切换动画组（CombatWpn，若配置存在）；配置不存在时静默跳过
  — 新增接口：`public void SetAdditiveBodyOverlay(NpcState state)` — 对 Scared/Panicked 等在 AdditiveBodyDefault(index=4) 层叠加对应恐惧动画，Weight 从 0 淡入；Flee 在底层 Base 层或 UpperBody 层叠加跑动姿态
  — 新增接口：`public void ClearAdditiveBodyOverlay()` — AdditiveBodyDefault 层 Weight 淡出归零
  — 所有接口：无对应动画配置时静默跳过，不报错
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs
  — HandleServerState() 中对 Combat/Flee/Watch/Investigate/Scared/Panicked/Curious/Nervous/Angry 调用对应的 `AnimationComp.SetAnimationGroup()` 或 `AnimationComp.SetAdditiveBodyOverlay()`
  — 这些状态对应的 serverStateMap 映射（若当前映射到 IdleState/MoveState）保持原映射，仅在进入/退出时追加动画组切换调用
  — 状态退出时调用 `AnimationComp.ClearAdditiveBodyOverlay()` 和 `AnimationComp.ClearAnimationGroupOverride()`（或 SetAnimationGroup 为默认组）

## 验证标准
- 客户端无 CS 编译错误
- GM 指令触发 NpcState=Combat，截图确认动画与普通 Idle/Move 有视觉区分
- GM 指令触发 NpcState=Scared，MCP 反射确认 AdditiveBodyDefault 层 Weight > 0
- GM 指令触发 NpcState=Flee，截图确认移动动画与普通 Move 有视觉区分
- 状态退出时 AdditiveBodyDefault 层 Weight 归零（无残留）
- 无对应动画配置时回退基础 Idle/Move 不报错

## 依赖
- 依赖 task-03（FsmComp 在 task-03 已添加 ScenarioState 映射，task-07 继续修改同文件）
- 依赖 task-06（AnimationComp 在 task-06 已完成 Timeline 支持，task-07 继续追加接口）
