---
name: Client FSM 状态机 + 动画系统
status: done
---

## 范围
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs — 轻量级 FSM 状态机组件。状态由服务器 AnimState 驱动，不做客户端自主决策。支持 ForceState(Idle) 用于对象池 ResetForPool()
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs — Animancer 多层动画组件。分层架构参照 TownNpcAnimationComp（UpperBody/Arms/AdditiveBody/Face）但按大世界需求裁剪。支持 HiZCulling 暂停/恢复 Animancer 图。动画速度与移速归一化匹配（refSpeed 匹配实际移速）
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcIdleState.cs — Idle 状态：播放 idle 动画，OnExit Stop 所有使用过的动画层
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcMoveState.cs — Move 状态（Walk/Run）：播放移动动画，速度归一化。角度变量必须带单位后缀（headingDeg/headingRad）
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcTurnState.cs — Turn 状态：原地转向动画，角度阈值用度数（TurnThresholdDeg），与 Mathf.Atan2 弧度返回值显式转换
- 修改: freelifeclient/.../BigWorldNpcController.cs — OnInit 中补充 AddComp(FsmComp) 和 AddComp(AnimationComp)

## 验证标准
- Unity 编译无 CS 错误
- FSM 每个 State 的 OnExit 必须 Stop 所有使用过的动画层（无动画残留）
- 播放 clip 前检查 isLooping 设置（FBX 可能未勾选 Loop）
- 动画归一化 refSpeed 匹配实际移速，不会视觉冻结或过快
- 角度比较两侧单位一致，无弧度与度数混用
- 不引用 S1Town 的 TownNpcFsmComp 或状态枚举

## 依赖
- 依赖 task-05（Controller 和基础 Comp 框架）
