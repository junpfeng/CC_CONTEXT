# 设计文档：行为树行为节点重构

## 一、需求回顾

以 BTree.md 设计原则重构现有行为树系统：
- 引入行为节点层（NPC 自然行为语义）
- 将 executor.go 中 16+ 个硬编码 handler 迁移为 BT 配置驱动
- 简化 JSON 树配置（原子节点组合 → 单个行为节点）

## 二、现状分析

### 当前执行流程

```
GSS Brain 产生 Plan → OnPlanCreated 遍历 Tasks:
    ├── Channel 1: task.Name 匹配注册的 BT 树 → btRunner.Run()
    └── Channel 2: 无匹配 → executeTask() → switch(taskType) → handleXxxTask()
```

### 关键发现

1. **9 个 Plan 已有 JSON 树配置**（idle/home_idle/move/dialog/pursuit/investigate/meeting_idle/meeting_move/sakura_npc_control）
2. **当前 JSON 树使用原子节点组合**（如 move_entry.json 有 20+ 原子节点）
3. **4 个行为节点已存在**：StartPursuit, StopPursuit, EnterDialog, ExitDialog（在 action_nodes.go）
4. **OnPlanCreated 只匹配 task.Name**，没有按 `planName + "_" + phase` 构造树名的逻辑
5. **executor_helper.go** 包含共用工具函数（getTransformFromFeatures, setupNavMeshPathToFeaturePos 等）

## 三、整体设计

### 3.1 改动范围

| 改动项 | 文件 | 说明 |
|--------|------|------|
| 重命名 4 个节点 | `nodes/action_nodes.go` → `nodes/behavior_nodes.go` | 改名 + 别名兼容 |
| 新增 13 个行为节点 | `nodes/behavior_nodes.go` | 封装 handler 逻辑 |
| 注册新节点 | `nodes/factory.go` | RegisterWithMeta |
| 增强调度逻辑 | `decision/executor.go` | 添加 planName+phase 构造查找 |
| 更新 JSON 树配置 | `bt/trees/*.json` | 用行为节点替代原子组合 |
| 标记废弃 handler | `decision/executor.go` | 添加 Deprecated 注释 |

### 3.2 不改动范围

| 不改动 | 原因 |
|--------|------|
| GSS Brain 输出 | 纯内部重构，不改变 Plan/Task 数据结构 |
| BtRunner / BtContext | 行为节点通过 ctx.Scene 访问组件，不需要修改 |
| plan_config.json | 三阶段映射保持不变 |
| init Plan 的 handler | 一次性初始化逻辑，不适合 BT 化 |
| Main Task handler（均为空操作） | 现有 JSON main 树已处理 |

## 四、行为节点详细设计

### 4.1 重命名节点（4 个）

| 当前名 | 新名 | 注册别名 | BTree.md 对应 |
|--------|------|----------|---------------|
| `StartPursuit` | `ChaseTarget` | `StartPursuit` | ChaseTarget |
| `StopPursuit` | `ClearPursuitState` | `StopPursuit` | ClearPursuitState |
| `EnterDialog` | `StartDialog` | `EnterDialog` | StartDialog |
| `ExitDialog` | `EndDialog` | `ExitDialog` | EndDialog |

**别名策略**：在 factory.go 中同时注册新名和旧名（指向同一个 creator），确保现有 JSON 配置（如 pursuit_entry.json 使用 `StartPursuit`）不会立即失效。

### 4.2 新增行为节点（13 个）

#### 移动行为

**GoToSchedulePoint** ← `handleMoveEntryTask` (lines 970-1080)
```
语义：NPC 按日程走到下一个地点
参数：无
同步：是（设置路点后由移动系统驱动）
逻辑：
  1. 获取 NpcScheduleComp → 当前日程
  2. 获取 DecisionComp → feature_args1
  3. 如果 feature_args1 == "pathfind_completed" → 清除标记，返回 Success
  4. 获取 feature_start_point、feature_end_point
  5. 获取旋转特征值
  6. RoadNetworkMgr.FindPathToVec3List(start, end)
  7. npcMoveComp.StartMove() → SetPathFindType(RoadNetwork) → SetPointList
组件依赖：NpcMoveComp, NpcScheduleComp, DecisionComp, Transform
资源依赖：TimeMgr, RoadNetworkMgr
```

**GoToMeetingPoint** ← `handleMeetingMoveEntryTask` (lines 1110-1161)
```
语义：NPC 走到会议地点
参数：无
同步：是
逻辑：
  1. 获取 Transform → 当前位置
  2. RoadNetworkMgr.FindNearestPointID(当前位置) → startPoint
  3. 获取 feature_meeting_end_point → endPoint
  4. 获取旋转特征值
  5. RoadNetworkMgr.FindPathToVec3List(start, end)
  6. npcMoveComp.SetPointList("gotoMeeting", pathList, rot) → StartMove()
组件依赖：NpcMoveComp, DecisionComp, Transform
资源依赖：RoadNetworkMgr
```

