# 设计文档：行为树单树化重构

## 1. 需求回顾

### 1.1 现状问题

当前每种行为需要 **3 个 JSON 文件** + plan_config.json 映射：

```
idle_entry.json   → StandAtSchedulePos（进入行为）
idle_main.json    → Repeater + Wait（主循环）
idle_exit.json    → ClearIdleState（退出清理）
```

**问题**：
1. **文件膨胀**：10 个 plan × 3 = 30 个 JSON 文件 + 2 个 transition 文件 + plan_config.json
2. **映射冗余**：plan_config.json 只是机械地列出 `name → tree/entry_tree/exit_tree`
3. **调度复杂**：Executor 需要三阶段状态机（已 Deprecated 但代码仍在）+ Channel 1/1.5/2 分发
4. **exit 时机依赖外部**：树被中断时，exit 逻辑需要 Executor 额外调度

### 1.2 目标

- 每种行为 **只配置 1 个 JSON 文件**
- 行为树自身包含完整生命周期（entry + main + exit）
- 行为切换时，**退出清理自动执行**，无需外部调度
- 消除 plan_config.json 和三阶段状态机

---

## 2. 架构设计

### 2.1 核心思路：三阶段内聚到树内部

将 entry/main/exit 三阶段从 Executor 外部调度，**内聚到行为树 JSON 内部**：

```
旧方案（Executor 调度三阶段）：
  Executor → run(idle_entry) → run(idle_main) → run(idle_exit)

新方案（树自包含生命周期）：
  Executor → run(idle)
  idle 树内部：entry(Sequence第一步) → main(Repeater循环) → exit(on_exit钩子)
```

### 2.2 关键设计：on_exit 子树

**问题**：当 Brain 产生新 Plan，当前树被 `Runner.Stop()` 中断时，如何执行 exit 清理？

**方案**：BTreeConfig 新增 `on_exit` 字段，Runner.Stop 时自动执行。

```
Runner.Stop(entityID) 流程：
  1. 递归调用所有 Running 节点的 OnExit()（已有逻辑，节点级清理）
  2. 【新增】如果树配置有 on_exit，构建并执行 on_exit 子树
  3. 清理 Blackboard Observer
```

### 2.3 新 JSON 格式

```json
{
  "name": "idle",
  "description": "NPC 空闲状态",
  "on_exit": {
    "type": "ClearIdleState"
  },
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "UpdateSchedule", "params": {"interval_ms": 5000}}
    ],
    "children": [
      {"type": "StandAtSchedulePos"},
      {"type": "Repeater", "params": {"count": 0}, "child": {
        "type": "Wait", "params": {"duration_ms": 1000}
      }}
    ]
  }
}
```

**对比旧方案**：
- `entry` 逻辑（StandAtSchedulePos）→ 合并为 root Sequence 的第一个子节点
- `main` 逻辑（Repeater+Wait）→ root Sequence 后续子节点
- `exit` 逻辑（ClearIdleState）→ 放入 `on_exit` 字段

### 2.4 on_exit 执行语义

| 场景 | 节点 OnExit() | on_exit 子树 |
|------|--------------|-------------|
| 树正常完成（Success/Failed） | 调用 | 执行 |
| Runner.Stop() 中断（Plan 切换） | 调用 | 执行 |
| on_exit 子树自身执行 | - | 失败不影响，仍继续切换 |

**关键约束**：
- on_exit 子树必须是 **同步的**（OnEnter 返回 Success/Failed，不返回 Running）
- 这符合现状：所有 exit 树都是单个行为节点，同步完成

### 2.5 Transition 树的处理

当前有 2 个 transition 树：
- `pursuit_to_move_transition` → ReturnToSchedule
- `sakura_npc_control_to_move_transition` → ReturnToSchedule

这些是 **跨行为过渡**（从 A 行为切到 B 行为之间的过渡动作），由 Brain 在 Plan 的 Task 列表中通过 `task.Name` 精确匹配（Channel 1）。

**方案**：保留这些 transition JSON 文件不变。它们不属于任何单一行为，而是独立的过渡行为树。

---

## 3. 详细设计

### 3.1 BTreeConfig 变更（types.go）

```go
// BTreeConfig 行为树配置根结构
type BTreeConfig struct {
    Name        string      `json:"name"`
    Description string      `json:"description,omitempty"`
    Root        NodeConfig  `json:"root"`
    OnExit      *NodeConfig `json:"on_exit,omitempty"` // 【新增】退出时执行的清理子树
}
```

### 3.2 BtRunner 变更（runner.go）

