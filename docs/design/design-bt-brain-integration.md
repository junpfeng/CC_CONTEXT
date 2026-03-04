# 设计方案：BT 与 Brain 集成重设计

## 1. 问题诊断

### 1.1 当前架构

```
Brain（1秒）                          Executor（即时）                    BtRunner（每帧）
┌──────────────┐    Plan{Tasks[4]}    ┌───────────────────┐              ┌──────────────┐
│ 评估 Feature  │ ─────────────────→  │ for task in tasks: │              │              │
│ 选择 Transition│                     │   Exit  → Stop()  │ ──Stop()──→ │  停止旧树     │
│ 生成 4 个 Task │                     │   Enter → skip    │              │              │
│              │                     │   Main  → Run()   │ ──Run()───→ │  启动新树     │
│              │                     │   Trans → Run()   │              │              │
│              │                     │                   │              │              │
│              │                     │   找不到树？       │              │              │
│              │                     │   → 硬编码回退     │              │              │
│              │                     │   （~900 行）      │              │              │
└──────────────┘                     └───────────────────┘              └──────────────┘
```

### 1.2 六个"味道"

| # | 问题 | 原因 |
|---|------|------|
| 1 | **计划粒度过细** | Brain 把 idle/move/home_idle 当作独立计划，但它们只是"日常日程"的阶段。导致 N×N 转移爆炸（DAN_STATE: 7 Plan, 37 Transition） |
| 2 | **BT 树退化为单节点** | 每棵树只有 `{ "type": "XxxBehavior" }`，无参数、无组合、无分支。JSON 层退化为 name→nodeType 映射表 |
| 3 | **BT 核心能力闲置** | Service/Decorator/Abort 事件驱动机制全部未使用 |
| 4 | **双重生命周期** | Brain 生成 entry/exit/main 任务序列，BT 节点也有 OnEnter/OnTick/OnExit。两套生命周期打架 |
| 5 | **Executor 翻译层** | 900+ 行硬编码 handle 函数，与 BT 行为节点功能完全重复 |
| 6 | **决策边界模糊** | Brain 同时做战略决策（响应事件）和战术决策（日程路由），BT 沦为纯执行 |

### 1.3 根因：决策边界划错了位置

```
现在：Brain 做战略+战术 → BT 纯执行 → 树退化为单节点
应该：Brain 做战略     → BT 做战术 → 树有真正的结构
```

Brain 的计划粒度太细（原子动作级），留给 BT 的只剩"执行这一个动作"。BT 框架的核心价值（组合、事件驱动、策划可配）无法发挥。

### 1.4 当前计划的两类本质

分析 DAN_STATE 的 37 条转移，计划自然分为两类：

**第一类：日程循环（idle ↔ move ↔ home_idle）**
- 转移条件全部由 `feature_schedule` 驱动
- 这不是三种行为，而是一种行为"日常日程"的三个阶段
- 循环完全可以在 BT 树内部用 Selector + Decorator 完成

**第二类：事件响应（dialog、pursuit、meeting、investigate、proxy_trade、sakura_control）**
- 由外部事件触发（对话请求、追逐目标出现、聚会通知等）
- 是对日常行为的打断，是真正独立的行为

其中 meeting 也有内部阶段（meeting_move ↔ meeting_idle），同属第一类问题。

---

## 2. 目标架构

### 2.1 核心理念

```
Brain 做战略决策：日常 ↔ 聚会 ↔ 对话 ↔ 追逐 ↔ ...
BT   做战术决策：日常 = Selector(移动 | 回家 | 待机)，聚会 = Selector(前往 | 等待)
                 Service 泵数据 → Decorator 守条件 → Abort 切分支
```

### 2.2 计划重划

```
现在（DAN_STATE: 7 Plan, 37 Transition）     →    重划后（4 Plan, ~11 Transition）

home_idle ─┐                                      ┌──────────────┐
idle      ─┼── 合并 ─────────────────────────────→ │ daily_schedule│  (BT Selector 内部路由)
move      ─┘                                      └──────────────┘

meeting_move ─┐                                   ┌──────────────┐
meeting_idle ─┼── 合并 ──────────────────────────→ │ meeting      │  (BT Selector 内部路由)
              ┘                                   └──────────────┘

dialog          ───── 保持原子行为 ──────────────→  dialog
pursuit         ───── 保持原子行为 ──────────────→  pursuit
investigate     ───── 保持原子行为 ──────────────→  investigate
proxy_trade     ───── 保持原子行为 ──────────────→  proxy_trade
sakura_control  ───── 保持原子行为 ──────────────→  sakura_control
```

