═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.3
  任务：task-02（REQ-002 TurnState 完善）
  审查文件：2 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | TurnState: Animancer/FL.Framework.Lib/FL.Gameplay.Config/UnityEngine；FsmComp: 含 Vector3 alias 消解歧义 |
| 编译：类型歧义 | ✅ | FsmComp.cs:8 `using Vector3 = UnityEngine.Vector3` 已显式消解 |
| 编译：命名空间 | ✅ | 两文件均使用 `FL.Gameplay.Modules.BigWorld`，与目录层级一致 |
| 编译：API 存在性 | ✅ | AnimancerLayers.Base、Play(TransitionKey)、Stop(int)、LogModule.BigWorldNpc 均已验证存在 |
| 1.1 YAGNI | ✅ | 实现范围在 plan 约定内，无额外功能 |
| 1.2 框架优先 | ✅ | 使用项目已有 GuardedFsm、FsmState 框架 |
| 3.3 事件订阅配对 | ✅ | OnEnable/OnDisable 成对订阅/取消订阅 MonsterStateUpdate |
| 4.1 UniTask | ✅ | 无异步方法，不涉及 |
| 7.1 日志规范 | ✅ | FsmComp.cs:252 使用 `+` 拼接，无 `$""` 插值 |
| 7.3 命名规范 | ✅ | 角度变量带 Deg 后缀（lesson-002 合规） |
| 9.1 状态机 | ✅ | 使用 FSM 而非 bool 标记 |
| 共享资源修改 | ❌ | TurnState.cs:54 直接修改 AnimationClip.wrapMode（共享 Asset），见 HIGH-1 |

### 服务端

无服务端改动，跳过。

---

## 二、Plan 完整性

### 已实现
- [x] `BigWorldNpcTurnState.cs` — TurnThresholdDeg=30f、2s 超时、左右 Clip 选择、OnExit 停止动画层
- [x] `BigWorldNpcFsmComp.cs` — TurnState 注册、heading 差每帧检测（DeltaAngle）、_prevStateType 保存/恢复、EnterTurnState/ExitTurnState、ForceIdle 清除 _prevStateType、OnClear 重置字段
- [x] TurnState 期间跳过 MoveMode 状态切换（FsmComp.cs:270-271）
- [x] ShouldTurn/ShouldTurnRad 辅助方法（度数/弧度双接口）

### 遗漏
无 plan 要求的遗漏项。

### 偏差
- **FsmComp.cs:242-245**：plan 描述"TurnState 结束时恢复前序状态"，但未明确要求 `OnUpdateMonsterState` 中保护 TurnState 不被同状态更新打断。实现中缺少此保护，详见 HIGH-2。

---

## 三、边界情况

**[HIGH-2] BigWorldNpcFsmComp.cs:242-245 - OnUpdateMonsterState 无 TurnState 保护**

```csharp
var localIndex = GetLocalStateIndex(stateId);
if (_stateId != localIndex)        // TurnState 期间 _stateId = TurnState_index
{
    ChangeStateById(localIndex);   // 任何服务端状态推送（含同状态重推）均会打断 TurnState
}
```

- **场景**：NPC 处于 Idle 时检测到朝向差，进入 TurnState（_stateId = TurnState_index）。若服务端此时推送同一 Idle 状态（localIndex=0），条件 `0 != TurnState_index` 成立，TurnState 立即被中断退出。服务端推送频率越高，转身动画越难完成。
- **影响**：转身动画频繁被打断，视觉上出现抖动/弹跳。在服务端持续推送状态时（即使状态不变），TurnState 永远无法完整播放。
- **建议**：在 `OnUpdateMonsterState` 中增加 TurnState 保护，仅当新状态与进入 TurnState 前的状态不同时才中断转身：保存 `_prevStateId`，并在判断时用 `_prevStateId != localIndex` 代替 `_stateId != localIndex`，或在条件中加 `!(CurrentState is BigWorldNpcTurnState)`。

---

## 四、代码质量

**[HIGH-1] BigWorldNpcTurnState.cs:52-55 - 直接修改 AnimationClip 共享 Asset**

```csharp
if (_playingState.Clip != null && _playingState.Clip.isLooping)
{
    _playingState.Clip.wrapMode = WrapMode.Once;  // 修改的是共享 Asset，非实例
}
```

- **场景**：若转身 Clip 被误配置为循环动画（`isLooping = true`），此行会永久修改该 AnimationClip asset。由于 AnimationClip 是所有使用该 Clip 的 NPC 共享的 Asset，修改后所有 NPC 的该动画均被影响，且在 Editor Play 模式下退出后修改会持久化到磁盘。
- **影响**：可能导致其他模块使用相同 Clip 时行为异常；在 Editor 中会污染 Asset（虽在运行时少见，但属于错误实践）。
- **建议**：改用 Animancer State 层面的控制，例如设置 `_playingState.NormalizedEndTime = 1f`（使动画在结束帧停止）或在 Clip Transition 配置中设置 wrapMode，而非修改 Clip asset 本身。

**[MEDIUM-1] BigWorldNpcFsmComp.cs:197-200 - ExitTurnState 中 IndexOf 返回首个重复项**

- `_stateTypes` 中同一 Type（如 BigWorldNpcMoveState）存在多个条目（对应不同 serverStateId）。`IndexOf(restoreType)` 始终返回第一个出现位置（索引1，对应 serverStateId=2），而实际进入 TurnState 前的状态可能是索引13（Flee）。
- **影响**：ExitTurnState 后 `_stateId=1`，下次服务端推送 Flee（localIndex=13）时，`1 != 13` 触发立即再次切换（MoveState→MoveState，同类型不同索引）。视觉无差异但存在多余状态切换。
- **建议**：同时保存 `_prevStateId`（int），ExitTurnState 中直接 `ChangeStateById(_prevStateId)` 而非 IndexOf 查找。

**[MEDIUM-2] BigWorldNpcFsmComp.cs:347 - OnClear 后 _fsm 未置 null**

```csharp
_fsm?.Dispose();
// _fsm = null; 缺失
```

- **影响**：OnClear 后若有任何调用路径触发 `_fsm?.Update(deltaTime)`（FsmComp.cs:326），会在 dispose 后的 FSM 上调用 Update，行为未定义。
- **建议**：`_fsm.Dispose()` 后紧跟 `_fsm = null`。

**[MEDIUM-3] BigWorldNpcFsmComp.cs:346 - OnClear 中 _stateTypes 未清空**

- `_stateTypes?.Clear()` 未在 OnClear 中调用，对象池复用时 `CreateFsm()` 会创建新列表并覆盖引用，旧列表等待 GC。
- **影响**：轻微内存泄漏（短暂），不影响正确性，但与 `_serverStateMap?.Clear()` 的清理风格不一致。
- **建议**：在 OnClear 中补充 `_stateTypes?.Clear()`，或将 `_stateTypes = null`，与 `_serverStateMap` 保持一致处理。

---

## 五、总结

```
  CRITICAL: 0 个
  HIGH:     2 个（强烈建议修复）
  MEDIUM:   3 个（建议修复，可酌情跳过）

  结论: 需修复后再提交

  重点关注:
  1. [HIGH-2] OnUpdateMonsterState 缺少 TurnState 保护，服务端同状态重推会打断转身动画，导致转身视觉效果失效
  2. [HIGH-1] AnimationClip.wrapMode 共享 Asset 修改，需改用 Animancer State 层面控制
  3. [MEDIUM-1] ExitTurnState 中 _prevStateId 应直接保存索引而非依赖 IndexOf 查找
```

<!-- counts: critical=0 high=2 medium=3 -->
