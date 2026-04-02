---
name: 客户端 NPC 动画与移动表现完善
status: completed
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcMoveComp.cs — 完善 TransformSnapshotQueue 插值逻辑（OnDataChanged 入队快照 → Update 时间插值）；暴露 CurrentSpeed 属性（帧间位移/deltaTime）；MoveMode 枚举判断（Idle/Walk/Run 根据速度阈值 RunSpeedThreshold=2.5f）
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs — 速度驱动动画混合（读 MoveComp.CurrentSpeed → Animancer 切换 Idle/Walk/Run）；crossFadeDuration=0.2f 平滑过渡；动画归一化速度（animSpeed = CurrentSpeed / refSpeed，Walk refSpeed=1.2, Run refSpeed=4.0）；播放前检查 clip.isLooping
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs — 完善 3 态 FSM（IdleState/MoveState/TurnState）由 MoveComp.MoveMode 驱动切换
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs — 确保 OnInit 中组件注册顺序完整（TransformComp → MoveComp → AppearanceComp → AnimationComp → FsmComp → EmotionComp）；OnClear 中所有组件正确清理

## 验证标准
- Unity 编译无 CS 错误（通过 console-get-logs 或 Roslyn 检查）
- 无 CS0104 Vector3 歧义（如 using FL.NetModule 需加 alias）
- 日志无 $"" 插值（lesson-003）
- async 方法带 CancellationToken（feedback_unitask_cancellation）
- MoveComp.CurrentSpeed 正确计算
- AnimationComp 根据速度切换 Idle/Walk/Run
- FSM 状态切换逻辑正确
- OnClear 释放所有资源（动画停止、引用置 null、CancellationToken.Cancel）

## 依赖
- 无（客户端可独立于服务端编译）
