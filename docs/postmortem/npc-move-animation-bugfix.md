# NPC 移动动画不匹配 Bug 修复记录

## 原始问题

Donna 等小镇 NPC 行走时显示奔跑或站立动画，而非走路动画。

## 修复过程（共四层问题）

### 第一层：FSM 状态映射错位

**现象**：所有 NPC Move(2)→RunState，Stop(1)→MoveState，整体偏移一格。

**根因**：服务端 `EMoveState` 枚举从 1 开始（Stop=1, Move=2, Run=3），客户端 `_stateTypes` 列表从 0 开始。原设计通过 `-1` 偏移映射，但 `-1` 散落在 6 处代码中，维护中被部分删除（`GetCurrentStateId` 改为直接 `return ServerStateId`），导致映射错位。

**修复**：
- `TownFsmComp`：用 `Dictionary<int,int>` 显式映射替代隐式 -1
- 新增 `RegisterServerState<T>(serverStateId)` 和 `ChangeStateByServerStateId(int)` 方法
- 清除 6 处散落的 -1（TownNpcStateData×2、TownNpcController×1、TurnState×1、InDoorState×1、TradeEffectState×1）

**修改文件**：TownFsmComp.cs、TownNpcStateData.cs、TownNpcController.cs、TownNpcTurnState.cs、TownNpcInDoorState.cs、TownNpcTradeEffectState.cs

### 第二层：物理移动状态与行为状态混用

**现象**：情绪系统触发后，NPC 移动插值数据被丢弃，位置通过 TransformSnapShot 瞬移更新而非平滑插值。

**根因**：`TownNpcStateData.StateId` 同时被 `MoveStateProto.State`(1-3) 和 `NpcEmotionChangeNtf.EmotionState`(12-16) 写入。情绪覆盖 StateId 后，`TryUpdateMoveControlData` 中 `StateId != MOVE_STATE_MOVE(2)` 判断失效（如 StateId=12），移动插值数据被丢弃。

**修复**：
- `TownNpcStateData` 新增 `PhysicalMoveState` 字段，仅由 MoveStateProto.State 写入
- 3 处移动判断改用 PhysicalMoveState（TownNpcClientData×2、TownNpcInteractableComp×1）

**修改文件**：TownNpcStateData.cs、TownNpcClientData.cs、TownNpcInteractableComp.cs

### 第三层：动画参数设置静默失败

**现象**：FSM 状态正确（MoveState），但 LinearMixer 参数=1.0（奔跑）而非 0.3（走路）。运行时诊断：6 个 MoveState NPC 中 5 个 param=1.0。

**根因**：`TownNpcMoveState.OnEnter()` 调用 `SetParameter(BaseMove, 0.3)` 时，动画配置可能未加载完（`_replaceTransitions` 为空），SetParameter 静默失败（无日志无异常）。LinearMixer 默认 Parameter=1.0。后续服务端持续发 State=2 但 stateId 未变化，不重新触发 OnEnter。

**修复**：
- MoveState/IdleState/RunState 的 `OnUpdate` 中加防守：检测参数值不对时重新设置
- ScenarioState 的 `OnUpdate` 中对走路阶段（phase 1/2/6）加同样防守
- 修复 ScenarioComp 和 ScenarioState 中 `Vector2.right`(=1.0) 应为 `0.3f * Vector2.right` 的 2 处错误

**修改文件**：TownNpcMoveState.cs、TownNpcIdleState.cs、TownNpcRunState.cs、TownNpcScenarioState.cs、TownNpcScenarioComp.cs

### 第四层：服务端 syncNpcMovement 桥接层两个 bug（已修复）

**现象**：NPC 在 Scenario 走路阶段（phase=1/2/6），FSM 被强制切到 Idle，播放站立动画，但位置仍在更新。

**Bug A：IsFinish && IsSameTarget 跳过条件不充分**

路网 A* 可能只返回部分路径。NPC 走完后 `IsFinish=true`、`IsSameTarget=true`，但实际未到达目标。syncNpcMovement 跳过不再寻路，eState 永久停在 Stop。

修复：跳过前检查 NPC 当前位置是否已接近 MoveTarget（距离 < 0.5m），未到达则重新寻路。新增 `isEntityNearTarget` 方法。

**Bug B：state_sensor 覆盖 IsMoving**