### 2.3 目标数据流

```
Brain（1秒，战略）          Executor（即时）           BtRunner（每帧，战术）
┌──────────────┐           ┌────────────────┐        ┌──────────────────────────────┐
│ 有对话请求？   │ ─plan──→ │ btRunner.Run() │ ──────→│ daily_schedule 树：            │
│ 有追逐目标？   │  Name    │                │        │  Service 同步 feature_schedule │
│ 有聚会通知？   │          │ 没有树？        │        │  Decorator 检查 schedule 值    │
│ 都没有→日常   │          │ → 硬编码回退    │        │  Abort 切换 移动/待机/回家     │
└──────────────┘           └────────────────┘        └──────────────────────────────┘
```

### 2.4 决策边界

| 层级 | 职责 | 频率 | 示例 |
|------|------|------|------|
| Brain | 战略决策：切换行为大类 | 1秒 | "日常→追逐" / "追逐→日常" |
| BT Selector + Abort | 战术决策：行为内部分支切换 | 每帧（事件驱动） | "日常-移动→日常-待机" |
| BT 叶子节点 | 执行：具体动作 | 每帧 | MoveBehavior / IdleBehavior |

---

## 3. 详细设计

### 3.1 daily_schedule 行为树

```
daily_schedule
│
└─ Selector
    │
    ├─ Service: SyncFeatureToBlackboard
    │   mappings: { feature_schedule → "schedule" }
    │   interval_ms: 500
    │   (OnActivate 时立即同步一次，树启动即有新鲜数据)
    │
    ├─ [0] MoveBehavior ← 最高优先级
    │   decorator: BlackboardCheck(schedule == "MoveToBPointFormAPoint", abort=both)
    │
    ├─ [1] HomeIdleBehavior
    │   decorator: BlackboardCheck(schedule == "StayInBuilding", abort=both)
    │
    └─ [2] IdleBehavior ← 最低优先级（默认）
        decorator: BlackboardCheck(schedule == "LocationBasedAction", abort=both)
```

JSON 配置：

```json
{
  "name": "daily_schedule",
  "description": "NPC 日常日程 — 根据日程状态自动切换移动/待机/回家",
  "root": {
    "type": "Selector",
    "services": [
      {
        "type": "SyncFeatureToBlackboard",
        "interval_ms": 500,
        "params": {
          "mappings": { "feature_schedule": "schedule" }
        }
      }
    ],
    "children": [
      {
        "type": "MoveBehavior",
        "description": "前往日程地点",
        "decorators": [{
          "type": "BlackboardCheck",
          "abort_type": "both",
          "params": { "key": "schedule", "operator": "==", "value": "MoveToBPointFormAPoint" }
        }]
      },
      {
        "type": "HomeIdleBehavior",
        "description": "在家待机",
        "decorators": [{
          "type": "BlackboardCheck",
          "abort_type": "both",
          "params": { "key": "schedule", "operator": "==", "value": "StayInBuilding" }
        }]
      },
      {
        "type": "IdleBehavior",
        "description": "在日程点待机",
        "decorators": [{
          "type": "BlackboardCheck",
          "abort_type": "both",
          "params": { "key": "schedule", "operator": "==", "value": "LocationBasedAction" }
        }]
      }
    ]
  }
}
```

#### 事件驱动运行流程

```
NPC 在 IdleBehavior (待机中)
    │
    ├─ 日程系统更新: feature_schedule = "MoveToBPointFormAPoint"
    │
    ├─ Service (500ms 周期) 同步 → BB["schedule"] = "MoveToBPointFormAPoint"
    │   └─ markDirty("schedule")
    │
    ├─ Selector.OnTick 检查脏 key
    │   ├─ child[0] MoveBehavior 的 decorator: schedule=="Move..." → TRUE
    │   │   abort_type=both 含 lower_priority → 触发 abort child[2]
    │   │
    │   ├─ IdleBehavior.OnExit() → 清除 OutFinishStamp
    │   │
    │   └─ Selector 重新评估 → child[0] 通过 → MoveBehavior.OnEnter()
    │       └─ 查询路网 → 设置路点 → StartMove()
    │
NPC 移动中 (MoveBehavior Running)
    │
    ├─ 到达目的地, 日程系统更新: feature_schedule = "LocationBasedAction"
    │
    ├─ Service 同步 → BB["schedule"] = "LocationBasedAction"
    │   └─ markDirty("schedule")
    │
    ├─ Selector.OnTick:
    │   ├─ child[0] decorator: schedule=="Move..." → FALSE
    │   │   abort_type=both 含 self → 触发 self abort
    │   │
    │   ├─ MoveBehavior.OnExit() → StopMove()
    │   │
    │   └─ 重新评估 → child[2] 通过 → IdleBehavior.OnEnter()
    │       └─ 设置位置/超时
    │
NPC 在 IdleBehavior (待机中)
```

