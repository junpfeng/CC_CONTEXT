# Bug 根因分析：NPC 巡逻振荡（TurnState 被同索引状态反复打断）

**版本**: 0.0.3 / V2_NPC
**Bug ID**: #2
**分析日期**: 2026-03-29
**关联**: V2_NPC_analysis_1.md（NPC 不移动根因）

---

## 一、现象描述

大世界 V2 NPC 在巡逻时出现抖动/振荡：NPC 尝试转身（进入 TurnState），但转身被网络状态推送立即打断，NPC 恢复原状态后再次触发转身，如此循环，表现为原地振荡。

---

## 二、根因定位

### 根因：`OnNetworkUpdate` 使用 `_stateTypes.IndexOf` 导致状态索引比对失效

**位置**：`freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs`

原实现中，`ExitTurnState()` 恢复前序状态时调用：

```csharp
int prevIndex = _stateTypes.IndexOf(_prevStateType);
ChangeStateById(prevIndex);
```

`_stateTypes` 是 `List<Type>`，若列表中含重复类型（同一状态类注册多次），`IndexOf` 始终返回第一个匹配位置，导致恢复到错误的状态索引。

`OnNetworkUpdate` 中同样使用 `_stateTypes.IndexOf` 推算 `localIndex`，在 TurnState 期间收到与前序状态相同类型的推送时：

- `_stateId != localIndex` 判断认为需要切换（因为当前是 TurnState）
- 直接执行 `ChangeStateById(localIndex)`，打断 TurnState
- 打断后再次触发转身条件 → 再次进入 TurnState → 循环振荡

---

## 三、完整失效链路

```
[Server] 帧同步推送 NpcState（同一状态 ID 持续到达）
  └─ OnNetworkUpdate() 收到推送
     └─ _stateTypes.IndexOf(_prevStateType) 返回首次位置（可能与当前 TurnState 索引混淆）
        └─ _stateId != localIndex → 执行 ChangeStateById，打断 TurnState
           └─ NPC 返回巡逻状态
              └─ 巡逻状态检测到转向需求 → 再次进入 TurnState
                 └─ 振荡循环 ✗
```

---

## 四、修复方案

**使用整数索引 `_prevStateId` 取代类型查找**，消除重复类型歧义：

```csharp
// 修复前（类型查找，有歧义）
_prevStateType = CurrentState?.GetType();
int prevIndex = _stateTypes.IndexOf(_prevStateType);

// 修复后（整数索引，精确）
_prevStateId = _stateId;  // 保存当前状态的整数 ID
// ExitTurnState 中直接用 _prevStateId 恢复
```

`OnNetworkUpdate` 中 TurnState 期间收到同索引推送时直接忽略，等待 TurnState 自然完成：

```csharp
if (CurrentState is BigWorldNpcTurnState)
{
    var prevIndex = _prevStateId >= 0 ? _prevStateId : 0;
    if (localIndex != prevIndex)
        ChangeStateById(localIndex);
    // 同索引则忽略，不打断 TurnState
}
```

附加修复：转身检测排除 `BigWorldNpcScenarioState` 和 `BigWorldNpcScheduleIdleState`，避免这两种状态下误触发转身。

---

## 五、影响范围与风险

| 项目 | 评估 |
|------|------|
| 影响范围 | 大世界所有 V2 NPC 的巡逻转身逻辑 |
| 严重程度 | P1 — 视觉表现异常（振荡），不影响核心移动功能 |
| 修复风险 | 低 — 整数索引更精确，消除了类型歧义 |
| 回归风险 | 需验证：ScenarioState/ScheduleIdleState 下 NPC 不触发不必要的转身 |

---

## 六、关联文件

| 文件 | 修改内容 |
|------|---------|
| `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs` | `_prevStateId` 字段、`EnterTurnState`/`ExitTurnState` 整数索引、`OnNetworkUpdate` 同索引忽略逻辑 |
| `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs` | `InitData()` 在 AddComp 后立即应用初始服务端状态 |
