═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC (task-06 及关联客户端 task-08/09)
  版本：0.0.2
  审查文件：8 个（服务端 4 + 客户端 4）
═══════════════════════════════════════════════

审查范围（develop-log 记录）：
- `bigworld_ext_handler.go`
- `bigworld_npc_spawner.go`（截取前150行，余下部分通过 grep 补充验证）
- `patrol_route_manager.go`
- `scene_impl.go`（大世界初始化段）
- `BigWorldNpcFsmComp.cs`
- `BigWorldNpcAnimationComp.cs`
- `BigWorldNpcMoveComp.cs`
- `BigWorldNpcController.cs`

---

## 一、合宪性审查

### 客户端
| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using | ✅ | 所有新 .cs 文件均有 `using UnityEngine;` 及 `Vector3 = UnityEngine.Vector3` 别名 |
| 编译：命名空间 | ✅ | 均使用 `FL.Gameplay.Modules.BigWorld` |
| 编译：API 存在性 | ✅ | 已通过 develop-log 编译验证确认 |
| 1.1 YAGNI | ✅ | 仅实现 plan 范围内功能 |
| 1.2 框架优先 | ✅ | 使用 LoaderManager、ManagerCenter 等已有基础设施 |
| 1.4 MonoBehaviour 节制 | ✅ | 未误用 MonoManager |
| 3.3 事件订阅配对 | ✅ | BigWorldNpcFsmComp.OnEnable/OnDisable 成对，BigWorldNpcController.OnDispose 取消订阅 |
| 4.1 UniTask | ✅ | OnInit 使用 UniTask，无 Unity 协程 |
| 4.3 CancellationToken | ✅ | LoadAppearanceAsync 传 _cts.Token |
| 7.1 日志规范 | ✅ | 未见 `$""` 插值，均用 `+` 拼接 |
| 7.2 错误处理 | ✅ | 关键路径有错误日志 |
| 6.1 热路径分配 | ⚠️ | BigWorldNpcMoveComp:86 每帧调 GetTransform()（见 MEDIUM#3） |
| 动画 Clip 资产修改 | ❌ | BigWorldNpcAnimationComp:302 直接修改 AnimationClip.wrapMode（见 HIGH#1） |

### 服务端
| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 | ✅ | 未修改 orm/proto 等生成代码 |
| 错误处理 | ✅ | 所有 error 显式处理，无 `_ = err` |
| %v 格式符 | ✅ | 未见 %d/%s 违规 |
| npc_entity_id/npc_cfg_id 字段 | ✅ | 两字段成对出现 |
| 模块标签格式 | ❌ | bigworld_ext_handler.go 所有日志使用 `ClassName.Method:` 而非 `[ClassName]`（见 HIGH#2） |
| Actor 独立性 | ✅ | 所有 Spawner/Handler 在 Scene goroutine 内操作 |
| safego | ✅ | 未见未保护的 goroutine 新建 |
| defer 锁 | ✅ | 无新增锁定，不适用 |
| 全局变量 | ✅ | 未新增全局变量 |

---

## 二、Plan 完整性

### 已实现（task-06 核心范围）
- [x] `bigworld_ext_handler.go` — 路线分配、NPC 清理、外观随机，符合 plan
- [x] `bigworld_npc_spawner.go` — footwalk 过滤 + WalkZone 配额系统，符合 plan
- [x] `bigworld_walk_zone.go` — WalkZoneConfig/WalkZoneQuotaCalculator（文件存在，grep 确认被引用）
- [x] `scene_impl.go` — 巡逻路线加载、V2 管线创建、WalkZone 注入，符合 plan
- [x] `patrol_route_manager.go` — AssignNpc/ReleaseAllByNpc/GetNextNode 接口，符合 plan
- [x] `bigworld_gm.go` — GM 命令文件存在（未完整审查内容）
- [x] 客户端 FSM/Animation/Move/Controller — task-08 实现，符合 plan

### 未在 task-06 develop-log 中明确记录
- [ ] `schedule_handlers.go` — RoadNetQuerier 接口扩展按类型查询。plan 要求此文件；develop-log 未记录修改。可能在 task-02 中处理，需确认

### 偏差
- 无明显偏差，实现与 plan 设计一致

---

## 三、边界情况