### 3.2 meeting 行为树

```json
{
  "name": "meeting",
  "description": "NPC 聚会 — 根据聚会状态切换前往/等待",
  "root": {
    "type": "Selector",
    "services": [
      {
        "type": "SyncFeatureToBlackboard",
        "interval_ms": 500,
        "params": {
          "mappings": { "feature_meeting_state": "meeting_state" }
        }
      }
    ],
    "children": [
      {
        "type": "MeetingMoveBehavior",
        "description": "前往聚会地点",
        "decorators": [{
          "type": "BlackboardCheck",
          "abort_type": "both",
          "params": { "key": "meeting_state", "operator": "==", "value": 1 }
        }]
      },
      {
        "type": "MeetingIdleBehavior",
        "description": "在聚会位置待机",
        "decorators": [{
          "type": "BlackboardCheck",
          "abort_type": "both",
          "params": { "key": "meeting_state", "operator": "==", "value": 2 }
        }]
      }
    ]
  }
}
```

### 3.3 原子行为树（保持不变）

以下行为树保持单节点形态，因为它们本身就是原子行为：

```json
{ "name": "dialog",         "root": { "type": "DialogBehavior" } }
{ "name": "pursuit",        "root": { "type": "PursuitBehavior" } }
{ "name": "investigate",    "root": { "type": "InvestigateBehavior" } }
{ "name": "proxy_trade",    "root": { "type": "ProxyTradeBehavior" } }
{ "name": "sakura_npc_control", "root": { "type": "PlayerControlBehavior" } }
```

这些行为由 Brain 切换触发，不需要树内部分支。

### 3.4 Brain 配置简化

#### DAN_STATE（Before: 7 Plan, 37 Transition）

```json
{
  "name": "Dan_State",
  "init_plan": "daily_schedule",
  "plans": [
    { "name": "daily_schedule", "main_task": "daily_schedule" },
    { "name": "meeting",        "main_task": "meeting" },
    { "name": "dialog",         "main_task": "dialog" },
    { "name": "pursuit",        "main_task": "pursuit" }
  ],
  "transitions": [
    { "from": "daily_schedule", "to": "dialog",   "priority": 1, "condition": "dialog_req == true" },
    { "from": "daily_schedule", "to": "pursuit",  "priority": 2, "condition": "state_pursuit == true" },
    { "from": "daily_schedule", "to": "meeting",  "priority": 2, "condition": "meeting_state >= 1" },

    { "from": "dialog",  "to": "daily_schedule",  "priority": 1, "condition": "dialog_finish_req == true" },
    { "from": "dialog",  "to": "pursuit",         "priority": 2, "condition": "state_pursuit == true" },

    { "from": "pursuit", "to": "daily_schedule",  "priority": 1, "condition": "state_pursuit == false" },

    { "from": "meeting", "to": "daily_schedule",  "priority": 1, "condition": "meeting_state == 0" },
    { "from": "meeting", "to": "dialog",          "priority": 1, "condition": "dialog_req == true" },
    { "from": "meeting", "to": "pursuit",         "priority": 2, "condition": "state_pursuit == true" }
  ]
}
```

> 注：上方 condition 为伪代码表示，实际为 JSON 嵌套格式。

#### 其他模板同理

| 模板 | Before | After | 改动 |
|------|--------|-------|------|
| DAN_STATE | 7 Plan, 37 Trans | 4 Plan, ~9 Trans | 合并 idle/move/home_idle + meeting_move/meeting_idle |
| CUSTOMERNPC_STATE | 7 Plan, ~37 Trans | 4 Plan, ~9 Trans | 同 DAN_STATE |
| DEALERNPC_STATE | 8 Plan, ~48 Trans | 5 Plan, ~13 Trans | 同上 + proxy_trade |
| SAKURA_COMMON_STATE | 5 Plan, 11 Trans | 3 Plan, ~5 Trans | 合并 idle/move/home_idle，无 meeting |

#### 为什么 Brain 不用关心子状态

