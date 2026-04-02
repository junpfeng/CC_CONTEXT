═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.2
  审查文件：4 个（develop-log 记录的变更）
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | 各文件 using 完整，`Vector3 = UnityEngine.Vector3` 显式 alias ✅ |
| 编译：命名空间 | ✅ | 均使用 `FL.Gameplay.Modules.BigWorld` ✅ |
| 编译：API 存在性 | ✅ | BoneInfoUtil 在 Controller 基类中定义；PreviousPosition 在 TransformComp 中定义 |
| 编译：类型歧义 | ✅ | Vector3/Vector2 均有 UnityEngine alias，无歧义 |
| 1.1 YAGNI | ✅ | 无超出 plan 的额外功能 |
| 1.2 框架优先 | ✅ | 使用 Comp/Controller 框架；LoaderManager 异步加载 |
| 4.1-4.3 异步编程 | ✅ | OnInit 为 async UniTask；CancellationToken 正确使用；无 Unity 协程 |
| 5.x 网络通信 | ✅ | 通过 _npcData 信号接收服务端数据，不直接操作网络层 |
| 6.x 内存性能 | ✅ | AnimSpeedChangedThreshold 防每帧 SetSpeed；sqrMagnitude 代替 magnitude |
| 7.1 日志规范 | ✅ | 使用 MLog.Error?.Log()，`+` 拼接，无 $"" 插值（develop-log 确认已修复） |
| 7.3 命名规范 | ✅ | 私有字段 _camelCase；公共属性 PascalCase；常量 PascalCase（项目约定） |
| 8.1-8.2 资源加载 | ✅ | LoaderManager.LoadAssetAsync 异步加载 AvatarMask ✅ |
| 9.1-9.3 状态机 | ✅ | 使用 GuardedFsm 框架；无 bool 标记链 |
| 3.3 订阅配对 | ⚠️ | FsmComp.OnEnable 使用 UnListen+Listen 防重复注册 ✅；Controller.OnInit/OnDispose 订阅配对 ✅；但 ResetForPool 缺少取消订阅（见 HIGH-1） |

### 服务端

| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 | ✅ | develop-log 无服务端文件变更，无禁区修改 |
| Go 编译 | ✅ | develop-log 注明"Go 服务端编译通过" |

---

## 二、Plan 完整性

### 已实现（develop-log 跟踪）

- [x] `BigWorldNpcMoveComp.cs` — 速度计算修复、deltaTime 守卫、MoveMode 自动切换
- [x] `BigWorldNpcAnimationComp.cs` — 速度驱动动画混合、CrossFade、isLooping 非破坏性检查、HiZ 剔除
- [x] `BigWorldNpcFsmComp.cs` — MoveMode 驱动 FSM 切换、_stateId 同步路径、pendingState 机制
- [x] `BigWorldNpcController.cs` — 组件注册顺序、SetCulled、ResetForPool、CancellationToken 管理

### 已验证存在（非本轮新增，前置任务实现）

- [x] `MapBigWorldNpcLegend.cs` — 文件已存在于 UI/Map/TagInfo/ 目录
- [x] `MapLegendControl.ToggleShowAllBigWorldNpc()` — 方法已存在（第1925行）
- [x] 服务端 Go 代码 — develop-log 注明编译通过，推测前置任务已实现

### 未在本轮 develop-log 中跟踪（需人工确认）

- [ ] `npc_zone_quota.json` — WalkZone 配额配置是否已生成
- [ ] `ai_patrol/bigworld/*.json` — 巡逻路线 JSON 文件（15-25条）是否已生成
- [ ] `scene.xlsx / NpcCreator.xlsx / icon.xlsx` — 配置表是否已更新
- [ ] `generate_ped_road.py / generate_patrol_routes.py` — 脚本是否已提交

> **说明**：develop-log 仅记录了本轮（Fix Round 1 后）的 4 个客户端文件。服务端和配置相关工作推测在 task-01~07 中完成，本次 review 聚焦于本轮变更文件。

### 偏差

- `BigWorldNpcFsmComp`：plan 要求"状态由服务器 AnimState 驱动"，实现同时存在 MoveMode 驱动路径（OnUpdateByRate）和服务端状态驱动路径（OnUpdateMonsterState）。双路径之间存在 _stateId 同步问题（见 HIGH-2）。

---

## 三、边界情况

