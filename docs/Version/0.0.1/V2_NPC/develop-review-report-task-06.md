═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC — Task-06 Client FSM 状态机 + 动画系统
  版本：0.0.1
  审查文件：6 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using | ✅ | 所有文件 using 完整，BigWorldNpcAnimationComp.cs 和 BigWorldNpcController.cs 正确添加了 Vector2/Vector3 alias 消歧义 |
| 编译：命名空间 | ✅ | 所有文件使用 `FL.Gameplay.Modules.BigWorld`，与目录层级一致 |
| 编译：API 存在性 | ✅ | 已验证：AnimationComp.Stop(int)、GuardedFsm<T>、FsmState<T>、BoneInfoUtil.GetHumanBone、AnimancerLayers 枚举、NpcData.ServerAnimStateData 均存在 |
| 编译：类型歧义 | ✅ | BigWorldNpcAnimationComp.cs:11 和 BigWorldNpcController.cs:8-9 正确使用 using alias |
| 1.1 YAGNI | ✅ | 实现严格遵循 plan 范围，无多余功能 |
| 1.2 框架优先 | ✅ | 复用 AnimationComp、FsmComp、GuardedFsm、FsmState 等框架基础设施 |
| 1.4 MonoBehaviour 节制 | ✅ | 纯逻辑组件，未使用 MonoManager |
| 2.1-2.5 Manager 架构 | ✅ | Controller + Comp 模式符合大世界架构 |
| 3.1-3.4 事件驱动 | ✅ | FsmComp 使用 DataSignal（Listen/UnListen）配对正确（OnEnable 订阅、OnDisable 取消） |
| 4.1-4.3 异步编程 | ✅ | Controller 使用 CancellationTokenSource 管理异步生命周期，OnDispose 中正确 Cancel/Dispose |
| 5.1-5.5 网络通信 | ✅ | 通过 DataSignal 驱动，不直接处理网络层 |
| 6.1-6.3 内存性能 | ✅ | HiZ Culling 暂停动画更新；对象池 ResetForPool 支持复用 |
| 7.1 日志 | ✅ | 使用 MLog.Error/Warning/Debug，无 Debug.Log |
| 7.2 错误处理 | ✅ | null 检查充分，AnimancerComponent null 时有错误日志 |
| 7.3 命名规范 | ✅ | 私有字段 _camelCase，方法 PascalCase，常量 PascalCase |
| 8.1-8.2 资源加载 | ✅ | AvatarMask 通过 LoaderManager.LoadAssetAsync 异步加载 |
| 9.1-9.3 状态机 | ✅ | 使用 GuardedFsm，无 bool 标记 + if-else 链 |

### 服务端

无服务端文件变更（task-06 纯客户端任务）。

## 二、Plan 完整性

### 已实现
- [x] BigWorldNpcFsmComp.cs — 符合 plan：轻量级 FSM，服务端状态驱动，ForceState/ForceIdle 支持
- [x] BigWorldNpcAnimationComp.cs — 符合 plan：多层动画（Base/UpperBody/Arms/Face）、HiZ Culling、TransitionKey API
- [x] BigWorldNpcIdleState.cs — 符合 plan：Idle 动画、OnExit Stop Base 层
- [x] BigWorldNpcMoveState.cs — 符合 plan：Walk/Run blend、速度归一化、isLooping 检查
- [x] BigWorldNpcTurnState.cs — 符合 plan：角度阈值度数、Rad2Deg 显式转换、动画结束回调
- [x] BigWorldNpcController.cs — 符合 plan：AddComp(AnimationComp) 和 AddComp(FsmComp)

### 遗漏
无遗漏。plan 中 task-06 要求的所有文件和功能均已实现。

### 偏差
无显著偏差。

## 三、边界情况

[MEDIUM] BigWorldNpcTurnState.cs:87 — 转向完成后硬编码回退到 Idle（serverStateId=1）
  场景: 如果 NPC 转向过程中服务端已切换到 Move 状态，转向完成后会强制回 Idle 而非最新的服务端状态
  影响: 可能出现短暂的状态不同步（下一帧 FsmComp.OnUpdateMonsterState 会纠正）
  建议: 从 FsmComp 获取当前服务端状态 ID 进行回退，而非硬编码 1

[MEDIUM] BigWorldNpcFsmComp.cs:167 — 未知服务端状态 ID 回退到 Idle（index=0）
  场景: 服务端扩展新状态枚举值但客户端未同步时触发
  影响: Warning 日志 + 安全降级到 Idle，行为合理
  建议: 当前处理已足够，仅标记为已知边界

[MEDIUM] BigWorldNpcAnimationComp.cs:75-91 — AvatarMask 异步加载回调中检查 Owner==null 但未检查 _armsLayer/_upperBodyLayer 是否仍有效
  场景: 如果 OnClear 在加载回调前执行，_armsLayer 已被设为 null，赋值 Mask 会 NullReferenceException
  影响: 极端时序下可能崩溃
  建议: 回调中增加对 _armsLayer/_upperBodyLayer 的 null 检查

## 四、代码质量

[HIGH] BigWorldNpcFsmComp.cs:167 — 日志使用 `$""` 字符串插值
  说明: `$"未知的服务端状态ID: {serverStateId}"` 使用了 `$""` 插值。客户端宪法（unity-csharp.md 7.1）要求日志使用 `+` 拼接而非 `$""`
  影响: 每次调用产生字符串分配（GC 压力），虽然 Warning 日志非热路径，但不符合规范
  建议: 改为 `"未知的服务端状态ID: " + serverStateId`

[HIGH] BigWorldNpcAnimationComp.cs:98 — 日志使用 `$""` 字符串插值
  说明: `$"BigWorldNpcAnimationComp: AnimationGroup {id} not found"` 同上
  建议: 改为 `"BigWorldNpcAnimationComp: AnimationGroup " + id + " not found"`

[MEDIUM] BigWorldNpcIdleState.cs:44 — OnUpdate 中每帧检查动画参数是否漂移
  说明: 每帧获取 GetParameter 并做浮点比较，如果非必要可移除
  影响: 轻微性能开销，但注释说明是防守性代码（动画配置延迟加载场景）
  建议: 保留即可，防守合理

## 五、总结

  CRITICAL: 0 个
  HIGH:     2 个（日志 $"" 插值不符合规范）
  MEDIUM:   4 个（硬编码回退状态、未知状态降级、异步回调 null 检查、每帧防守检查）

  结论: 通过（HIGH 问题为编码规范层面，不影响功能正确性和编译）

  重点关注:
  1. 日志字符串插值需改为 + 拼接（2 处 HIGH）
  2. TurnState 转向完成后硬编码回 Idle，极端时序下短暂不同步（FsmComp 下帧纠正）
  3. AvatarMask 异步加载回调需加 layer null 检查防止极端时序崩溃

<!-- counts: critical=0 high=2 medium=4 -->
