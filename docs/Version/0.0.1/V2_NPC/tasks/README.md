# 大世界 V2 NPC 系统 — 任务拆分

## 总览

共 8 个任务，按依赖关系分 5 个波次。**服务端（task-01~04）与客户端（task-05~07）可并行开发**，仅在最终集成（task-08）时汇合。

## 依赖图

```
Wave 1:  task-01 (Server 基础)          task-05 (Client 基础)
              │                              │
Wave 2:  task-02 (Server Handler)        task-06 (Client FSM+动画)
              │                              │
Wave 3:  task-03 (Server Spawner)        task-07 (Client Manager)
              │                              │
Wave 4:  task-04 (Server GM+配置)            │
              │                              │
Wave 5:  └──────── task-08 (端到端集成) ─────┘
```

## 任务列表

| 编号 | 名称 | 端 | 依赖 | 文件数 |
|------|------|-----|------|--------|
| task-01 | Server Pipeline 注册与数据结构基础 | Server | 无 | 4 |
| task-02 | Server 四维度 Handler 实现 | Server | task-01 | 4 |
| task-03 | Server ExtHandler + Spawner + Update System | Server | task-01, task-02 | 3 |
| task-04 | Server GM 命令 + JSON 配置文件 | Server | task-03 | 3+ |
| task-05 | Client Controller + 基础组件 | Client | 无 | 4 |
| task-06 | Client FSM 状态机 + 动画系统 | Client | task-05 | 5+ |
| task-07 | Client BigWorldNpcManager 管理器 | Client | task-05, task-06 | 1 |
| task-08 | 端到端集成联调 | Both | task-03, task-04, task-07 | 多文件微调 |

## 并行策略

- **Wave 1 并行**：task-01（Server）+ task-05（Client）无依赖可同时开发
- **Wave 2 并行**：task-02（Server）+ task-06（Client）各自依赖上一波次同端任务
- **Wave 3 并行**：task-03（Server）+ task-07（Client）
- **Wave 4**：task-04 仅依赖服务端链路
- **Wave 5**：task-08 汇合两端，执行集成联调

## 关键约束提醒

- 协议零新增：复用现有 NpcDataUpdate / NpcV2Info，不新增 Proto 消息
- 代码解耦：BigWorld NPC 不 import Town/Sakura 的扩展处理器或客户端模块
- 角度单位：所有角度变量命名带后缀（Deg/Rad），禁止混用
- EntityId 类型：客户端用 ulong，不是 int
- GM 前缀：所有 GM 命令必须以 `/ke* gm` 开头
