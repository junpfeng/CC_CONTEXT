═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.1
  任务：task-07（客户端大世界NPC管理器）
  审查文件：1 个
═══════════════════════════════════════════════

**审查文件：**
- `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Managers/BigWorldNpcManager.cs`（497 行）

**上轮 Review 修复确认：**
- ✅ ProcessPendingSpawnQueue 已添加 CancellationToken（line 73, 192）
- ✅ Tick 循环已用 _tempTickKeys 快照（line 127-138）
- ✅ ProcessFullSync 已复用 _tempRemoveList（line 428）
- ✅ ProcessPendingSpawnQueue 已有完整 try-catch 包裹（line 194-217）
- ✅ 常量已统一为 PascalCase（line 20-31）

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using | ✅ | using 完整，`Vector3 = UnityEngine.Vector3` 消歧义正确 |
| 编译：命名空间 | ✅ | `FL.Gameplay.Modules.BigWorld` 与目录 `Modules/BigWorld/Managers/` 匹配 |
| 编译：API 存在性 | ✅ | BaseManager/ObjectPoolUtility/BigWorldNpcController/DataManager/NpcData/LogModule.BigWorldNpc 全部 Grep 验证存在 |
| 编译：类型歧义 | ✅ | 已添加 `Vector3 = UnityEngine.Vector3` alias（line 9） |
| 1.1 YAGNI | ✅ | 功能范围与 plan 一致，无多余实现 |
| 1.2 框架优先 | ✅ | 使用 BaseManager 基类、ObjectPoolUtility 对象池、MLog 日志 |
| 1.4 MonoBehaviour 节制 | ✅ | Manager 为纯逻辑，未使用 MonoManager |
| 2.1-2.5 Manager 架构 | ✅ | 继承 `BaseManager<BigWorldNpcManager>`，OnInit/OnShutdown/OnUpdate 生命周期正确 |
| 3.1-3.4 事件驱动 | ✅ | 无事件订阅（采用 DataManager.Npcs 数据驱动），无配对问题 |
| 4.1-4.3 异步编程 | ✅ | 使用 UniTask，ProcessPendingSpawnQueue 为 async UniTaskVoid + CancellationToken（已修复） |
| 5.1-5.5 网络通信 | ✅ | 不直接处理网络，通过 DataManager 间接驱动 |
| 6.1-6.3 内存性能 | ✅ | 预分配 List/Dictionary/Queue，热路径无堆分配，_tempTickKeys/_tempRemoveList 复用 |
| 7.1 日志 | ✅ | 使用 MLog，全部 `+` 拼接无 `$""` 插值 |
| 7.2 错误处理 | ✅ | 所有 catch 块均有 MLog.Error 日志，OperationCanceledException 单独处理（不打日志，正确） |
| 7.3 命名规范 | ✅ | 常量 PascalCase，私有字段 _camelCase，方法 PascalCase |
| 8.1-8.2 资源加载 | ✅ | 通过 ObjectPoolUtility 异步加载，无同步加载 |
| 9.1-9.3 状态机 | ✅ | Manager 无复杂状态逻辑，不需要 FSM |

### 服务端

本任务（task-07）仅涉及客户端文件，无服务端代码变更。

## 二、Plan 完整性

### 已实现
- [x] `BigWorldNpcManager.cs` — 大世界 NPC 生命周期 + 对象池管理器
- [x] 对象池预热：ObjectPoolUtility.PrewarmGameObject（PoolSize=20）
- [x] 数据驱动：DataManager.Npcs diff poll，ServerAnimStateData != null 过滤 V2 NPC
- [x] 竞态保护：_isReady + _pendingSpawnQueue + 占位 null 防重复生成
- [x] 分帧 despawn：MaxDespawnPerFrame=5
- [x] LOD 三档管理：Full<50m / Reduced 50-150m / Minimal>150m，每秒更新
- [x] 断线重连：BeginReconnectValidation + ProcessFullSync 全量 diff + 5s 超时
- [x] CancellationToken 支持：_cts 在 OnInit 创建、OnShutdown 取消
- [x] 公开查询 API：TryGetNpc / ActiveCount / ClearAll
- [x] EntityId 使用 ulong
- [x] 不引用 S1Town 命名空间（解耦正确）

### 遗漏
- 无。task-07 plan 要求全部实现。
- （注：BigWorldNpcManager.CreateInstance 注册点未在本文件中，属集成层职责，非本 task 遗漏）

### 偏差
- 无显著偏差。实现与 plan 设计一致。

## 三、边界情况

[HIGH] BigWorldNpcManager.cs:84-90 — OnShutdown 中 Dispose 后未 ReturnToPool
  场景: Manager 销毁时（场景切换/游戏关闭），遍历 _entityDict 调用 kvp.Value.Dispose() 但未将 GameObject 归还对象池
  影响: ObjectPoolUtility 仍持有这些 GameObject 的引用，但对象已随 _rootTransform 被 Destroy（line 100）。若 ObjectPoolUtility 生命周期长于本 Manager，后续复用时可能拿到 destroyed 对象。对比 DespawnNpc（line 371-373）和 ClearAll（line 483-486）均正确执行 Dispose + ReturnToPool，此处行为不一致
  建议: 与 ClearAll 保持一致：
  ```csharp
  foreach (var kvp in _entityDict)
  {
      if (kvp.Value != null)
      {
          var go = kvp.Value.gameObject;
          kvp.Value.Dispose();
          ReturnToPool(go);
      }
  }
  ```

[MEDIUM] BigWorldNpcManager.cs:247 — _pendingDespawnList.Contains() 为 O(n) 线性查找
  场景: 每帧 SyncWithDataManager 中对需移除的 entityId 做 Contains 检查
  影响: MaxDespawnPerFrame=5 限制了列表长度，NPC 总量 ≤20 时性能可接受
  建议: 当前规模无需改动。若后续 NPC 规模扩展，可改用 HashSet<ulong>

[MEDIUM] BigWorldNpcManager.cs — Manager 注册点缺失
  场景: 未找到 BigWorldNpcManager.CreateInstance() 调用。Manager 需在启动流程中注册才能工作
  影响: 若无其他 task 负责集成，Manager 不会被初始化
  建议: 确认集成由哪个 task 负责（如 task-10 场景加载流程）

## 四、代码质量

**安全检查 (CRITICAL)：** 无问题
- 无硬编码密钥/Token
- 不直接修改游戏状态，仅响应服务器数据（DataManager.Npcs）
- 无敏感数据日志输出

**质量检查 (HIGH)：** 无问题
- 最长方法 SpawnNpc 约 75 行，未超 80 行限制
- 嵌套最深 3 层，未超 4 层限制
- 常量均已提取且命名规范
- 无重复代码

**可维护性检查 (MEDIUM)：** 无问题
- 公共 API 均有 XML 文档注释
- 代码分区清晰（生命周期 / 对象池 / 生成销毁 / LOD / 断线重连 / 公开 API）
- 关键操作有日志覆盖

## 五、总结

  CRITICAL: 0 个
  HIGH:     1 个（必须修复）
  MEDIUM:   2 个（建议修复，可酌情跳过）

  结论: 需修复后再提交

  重点关注:
  1. OnShutdown 中 Dispose 后未 ReturnToPool，与 DespawnNpc/ClearAll 行为不一致，可能导致对象池状态异常
  2. _pendingDespawnList 使用 List.Contains 线性查找，当前规模可接受，扩展时需注意
  3. CreateInstance 注册点需确认由集成 task 负责

<!-- counts: critical=0 high=1 medium=2 -->
