# V2_NPC 任务索引

纯客户端改动，零协议/服务端变更。所有修改限于 `BigWorldNpc*` 命名文件。

## 任务列表

| # | 名称 | 需求 | 优先级 | 依赖 | 主要文件 |
|---|------|------|--------|------|---------|
| [task-01](task-01.md) | 性别Prefab选择 | REQ-001 | P0 | 无 | BigWorldNpcController, (AppearanceComp) |
| [task-02](task-02.md) | TurnState 完善 | REQ-002 | P0 | 无 | BigWorldNpcTurnState, BigWorldNpcFsmComp |
| [task-03](task-03.md) | ScenarioState + ScheduleIdleState | REQ-003 | P0 | task-02 | BigWorldNpcScenarioState(新建), BigWorldNpcScheduleIdleState(新建), BigWorldNpcFsmComp |
| [task-04](task-04.md) | RightArm + AdditiveBodyExtra 动画层补齐 | REQ-004 | P1 | 无 | BigWorldNpcAnimationComp |
| [task-05](task-05.md) | Face 层 + 面部动画 + EmotionComp 联动 | REQ-005 | P1 | task-04 | BigWorldNpcAnimationComp, BigWorldNpcEmotionComp |
| [task-06](task-06.md) | Timeline 动画支持 | REQ-006 | P1 | task-05 | BigWorldNpcAnimationComp |
| [task-07](task-07.md) | 战斗/警惕/逃跑状态动画表现 | REQ-007 | P2 | task-03, task-06 | BigWorldNpcAnimationComp, BigWorldNpcFsmComp |
| [task-08](task-08.md) | 击中反应动画 | REQ-008 | P2 | task-07 | BigWorldNpcAnimationComp |

## 并行开发建议

```
Wave 1（可并行）: task-01 | task-02 | task-04
Wave 2（可并行）: task-03（需 task-02）| task-05（需 task-04）
Wave 3:          task-06（需 task-05）
Wave 4:          task-07（需 task-03 + task-06）
Wave 5:          task-08（需 task-07）
```

## 文件改动总览

| 文件 | 动作 | 涉及任务 |
|------|------|---------|
| BigWorldNpcController.cs | 修改 | task-01 |
| BigWorldNpcAppearanceComp.cs | 修改（按需） | task-01 |
| BigWorldNpcFsmComp.cs | 修改 | task-02 → task-03 → task-07 |
| BigWorldNpcTurnState.cs | 修改 | task-02 |
| BigWorldNpcScenarioState.cs | **新建** | task-03 |
| BigWorldNpcScheduleIdleState.cs | **新建** | task-03 |
| BigWorldNpcAnimationComp.cs | 修改 | task-04 → task-05 → task-06 → task-07 → task-08 |
| BigWorldNpcEmotionComp.cs | 修改 | task-05 |

## 编码自查清单（每个 task 完成后执行）

- `grep 'MLog.*\$"' --include='*.cs'` — 禁止日志 `$""` 插值
- 角度变量必须含 Deg/Rad 后缀，阈值常量同理
- FSM OnExit 必须 Stop 所有使用过的动画层
- async UniTaskVoid 方法带 CancellationToken，OnClear 中 Cancel
- using FL.NetModule 时需 Vector3/Vector2 alias