**GoToInvestigatePos** ← `handleInvestigateEntryTask` (lines 622-634)
```
语义：NPC 走到调查位置
参数：无
同步：是
逻辑：
  1. setupNavMeshPathToFeaturePos 的封装
  2. StopMove → SetPathFindType(NavMesh) → SetTarget(WayPoint)
  3. 从特征值获取目标坐标 → NavMesh.FindPath → SetPointList
组件依赖：NpcMoveComp, DecisionComp, Transform
资源依赖：NavMeshMgr
```

**ReturnToSchedule** ← `handlePursuitToMoveTransition` + `handleSakuraNpcControlToMoveTransition` (lines 706-736, 674-704)
```
语义：从当前位置回归日程路线（用于 pursuit→move、sakura_control→move 过渡）
参数：无
同步：是
逻辑：
  1. setupNavMeshPathToFeaturePos 的封装
  2. SetFeature(feature_args1, "pathfind_completed")
组件依赖：NpcMoveComp, DecisionComp, Transform
资源依赖：NavMeshMgr
```

**StopMoving** ← `handleMoveExitTask` + `handleMeetingMoveExitTask` (lines 1083-1100, 1164-1174)
```
语义：NPC 停下来
参数：无
同步：是
逻辑：npcMoveComp.StopMove()
组件依赖：NpcMoveComp
```

#### 驻留行为

**StandAtSchedulePos** ← `handleIdleEntryTask` (lines 905-967)
```
语义：NPC 站在日程位置上等待
参数：无
同步：是
逻辑：
  1. 获取 NpcScheduleComp → 当前日程 → serverTimeout / clientTimeout
  2. 如果 serverTimeout > 0 → dialogComp.SetOutFinishStamp(now + timeout)
  3. 如果 clientTimeout > 0 → townNpcComp.SetOutDurationTime(timeout)
  4. setTransform (从特征值设置位置和旋转)
组件依赖：NpcScheduleComp, DialogComp, TownNpcComp, DecisionComp, Transform
资源依赖：TimeMgr
```

**StandAtHomePos** ← `handleHomeIdleEntryTask` (lines 795-814)
```
语义：NPC 站在家里
参数：无
同步：是
逻辑：
  1. SetFeature(feature_out_timeout, true)
  2. setTransform (从特征值设置位置和旋转)
组件依赖：DecisionComp, Transform
```

**StandAtMeetingPos** ← `handleMeetingIdleEntryTask` (lines 1103-1107)
```
语义：NPC 站在会议位置上
参数：无
同步：是
逻辑：setMeetingTransform (从 feature_meeting_pos/rot 设置位置和旋转)
组件依赖：DecisionComp, Transform
```

#### 交易行为

**StartProxyTrade** ← `handleProxyTradeEntryTask` (lines 1273-1284)
```
语义：NPC 进入代理交易
参数：无
同步：是
逻辑：proxyTradeComp.SetTradeStatus(TradeStatus_InTrade)
组件依赖：TradeProxyComp
```

**EndProxyTrade** ← `handleProxyTradeExitTask` (lines 1342-1352)
```
语义：NPC 退出代理交易
参数：无
同步：是
逻辑：proxyTradeComp.SetTradeStatus(TradeStatus_None)
组件依赖：TradeProxyComp
```

#### 控制行为

**EnterPlayerControl** ← `handleSakuraNpcControlEntryTask` (lines 1243-1271)
```
语义：NPC 被玩家控制
参数：无
同步：是
逻辑：
  1. npcMoveComp.StopMove()
  2. controlComp.SetEventType(Control_EventType_None)
组件依赖：NpcMoveComp, SakuraNpcControlComp
```

**ExitPlayerControl** ← `handleSakuraNpcControlExitTask` (lines 1287-1315)
```
语义：NPC 退出玩家控制
参数：无
同步：是
逻辑：
  1. controlComp.SetEventType(Control_EventType_None)
  2. setupNavMeshPathToFeaturePos（预设寻路路径，配合后续 move）
组件依赖：SakuraNpcControlComp, NpcMoveComp, DecisionComp, Transform
资源依赖：NavMeshMgr
```

#### 清理行为

**ClearInvestigateState** ← `handleInvestigateExitTask` (lines 637-661)
```
语义：清除调查相关状态
参数：无
同步：是
逻辑：
  1. policeComp.SetInvestigatePlayer(0)
  2. SetFeature(feature_release_wanted, false)
  3. SetFeature(feature_pursuit_miss, false)
组件依赖：NpcPoliceComp, DecisionComp
```

### 4.3 未覆盖的 Handler 处理

