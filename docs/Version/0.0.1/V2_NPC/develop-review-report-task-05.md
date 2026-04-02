═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.1
  任务：task-05（Client Controller + Components）
  审查文件：5 个
═══════════════════════════════════════════════

## 审查范围

| 文件 | 类型 | 行数 |
|------|------|------|
| `BigWorldNpcController.cs` | 新增 | ~119 |
| `BigWorldNpcTransformComp.cs` | 新增 | ~153 |
| `BigWorldNpcMoveComp.cs` | 新增 | ~141 |
| `BigWorldNpcAppearanceComp.cs` | 新增 | ~141 |
| `LogModule.cs` | 修改 | +1 |

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| **编译：using** | ✅ | 所有文件 using 完整，Vector3 alias 消歧义正确 |
| **编译：命名空间** | ✅ | `FL.Gameplay.Modules.BigWorld` 与目录层级一致 |
| **编译：API 存在性** | ✅ | Controller、AddComp、TransformSnapshotQueue、BodyPartsMap 等全部经 Grep 验证存在 |
| **编译：类型歧义** | ✅ | `using Vector3 = UnityEngine.Vector3;` 已在所有引用 FL.NetModule 的文件中添加 |
| 1.1 YAGNI | ✅ | 仅实现 plan 要求的三个组件，FSM/Animation 明确标注 task-06 |
| 1.2 框架优先 | ✅ | 复用 Controller/Comp/TransformSnapshotQueue/BodyPartsMap 等已有基础设施 |
| 1.4 MonoBehaviour 节制 | ✅ | 纯逻辑，无 MonoManager 误用 |
| 2.1-2.5 Manager 架构 | ✅ | 不涉及 Manager（Controller 层） |
| 3.1-3.4 事件驱动 | ✅ | 无事件订阅，不需要取消配对 |
| 4.1-4.3 异步编程 | ❌ | AppearanceComp 未持有内部 CTS，OnClear 无法主动取消异步加载（见 HIGH #3） |
| 5.1-5.5 网络通信 | ✅ | 不直接涉及网络层 |
| 6.1-6.3 内存性能 | ✅ | TransformComp 缓存 proto 对象避免热路径分配，sqrMagnitude 避免开方 |
| 7.1 日志 | ✅ | 全部使用 MLog，无 Debug.Log；字符串用 `+` 拼接 |
| 7.2 错误处理 | ✅ | catch 块有日志，异常路径有 fallback |
| 7.3 命名规范 | ✅ | PascalCase/\_camelCase 符合规范 |
| 8.1-8.2 资源加载 | ✅ | 外观通过 BodyPartsMap 异步加载 |
| 9.1-9.3 状态机 | ✅ | MoveMode 枚举管理状态，无 bool+if-else 链 |

### 服务端

本任务无服务端代码变更。

## 二、Plan 完整性

### 已实现
- [x] `BigWorldNpcController.cs` — 主控制器，AddComp 顺序正确（Transform → Move → Appearance）
- [x] `BigWorldNpcTransformComp.cs` — LOD 感知位置同步，三级帧间隔控制
- [x] `BigWorldNpcMoveComp.cs` — 移动状态管理组件
- [x] `BigWorldNpcAppearanceComp.cs` — 三级 fallback 外观加载
- [x] `LogModule.BigWorldNpc` — 日志分类已添加

### 遗漏
无。Plan 中 task-05 要求的 4 个文件全部实现。FSM/Animation 明确标注为 task-06 范围。

### 偏差
- **BigWorldNpcTransformComp.cs** — Plan 要求 LOD-aware 插值时间窗口（FULL 300ms / REDUCED 500ms+EaseOut / MINIMAL 800ms+线性），当前实现仅通过帧间隔 1/3/6 跳帧控制更新频率，未向 TransformSnapshotQueue 传递插值策略参数。帧间隔与 300ms/500ms/800ms 无对应关系（帧率不同效果不同）。详见 HIGH #1。
- **BigWorldNpcAppearanceComp.cs** — Plan 要求三级 fallback（skip part → body-only → prefab default mesh），当前 body-only 与 prefab-default 实际上是同一条路径。详见 MEDIUM #4。

