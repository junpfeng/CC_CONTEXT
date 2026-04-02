# Bug 分析：看不到正常巡逻的 NPC

## Bug 描述

版本 0.0.3 / V2_NPC 合并后，大世界 NPC 无法正常巡逻。
表现为：NPC 生成在原地后不移动，或在方向切换时持续抖动/卡住，玩家看不到任何 NPC 在执行正常的巡逻行走。

## 代码定位

| 文件 | 行号 | 问题 |
|------|------|------|
| `BigWorldNpcFsmComp.cs:243-259` | OnUpdateMonsterState | 服务端同状态重推直接打断 TurnState |
| `BigWorldNpcFsmComp.cs:358` | OnUpdateByRate 转身检测 | 缺少 ScenarioState/ScheduleIdleState 排除 |
| `BigWorldNpcController.cs:OnInit` | FsmComp 初始化后 | 未读取当前 NpcState 应用到 FsmComp |

**当前行为（主要）**：
- NPC 巡逻途中改变方向 → FsmComp 检测 heading 差 ≥ 30° → 进入 TurnState
- 服务端下一帧重推当前 NpcState=Patrol(17)→ MoveState(index=1)
- `OnUpdateMonsterState`：`_stateId(TurnState_index) != 1` → `ChangeStateById(1)` → TurnState 立即退出
- 下一帧 heading 差仍 ≥ 30° → 再次进入 TurnState → 再次被打断
- 结果：NPC 在每个转角处高频振荡，永远无法完成转身，巡逻移动失效

**预期行为**：TurnState 期间若服务端推送的状态 == 进入 TurnState 前的状态，不打断 TurnState。

## 全链路断点分析

### idea.md → feature.json
- 是否覆盖：**是**
- idea.md 原文："NPC 转向时没有转身过渡" → P0 优先级
- feature.json REQ-002：完整描述了 TurnState 设计，包含"动画结束后自动切回触发前的状态"
- feature.json 验收标准：
  > "TurnState 期间移动输入仍正常响应（不卡在转身），超时 2s 强制退出"

  **注意**：验收标准关注"超时"兜底，但未明确要求"服务端同状态重推不打断"——这是边界场景遗漏。

### feature.json → plan.json
- 是否覆盖：**是（有遗漏）**
- plan.json TurnState 设计中说明：`OnUpdateMonsterState` 中若 `_stateId != localIndex` 则切换
- 该判断逻辑天然存在 TurnState 保护缺失的 bug，**plan 未提及需处理 TurnState 期间服务端重推**

### plan.json → tasks/
- 是否覆盖：**是**
- task-02 完整实现了 TurnState，依赖 plan 的设计

### tasks/ → 代码实现
- 是否实现：**是（含 bug）**
- `OnUpdateMonsterState:256` — `if (_stateId != localIndex) ChangeStateById(localIndex)` 按 plan 实现，但未处理 TurnState 中间状态
- `OnUpdateByRate:358` — `!(CurrentState is BigWorldNpcTurnState)` 正确排除 TurnState，但未排除 ScenarioState/ScheduleIdleState（task-03 新增状态后遗漏同步更新）

### Review 检出
- 是否被 Review 发现：**是（两处 HIGH 均被 Review 发现）**

**task-02 review HIGH-2**：
> OnUpdateMonsterState 无 TurnState 保护，服务端同状态重推会打断转身动画，导致转身视觉效果失效

**task-03 review HIGH**：
> TurnState 守卫缺少对 ScenarioState/ScheduleIdleState 的排除——场景坐下 NPC 会被服务端 heading 变化触发站起转身（约 2 秒中断）

- 修复结果：**两处 HIGH 均未修复**

迭代日志：
- task-02：终止原因"质量达标"，但 Critical=0, High=2, Medium=3，最佳成绩(棘轮)=999（首轮即接受）
- task-03：终止原因"质量达标"，但 Critical=0, High=1, Medium=4

## 归因结论

**主要原因**：Review 检出 → 修复未执行（收敛失败）

