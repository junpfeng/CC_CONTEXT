# NPC 日程与巡逻系统 — Phase 6 审查报告

## 审查结果总览

| 审查维度 | 结果 | 发现问题 | 已修复 |
|----------|------|---------|--------|
| 代码质量 | 通过 | 5 个 | 5 个 |
| 安全审查 | 通过 | 2 中 + 3 建议 | 5 个 |
| 事务性审查 | 通过 | 3 严重 + 5 建议 | 5 个 |
| 测试覆盖 | 通过 | 4 个 P0 缺口 | 4 个 |

## 已修复问题

### FIX-1: distanceSqToTarget 使用 3D 距离（严重）
- **文件**: `handlers/util.go:26`
- **问题**: 包含 Y 轴的 3D 欧氏距离，斜坡/台阶上无法判定到达
- **修复**: 改为 XZ 平面距离 `dx*dx + dz*dz`

### FIX-2: NpcID=0 占位写入（严重）
- **文件**: `handlers/schedule_handlers.go:99`
- **问题**: `ctx.NpcState.Self.NpcID = 0` 清零了 NPC 身份标识
- **修复**: 移除该行

### FIX-3: PatrolHandler.OnExit 未释放路线分配（严重）
- **文件**: `handlers/schedule_handlers.go:276`
- **问题**: 仅释放节点互斥，未释放路线 AssignedNpcs，导致正常切 plan 时路线计数泄漏
- **修复**: OnExit 追加 `ReleaseAllByNpc` 调用，PatrolQuerier 接口同步更新

### FIX-4: ScenarioHandler 占用无超时保护（严重）
- **文件**: `handlers/schedule_handlers.go:352-358`
- **问题**: NPC 寻路卡死时场景点被永久占用
- **修复**: 占用时记录超时截止（NextNodeTime 负值编码），移动阶段 30s 超时强制释放

### FIX-5: ScenarioHandler 硬编码 30s duration
- **文件**: `handlers/schedule_handlers.go` + `state/npc_state.go`
- **问题**: 场景点停留时长固定 30s，忽略配置表 Duration 字段
- **修复**: ScenarioPointResult 新增 Duration 字段，占用时保存到 ScheduleState.ScenarioDuration，到达后优先使用配置值

### FIX-6: ScenarioPointManager 接口适配
- **文件**: `npc_mgr/scenario_adapter.go`（新建）
- **问题**: ScenarioPointManager.FindNearest 返回 `*ScenarioPoint`，与 ScenarioFinder 接口的 `*ScenarioPointResult` 不匹配
- **修复**: 创建 scenarioFinderAdapter 适配器，同时实现 ScenarioFinder + ScenarioNpcCleaner

### FIX-7: PopScheduleManager totalQuota 溢出保护
- **文件**: `schedule/pop_schedule_manager.go:58-88`
- **问题**: 四个 int32 字段相加可能溢出为负值，导致错误的 Despawn
- **修复**: SetAllocation 时钳位负值为 0，总量超 1000 按比例截断

### FIX-8: PatrolHandler OnTick 重试冷却
- **文件**: `handlers/schedule_handlers.go:218-232`
- **问题**: AssignNpc 失败后每帧重试，浪费 CPU
- **修复**: 分配失败后设 5 秒冷却间隔（复用 NextNodeTime 字段）

### FIX-9: 客户端 NpcId 负值校验
- **文件**: 5 个 Ntf handler（NpcScheduleChangeNtf/NpcPatrolNodeArriveNtf/NpcPatrolAlertChangeNtf/NpcScenarioEnterNtf/NpcScenarioLeaveNtf）
- **问题**: long→ulong 强转时负值变为极大正整数，静默丢弃
- **修复**: 添加 `NpcId <= 0` 前置检查，Warning 日志

## 已确认的误报

| 审查结论 | 实际情况 |
|----------|---------|
| PatrolRouteManager 未实现 PatrolQuerier 接口 | ✅ 已实现（reviewer 漏检 GetNodePosition/GetNodeDuration） |
| ScheduleHandler 从不写入 CurrentPlan="schedule" | ✅ case 4/5/7 分别写入 patrol/scenario/guard，idle 由 setNpcNpcStateIdle 处理 |

## 测试补充

### PopScheduleManager（9 个新测试）
- Evaluate: Spawn/Despawn/NoChange/Override/EmptyRegion/NegativeFields
- GetTimeSlot: 9 个边界值
- SelectNpcType: 权重随机 + 空权重

### Handler 层（16 个新测试）
- ScheduleHandler: NoTemplate/BehaviorTypePatrol/Scenario/Guard/OnExit
- PatrolHandler: OnEnter/RouteIdZero/ArriveAtNode/StayExpired/OnExit
- ScenarioHandler: FindAndOccupy/OccupyTimeout/ArriveAndExecute/DurationExpired/OnExit
- GuardHandler: OnTick

## 构建验证

- `make build`（16 个微服务） ✅
- `make test`（全部测试） ✅ 无 FAIL
- `make robot` ✅
