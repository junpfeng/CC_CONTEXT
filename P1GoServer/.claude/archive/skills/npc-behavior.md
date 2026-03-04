---
name: npc-behavior
description: NPC 行为开发，实现新的 NPC 行为逻辑
---

# NPC 行为开发助手

当用户需要实现新的 NPC 行为时使用。

## 完整行为开发流程

### 1. 定义计划和转移

在 GSS 配置中定义：

```yaml
# 计划定义
plans:
  - name: "my_behavior"
    entry_task: "my_behavior_entry"
    exit_task: "my_behavior_exit"
    main_task: "my_behavior_main"

# 状态转移
transitions:
  - name: "idle_to_my_behavior"
    from: "idle"
    to: "my_behavior"
    priority: 100
    condition:
      op: "and"
      conditions:
        - key: "feature_trigger_my_behavior"
          op: "eq"
          value: true
```

### 2. 添加感知特征

```go
// 在合适的感知器中添加特征更新
func (s *MySensor) Update(entityID uint64) {
    // 计算是否应该触发行为
    shouldTrigger := s.checkCondition(entityID)

    aiDecision.UpdateFeature(decision.UpdateFeatureReq{
        Key:   "feature_trigger_my_behavior",
        Value: shouldTrigger,
    })
}
```

### 3. 实现执行器

```go
// executor.go

// 进入行为
func (e *Executor) handleMyBehaviorEntryTask(entityID uint32) {
    entity := e.scene.GetEntity(entityID)

    // 获取必要组件
    npcMoveComp := getNpcMoveComp(entity)

    // 初始化行为状态
    npcMoveComp.StopMove()

    // 设置行为参数
    log.Debugf("[MyBehavior] NPC %d entered my_behavior", entityID)
}

// 退出行为
func (e *Executor) handleMyBehaviorExitTask(entityID uint32) {
    // 清理状态
    log.Debugf("[MyBehavior] NPC %d exited my_behavior", entityID)
}

// 主循环
func (e *Executor) handleMyBehaviorMainTask(entityID uint32) {
    // 持续执行的逻辑
}
```

### 4. 注册处理函数

```go
func (e *Executor) executeEntryTask(entityID uint32, planName string, task *decision.Task) {
    switch planName {
    // ... 其他计划
    case "my_behavior":
        e.handleMyBehaviorEntryTask(entityID)
    }
}
```

## 常见行为模式

### 移动行为
```go
// 设置路点
npcMoveComp.SetPointList(points)
npcMoveComp.StartMove()

// NavMesh 寻路
npcMoveComp.SetNavPath(targetPos)
npcMoveComp.StartRun()
```

### 追逐行为
```go
// 设置目标实体
npcMoveComp.NavMesh.TargetType = NavMeshTargetType_Player
npcMoveComp.NavMesh.TargetEntity = playerEntityID
npcMoveComp.StartRun()
```

### 等待行为
```go
// 停止移动，等待条件满足
npcMoveComp.StopMove()
// 在 MainTask 中检查条件
```

### 交互行为
```go
// 面向目标
transformComp.LookAt(targetPos)
// 播放动画（通过客户端消息）
```

## 关键文件

- @servers/scene_server/internal/ecs/system/decision/executor.go
- @servers/scene_server/internal/ecs/system/decision/executor_helper.go
- @servers/scene_server/internal/ecs/com/cnpc/npc_move.go
- @servers/scene_server/internal/common/ai/decision/gss_brain/config/

## 使用方式

- `/npc-behavior create <name>` - 创建新行为
- `/npc-behavior flow <name>` - 查看行为流程
- `/npc-behavior debug <npc_id>` - 调试 NPC 行为