**根因链**：
```
feature.json REQ-002 未明确"服务端重推不打断 TurnState"这一边界场景
  ↓
plan.json 沿用 "_stateId != localIndex 则切换" 的简单判断，未设计 TurnState 保护机制
  ↓
task-02 按 plan 实现，代码天然含 TurnState 被打断的 bug
  ↓
Review 发现 HIGH-2 并给出修复建议
  ↓
auto-work 收敛逻辑：Critical=0 → 判断"质量达标"，跳过修复轮次
  ↓
task-03 新增 ScenarioState/ScheduleIdleState 后，OnUpdateByRate 的 TurnState 守卫未同步更新
  ↓
Review 再次发现 HIGH，再次未修复
  ↓
两处 HIGH bug 同时存在：巡逻 NPC 在每次转向时 TurnState 被打断 + 到达路点时被误触发转身
  ↓
玩家看不到正常巡逻的 NPC
```

**次要原因**：初始 NpcState 未应用到 FsmComp

`NpcData.TryUpdateServerAnimStateData` 的 InitData 路径不触发任何 DataSignal。`BigWorldNpcController.OnInit` 在注册 `ServerAnimStateDataUpdate` 监听之前，NPC 的初始状态已经设置完毕，FSM 错过初始状态。首次登录时巡逻 NPC 在最初几秒内处于错误的 Idle 状态，直到服务端推送下一次状态变更。

## 修复方案

### 修复 1（主因）：OnUpdateMonsterState 增加 TurnState 保护

**文件**：`BigWorldNpcFsmComp.cs:243`

```csharp
// 修复前
var localIndex = GetLocalStateIndex(stateId);
if (_stateId != localIndex)
{
    ChangeStateById(localIndex);
}

// 修复后：TurnState 期间，仅当新状态与进入 TurnState 前的状态不同时才中断
var localIndex = GetLocalStateIndex(stateId);
if (_stateId != localIndex)
{
    if (CurrentState is BigWorldNpcTurnState)
    {
        // TurnState 期间只在状态真正改变时中断（对比前序状态，不是 TurnState 本身）
        var prevIndex = _prevStateType != null ? _stateTypes.IndexOf(_prevStateType) : 0;
        if (localIndex != prevIndex)
        {
            _prevStateType = null; // 清除前序，避免 ExitTurnState 恢复到旧状态
            ChangeStateById(localIndex);
        }
    }
    else
    {
        ChangeStateById(localIndex);
    }
}
```

### 修复 2（次因）：OnUpdateByRate 转身检测排除 ScenarioState/ScheduleIdleState

**文件**：`BigWorldNpcFsmComp.cs:358`

```csharp
// 修复前
if (_isFsmReady && !(CurrentState is BigWorldNpcTurnState))

// 修复后
if (_isFsmReady
    && !(CurrentState is BigWorldNpcTurnState)
    && !(CurrentState is BigWorldNpcScenarioState)
    && !(CurrentState is BigWorldNpcScheduleIdleState))
```

### 修复 3（次因）：初始 NpcState 应用

**文件**：`BigWorldNpcController.cs`，在 `FsmComp = this.AddComp<BigWorldNpcFsmComp>()` 之后添加：

```csharp
// 应用初始服务端状态（InitData 路径不触发 DataSignal，需主动同步）
if (_npcData.ServerAnimStateData != null)
{
    FsmComp.ChangeStateByServerStateId((int)_npcData.ServerAnimStateData.MonsterState);
}
```

### 工作流优化建议

**问题 1**：auto-work 收敛逻辑以 Critical=0 为"质量达标"，导致 High 问题直接提交。

**建议**：在 `feature:develop` 的 `develop-iteration-log` 终止条件中，将阈值从 `Critical=0` 改为 `Critical=0 AND High=0`，或至少要求 High 需要一轮修复尝试。

**改哪里**：`skills/feature-develop.md` 中的收敛判断逻辑 / auto-work 脚本中的 keepDecision 判断。

**问题 2**：task-03 新增 ScenarioState/ScheduleIdleState 后，未同步检查 task-02 中已有的 TurnState 守卫是否需要更新。

**建议**：在 `feature:developing` 编码完成后的合规自查（lesson-005）中，增加"检查新增的 FSM 状态是否需要同步更新现有的状态保护条件"检查项。

**改哪里**：`.claude/rules/auto-work-lesson-005.md`，在 Go/C# 扫描清单中补充 FSM 状态保护项。
