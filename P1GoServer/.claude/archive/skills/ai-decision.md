---
name: ai-decision
description: AI 决策系统开发和调试
---

# AI 决策系统开发助手

当用户需要开发或调试 AI 决策相关功能时使用。

## 功能

### 1. 添加新计划（Plan）

在 GSS 配置中添加新计划：

```go
// gss_brain/config/plan.go
type Plan struct {
    Name      string // 计划名称，如 "patrol", "rest"
    EntryTask string // 进入时执行的任务
    ExitTask  string // 退出时执行的任务
    MainTask  string // 主循环任务
}
```

### 2. 添加状态转移（Transition）

```go
type Transition struct {
    Name           string    // 转移名称
    From           string    // 源计划（如 "idle"）
    To             string    // 目标计划（如 "patrol"）
    Priority       int64     // 优先级
    Probability    int64     // 概率
    Condition      Condition // 触发条件
    TransitionTask string    // 转移任务
}
```

### 3. 添加新特征（Feature）

特征命名规范：`feature_<category>_<name>`

```go
// 在感知器中更新特征
decisionComp.UpdateFeature(decision.UpdateFeatureReq{
    Key:   "feature_my_new_feature",
    Value: calculatedValue,
})

// 在条件中使用
Condition{
    Op: "and",
    Conditions: []ConditionItem{
        {Key: "feature_my_new_feature", Op: "eq", Value: true},
    },
}
```

### 4. 实现执行器处理

```go
// executor.go
func (e *Executor) handleMyPlanEntryTask(entityID uint32) {
    // 获取必要组件
    entity := e.scene.GetEntity(entityID)

    // 实现进入逻辑
}

func (e *Executor) handleMyPlanExitTask(entityID uint32) {
    // 实现退出逻辑
}

func (e *Executor) handleMyPlanMainTask(entityID uint32) {
    // 实现主循环逻辑
}
```

## 调试技巧

### 查看当前计划
```go
plan := decisionComp.CurPlan()
log.Debugf("NPC %d current plan: %s", entityID, plan.Name)
```

### 查看特征值
```go
value, ok := decisionComp.GetFeatureValue("feature_xxx")
if ok {
    log.Debugf("feature_xxx = %v", value.Value())
}
```

### 强制触发决策
```go
decisionComp.UpdateFeatureCommand(decision.UpdateFeatureReq{
    Key:   "feature_trigger",
    Value: true,
})
```

## 关键文件

- @servers/scene_server/internal/common/ai/decision/types.go
- @servers/scene_server/internal/common/ai/decision/agent/agent.go
- @servers/scene_server/internal/common/ai/decision/agent/gss.go
- @servers/scene_server/internal/common/ai/decision/gss_brain/config/
- @servers/scene_server/internal/ecs/system/decision/executor.go

## 使用方式

- `/ai-decision plan <name>` - 分析或创建计划
- `/ai-decision transition` - 设计状态转移
- `/ai-decision feature <name>` - 添加新特征
- `/ai-decision debug <npc_id>` - 调试指定 NPC 的决策
