---
name: REQ-003 ScenarioState + ScheduleIdleState
status: completed
---

## 范围
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcScenarioState.cs
  — 继承 BigWorldNpcBaseState；OnEnter() 按 `_controller.NpcData.BaseInfo.NpcCfgId` 查 NpcCfg 配置表取 `scenario_default_anim_key`（字段名以实际配置类为准），Key 为空则降级播放 Idle 并打 Warning 日志（+ 拼接，无 $""）；OnUpdate() 无逻辑（动画自循环）；OnExit() CrossFade 淡出 0.3s 回 Idle；若 NpcCfg 无此字段，改从 ServerAnimStateData 已有字段（如 ExtraInfo）读取 Key 并在代码注释标记偏离
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/State/BigWorldNpcScheduleIdleState.cs
  — 继承 BigWorldNpcBaseState；OnEnter() 播放 ScheduleIdle 动画 Key，Key 不存在时回退 Idle；OnUpdate() 无逻辑；OnExit() CrossFade 淡出 0.3s
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs
  — serverStateMap 中添加 `NpcState.Scenario → BigWorldNpcScenarioState` 映射；添加 `NpcState.ScheduleIdle → BigWorldNpcScheduleIdleState` 映射；CreateFsm() 中注册两个新状态实例

## 验证标准
- 客户端无 CS 编译错误
- GM 指令触发 NpcState=Scenario，MCP 截图确认场景点动画播放
- GM 指令触发 NpcState=ScheduleIdle，确认等待动画播放
- 状态退出时动画淡出无残留（Profiler 层权重归零）
- 动画 Key 不存在时有 Warning 日志且回退 Idle 不崩溃
- Idle/Move/Run 状态在非 Scenario 时行为无变化（回归截图对比）

## 依赖
- 依赖 task-02（FsmComp 在 task-02 已修改，task-03 继续在同文件追加改动）