| Handler | 处理方式 | 原因 |
|---------|---------|------|
| `handleIdleExitTask` | 用原子节点在 JSON exit 树中处理 | 逻辑极简（SetOutFinishStamp(0)），已有 SetDialogOutFinishStamp 原子节点 |
| `handleHomeIdleExitTask` | 用原子节点在 JSON exit 树中处理 | 逻辑极简（SetFeature(knock_req, false)），已有 SetFeature 原子节点 |
| `handleInitMainTask` | 保留为 handler | 一次性初始化逻辑（读DB/Config），不属于常规 NPC 行为 |
| `handleInitExitTask` | 保留（空操作） | 无逻辑 |
| `handleXxxMainTask`（5个空操作） | 现有 JSON main 树已覆盖 | 均为空函数 |

## 五、OnPlanCreated 调度增强

### 当前问题

`OnPlanCreated` 只检查 `task.Name` 是否匹配已注册的 BT 树。如果 GSS Brain 没有设置 task.Name 为树名（如 "pursuit_entry"），即使 JSON 树已注册也不会被使用。

### 解决方案

添加第二层查找——从 `planName + "_" + phase` 构造树名：

```go
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    for _, task := range req.Plan.Tasks {
        // Step 1: task.Name 直接匹配（现有逻辑，不变）
        if task.Name != "" && e.btRunner != nil && e.btRunner.HasTree(task.Name) {
            e.btRunner.Run(task.Name, uint64(req.EntityID))
            continue
        }

        // Step 2: 从 planName + phase 构造树名（新增）
        treeName := e.buildPhasedTreeName(req.Plan.Name, task.Type)
        if treeName != "" && e.btRunner != nil && e.btRunner.HasTree(treeName) {
            e.btRunner.Run(treeName, uint64(req.EntityID))
            continue
        }

        // Step 3: 回退到硬编码 handler（现有逻辑，不变）
        e.executeTask(req.EntityID, req.Plan.Name, req.Plan.FromPlan, task)
    }
    return nil
}

func (e *Executor) buildPhasedTreeName(planName string, taskType int) string {
    switch taskType {
    case decision.TaskTypeGSSEnter:
        return planName + "_entry"
    case decision.TaskTypeGSSExit:
        return planName + "_exit"
    case decision.TaskTypeGSSMain:
        return planName + "_main"
    default:
        return "" // Transition 仍用 task.Name 匹配
    }
}
```

**效果**：只要 JSON 树以 `{planName}_{phase}` 命名并注册，即自动走 BT 通道。

### Transition Task 处理

Transition 类型的 task（如 `pursuit_to_move_transition`）保持用 task.Name 匹配。需要为 transition 也注册 JSON 树：

```json
{
  "name": "pursuit_to_move_transition",
  "root": { "type": "ReturnToSchedule" }
}
```

## 六、JSON 树配置更新

### 6.1 使用行为节点的简化配置

**Before (pursuit_entry.json - 当前)**:
```json
{
  "name": "pursuit_entry",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "Log", "params": {"message": "[PursuitEntry] start", "level": "debug"}},
      {"type": "StartPursuit"},
      {"type": "Log", "params": {"message": "[PursuitEntry] completed", "level": "info"}}
    ]
  }
}
```

**After (pursuit_entry.json - 重构后)**:
```json
{
  "name": "pursuit_entry",
  "root": { "type": "ChaseTarget" }
}
```

### 6.2 各 Plan 配置更新清单

| Plan | Phase | 当前 JSON | 改为 |
|------|-------|----------|------|
| pursuit | entry | Sequence[Log, StartPursuit, Log] | `ChaseTarget` |
| pursuit | exit | Sequence[Log, StopPursuit, Log] | `ClearPursuitState` |
| dialog | entry | Sequence[Log, EnterDialog, Log] | `StartDialog` |
| dialog | exit | Sequence[Log, ExitDialog, Log] | `EndDialog` |
| move | entry | 复杂原子组合 (20+ 节点) | `GoToSchedulePoint` |
| move | exit | Sequence[StopMove, Log] | `StopMoving` |
| idle | entry | 复杂原子组合 (15+ 节点) | `StandAtSchedulePos` |
| idle | exit | 需创建/更新 | Sequence[SetDialogOutFinishStamp(0)] |
| home_idle | entry | 需检查 | `StandAtHomePos` |
| home_idle | exit | 需检查 | Sequence[SetFeature(knock_req, false)] |
| meeting_idle | entry | 需检查 | `StandAtMeetingPos` |
| meeting_move | entry | 需检查 | `GoToMeetingPoint` |
| meeting_move | exit | 需检查 | `StopMoving` |
| investigate | entry | 需检查 | `GoToInvestigatePos` |
| investigate | exit | 需检查 | `ClearInvestigateState` |
| sakura_npc_control | entry | 需检查 | `EnterPlayerControl` |
| sakura_npc_control | exit | 需检查 | `ExitPlayerControl` |
| proxy_trade | entry | 需创建 | `StartProxyTrade` |
| proxy_trade | exit | 需创建 | `EndProxyTrade` |
| - | transition | 需创建 | `ReturnToSchedule`（2个 transition 共用） |