`state_sensor.go:119` 每帧将 `IsMoving` 覆盖为 `action.IsSprint`。NPC 走路（非冲刺）时 `IsSprint=false`，导致 `IsMoving=false`，syncNpcMovement 第 250 行直接 return。ScheduleHandler 设的 `IsMoving=true` 被传感器覆盖。

修复：V2 管线下传感器不覆盖 IsMoving，由 Handler 层全权管理。

**修改文件**：bt_tick_system.go、state_sensor.go

## 经验教训

1. **值域转换集中一处**：1-based→0-based 的 -1 散落 6 处，维护中被部分删除导致错位
2. **一个字段一个职责**：StateId 同时承担 FSM 驱动和移动判断，情绪覆盖后移动判断失效
3. **静默失败最难排查**：SetParameter 找不到 key 时无日志无异常，只能通过运行时诊断发现
4. **OnEnter 设置必须有 OnUpdate 兜底**：依赖异步加载的设置不能只在 OnEnter 做一次
5. **同一根因排查所有调用点**：修完 MoveState 后遗漏了 ScenarioState 的同类问题
6. **诊断数据中的异常值不能假设正常**：采样中 Scenario param=1.0 被错误判断为正常行为
7. **客户端表现 bug 先跑运行时诊断**：不要只读代码推理，用 MCP 脚本读实际参数值一跑就定位
8. **多层 bug 要全链路追踪**：FSM 映射→状态混用→参数失败→服务端时序，四层问题逐层暴露

---

## syncNpcMovement 桥接层设计 Review

代码位置：`bt_tick_system.go:248-291`

### 功能

将 AI 决策层的 `NpcState.Movement.MoveTarget`（"去哪"）转换为 ECS 执行层的 `NpcMoveComp.pointList`（路径点列表）。三级寻路 fallback：路网 A* → NavMesh → 直线兜底。

### P0 问题

**1. IsFinish && IsSameTarget 跳过条件不充分（第 271-273 行）**
- 现象：NPC 走完路网部分路径后 eState 永久停在 Stop，客户端显示站立滑行
- 根因：路网 A* 可能只返回部分路径，NPC 走完后 `IsFinish=true`，但 MoveTarget 没变所以 `IsSameTarget=true`，syncNpcMovement 直接跳过不再寻路
- 修复：跳过前额外检查 NPC 当前位置与 MoveTarget 的距离，未到达（如 > 0.5m）则重新寻路。注意不能用 `!mv.IsMoving`，因为 syncNpcMovement 只有 IsMoving=true 时才会执行到此处

**2. MoveTarget 零值判断有缺陷（第 254 行）**
- `X==0 && Y==0 && Z==0` 判断，如果目标恰好在原点则无法移动
- 建议改用专用标志位或 NaN 表示"无目标"

### P1 问题

**3. IsMoving=false 时不清理残留路径（第 250-251 行）**
- AI 设置 `IsMoving=false` 后 syncNpcMovement 直接 return，NpcMoveComp 可能仍有残留路径点
- 实际影响有限：PauseState 已设 eState=Stop，NpcMoveSystem 跳过 IsPaused 的 NPC，残留路径点不会被消费
- 但如果后续有代码调用 `ResumeState()` 而不先 `Clear()`，会复活旧路径
- 建议：IsMoving 从 true→false 时主动 `moveComp.Clear()` + `StopMove()` 作为防守

**4. 路网/NavMesh 返回的路径终点可能不等于 MoveTarget**
- A* 返回最近网格点，与真实目标有误差
- `IsSameTarget` 容差 0.1m，但累积误差可能超过
- 建议：IsSameTarget 比较**期望目标**而非路径终点

**5. 未消费路径点检查过于保守（第 266-268 行）**
- `GetNextPoint()!=nil` 时直接跳过，NPC 无法在移动中途响应新目标
- 需等当前路径全走完才能响应目标变更

**6. IsMoving 清除责任模糊**
- IsMoving 由 Handler 设置/清除，但无机制检测 Handler 忘记清除的情况
- 如果 IsMoving 永远为 true，syncNpcMovement 每帧尝试寻路（但被 IsFinish && IsSameTarget 挡住）

### P2 问题

**7. 日志不对称**
- 寻路成功无日志，只有直线兜底时打日志，难以排查寻路问题