**Before**: pursuit 结束 → Brain 根据 schedule 决定回 idle/move/home_idle（3 条 transition）。
**After**: pursuit 结束 → Brain 只说"回 daily_schedule"。BT Selector 根据当前 schedule 自动选对分支。

Brain 不需要知道 daily_schedule 内部有几个子状态。

### 3.5 Executor 简化

```go
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    planName := req.Plan.Name

    // 第一层：行为树（Run 内部 Stop 旧树 + 启动新树）
    if e.btRunner != nil && e.btRunner.HasTree(planName) {
        if err := e.btRunner.Run(planName, uint64(req.EntityID)); err != nil {
            e.Scene.Warningf("[Executor] failed to run tree %s: %v", planName, err)
        }
        return nil
    }

    // 第二层：硬编码回退（init 等未迁移 Plan）
    e.executePlanLegacy(req)
    return nil
}
```

### 3.6 Transition 处理

当前 transition 逻辑（pursuit → move 时的 NavMesh 寻路）合并到离开方的 OnExit：

| 行为节点 | OnExit 现状 | 需补充 |
|----------|------------|--------|
| PursuitBehavior | StopMove + ClearTarget | **补充 setupNavMeshPathToFeaturePos + 设置 feature_args1** |
| PlayerControlBehavior | Clear event + NavMesh 寻路 | 已包含，不需要改 |

MoveBehavior.OnEnter 已有 `feature_args1 == "pathfind_completed"` 快速路径检查，行为不变。

---

## 4. 行为等价性分析

### 4.1 日程循环（BT 内部切换取代 Brain 转移）

| 场景 | Before (Brain 转移) | After (BT Abort) | 等价 |
|------|---------------------|-------------------|------|
| 待机→移动 | Brain: idle→move | Service 同步 schedule → Decorator abort → MoveBehavior.OnEnter | **等价** |
| 移动→待机 | Brain: move→idle | Service 同步 schedule → Decorator self-abort → IdleBehavior.OnEnter | **等价** |
| 移动→回家 | Brain: move→home_idle | 同上，HomeIdleBehavior 分支 | **等价** |
| 回家→移动 | Brain: home_idle→move | 同上 | **等价** |

### 4.2 行为间切换（Brain 转移 + BT Run/Stop）

| 场景 | Before | After | 等价 |
|------|--------|-------|------|
| 日常→追逐 | Brain: idle→pursuit, Executor: Stop+Run | Brain: daily_schedule→pursuit, Run("pursuit") 内部 Stop | **等价**：IdleBehavior.OnExit 被调用 |
| 追逐→日常 | Brain: pursuit→idle/move/home_idle (3条) | Brain: pursuit→daily_schedule (1条), BT Selector 选分支 | **等价**：PursuitBehavior.OnExit 清理 + 正确分支激活 |
| 日常→对话 | Brain: idle→dialog | Brain: daily_schedule→dialog | **等价** |
| 日常→聚会 | Brain: idle→meeting_move/idle | Brain: daily_schedule→meeting, BT Selector 选分支 | **等价** |

### 4.3 Blackboard 跨树共享

当 daily_schedule → pursuit → daily_schedule 时：
- Blackboard 在 Stop 时保留（跨树共享）
- daily_schedule 重启时，Service.OnActivate 立即同步最新 feature → BB 数据新鲜
- Selector 基于新鲜 BB 选择正确分支

---

## 5. 迁移策略

### 5.1 四步迁移

#### Step 1：补全 PursuitBehavior.OnExit（最小改动）

补充 NavMesh 寻路逻辑（从 handlePursuitToMoveTransition 迁移）。

| 文件 | 改动 |
|------|------|
| `bt/nodes/behavior_nodes.go` | PursuitBehavior.OnExit 补充 setupNavMeshPathToFeaturePos + feature_args1 |

#### Step 2：创建组合 BT 树（纯新增，不破坏现有）

| 文件 | 说明 |
|------|------|
| `bt/trees/daily_schedule.json` | 新增：Selector + Service + Decorator |
| `bt/trees/meeting.json` | 新增：Selector + Service + Decorator |

此时新旧 BT 树共存，不影响现有功能。

#### Step 3：更新 Brain 配置 + 简化 Executor

| 文件 | 改动 |
|------|------|
| `config/.../ai_decision/*.json` | 合并 Plan，简化 Transition |
| `ecs/system/decision/executor.go` | OnPlanCreated 简化为 Run(planName) + legacy fallback |
| `bt/integration_phased_test.go` | 更新测试：新的 planName 列表 |