#### Run() 无变化
Run() 逻辑不变，仍然从 `cfg.Root` 构建节点树并启动。

#### Stop() 增加 on_exit 执行

```go
func (r *BtRunner) Stop(entityID uint64) {
    instance, ok := r.runningTrees[entityID]
    if !ok {
        return
    }

    // 1. 递归调用所有运行中节点的 OnExit（已有逻辑）
    r.stopNode(instance.Root, instance.Context)

    // 2.【新增】执行 on_exit 子树（如果有）
    r.executeOnExitTree(instance)

    // 3. 清理 Observer 和脏 key（已有逻辑）
    instance.Context.RemoveObservers()
    instance.Context.ClearFrameDirtyKeys()
    delete(r.runningTrees, entityID)
}
```

#### 新增 executeOnExitTree()

```go
func (r *BtRunner) executeOnExitTree(instance *TreeInstance) {
    cfg, ok := r.treeConfigs[instance.TreeName]
    if !ok || cfg.OnExit == nil {
        return
    }

    // 从配置构建 on_exit 节点树
    exitRoot, err := r.loader.BuildNode(cfg.OnExit)
    if err != nil {
        log.Warningf("[BtRunner] build on_exit tree failed, tree=%s, err=%v",
            instance.TreeName, err)
        return
    }

    // 同步执行 on_exit（必须在一帧内完成）
    status := exitRoot.OnEnter(instance.Context)
    if status == node.BtNodeStatusRunning {
        log.Warningf("[BtRunner] on_exit tree returned Running (not supported), tree=%s",
            instance.TreeName)
        exitRoot.OnExit(instance.Context)
        return
    }
    // Success/Failed 都正常结束
    exitRoot.OnExit(instance.Context)
}
```

#### Tick() 完成时也执行 on_exit

当树正常完成（非中断）时，也需要执行 on_exit：

```go
func (r *BtRunner) Tick(entityID uint64, deltaTime float32) node.BtNodeStatus {
    // ... 现有逻辑 ...

    if status == node.BtNodeStatusSuccess || status == node.BtNodeStatusFailed {
        // 【新增】正常完成时也执行 on_exit
        r.executeOnExitTree(instance)
        // ... 现有日志 ...
    }

    return status
}
```

### 3.3 Executor 变更（executor.go）

#### OnPlanCreated() 简化

Channel 1.5 的 `buildPhasedTreeName()` 不再需要（因为不再有 `_entry/_exit/_main` 后缀树）。
但为了**向后兼容**，保留 Channel 1.5 作为 fallback，逐步迁移。

最终目标状态（迁移完成后）：

```go
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    for _, task := range req.Plan.Tasks {
        // Channel 1：task.Name 精确匹配
        if task.Name != "" && e.btRunner.HasTree(task.Name) {
            e.btRunner.Run(task.Name, uint64(req.EntityID))
            continue
        }

        // Channel 2：硬编码回退（逐步淘汰）
        e.executeTask(req.EntityID, req.Plan.Name, req.Plan.FromPlan, task)
    }
    return nil
}
```

#### 删除废弃代码

以下代码在迁移完成后可以删除：
- `PlanExecPhase` 及相关常量
- `PlanExecution` 结构体
- `handlePlanWithStateMachine()` 及关联的 startPlan/startMainTree/startExitTree/gracefulTransition/finishTransition/onTreeCompleted
- `TickPlanExecution()`
- `planConfigs` 字段和 RegisterPlanConfig/LoadPlanConfigs/GetPlanConfig
- `buildPhasedTreeName()`

### 3.4 plan_config.json 处理

**删除** `plan_config.json`，因为不再需要 plan → tree/entry_tree/exit_tree 映射。

行为树名称直接等于 plan 名称（如 `idle` 树对应 `idle` plan）。

### 3.5 JSON 文件变更

#### 10 个 plan 的合并方案

每个 plan 从 3 个文件合并为 1 个文件：

| Plan | entry 节点 | main 逻辑 | exit 节点 | 合并后 |
|------|-----------|----------|----------|--------|
| idle | StandAtSchedulePos | Repeater+Wait+UpdateSchedule | ClearIdleState | idle.json |
| home_idle | StandAtHomePos | Repeater+Wait | ClearHomeIdleState | home_idle.json |
| move | GoToSchedulePoint | Repeater+Wait | StopMoving | move.json |
| dialog | StartDialog | Repeater+Wait | EndDialog | dialog.json |
| pursuit | ChaseTarget | Selector+Service+Abort | ClearPursuitState | pursuit.json |
| investigate | GoToInvestigatePos | Repeater+Wait | ClearInvestigateState | investigate.json |
| meeting_idle | StandAtMeetingPos | Repeater+Wait | ClearMeetingIdleState（无，目前为空） | meeting_idle.json |
| meeting_move | GoToMeetingPoint | Repeater+Wait | StopMoving（复用 move exit） | meeting_move.json |
| sakura_npc_control | EnterPlayerControl | Repeater+Wait | ExitPlayerControl | sakura_npc_control.json |
| proxy_trade | StartProxyTrade | Repeater+Wait | EndProxyTrade | proxy_trade.json |

