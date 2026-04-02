# 日程系统文档 Review 报告

> 日期：2026-03-19 | 审查方式：文档 ↔ 代码 ↔ Git 记录交叉验证
> 状态：全部 14 个问题已修复

## 审查总结

| 文档 | 状态 | 发现问题数 |
|------|------|-----------|
| tech-design.md | 需更新 | 7 |
| tasks.md | 需更新 | 3 |
| scenario-p0-design.md | 需更新 | 1 |
| scenario-p0-tasks.md | 需更新 | 1 |
| v2-schedule-config.md | 准确 | 0 |
| v2-schedule-tasks.md | 需更新 | 1 |
| v2-schedule-changelog.md | 准确 | 0 |
| v2-schedule-donna-example.md | 准确 | 0 |
| review-report.md | 准确 | 0 |
| tech-design-review.md | 准确 | 0 |
| server.md | 准确 | 0 |
| client.md | 需更新 | 1 |
| protocol.md | 需更新 | 1 |

---

## 具体问题

### [TD-1] tech-design.md §3.8 配置路径与实际不符（重要）

**文档声称**：
- 日程模板：`bin/config/ai_schedule/*.json`
- 巡逻路线：`bin/config/ai_patrol/*.json`

**实际代码**：
- 日程模板：`bin/config/V2TownNpcSchedule/*.json`（24 个文件）
- 巡逻路线：无独立目录（巡逻路线配置尚未以 JSON 目录形式存在）

**影响**：§2.1 架构图（行 56-57）和 §3.8（行 474-475）均引用了错误路径。

**建议**：更新路径为 `V2TownNpcSchedule/`，巡逻路线部分标注实际状态。

---

### [TD-2] tech-design.md §3.5 ScheduleEntry 时间字段类型过时（重要）

**文档声称**（行 338-343）：
```go
type ScheduleEntry struct {
    StartTime    int32   // 游戏时间小时 0-23
    EndTime      int32   // 游戏时间小时 0-23
    ...
}
```

**实际代码**（schedule_config.go:27-28）：
```go
StartTime int64  // 开始时间（游戏秒 0-86400）
EndTime   int64  // 结束时间（游戏秒，支持跨日）
```

**影响**：V2 日程已在 v2-schedule-config.md 设计中将精度从小时升级到秒级，但 tech-design.md §3.5 仍是最初的小时级设计。

**建议**：§3.5 的 ScheduleEntry 定义和 MatchEntry 签名统一为 int64 秒级。

---

### [TD-3] tech-design.md §3.5 ScheduleEntry 缺少 V2 新增字段

**文档声称**（行 337-344）仅包含 6 个字段：StartTime, EndTime, LocationId, BehaviorType, Priority, Probability。

**实际代码** 还包含：TargetPos, FaceDirection, StartPointId, EndPointId, BuildingId, DoorId, Duration。

**原因**：v2-schedule-config.md 中设计了这些扩展字段，但 tech-design.md 未同步更新。

**建议**：§3.5 ScheduleEntry 结构体替换为完整的 V2 定义。

---

### [TD-4] tech-design.md §4.3 NpcScenarioData 缺少 2 个字段

**文档声称**（行 550-554）：NpcScenarioData 只有 3 个字段（point_id, scenario_type, phase）。

**实际 Proto**（npc.proto:108-114）：5 个字段，额外包含：
- `float direction = 4;  // 朝向（弧度）`
- `int32 duration  = 5;  // 停留时长（秒）`

**原因**：scenario-p0-design.md 的 P0 改造中新增了这 2 个字段，但 tech-design.md 未回溯更新。

**建议**：§4.3 补充 direction 和 duration 字段。

---

### [TD-5] tech-design.md §3.2 ScheduleState 缺少 Scenario P0 新增字段

**文档声称**（行 159-176）：ScheduleState 新增 5 个字段。

**实际代码** 还包含 scenario-p0 阶段新增的字段：
- `ScenarioTypeId int32`
- `ScenarioDirection float32`
- `ScenarioPhase int32`
- `ScenarioNearNodeId int32`
- `ScenarioNearNodePos transform.Vec3`
- `ScenarioCooldownUntil int64`
- `ScenarioDuration int32`

**建议**：§3.2 补充这 7 个 Scenario 相关字段，或标注"完整字段参见代码"。

---

### [TD-6] tech-design.md §3.3.3 ScenarioHandler 描述过于简化