### 6.3 新增 JSON 配置文件

需要为 proxy_trade 和 transition 新增配置（其他 Plan 已有 JSON 文件）：

- `proxy_trade_entry.json`
- `proxy_trade_exit.json`
- `proxy_trade_main.json`
- `pursuit_to_move_transition.json`
- `sakura_npc_control_to_move_transition.json`

plan_config.json 需新增 proxy_trade 条目。

## 七、文件改动清单

### 业务工程 (P1GoServer/)

```
servers/scene_server/internal/common/ai/bt/
├── nodes/
│   ├── action_nodes.go → 重命名为 behavior_nodes.go
│   │   - 重命名 4 个现有节点（保留旧类型名做别名）
│   │   - 新增 13 个行为节点
│   │
│   └── factory.go
│       - 注册 13 个新节点（RegisterWithMeta）
│       - 为 4 个重命名节点注册别名
│
├── trees/
│   ├── 更新 ~17 个现有 JSON 文件（用行为节点替代原子组合）
│   ├── 新增 ~5 个 JSON 文件（proxy_trade + transition）
│   └── plan_config.json（新增 proxy_trade 条目）
│
└── (不改) config/, context/, node/, runner/

servers/scene_server/internal/ecs/system/decision/
├── executor.go
│   - OnPlanCreated 添加 buildPhasedTreeName 逻辑
│   - 被 BT 替代的 handler 添加 Deprecated 注释
│
└── (不改) executor_helper.go, executor_resource.go
```

## 八、迁移策略

### 阶段 1：基础设施（无行为变更）
1. 重命名 action_nodes.go → behavior_nodes.go
2. 重命名 4 个现有节点 + 注册别名
3. OnPlanCreated 添加 buildPhasedTreeName
4. 构建验证

### 阶段 2：实现行为节点（无行为变更）
1. 实现 13 个新行为节点
2. 在 factory.go 注册
3. **不更新 JSON 配置** — 新节点已注册但未被引用，不影响现有行为
4. 构建验证 + 单元测试

### 阶段 3：切换执行通道
1. 更新 JSON 树配置，用行为节点替代原子组合
2. 新增 proxy_trade 和 transition 的 JSON 配置
3. 更新 plan_config.json
4. 此时 BT 通道接管，handler 不再被触发
5. 全量测试验证

### 阶段 4：清理
1. 被替代的 handler 标记 Deprecated
2. 确认稳定后，后续版本删除

## 九、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 行为节点逻辑与 handler 不完全一致 | NPC 行为异常 | 逐个对比 handler 代码，行为节点内部实现 1:1 复制 |
| buildPhasedTreeName 导致原本不走 BT 的 task 被路由到 BT | 行为变更 | 阶段 1 不更新 JSON，先验证调度逻辑正确 |
| 日志格式变化 | 不影响功能，但影响日志排查 | 行为节点保持与 handler 相同的日志格式和级别 |
| 别名注册冲突 | 编译错误 | 别名直接指向同一个 creator，无冲突 |
| NavMesh/RoadNetwork 寻路节点需要 executor_helper 中的工具函数 | 代码重复 | 将通用逻辑抽取为 bt/nodes 包的工具函数 |

## 十、通用工具函数

行为节点需要复用 executor_helper.go 中的工具逻辑。设计方案：

在 `bt/nodes/` 新增 `behavior_helpers.go`，提供行为节点共用的工具函数：

```go
// getTransformFromFeatures 从特征值获取位置和旋转
func getTransformFromFeatures(ctx *context.BtContext) (pos, rot transform.Vec3, ok bool)

// setTransformFromFeatures 从特征值设置 Transform 组件
func setTransformFromFeatures(ctx *context.BtContext) bool

// setMeetingTransformFromFeatures 从会议特征值设置 Transform 组件
func setMeetingTransformFromFeatures(ctx *context.BtContext) bool

// setupNavMeshPath 使用 NavMesh 从当前位置寻路到特征值坐标
func setupNavMeshPath(ctx *context.BtContext) (*transform.Vec3, int, error)

// clearDialogEventFeatures 清除对话相关特征
func clearDialogEventFeatures(ctx *context.BtContext)

// updateFeature 更新单个特征值
func updateFeature(ctx *context.BtContext, key string, value any)

// updateFeatures 批量更新特征值
func updateFeatures(ctx *context.BtContext, features map[string]any)
```

这些函数使用 `*context.BtContext` 而非 `*Executor`，解耦对 executor 的依赖。
