---
name: town-task
description: 小镇任务系统开发助手。当用户需要添加新任务事件类型、调试任务进度、理解任务流程时使用
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
argument-hint: "[add-event|debug|flow] [参数]"
---

# 小镇任务系统开发助手

帮助开发者快速完成小镇任务系统相关的开发工作。

## 使用方式

- `/town-task add-event <事件名称>` - 添加新的任务事件类型
- `/town-task debug <stageId>` - 调试指定任务阶段的配置和代码
- `/town-task flow` - 展示任务系统的完整流程图

## 核心文件位置

| 文件 | 路径 | 职责 |
|------|------|------|
| TaskManager | `servers/scene_server/internal/ecs/res/town/town_task.go` | 任务管理器 |
| Task | `servers/scene_server/internal/common/town_task/task.go` | 任务结构体 |
| Condition | `servers/scene_server/internal/common/town_task/task_condition.go` | 条件系统 |
| EventType | `servers/scene_server/internal/common/town_task/task_event.go` | 事件类型定义 |

## 执行步骤

### add-event: 添加新事件类型

1. 读取 `task_event.go`，在合适的位置添加新的 EventType 常量
2. 读取 `task_condition.go`，在 `AddCondition` 的 switch 中添加对应的 case
3. 确定事件分类（State/Progress/AutoTime），使用对应的 Condition 类型
4. 提示用户需要在配置表 CfgTownTaskTarget 中添加对应配置

### debug: 调试任务

1. 读取配置表相关代码，找到 stageId 对应的配置
2. 分析 targets 列表中的事件类型
3. 检查 TriggerEvent 的调用点
4. 输出任务流程和可能的问题点

### flow: 展示流程

输出任务系统的核心流程：

```
配置加载 -> registerAllTask() -> observers 注册
     |
     v
玩家进入 -> initOpenTasks() -> 创建初始任务
     |
     v
事件触发 -> TriggerEvent() -> onNotify() -> 更新条件
     |
     v
任务完成 -> onTaskFinish() -> CreateNextTasks() -> 创建后续任务
```

## 事件分类参考

| 分类 | Condition类型 | 特点 | 示例 |
|------|---------------|------|------|
| State | StateCondition | 触发一次即完成 | 打开手机、交互物件 |
| Progress | ProgressCondition | 累积达到目标值 | 收集N个物品 |
| AutoTime | AutoTimeCondition | 等待倒计时结束 | 等待藏匿点刷新 |

## 注意事项

- EventType 的值必须唯一，通常使用5位数字（如 10101, 20201）
- 新事件类型需要同步更新配置表 CfgTownTaskTarget
- State 类事件的 target 固定为 1，Progress 事件的 target 从配置读取