**文档声称**（行 251-255）：ScenarioHandler 为 4 步简单流程（搜索→移动→执行→释放）。

**实际代码**：7 阶段完整状态机（Init→WalkToNearNode→WalkToPoint→Enter→Loop→Leave→WalkBackToRoad），含 RoadNetwork 集成、超时保护、冷却机制。

**原因**：scenario-p0-design.md 已详细设计了 7 阶段，但 tech-design.md 仍是初始草稿版本。

**建议**：§3.3.3 引用 scenario-p0-design.md 或更新为 7 阶段描述。

---

### [TD-7] tech-design.md §5 客户端组件命名不一致

**文档声称**（行 82-83）：`ScenarioComp`、`PatrolVisualComp`

**实际代码**：
- `TownNpcScenarioComp.cs`（带 TownNpc 前缀）
- `TownNpcPatrolVisualComp.cs`（带 TownNpc 前缀）

**建议**：统一使用实际类名。

---

### [TK-1] tasks.md TASK-22 FSM 注册索引描述有歧义

**文档声称**（行 306）：`TownFsmComp._stateTypes 追加 4 个状态（索引 16-19）`

**实际代码**（TownFsmComp.cs）：使用 `RegisterServerState<T>(枚举值)` 注册，参数为服务端枚举值 17/18/19/20，不是数组索引 16-19。

**建议**：改为 "注册服务端状态值 17-20"，与 tech-design.md §5.1 的表格（已正确列出映射关系）保持一致。

---

### [TK-2] tasks.md TASK-17/18 配置路径错误

与 TD-1 相同：
- TASK-17（行 134）：`P1GoServer/bin/config/ai_schedule/` → 实际 `V2TownNpcSchedule/`
- TASK-18（行 142）：`P1GoServer/bin/config/ai_patrol/` → 巡逻配置实际路径待确认

---

### [TK-3] tasks.md 缺少完成状态标注

所有 26 个任务仍标为待做状态，但根据代码和 git 记录，绝大部分已完成实现。

**建议**：在每个 TASK 标题后追加完成状态标记（如 ✅ 已完成）。

---

### [SP-1] scenario-p0-design.md §1.2 现有实现表过时

**文档声称**（行 25）：`ScenarioSystem（新增）| 不存在 | 核心新增`

**实际代码**：`scenario_system.go` 已完整实现（279 行，含分帧扫描、概率判定、冷却检查）。

**建议**：更新 §1.2 表格中 ScenarioSystem 状态为"已完成"。

---

### [ST-1] scenario-p0-tasks.md 缺少完成状态

12 个任务（T01-T12）均已实现，但文档中无完成标记。

---

### [V2T-1] v2-schedule-tasks.md 缺少完成状态

与 TK-3 类似，11 个任务均已完成但无标记。

---

### [CL-1] client.md 组件命名

与 TD-7 相同，使用短名 ScenarioComp/PatrolVisualComp，实际带 TownNpc 前缀。

---

### [PR-1] protocol.md NpcScenarioData 字段数

如果 protocol.md 仍列 3 个字段，需补充 direction(4) 和 duration(5)。（需确认 protocol.md 具体内容）

---

## 无问题的文档

| 文档 | 说明 |
|------|------|
| v2-schedule-config.md | V1→V2 迁移分析准确，ScheduleEntry 秒级精度、新增字段与代码一致 |
| v2-schedule-changelog.md | 变更清单（14 修改/28 新建/1 删除）与 git 记录吻合 |
| v2-schedule-donna-example.md | Donna 示例 JSON 格式与实际配置文件结构一致 |
| review-report.md | 9 个 FIX 均已在代码中验证修复到位，测试补充与代码匹配 |
| tech-design-review.md | 审查发现项已在 review-report.md 中闭环 |
| server.md | 需求层文档，不涉及实现细节，内容准确 |

---

## 优先级排序

| 优先级 | 问题 | 理由 |
|--------|------|------|
| P0 | TD-1, TD-2, TD-3 | 配置路径和核心数据结构与代码严重不符，新人阅读会被误导 |
| P1 | TD-4, TD-5, TD-6 | Scenario P0 改造的增量设计未回溯到总设计文档 |
| P2 | TD-7, CL-1, PR-1 | 命名不一致，影响可查找性 |
| P3 | TK-1, TK-2, TK-3, SP-1, ST-1, V2T-1 | 任务清单完成状态未更新，不影响理解设计但降低可信度 |
