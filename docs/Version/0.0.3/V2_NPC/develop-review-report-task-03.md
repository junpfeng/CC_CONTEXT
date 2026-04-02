═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC（task-03）
  版本：0.0.3
  审查文件：3 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | ScenarioState/ScheduleIdleState 均无 FL.NetModule，无 Vector3 歧义；FsmComp.cs 正确添加 `using Vector3 = UnityEngine.Vector3` |
| 编译：命名空间 | ✅ | 三文件均在 `FL.Gameplay.Modules.BigWorld`，与目录层级一致 |
| 编译：API 存在性 | ✅ | `ConfigLoader.NpcMap.TryGetValue`、`animComp.Play`、`AnimancerLayers.Base`、`FsmState<T>` 均为已有 API |
| 编译：类型歧义 | ✅ | 两新文件不引入 FL.NetModule，无歧义风险 |
| 7.1 日志规范 | ✅ | 使用 `MLog.Warning?.Log` + `+` 拼接，未使用 `$""` 插值（lesson-003 合规）|
| 7.2 错误处理 | ✅ | animComp null 检查 early return；TryGetValue 安全访问；Play 返回 null 有降级路径 |
| 7.3 命名规范 | ✅ | 私有字段 `_usedBaseLayer`，常量/方法 PascalCase |
| 4.1-4.3 异步编程 | ✅ | 无异步操作，同步执行符合 FSM 状态模式 |
| 3.1-3.4 事件驱动 | ✅ | FsmComp OnEnable/OnDisable 事件订阅成对；两新状态文件无事件订阅 |
| 6.1-6.3 内存性能 | ✅ | OnUpdate 无逻辑，热路径零分配；状态切换时无额外堆分配 |
| 角度单位（lesson-002）| ✅ | `_pendingTurnDeltaAngleDeg`（Deg 后缀）、`TurnThresholdDeg`、`Mathf.DeltaAngle` 返回值均为度数，单位一致 |

### 服务端

本次 task-03 为纯客户端变更，无 Go 代码修改，服务端合宪性审查跳过。

---

## 二、Plan 完整性

### 已实现
- [x] `BigWorldNpcScenarioState.cs`（新建）— 符合 plan REQ-003，播放 specialIdle 动画，降级到 BaseMove
- [x] `BigWorldNpcScheduleIdleState.cs`（新建）— 符合 plan REQ-003，优先 specialIdle，静默回退 BaseMove
- [x] `BigWorldNpcFsmComp.cs`（修改）— Scenario(19)、ScheduleIdle(20) 均注册到 serverStateMap
- [x] MoveMode 切换保护 — guard 条件已添加（fix-round-2），ScenarioState/ScheduleIdleState 不被 MoveMode 打断

### 偏差（已记录）
- `BigWorldNpcScenarioState.cs:15-17` — plan 要求从 `NpcData.BaseInfo.NpcCfgId` 查取 `scenario_default_anim_key`；实际使用 `NpcData.MonsterInfo.NpcCreatorId` 查 `ConfigLoader.NpcMap`，字段为 `specialIdle`。dev-log 中已记录偏离及原因（HumanBaseData 无 NpcCfgId 字段）。

### 无遗漏
task-03 所有计划文件均已实现，无遗漏项。

---

## 三、边界情况

[HIGH] BigWorldNpcFsmComp.cs:358 — TurnState 守卫缺少 ScenarioState/ScheduleIdleState 排除
  场景: NPC 处于 ScenarioState（坐下/场景点动画），服务端推送新目标朝向，当前 heading 与目标差 >= 30°
  影响: FsmComp 触发 EnterTurnState，NPC 中断坐下动画播放转身动画（约 2 秒），TurnState 结束后
        ExitTurnState 虽能通过 _prevStateType 恢复 ScenarioState，但视觉上出现错误的"站起转身再坐下"。
        与 MoveMode 守卫（line 337-339 明确排除了 ScenarioState 和 ScheduleIdleState）形成不对称。
  当前守卫: `if (_isFsmReady && !(CurrentState is BigWorldNpcTurnState))`
  缺失守卫: 应补充 `&& !(CurrentState is BigWorldNpcScenarioState) && !(CurrentState is BigWorldNpcScheduleIdleState)`

[MEDIUM] BigWorldNpcScenarioState.cs:42-44 — 降级日志消息具有误导性
  场景: animKey 非空但 `animComp.Play(animKey)` 返回 null（动画 clip 未加载）
  影响: 打印 "场景动画 Key 为空或不存在" 与实际情况不符（Key 存在但 clip 加载失败），排查时误导方向
  建议: 分两路打日志——key 为空时打 "Key 为空"，play 返回 null 时打 "Key=xxx clip 加载失败，降级播放 Idle"

[MEDIUM] BigWorldNpcScenarioState.cs:74-88 + BigWorldNpcScheduleIdleState.cs:65-79 — PlayBaseIdle 代码重复
  影响: 同一方法逻辑在两文件中完全相同，后续修改（如调整 ChangeAnimationsByGroup 参数）需双处同步，
        遗漏任一处会造成不一致行为。dev-log 已标记为 TODO。
  建议: 提取到基类或公共静态工具方法（非本 task 强制，但建议在本 feature 内处理）

[MEDIUM] BigWorldNpcFsmComp.cs:83-84 — 集合初始容量与实际注册量不匹配
  影响: `new List<Type>(8)` 和 `new Dictionary<int,int>(8)` 初始容量为 8，实际注册 21 个状态，
        内部数组将扩容 2~3 次（8->16->32），产生额外堆分配。仅在 NPC 初始化时触发一次，不影响热路径。
  建议: 改为 `new List<Type>(24)` / `new Dictionary<int,int>(24)`

---

## 四、代码质量

[MEDIUM] BigWorldNpcScenarioState.cs:35-36 + BigWorldNpcScheduleIdleState.cs:59-60 — 修改共享动画资源
  `state.Clip.wrapMode = WrapMode.Loop` 直接修改 AnimationClip 资源对象（共享 ScriptableObject），
  所有使用该 clip 的 NPC 的 wrapMode 都会被改变。dev-log 已注明"与 IdleState 现有模式一致"，
  属已知 tech debt。潜在影响：若某 NPC 需要同一 clip 以 WrapMode.Once 播放，将受到干扰。

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     1 个（强烈建议修复）
  MEDIUM:   4 个（建议修复，可酌情跳过）

  结论: 需修复 HIGH 后再提交

  重点关注:
  1. [HIGH] FsmComp TurnState 守卫缺少对 ScenarioState/ScheduleIdleState 的排除——场景坐下 NPC 会被服务端 heading 变化触发站起转身（约 2 秒中断）。
  2. [MEDIUM] ScenarioState 降级日志不区分 "key 为空" 和 "clip 加载失败" 两种失败原因，影响调试。
  3. [MEDIUM] PlayBaseIdle 逻辑在两文件中重复，建议本 feature 内统一处理。
  4. [MEDIUM] wrapMode 修改共享资源是已知 tech debt，暂无紧急风险但需后续跟进。

<!-- counts: critical=0 high=1 medium=4 -->