## 三、边界情况

[HIGH] BigWorldNpcTransformComp.cs:74-96 - **跳帧导致插值时间轴断裂**
  场景: LOD 等级 > FULL 时，_updateFrameInterval > 1，多帧只调用一次 _snapshotQueue.Update()
  影响: TransformSnapshotQueue 内部使用 Time.unscaledDeltaTime，跳帧时只反映当前帧而非累积时间，导致插值速度异常减慢，NPC 移动表现卡顿
  建议: 在 OnUpdate 中累积 deltaTime，或改用外部传入累积时间的 Update 重载

[HIGH] BigWorldNpcAppearanceComp.cs:46-84 - **异步加载中途组件被清理**
  场景: LoadAppearanceAsync 正在 await，外部调用 OnClear → UnloadAppearance 将 _bodyPartsMap Dispose
  影响: await 返回后继续执行，可能操作已 Dispose 的 BodyPartsMap，导致 NRE 或访问已释放资源
  建议: await 返回后增加 `if (_controller == null || _bodyPartsMap == null) return;` 有效性校验

[MEDIUM] BigWorldNpcMoveComp.cs:104 - **GetTransform 返回值未检查 null**
  场景: entity 已回收但 IUpdate 未注销
  建议: 加 null 守卫 `var tf = _controller.GetTransform(); if (tf == null) return;`

[MEDIUM] BigWorldNpcController.cs:96-109 - **ResetForPool 未清理基类状态**
  场景: 对象池复用时跳过 OnDispose 直接调用 ResetForPool
  建议: 确认对象池回收流程是否先调用 OnDispose；若否，需在 ResetForPool 中重置基类残留数据

## 四、代码质量

[HIGH] BigWorldNpcTransformComp.cs:102-120 — **LOD 插值参数未按 plan 实现**
  Plan 要求三级 LOD 对应不同插值时间窗口和插值曲线（EaseOut/线性），当前仅用帧间隔 1/3/6 控制跳帧频率。帧间隔是硬编码魔法数字，未传递任何插值策略参数给 TransformSnapshotQueue。

[HIGH] BigWorldNpcAppearanceComp.cs:全局 — **缺少内部 CancellationTokenSource**
  组件未持有 _cts，OnClear 无法主动取消正在进行的异步加载。违反项目规范 feedback_unitask_cancellation（async 方法必须带 CancellationToken，OnClear 中 Cancel）。虽然外部传入了 token，但组件应维护自身的 CTS 以确保生命周期可控。

[MEDIUM] BigWorldNpcTransformComp.cs:107-114 — **帧间隔硬编码魔法数字**
  _updateFrameInterval 的 1/3/6 是魔法数字，应提取为命名常量并注释设计意图。

[MEDIUM] BigWorldNpcAppearanceComp.cs:58-63 — **body-only fallback 与 prefab-default 路径合并**
  三级 fallback 的第二级（body-only）和第三级（prefab-default）实际执行同一逻辑（不做任何操作）。如设计意图确实等价，应在注释中明确说明。

## 五、总结

  CRITICAL: 0 个
  HIGH:     4 个（必须修复）
  MEDIUM:   4 个（建议修复）

  结论: 需修复后再提交

  重点关注:
  1. TransformComp LOD 插值参数未按 plan 实现 — 仅做跳帧控制，缺少插值时间窗口和曲线策略
  2. AppearanceComp 异步安全 — 缺少内部 CTS + await 后未校验组件有效性，可能操作已释放资源
  3. TransformComp 跳帧时间轴断裂 — LOD > FULL 时插值速度异常减慢，NPC 移动卡顿

  代码亮点:
  - Vector3 using alias 消歧义处理规范，所有文件一致
  - Proto 对象缓存设计良好，热路径零堆分配
  - Controller CTS 生命周期管理完整
  - 组件职责分层清晰（Transform 负责插值、Move 负责状态、Appearance 负责外观）
  - 完全无 S1Town 耦合，模块隔离干净

<!-- counts: critical=0 high=4 medium=4 -->
