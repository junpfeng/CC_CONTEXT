---
name: ai-decision
description: NPC AI决策系统开发助手。当用户需要添加NPC行为计划、配置状态转移、调试决策流程、添加新Feature时使用
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
argument-hint: "[add-plan|add-transition|add-feature|debug|flow|executor] [参数]"
---

# NPC AI 决策系统开发助手

帮助开发者快速完成 NPC AI 决策系统相关的开发工作，包括 GSS Brain、Feature 感知、Executor 执行器等。

## 使用方式

| 命令 | 用途 | 示例 |
|------|------|------|
| `/ai-decision add-plan` | 添加新的行为计划 | `/ai-decision add-plan sakura_npc_control` |
| `/ai-decision add-transition` | 添加状态转移配置 | `/ai-decision add-transition idle_to_patrol` |
| `/ai-decision add-feature` | 添加新的特征值 | `/ai-decision add-feature feature_hungry` |
| `/ai-decision debug` | 调试NPC决策流程 | `/ai-decision debug 12345` |
| `/ai-decision flow` | 展示决策系统流程图 | `/ai-decision flow` |
| `/ai-decision executor` | 添加Executor任务处理 | `/ai-decision executor patrol` |

---

## 核心文件位置

### 决策层（AI Brain）
| 文件 | 路径 | 职责 |
|------|------|------|
| Agent | `common/ai/decision/agent/agent.go` | AI代理，管理Brain生命周期 |
| GSS Brain | `common/ai/decision/agent/gss.go` | GSS决策大脑实现 |
| Feature | `common/ai/decision/gss_brain/feature/feature.go` | 特征值存储与管理 |
| Condition | `common/ai/decision/gss_brain/condition/` | 条件评估系统 |
| Config | `common/ai/decision/gss_brain/config/config.go` | 配置加载与管理 |
| FSM | `common/ai/decision/fsm/gss_brain_fsm.go` | 状态机实现 |

### ECS系统层
| 文件 | 路径 | 职责 |
|------|------|------|
| DecisionSystem | `ecs/system/decision/decision.go` | 决策系统（每秒tick） |
| Executor | `ecs/system/decision/executor.go` | 任务执行器 |
| ExecutorHelper | `ecs/system/decision/executor_helper.go` | 执行器辅助函数 |
| SensorFeatureSystem | `ecs/system/sensor/sensor_feature.go` | 感知系统（500ms tick） |
| EventSensor | `ecs/system/sensor/event_sensor.go` | 事件感知 |
| EventSensorFeature | `ecs/system/sensor/event_sensor_feature.go` | 事件特征更新 |

### 组件层
| 文件 | 路径 | 职责 |
|------|------|------|
| DecisionComp | `ecs/com/caidecision/decision.go` | AI决策组件 |

### 配置文件
| 文件 | 路径 | 说明 |
|------|------|------|
| NPC行为配置 | `bin/config/ai_decision/*.json` | GSS状态转移配置 |

---

## 执行步骤

### add-plan: 添加新行为计划

**完整流程：**

1. **修改JSON配置** (`bin/config/ai_decision/XXX_State.json`)
   ```json
   {
     "plans": [
       // 在此添加新计划
       {
         "name": "patrol",           // 计划名称
         "entry_task": "do_entry",   // 进入任务
         "exit_task": "do_exit",     // 退出任务
         "main_task": "do_main"      // 主循环任务
       }
     ]
   }
   ```

2. **添加Executor处理** (`executor.go`)
   - 在 `validPlanNames` map 中添加新计划名
   - 添加 `handleXXXEntryTask()` 处理进入逻辑
   - 添加 `handleXXXExitTask()` 处理退出逻辑
   - 可选：添加 `handleXXXMainTask()` 处理主循环

3. **添加状态转移** (见 add-transition)

---

### add-transition: 添加状态转移

**修改JSON配置：**

```json
{
  "transitions": [
    {
      "name": "idle_to_patrol",       // 转移名称
      "from": "idle",                 // 源计划
      "to": "patrol",                 // 目标计划
      "priority": 2,                  // 优先级（越大越优先）
      "probability": 100,             // 概率权重
      "condition": {                  // 触发条件
        "op": "and",                  // 逻辑运算符: and/or
        "conditions": [
          {
            "op": "eq",               // 比较运算符: eq/ne/gt/ge/lt/le
            "key": "feature_patrol_req",
            "value": true
          }
        ]
      },
      "transition_task": "idle_to_patrol_transition"  // 可选：转移任务
    }
  ]
}
```

**条件运算符说明：**