#### Step 4：清理旧代码（可选，不阻塞）

| 文件 | 改动 |
|------|------|
| `bt/trees/idle.json` 等 | 删除被 daily_schedule 替代的单节点树 |
| `bt/trees/*_transition.json` | 删除 transition 独立树 |
| `executor.go` | 逐步删除 hardcoded handle* 函数 |

### 5.2 回滚安全

- Step 1-2 是纯新增，随时可回滚
- Step 3 修改 Brain 配置，回滚方式是恢复原 JSON 文件
- Step 4 可独立于 Step 3，不阻塞

---

## 6. 涉及文件汇总

### 必须改动

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `bt/nodes/behavior_nodes.go` | 修改 | PursuitBehavior.OnExit 补充 NavMesh |
| `bt/trees/daily_schedule.json` | **新增** | 组合树：Selector + Service + Decorator |
| `bt/trees/meeting.json` | **新增** | 组合树：Selector + Service + Decorator |
| `config/.../ai_decision/Dan_State.json` | 修改 | 合并 Plan，简化 Transition |
| `config/.../ai_decision/CustomeNpc_State.json` | 修改 | 同上 |
| `config/.../ai_decision/DealerNpc_State.json` | 修改 | 同上 + proxy_trade |
| `config/.../ai_decision/Sakura_Common_State.json` | 修改 | 同上（无 meeting） |
| `ecs/system/decision/executor.go` | 修改 | OnPlanCreated 简化 |
| `bt/integration_phased_test.go` | 修改 | 更新测试 |

### 不改动

| 文件 | 原因 |
|------|------|
| `bt/config/types.go` | BTreeConfig 不需要新增字段 |
| `bt/runner/runner.go` | Run() 已有正确行为 |
| `bt/nodes/blackboard_decorator.go` | 已支持字符串比较 + abort |
| `bt/nodes/service_sync_feature.go` | 已支持 feature → BB 同步 |
| `decision/agent/gss.go` | Brain 代码是配置驱动，不需要改代码 |
| `decision/types.go` | Plan 结构不变 |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| Service 同步延迟（500ms） | 分支切换有最多 500ms 延迟 | 可调低 interval_ms；OnActivate 时立即同步消除启动延迟 |
| BB 脏 key 在 abort 时的时序 | 可能在 OnExit 后仍有旧脏 key | BB 脏 key 三阶段（累积→消费→清理）保证帧内一致性 |
| PursuitBehavior.OnExit 增加 NavMesh | OnExit 耗时略增 | setupNavMeshPath 是瞬时操作（设置路径，不等待到达） |
| init Plan 无 BT 树 | 功能不变 | executePlanLegacy 保留硬编码回退 |
| Brain 配置 JSON 格式变化 | 需同步更新所有模板 | 按模板逐个迁移，可灰度 |

---

## 8. 验证

```bash
# 构建
go build ./servers/scene_server/internal/...

# BT 测试
go test -v ./servers/scene_server/internal/common/ai/bt/...
```

### 行为等价性验证重点

1. **daily_schedule 内部切换**：schedule 变化 → Service 同步 → Decorator abort → 正确分支激活
2. **daily_schedule ↔ pursuit**：Run("pursuit") 触发 daily_schedule 树 OnExit → PursuitBehavior 启动；反向时 daily_schedule 自动选对分支
3. **daily_schedule ↔ dialog**：对话暂停/恢复 + 日程时间补偿
4. **meeting 内部切换**：meeting_state 变化 → MeetingMove ↔ MeetingIdle
5. **pursuit → daily_schedule 的 NavMesh 过渡**：PursuitBehavior.OnExit 设置 NavMesh 路径 + feature_args1 → MoveBehavior.OnEnter 跳过路网寻路
6. **init Plan**：hardcoded 回退路径正常工作
7. **树完成 → TriggerCommand**：链路不变

---

## 9. 价值总结

| 维度 | Before | After |
|------|--------|-------|
| Brain Plan 数量 | 7-8 | 4-5 |
| Brain Transition 数量 | 37-48 | 9-13 |
| BT 树结构 | 单节点（无树） | **组合树**（Selector + Service + Decorator） |
| Service/Decorator/Abort | 闲置 | **核心驱动** |
| 策划配置能力 | 无（代码写死） | **可调**（分支顺序、同步间隔、条件参数） |
| 决策边界 | 模糊 | **清晰**（Brain 战略 / BT 战术） |
| Executor 复杂度 | 50+ 行 Task 遍历 | ~15 行 Run(planName) |
