---
name: REQ-002 TurnState 完善
status: completed
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcTurnState.cs
  — 确认 `TurnThresholdDeg = 30f` 常量（度数，Deg 后缀）；OnEnter() 读取 deltaAngleDeg 选择右转/左转 Clip，CrossFade 播放，启动 `_turnTimeoutTimer = 2f`；Update() 倒计时归零时调用 FsmComp.ExitTurnState()；检测 AnimancerState.IsPlaying == false 时切回前序状态；OnExit() 淡出转身动画层 Weight→0
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs
  — 新增 `private Type _prevStateType` 保存进入 TurnState 前的状态类型；Update() 中每帧检测 `Mathf.Abs(Mathf.DeltaAngle(currentHeadingDeg, targetHeadingDeg)) >= TurnThresholdDeg` 且 currentState != TurnState 时切入 TurnState；ExitTurnState() 恢复 _prevStateType；确认 CreateFsm() 中 BigWorldNpcTurnState 已注册；ResetForPool() 中清除 `_prevStateType = null`

## 验证标准
- 客户端无 CS 编译错误
- MCP 脚本设置 NPC 目标朝向差 40°，反射确认 FSM 当前状态为 TurnState
- 朝向差 20°（< 阈值 30°）时确认 FSM 不进入 TurnState
- TurnState 进入后 2.1s 确认已强制退出
- 转身完成后确认返回到触发前状态（Idle→Turn→Idle，Move→Turn→Move）
- grep `TurnThresholdDeg` 确认无魔法数字

## 依赖
- 无