| 运算符 | 含义 | 示例 |
|--------|------|------|
| `eq` | 等于 | `"op": "eq", "value": true` |
| `ne` | 不等于 | `"op": "ne", "value": 0` |
| `gt` | 大于 | `"op": "gt", "value": 100` |
| `ge` | 大于等于 | `"op": "ge", "value": 5` |
| `lt` | 小于 | `"op": "lt", "value": 10` |
| `le` | 小于等于 | `"op": "le", "value": 3` |

**嵌套条件示例：**

```json
{
  "op": "or",
  "conditions": [
    {
      "op": "and",
      "condition": {
        "op": "and",
        "conditions": [
          { "op": "eq", "key": "feature_a", "value": true },
          { "op": "gt", "key": "feature_b", "value": 5 }
        ]
      }
    },
    { "op": "eq", "key": "feature_c", "value": "active" }
  ]
}
```

---

### add-feature: 添加新特征值

**1. JSON配置中声明** (`bin/config/ai_decision/XXX_State.json`)
```json
{
  "features": {
    "feature_patrol_req": false,        // bool 类型
    "feature_patrol_target": 0,         // int 类型
    "feature_patrol_location": ""       // string 类型
  }
}
```

**2. 选择更新方式**

| 特征类型 | 更新位置 | TTL | 示例 |
|----------|----------|-----|------|
| 状态特征 | MiscSensor | 无 | `feature_state_pursuit` |
| 事件特征 | EventSensor | 1000ms | `feature_dialog_req` |
| 日程特征 | ScheduleSensor | 无 | `feature_schedule` |

**3. 添加Sensor更新逻辑**

状态特征（`misc_sensor.go`）:
```go
func (s *MiscSensor) Update(entityID uint64) {
    // 获取相关组件
    patrolComp, ok := common.GetComponentAs[*cpatrol.PatrolComp](...)
    if !ok { return }

    // 更新特征
    decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     entityID,
        FeatureKey:   "feature_patrol_req",
        FeatureValue: patrolComp.IsPatrolRequested(),
    })
}
```

事件特征（`event_sensor_feature.go`）:
```go
func (ef *EventSensorFeature) processPatrolEvent(entityID uint64, decisionComp *caidecision.DecisionComp) {
    // 更新事件特征（带TTL自动清理）
    decisionComp.UpdateFeature(decision.UpdateFeatureReq{
        EntityID:     entityID,
        FeatureKey:   "feature_patrol_req",
        FeatureValue: true,
        TTLMs:        EventFeatureTTL,  // 1000ms
    })
}
```

---

### executor: 添加Executor任务处理

**1. 注册计划名** (`executor.go`)

```go
// executeGSSEntryTask 中
validPlanNames := map[string]bool{
    "idle":    true,
    "move":    true,
    "patrol":  true,  // 新增
}

// executeGSSExitTask 中同样添加
```

**2. 添加Entry处理**

```go
func (e *Executor) handlePatrolEntryTask(entityID uint32) {
    e.Scene.Debugf("[Executor][PatrolEntry] start, npc_entity_id=%v", entityID)

    // 1. 获取必要组件
    npcMoveComp, ok := common.GetComponentAs[*cnpc.NpcMoveComp](
        e.Scene, uint64(entityID), common.ComponentType_NpcMove)
    if !ok { return }

    // 2. 设置移动状态
    npcMoveComp.StartMove()
    npcMoveComp.SetPathFindType(int32(cnpc.EPathFindType_NavMesh))

    // 3. 设置巡逻路径
    // ...

    e.Scene.Infof("[Executor][PatrolEntry] completed, npc_entity_id=%v", entityID)
}
```

**3. 添加Exit处理**

```go
func (e *Executor) handlePatrolExitTask(entityID uint32) {
    e.Scene.Debugf("[Executor][PatrolExit] start, npc_entity_id=%v", entityID)

    // 清理状态
    npcMoveComp, ok := common.GetComponentAs[*cnpc.NpcMoveComp](...)
    if ok {
        npcMoveComp.StopMove()
    }

    // 清理相关Feature
    decisionComp, ok := common.GetComponentAs[*caidecision.DecisionComp](...)
    if ok {
        decisionComp.UpdateFeature(decision.UpdateFeatureReq{
            EntityID:     uint64(entityID),
            FeatureKey:   "feature_patrol_req",
            FeatureValue: false,
        })
    }
}
```

**4. 注册到handleEntryTask/handleExitTask**

```go
func (e *Executor) handleEntryTask(entityID uint32, planName string) {
    switch planName {
    // ... 其他case
    case "patrol":
        e.handlePatrolEntryTask(entityID)
    }
}
```

---

### debug: 调试NPC决策

**调试步骤：**

