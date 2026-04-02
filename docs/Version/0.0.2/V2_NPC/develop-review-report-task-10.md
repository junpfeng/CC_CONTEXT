═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.2
  任务：task-10（本轮审查覆盖 task-07/08/09/10 新增/修改文件）
  审查文件：9 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | 所有新文件 using 完整；`FL.NetModule` + `UnityEngine` 同时引用时已加 `Vector3 = UnityEngine.Vector3` alias |
| 编译：命名空间 | ✅ | namespace 均与目录层级对应（`FL.Gameplay.Modules.BigWorld`、`FL.Gameplay.Modules.UI`、`FL.NetModule`） |
| 编译：API 存在性 | ✅ | 调用的 API（Animancer、LoaderManager、FsmComp、GuardedFsm 等）均可在代码库中确认存在 |
| 编译：类型歧义 | ✅ | BigWorldNpcController.cs、BigWorldNpcAnimationComp.cs、MapLegendControl.cs 均正确加了 `Vector2/Vector3` alias |
| 1.1 YAGNI | ✅ | 无 plan 未要求的额外功能 |
| 1.2 框架优先 | ✅ | 使用 ManagerCenter、EventManager、ObjectPoolUtility、LoaderManager 等现有基础设施 |
| 1.4 MonoBehaviour 节制 | ✅ | 纯逻辑未用 MonoManager |
| 2.1-2.5 Manager 架构 | ✅ | 无新建 Manager；对 BigWorldNpcManager/MapManager 的调用符合规范 |
| 3.1-3.4 事件驱动 | ✅ | MapLegendControl.cs Register/Unregister 中 `BigWorldNpcSpawned`/`BigWorldNpcDespawned` 订阅配对正确 |
| 4.1-4.3 异步编程 | ✅ | BigWorldNpcController 使用 UniTask + CancellationTokenSource；无裸 Task 或协程 |
| 5.1-5.5 网络通信 | ✅ | NpcPatrolNodeArriveNtf 走 partial NetMsgHandler 模式；无裸 HTTP/Socket |
| 6.1-6.3 内存性能 | ⚠️ | LoadAvatarMasks 异步加载未存 handle（见 M5） |
| 7.1 日志 | ✅ | 所有新 .cs 文件均用 MLog；无 Debug.Log；无 `$""` 插值（全部用 `+` 拼接） |
| 7.2 错误处理 | ✅ | null 检查完整；async UniTaskVoid 无裸 async void |
| 7.3 命名规范 | ✅ | 私有字段 `_camelCase`，方法/属性 `PascalCase`，常量 PascalCase |
| 8.1-8.2 资源加载 | ✅ | LoadAvatarMasks 通过 LoaderManager 异步加载；无同步加载 |
| 9.1-9.3 状态机 | ✅ | 复杂状态用 GuardedFsm；无 bool 标记链 |

### 服务端

| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 | ✅ | 未修改 orm/、common/config/cfg_*.go、resources/proto/、common/proto/*_service.go |
| 错误处理 | ✅ | 所有 error 显式处理；bigworld_gm.go:74 用 log.Errorf；无 `_ = err` |
| 全局变量 | ✅ | 无新增全局变量 |
| Actor 独立性 | ✅ | 所有数据访问在 Scene 回调中完成 |
| 消息传递 | ✅ | 跨 Actor 通信通过 scene/npcMgr 接口 |
| defer 释放锁 | ✅ | 无裸锁操作 |
| safego | ✅ | 无新建裸 goroutine |
| 日志格式符 | ⚠️ | `%d`/`%s` 未使用；但字段命名违反 logging.md（见 H1/H2） |

---

## 二、Plan 完整性

### 已实现

- [x] `BigWorldNpcMoveComp.cs` — 速度计算 + MoveMode 状态管理，符合 plan 设计
- [x] `BigWorldNpcAnimationComp.cs` — 多层动画 + 速度驱动混合 + HiZ Culling，符合 plan 设计
- [x] `BigWorldNpcFsmComp.cs` — 服务端 AnimState 驱动 + MoveComp 辅助驱动 FSM
- [x] `BigWorldNpcController.cs` — 组件聚合 + CTS 管理 + OnPatrolNodeArrive P0 桩
- [x] `MapBigWorldNpcLegend.cs` — 统一图标 + 跟随 NPC 位置 + 自动移除
- [x] `MapLegendControl.cs` — BigWorldNpcSpawned/Despawned 事件订阅 + LoadExistingBigWorldNpcLegends
- [x] `NpcPatrolNodeArriveNtf.cs` — 优先路由小镇 NPC，fallback 路由大世界 NPC
- [x] `bigworld_gm.go` — bw_npc spawn/clear/info 子命令实现
- [x] `bigworld.go` — bigworld_npc_spawn/clear/info/schedule/lod GM 命令实现
- [x] `map.go` — roadsByType 索引 + FindNearestPointIDByType/FindPathByType/GetPointsByType

### 遗漏

无 plan 要求的文件/功能遗漏。

### 偏差

- `BigWorldNpcFsmComp.cs` — plan 中 FSM 设计为"服务端 AnimState 单一驱动"，实现额外引入了 MoveComp 轮询驱动。属于有意的客户端辅助驱动设计，但未在 develop-log 中记录偏离点（见 M2）。

---

## 三、边界情况

[HIGH] bigworld.go:126-127 — NPC 信息日志字段命名违规
  场景: 执行 `/ke* gm bigworld_npc_info <cfgId>` 时
  影响: 日志聚合/告警系统无法按 `npc_cfg_id`/`npc_entity_id` 过滤 NPC 相关日志；违反 logging.md 强制规范
  建议: `cfgId=%v` → `npc_cfg_id=%v`，`entityId=%v` → `npc_entity_id=%v`

[HIGH] bigworld.go:173 — NPC 日程切换日志字段命名违规
  场景: 执行 `/ke* gm bigworld_npc_schedule <cfgId> <scheduleId>` 时
  影响: 同上；`cfgId=%v` 在日志系统中与 `npc_cfg_id` 字段对应不上
  建议: `cfgId=%v` → `npc_cfg_id=%v`

[MEDIUM] bigworld_gm.go:87 — NPC 生成成功日志缺少 npc_entity_id
  场景: GM 命令 bw_npc spawn 成功时
  影响: 日志 `npc_cfg_id` 有值但 `npc_entity_id` 缺失，违反 logging.md 成对规则
  建议: 若 entity_id 在此时已可从 spawner.activeNpcs 中获取，补充 `npc_entity_id=%v`；若确实无法获取，在 log 中注明 `npc_entity_id=pending` 或在后续分配后补日志

[MEDIUM] BigWorldNpcFsmComp.cs:160-173 + 188-208 — FSM 双驱动路径 desync 风险
  场景: `BigWorldNpcController.OnAnimStateUpdate` 通过 `ChangeStateByServerStateId` 更新 `_stateId`，但不更新 FsmComp 的 `_lastMoveMode`。`OnUpdateByRate` 独立通过 MoveComp 轮询更新 `_lastMoveMode` 并触发状态迁移。两路径并行运行。
  影响: `_stateId` 与 `_lastMoveMode` 短暂不同步时，会触发冗余状态迁移。极端情况（服务端快速发送 Stop → 位置插值尚未结束）下，FSM 经历 Idle→MoveState(MoveComp)→Idle 振荡，造成动画 crossfade 抖动。
  建议: 在 `ChangeStateByServerStateId` 后同步更新 `_lastMoveMode`，或在 develop-log 记录此双驱动设计的预期行为边界

[MEDIUM] BigWorldNpcController.cs:159-167 — OnPatrolNodeArrive 的 ForceIdle 未同步 _lastMoveMode
  场景: 服务端发送 NpcPatrolNodeArriveNtf（behaviorType>0, durationMs>0）时
  影响: `ForceIdle()` 绕过 `ChangeStateById` 路径，不更新 `_stateId` 也不更新 FsmComp 的 `_lastMoveMode`。若随后 MoveComp 检测到模式变化（Walk→Idle 正常收敛），FSM 会经历第二次到 Idle 的迁移（方向相同，结果正确，但有冗余 crossfade）。P0 阶段影响有限；扩展到 P1 复杂节点行为时此路径需重构。
  建议: 在 develop-log 中标注此 P0 桩的局限性

[MEDIUM] BigWorldNpcController.cs:133-146 — ResetForPool 未解除 _npcData 信号监听
  场景: NPC 对象池复用：ResetForPool → OnInit(newNpcData) 路径
  影响: 若 ResetForPool 在未经 OnDispose 的情况下被调用，旧 `_npcData` 上的 `OnTransformUpdate`/`OnAnimStateUpdate` 监听未被 UnListen。OnInit 随后将 `_npcData` 替换为新对象，旧监听泄漏，可能导致旧 NpcData 更新时错误触发已复用控制器的回调。
  建议: 确认对象池框架保证 OnDispose 先于 ResetForPool；或在 ResetForPool 开头显式调用 `_npcData?.UnListen<...>`

[MEDIUM] BigWorldNpcAnimationComp.cs:87-103 — LoadAvatarMasks 未存储资源句柄
  场景: BigWorldNpcAnimationComp.OnAdd 时调用 LoadAvatarMasks
  影响: `LoaderManager.LoadAssetAsync<AvatarMask>` 的返回句柄未存储，OnClear/OnRemove 中无法主动释放。若 AvatarMask 不在全局缓存中，NPC 高频池化时可能产生资源残留。
  建议: 存储 handle 变量，在 OnClear 中释放，与其他资源加载保持一致

---

## 四、代码质量

[HIGH] bigworld.go:126,173 — 见"三、边界情况"H1/H2（日志字段命名）

[MEDIUM] NpcPatrolNodeArriveNtf.cs:21 — NpcId 有效性检查类型风险
  `if (request.NpcId <= 0)` — proto 生成代码中 NpcId 字段类型需确认。若为 `long`，此检查有效（可检测负值和零）；若为 `ulong`，`<= 0` 永假，仅依赖后续 `TryGetNpc` 的内部处理。建议确认 proto 定义后对应调整为 `== 0` 或保留当前写法并加注释。

---

## 五、总结

```
  CRITICAL: 0 个（必须修复）
  HIGH:     2 个（强烈建议修复）
  MEDIUM:   5 个（建议修复，可酌情跳过）
```

  结论: **需修复后再提交**（HIGH 问题需处理）

  重点关注:
  1. bigworld.go 中 NPC 日志字段命名违反 logging.md（`cfgId`/`entityId` → `npc_cfg_id`/`npc_entity_id`），影响生产日志检索
  2. FsmComp 双驱动路径（OnAnimStateUpdate + OnUpdateByRate）造成 `_stateId` 与 `_lastMoveMode` 短暂 desync，需在 develop-log 记录偏离设计或修复同步
  3. ResetForPool 需确认对象池生命周期保证 OnDispose 先于 ResetForPool，防止 npcData 信号监听泄漏

<!-- counts: critical=0 high=2 medium=5 -->
