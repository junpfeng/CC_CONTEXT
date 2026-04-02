# NPC 日程与巡逻系统——设计审查报告

> 审查日期：2026-03-13 | 审查对象：tech-design.md v1.0 | 状态：**全部已修复** — 详见 `review-report.md`（FIX-1~FIX-9）

## 必须修改（5 项）

### R1. CurrentPlan 路由存在一帧延迟 [架构]

ScheduleHandler 通过设置 `ScheduleState.CurrentPlan` 间接控制 Brain 输出 plan name，但 Brain 在下一帧才读取该字段，导致行为切换有一帧延迟。

**建议**：ScheduleHandler 内部直接 dispatch 子 Handler（通过 PlanExecutor 的 plan 切换机制），不走 Brain 二次决策。或在文档中明确标注此延迟可接受。

### R2. FieldAccessor 必须注册新增字段 [架构]

`field_accessor.go` 的 `resolveSchedule` 必须注册 5 个新增字段（ScheduleTemplateId / PatrolRouteId / PatrolDirection / ScenarioPointId / AlertLevel），否则 V2Brain 条件表达式 `schedule.templateId > 0` 等全部解析失败。

**影响**：§6.3 的 locomotion 决策配置将完全无法工作。

### R3. CleanupNpcResources 清理范围不完整 [事务性]

§7.1 遗漏了巡逻节点互斥占用（`nodeOccup` map）的释放。NPC Despawn 时如果正停留在节点上，该节点将永久被标记"已占用"。

**建议**：
- PatrolRouteManager 新增 `ReleaseNodeOccup(npcId)` 方法
- 增加 `npcToRoute map[int64]int32` 反向索引（解决 ReleaseNpc 需要 routeId 的问题）
- 在 CleanupNpcResources 中明确列出完整清理清单

### R4. nil map panic 风险 [安全]

`ScenarioPoint.OccupiedNpcs` 和 `PatrolRoute.AssignedNpcs` 为 `map[int64]bool`，JSON 反序列化时若字段缺失，map 为 nil，写入时 panic。

**建议**：Manager 构造函数或配置加载后统一初始化 map。

### R5. NpcGroupWeights 零权重死循环 [安全]

`PopAllocation.NpcGroupWeights` 若所有权重为 0 或负值，`SelectNpcType` 随机选择将失败或死循环。

**建议**：加载时校验至少有一个正权重。

## 推荐修改（7 项）

### S1. 场景点阶段切换同步策略未明确 [协议]

ScenarioPhase 有 Enter/Loop/Leave 三阶段，但 Ntf 只有 Enter 和 Leave。Enter→Loop 的切换时机如何通知客户端？需明确是靠 TownNpcData 帧同步还是需要补充 Ntf。

### S2. NpcPatrolData 缺少 direction 字段 [协议]

服务端有 `PatrolDirection`，但 NpcPatrolData 未传输。若客户端需要区分正/反向（如朝向插值），需补充。

### S3. PatrolNode.BehaviorType 类型不一致 [协议]

服务端定义为 `string`（动画哈希），但 NpcPatrolNodeArriveNtf.behavior_type 为 `int32`。需统一。

### S4. CurrentNpcCount 与 len(AssignedNpcs) 描述矛盾 [事务性]

§3.6 ReleaseNpc 说明写 "CurrentNpcCount--"，与 §7.2 "用 len(map) 代替独立 counter" 矛盾。建议删除独立 counter 字段，或标注为 computed property。

### S5. PopScheduleManager 降频评估 [架构]

每帧调用 Evaluate 不必要，配额变化仅在时段切换时发生。建议降频到每秒或时段切换时评估。

### S6. SpatialGrid 坐标边界检查 [安全]

极端坐标可导致 CellKey 计算异常，大量点映射到同一 cell。建议 Insert 时校验坐标范围。

### S7. PauseAccum 上限保护 [安全]

虽然 int64 溢出极难触发，但若中断状态因 bug 无法恢复，建议添加上限 clamp + Error 日志。

## 确认无问题

- NpcState 枚举值 17-20 与现有值连续无冲突
- TownNpcData 字段号 17-19 无冲突，向后兼容
- 枚举命名前缀（SBT_/SP_/SCR_/PAL_）有效避免 proto3 命名空间冲突
- Handler 共享单例模式正确，状态存 NpcState
- 依赖注入方案（接口隔离 + npc_mgr 装配）可行
- ScheduleState 值类型 struct copy 自动包含新字段
- 单线程并发模型正确，无需加锁
- 平方距离判断符合项目规范
- 场景点 Occupy/Release 方案在单线程下足够
- deprecated 双写过渡方案合理