[HIGH] BigWorldNpcAnimationComp.cs:302 — `state.Clip.wrapMode = WrapMode.Loop` 修改共享 AnimationClip 资产
  场景: PlayMoveWithCrossFade 调用时，若动画 Clip 的 isLooping=false，代码修改 `AnimationClip.wrapMode`
  影响: AnimationClip 是共享资产，修改 wrapMode 影响所有使用该 Clip 的 NPC 实例；Editor 模式下永久修改资产；Build 中多实例共享内存 Clip 对象，行为不可预期
  建议: 删除此 if 块，改在 Animancer 过渡配置中设置 `isLooping=true`，或调用 Animancer 的 `state.IsLooping = true`（避免修改底层 AnimationClip 资产）

[HIGH] bigworld_ext_handler.go:69,74,80,97,123,132,153,156,157,161,186 — 日志模块标签格式违规（13 处）
  场景: 所有日志使用 `"BigWorldExtHandler.MethodName: ..."` 格式
  影响: 违反 P1GoServer logging.md 规范（统一格式 `[ModuleName] 描述, key=%v`），grep `[BigWorldExtHandler]` 无法定位任何日志，运维排查困难
  建议: 全量替换：`BigWorldExtHandler.loadScheduleConfig:` → `[BigWorldExtHandler]`，其余同理（共 13 处，全量覆盖）

[MEDIUM] BigWorldNpcFsmComp.cs:210 — leftFootVector.y 未清零
  场景: 计算左右脚前后位置时，仅 `rightFootVector.y = 0`，leftFootVector 保留 Y 分量
  影响: 坡道/台阶场景下 Vector3.Dot 结果因 Y 分量偏差，"左脚是否在前"判断出错，步伐动画相位同步不准确
  建议: 在 rightFootVector.y = 0 之后添加 `leftFootVector.y = 0;`

[MEDIUM] BigWorldNpcFsmComp.cs:71-73 — BigWorldNpcMoveState 重复注册导致状态索引歧义
  场景: Move=2 和 Run=3 均注册为 BigWorldNpcMoveState，_stateTypes 索引 1 和 2 类型相同
  影响: `ChangeState<BigWorldNpcMoveState>()` 的 IndexOf 始终返回 1；服务端下发 Run 后 _stateId=2，MoveMode 驱动再次切换时将 _stateId 重置为 1，导致下次收到 Run 消息时 `_stateId != localIndex` 判断失败，跳过 FSM 切换
  建议: 单独定义 `BigWorldNpcRunState`（复用 MoveState 逻辑），或不依赖服务端 Run 枚举（仅保留 Move/Stop，Walk/Run 由 AnimationComp 根据速度区分）

[MEDIUM] BigWorldNpcMoveComp.cs:86 — `_controller.GetTransform()` 每帧调用未缓存
  场景: OnUpdate 每帧执行，GetTransform() 可能触发 GetComponent 类型查询
  影响: 20 个 NPC 实例每帧调用，积累轻微 GC 压力，不符合热路径零分配要求
  建议: 在 OnAdded（所有组件已注册）时缓存 `_cachedTransform`，OnClear 时清空

---

## 四、代码质量

[HIGH] bigworld_ext_handler.go 全文（同 HIGH#2）— 日志格式系统性违规，13 处，需全量修复，不可只改部分

[MEDIUM] patrol_route_manager.go:97 — `direction >= 0` 包含无效值 direction=0
  `if len(node.Links) > 0 && direction >= 0` 中，direction=0 不是合法值（约定为 1/-1），会错误走正向分支
  建议: 改为 `direction > 0`

[MEDIUM] bigworld_ext_handler.go:124 — fmt.Errorf 中 `cfgId=` 与日志中 `npc_cfg_id=` 命名不一致
  `return fmt.Errorf("...: entity 为 nil, cfgId=%v", cfgId)` 与日志字段命名不一致
  建议: 统一改为 `npc_cfg_id=%v`

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     2 个（必须修复）
  MEDIUM:   5 个（强烈建议修复）

  结论: **需修复后再提交**

  重点关注:
  1. [HIGH] BigWorldNpcAnimationComp.cs:302 — AnimationClip.wrapMode 共享资产修改，Build 中多实例行为不可预期，需改用 Animancer state API
  2. [HIGH] bigworld_ext_handler.go 全文13处 — 日志模块标签格式违规，需全量替换为 `[BigWorldExtHandler]` 格式
  3. [MEDIUM] BigWorldNpcFsmComp.cs — Run/Move 双注册导致 _stateId 索引歧义（建议拆分 RunState）；leftFootVector.y 未清零（一行修复）

<!-- counts: critical=0 high=2 medium=5 -->