1. 获取NPC的 DecisionComp
2. 调用 `GetRunningInfo()` 获取当前状态
3. 分析 Feature 值
4. 检查配置中的 Transition 条件
5. 追踪 Executor 执行日志

**关键日志位置：**
- `[Executor][XXXEntry]` - 计划进入
- `[Executor][XXXExit]` - 计划退出
- `[EventSensorSystem]` - 事件处理
- `[SensorFeatureSystem]` - 特征更新

---

### flow: 决策系统流程图

```
┌─────────────────────────────────────────────────────────────────┐
│                      NPC AI 决策系统架构                         │
└─────────────────────────────────────────────────────────────────┘

                    ┌──────────────────┐
                    │   JSON Config    │
                    │  (Plans/Trans)   │
                    └────────┬─────────┘
                             │ 加载
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Agent (代理)                             │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                    GSS Brain                             │   │
│   │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌───────────┐  │   │
│   │  │ Feature │  │  FSM    │  │ Config  │  │ Condition │  │   │
│   │  │  (特征)  │  │ (状态机) │  │  (配置)  │  │  Mgr     │  │   │
│   │  └────┬────┘  └────┬────┘  └────┬────┘  └─────┬─────┘  │   │
│   │       │            │            │              │        │   │
│   │       └────────────┴────────────┴──────────────┘        │   │
│   │                         │                                │   │
│   │                    Tick() 每秒                           │   │
│   │                         │                                │   │
│   │              ┌──────────▼──────────┐                    │   │
│   │              │  评估Transition条件  │                    │   │
│   │              │  创建新Plan         │                    │   │
│   │              └──────────┬──────────┘                    │   │
│   └─────────────────────────┼───────────────────────────────┘   │
└─────────────────────────────┼───────────────────────────────────┘
                              │ Plan
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Executor (执行器)                           │
│                                                                  │
│   Plan { Tasks: [TransTask, ExitTask, EntryTask, MainTask] }    │
│                              │                                   │
│              ┌───────────────┼───────────────┐                  │
│              ▼               ▼               ▼                  │
│        TransTask        ExitTask        EntryTask               │
│        (状态转移)       (退出旧计划)     (进入新计划)             │
│              │               │               │                  │
│              └───────────────┴───────────────┘                  │
│                              │                                   │
│                    修改NPC组件状态                                │
│                    (移动/对话/追逐...)                           │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ 更新Feature
┌─────────────────────────────┴───────────────────────────────────┐
│                  SensorFeatureSystem (500ms)                     │
│                                                                  │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│   │ EventSensor  │  │ScheduleSensor│  │  MiscSensor  │         │
│   │  (事件特征)   │  │  (日程特征)   │  │  (状态特征)   │         │
│   └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

**FSM状态转移：**

```
[Init] ──创建初始Plan──▶ [WaitConsume] ◀───────┐
                              │                 │
                         GetNextPlan()          │
                              │                 │
                              ▼                 │
                      [WaitCreateNotify]        │
                              │                 │
                         创建新Plan             │
                              │                 │
                              └─────────────────┘
```

**任务执行顺序：**

```
状态转移时的Task执行顺序:

1. TransitionTask  (可选，处理转移逻辑)
2. ExitTask        (退出旧Plan，清理状态)
3. EntryTask       (进入新Plan，初始化状态)
4. MainTask        (主循环逻辑)
```

---

## 常见计划类型参考

| 计划名 | 用途 | Entry操作 | Exit操作 |
|--------|------|-----------|----------|
| `idle` | 空闲等待 | 设置位置、启动超时 | 清理超时 |
| `move` | 路径移动 | 寻路、开始移动 | 停止移动 |
| `dialog` | NPC对话 | 暂停移动、面向玩家 | 恢复状态 |
| `pursuit` | 追逐玩家 | NavMesh寻路、跑步 | 停止追逐 |
| `investigate` | 调查区域 | 移动到目标点 | 清理调查状态 |
| `home_idle` | 在家等待 | 设置超时、位置 | 清理敲门标记 |
| `meeting_idle` | 会议等待 | 设置位置 | - |
| `meeting_move` | 前往会议 | 寻路到会议点 | 停止移动 |
| `sakura_npc_control` | 被玩家控制 | 停止移动 | 恢复移动 |

---

## 注意事项

1. **Plan名称必须唯一** - 在同一配置文件中不能重复
2. **Transition优先级** - 数值越大优先级越高，相同优先级按概率选择
3. **Feature TTL** - 事件特征默认1000ms过期，状态特征无TTL
4. **Executor注册** - 新计划必须在 `validPlanNames` 中注册
5. **条件嵌套深度** - 最大支持5层嵌套
6. **分帧处理** - DecisionSystem每帧最多处理100个NPC