#### 合并示例：idle

**旧文件**（3 个）：
```
idle_entry.json: {"root": {"type": "StandAtSchedulePos"}}
idle_main.json:  {"root": {"type": "Sequence", "services": [...], "children": [Log, Repeater+Wait]}}
idle_exit.json:  {"root": {"type": "ClearIdleState"}}
```

**新文件**（1 个 `idle.json`）：
```json
{
  "name": "idle",
  "description": "NPC 空闲状态 - 站在日程位置，持续等待",
  "on_exit": {
    "type": "ClearIdleState"
  },
  "root": {
    "type": "Sequence",
    "services": [
      {"type": "UpdateSchedule", "params": {"interval_ms": 5000}}
    ],
    "children": [
      {"type": "StandAtSchedulePos"},
      {"type": "Repeater", "params": {"count": 0}, "child": {
        "type": "Wait", "params": {"duration_ms": 1000}
      }}
    ]
  }
}
```

#### 合并示例：pursuit（最复杂）

```json
{
  "name": "pursuit",
  "description": "NPC 追捕 - 追逐目标，目标丢失时结束",
  "on_exit": {
    "type": "ClearPursuitState"
  },
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "ChaseTarget"},
      {
        "type": "Selector",
        "services": [
          {
            "type": "SyncFeatureToBlackboard",
            "params": {
              "interval_ms": 200,
              "mappings": {"feature_pursuit_entity_id": "target_entity_id"}
            }
          }
        ],
        "children": [
          {
            "type": "Sequence",
            "decorators": [
              {
                "type": "BlackboardCheck",
                "params": {"key": "target_entity_id", "operator": "!=", "value": 0},
                "abort_type": "both"
              }
            ],
            "children": [
              {"type": "Log", "params": {"message": "[Pursuit] has target, pursuing", "level": "debug"}},
              {"type": "Repeater", "params": {"count": 0}, "child": {
                "type": "Wait", "params": {"duration_ms": 500}
              }}
            ]
          },
          {
            "type": "Sequence",
            "children": [
              {"type": "Log", "params": {"message": "[Pursuit] target lost", "level": "info"}}
            ]
          }
        ]
      }
    ]
  }
}
```

#### 保留不变的文件

- `return_to_schedule.json` — 公共子树
- `pursuit_to_move_transition.json` — 跨行为过渡
- `sakura_npc_control_to_move_transition.json` — 跨行为过渡
- `patrol.json` — 示例/测试树
- `conditional.json` — 示例/测试树
- `btree_schema.json` — JSON Schema

#### 删除的文件

- `plan_config.json`
- 20 个 `*_entry.json` 和 `*_exit.json` 文件
- 10 个 `*_main.json` 文件（被新的合并文件替代）

### 3.6 注册流程变更（example_trees.go）

#### RegisterTreesFromConfig 简化

不再需要跳过 plan_config.json 的特殊逻辑（文件已删除）。

#### 删除 RegisterTreesFromConfigWithPhases

这个函数用于注册三阶段树，不再需要。

### 3.7 树名称与 Brain Plan 的映射

**新规则**：行为树名称 == Plan 名称

```
Brain 产生 Plan "idle" → task.Name = "idle" → Channel 1 匹配 → Runner.Run("idle")
Brain 产生 Plan "pursuit" → task.Name = "pursuit" → Channel 1 匹配 → Runner.Run("pursuit")
```

这要求 Brain 在生成 Task 时，将 `task.Name` 设置为 plan 名称。
如果 Brain 侧暂不修改，Channel 1.5 可以兼容（用 planName + taskType 构造树名），但 `buildPhasedTreeName` 需要调整为不加后缀：

```go
// 过渡期：planName 直接作为树名
func (e *Executor) buildPhasedTreeName(planName string, taskType decision.TaskType) string {
    switch taskType {
    case decision.TaskTypeGSSMain:
        return planName  // 不再加 _main 后缀
    default:
        return ""  // entry/exit 不再单独调度
    }
}
```