[HIGH] BigWorldNpcController.cs:63-64 / 110-117 — **对象池复用时 _npcData 事件订阅泄漏**
  场景: NPC 回收到对象池后 `ResetForPool()` 未调用 `_npcData.UnListen`，再次从池中取出后 `OnInit` 对新 NpcData 新增订阅，但旧 NpcData 的 `MonsterTransformUpdate`/`ServerAnimStateDataUpdate` 订阅依然存活。若旧 NpcData 继续派发事件，`OnTransformUpdate`/`OnAnimStateUpdate` 将被错误触发。
  影响: 对象池高频复用场景下，旧 NpcData 事件驱动导致位置或状态错误更新，引发 NPC 闪烁/错位或状态机错误切换。
  建议: 在 `ResetForPool()` 开头增加 `_npcData?.UnListen<TransformSnapShotData>(...)` 和 `_npcData?.UnListen<ServerAnimStateData>(...)`；并在 OnInit 开头同样先 UnListen（防止 OnInit 被重复调用时双重订阅）。

[HIGH] BigWorldNpcFsmComp.cs:112-113 — **ForceIdle 绕过 _stateId 同步导致状态机对齐失效**
  场景: `ForceIdle()` → `ForceState(typeof(BigWorldNpcIdleState))` → `_fsm.ChangeState(stateType)` 直接操作 FSM，不经过 `ChangeStateById`，`_stateId` 未更新（保留上一个状态的索引）。对象池复用后，若服务端发来 `localIndex == 旧_stateId` 的状态，`OnUpdateMonsterState` 的守卫 `if (_stateId != localIndex)` 会误判为"无需切换"，跳过本应执行的状态转换。
  影响: NPC 复用后服务端首次同步的移动/Idle 状态可能不被应用，NPC 视觉上停在 Idle 而实际应在移动。
  建议: 将 `ForceState` 改为调用 `ChangeStateById(0)` 路径（IdleState 的索引为 0），或在 `ForceState` 后显式 `_stateId = _stateTypes.IndexOf(stateType)`。

---

## 四、代码质量

[MEDIUM] BigWorldNpcFsmComp.cs:83-93 — **ChangeState\<T\> else 分支不更新 _stateId**
  当 `typeof(T)` 不在 `_stateTypes` 中时（当前注册状态均在其中，理论上不可达），else 分支直接调用 `_fsm.ChangeState<T>()` 跳过 `_stateId` 更新。若未来新增状态类型时误入此路径，_stateId 会静默失同步。
  建议: 删除 else 分支，或改为 `MLog.Error?.Log(...)` + 提前 return，使问题在开发阶段暴露。

[MEDIUM] BigWorldNpcFsmComp.cs:190-198 — **OnClear 未清理 _stateTypes**
  `OnClear()` 清理了 `_serverStateMap`、`_fsm`、`_moveComp` 等，但 `_stateTypes` 列表未 Clear/Null。`_fsm?.Dispose()` 是否会级联释放状态类型不确定。与其他成员清理不一致，存在内存保持风险。
  建议: 在 OnClear 末尾加 `_stateTypes?.Clear(); _stateTypes = null;`。

[MEDIUM] BigWorldNpcAnimationComp.cs:106-122 — **ChangeAnimationsByGroup 传 null 旧过渡名**
  `_replaceTransitions.TryGetValue(pair.Key, out string name)` 返回 false 时（新 key），`name` 为 null，随后 `AnimationManager.ChangeTransitionByKey(this, null, pair.Value.name, ...)` 被调用。首次 `OnAdd` 时 `_replaceTransitions` 为空，所有 key 均走此路径。AnimationManager 能否安全处理 null 旧名依赖其实现，当前未见空值保护。
  建议: 在调用前显式判断 `string oldName = _replaceTransitions.TryGetValue(pair.Key, out var n) ? n : null;` 并在 AnimationManager 接口层文档化是否允许 null，或改为 `string.Empty`。

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     2 个（必须修复）
  MEDIUM:   3 个（建议修复）

  结论: 需修复后再提交

  重点关注:
  1. [HIGH-1] BigWorldNpcController.ResetForPool 事件泄漏 — 对象池高频复用场景下必现，应在合入前修复
  2. [HIGH-2] BigWorldNpcFsmComp.ForceIdle _stateId 失同步 — 导致服务端首帧状态被跳过，NPC 复用后行为异常

<!-- counts: critical=0 high=2 medium=3 -->