---

## 4. 行为切换流程

### 4.1 正常切换（Brain 产生新 Plan）

```
当前运行 idle 树 → Brain 产生 pursuit Plan

1. Brain 下发 Task 列表: [exit_task, transition_task, entry_task, main_task]
2. Executor 按序处理:
   - exit_task: Runner.Stop(entityID)
     → 节点级 OnExit 清理
     → on_exit 子树执行 ClearIdleState
   - transition_task: Runner.Run("pursuit_to_move_transition")
     → ReturnToSchedule 同步完成
   - entry_task + main_task: Runner.Run("pursuit")
     → ChaseTarget(entry) → Selector 循环(main)
```

**注意**：exit 由 `Runner.Stop()` 自动触发 on_exit，不需要 Executor 额外调度 exit 树。Brain 下发的 `exit_task` 只需要触发 `Runner.Stop()`。

### 4.2 树正常完成

```
pursuit 树目标丢失 → Selector 第二分支返回 Success → 树正常完成

1. Runner.Tick() 检测到 Success
2. 执行 on_exit 子树: ClearPursuitState
3. 清理实例
4. 等待 Brain 下一次决策
```

---

## 5. 兼容性与迁移策略

### 5.1 分阶段迁移

**第一阶段**：基础设施
- 修改 BTreeConfig 支持 on_exit
- 修改 Runner.Stop() 和 Tick() 执行 on_exit

**第二阶段**：JSON 合并
- 创建 10 个新的合并 JSON 文件
- 保留旧的 30 个文件（暂不删除）
- 新树名称（idle）和旧树名称（idle_main）同时注册

**第三阶段**：调度切换
- 修改 Executor Channel 1.5 使用新树名
- 验证所有行为正常

**第四阶段**：清理
- 删除旧的 30 个 entry/exit/main JSON 文件
- 删除 plan_config.json
- 删除 Executor 中废弃的三阶段状态机代码
- 更新测试

### 5.2 回退方案

如果新方案出现问题，只需：
1. 恢复旧 JSON 文件
2. 将 `buildPhasedTreeName()` 恢复加后缀逻辑
3. Runner.Stop() 中 on_exit 逻辑是增量的，不影响旧行为

---

## 6. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| on_exit 子树返回 Running | 阻塞 Stop 流程 | 强制检查，Running 时 warning + 强制 OnExit |
| entry 节点失败导致树失败 | NPC 卡住 | 与旧方案行为一致（entry_tree 失败时也停止） |
| Brain 下发 exit_task 但树已停止 | Runner.Stop 对已停止的树无操作 | 安全，Stop 内部有 exist 检查 |
| 合并 JSON 时遗漏节点 | 行为不一致 | 逐树对比 entry+main+exit，审查确认 |

---

## 7. 涉及文件清单

### 修改的文件

| 文件 | 变更说明 |
|------|---------|
| `bt/config/types.go` | BTreeConfig 新增 OnExit 字段 |
| `bt/runner/runner.go` | Stop() 和 Tick() 增加 on_exit 执行 |
| `bt/trees/example_trees.go` | 删除 plan_config.json 跳过逻辑 |
| `executor.go` | 简化 Channel 1.5，清理废弃代码 |

### 新增的文件

| 文件 | 说明 |
|------|------|
| `bt/trees/idle.json` | 合并后的 idle 树 |
| `bt/trees/home_idle.json` | 合并后的 home_idle 树 |
| `bt/trees/move.json` | 合并后的 move 树 |
| `bt/trees/dialog.json` | 合并后的 dialog 树 |
| `bt/trees/pursuit.json` | 合并后的 pursuit 树 |
| `bt/trees/investigate.json` | 合并后的 investigate 树 |
| `bt/trees/meeting_idle.json` | 合并后的 meeting_idle 树 |
| `bt/trees/meeting_move.json` | 合并后的 meeting_move 树 |
| `bt/trees/sakura_npc_control.json` | 合并后的 sakura_npc_control 树 |
| `bt/trees/proxy_trade.json` | 合并后的 proxy_trade 树 |

### 删除的文件

| 文件 | 原因 |
|------|------|
| `bt/trees/plan_config.json` | 不再需要三阶段映射 |
| `bt/trees/*_entry.json` (10个) | 合并到主树 root 中 |
| `bt/trees/*_exit.json` (10个) | 合并到主树 on_exit 中 |
| `bt/trees/*_main.json` (10个) | 被新的合并文件替代 |
| `bt/config/plan_config.go` | 不再需要 PlanConfig 加载器 |
