# 行为树详细参考

> 本文档是从 `rules/behavior-tree.md` 拆出的详细内容，供开发时按需查阅。

## 节点清单

### 行为节点（Behavior Nodes）— 策划用

长运行自包含节点：OnEnter（初始化→Running）→ OnTick（保持 Running）→ OnExit（清理）。

| 节点名 | 语义 | OnEnter | OnExit |
|--------|------|---------|--------|
| `IdleBehavior` | 站在日程位置 | 设 Transform + 对话超时 | 重置 OutFinishStamp |
| `HomeIdleBehavior` | 站在家门口 | 设 feature_out_timeout + Transform | 清 feature_knock_req |
| `MoveBehavior` | 按日程移动 | 查路网路径 → 设移动组件 | StopMove |
| `DialogBehavior` | 和玩家对话 | 清事件 → 暂停对话 → 记录时间 | 恢复对话 → 补偿时间 |
| `PursuitBehavior` | 追逐目标 | NavMesh → 设追逐目标 | StopMove + 清目标 + NavMesh回程 |
| `InvestigateBehavior` | 前往调查 | NavMesh 寻路到 Feature 位置 | 清调查玩家 + 清 Feature |
| `MeetingIdleBehavior` | 站在聚会位置 | 从 meeting Feature 设 Transform | 无操作 |
| `MeetingMoveBehavior` | 走到聚会地点 | 找最近路点 → 查路网 → 设移动 | StopMove |
| `PlayerControlBehavior` | 被玩家控制 | 停止移动 + 清事件 | NavMesh 返回位置 |
| `ProxyTradeBehavior` | 代理交易 | SetTradeStatus(InTrade) | SetTradeStatus(None) |
| `ReturnToSchedule` | 回归日程（一次性） | OnEnter 返回 Success | — |

### 基础/原子节点（Primitive Nodes）— 程序员用

#### 异步节点（OnTick 监控完成）

| 节点名 | 语义 | OnEnter | OnTick | OnExit |
|--------|------|---------|--------|--------|
| `ChaseTarget` | NavMesh持续追逐 | 设追逐模式→Running | 持续Running / 视野丢失超时→Failed | StopMove + 清追逐 |
| `WaitForNavMeshArrival` | 等待NavMesh到达 | Running | 路径完成→Success / 异常停止→Failed | 被打断时StopMove |
| `WaitForRoadNetworkArrival` | 等待路网到达 | Running | IsFinish→Success | 被打断时StopMove |

#### 同步动作节点（OnEnter 立即完成）

| 节点名 | 语义 | OnEnter 行为 |
|--------|------|-------------|
| `SetupNavMeshPathToFeature` | NavMesh寻路到Feature位置 | 读Feature→寻路→设路径→Success |
| `StartMove` | 开始移动 | 调用StartMove/StartRun→Success |
| `PerformArrest` | 等待逮捕完成 | 确认IsArresting→Running，OnTick等IsArresting变false→Success |
| `ClearInvestigation` | 清除调查状态 | 清PoliceComp+Feature→Success |

### 控制节点

| 节点名 | 类型 | 说明 |
|--------|------|------|
| Sequence | 控制 | 依次执行子节点，遇到失败则停止 |
| Selector | 控制 | 依次尝试子节点，遇到成功则停止 |
| SimpleParallel | 控制 | 同时执行主任务 + 后台任务（finish_mode: immediate/delayed） |

### 装饰器节点

装饰节点在树中是被装饰节点的**父节点**，恰好持有一个子节点（`children[0]`）。通过在生命周期方法中手动委托给子节点并拦截返回值来实现装饰效果。三种拦截模式：后置拦截（改返回值）、前置拦截（条件不满足不调子节点）、循环拦截（子节点完成后 Reset 重跑）。

| 节点名 | 说明 |
|--------|------|
| Inverter | 反转子节点结果（Success ↔ Failed） |
| Repeater | 重复执行子节点 N 次（count=0 为无限重复） |
| Timeout | 超时后返回 Failed（timeout_ms / timeout_ms_key） |
| Cooldown | 成功后冷却期内跳过执行（cooldown_ms / cooldown_ms_key） |
| ForceSuccess | 子节点无论结果都返回 Success |
| ForceFailure | 子节点无论结果都返回 Failed |
| SubTree | 引用另一棵已注册的行为树（tree_name 参数） |

### 条件装饰器（Conditional Decorators）

| 节点名 | 说明 |
|--------|------|
| BlackboardCheck | 检查黑板值（支持 ==, !=, >, <, is_set 等运算符） |
| FeatureCheck | 检查 Feature 值（同 BlackboardCheck 的运算符） |

条件装饰器通过 `decorators` 字段附加到节点上，支持 `abort_type` 触发事件驱动中断。

### 服务节点（Services）

| 节点名 | 说明 |
|--------|------|
| SyncFeatureToBlackboard | 周期性将 Feature 值同步到 Blackboard（interval_ms，默认 200ms） |
| UpdateSchedule | 周期性更新日程数据到 Blackboard |
| Log | 周期性输出调试日志（interval_ms，默认 5000ms） |

## UE5 行为树特性

本系统对齐 UE5 行为树的核心特性：

### Decorator Abort（中断机制）

| abort_type | 行为 |
|------------|------|
| `none` | 不触发中断（默认） |
| `self` | 条件变化时中断当前子树 |
| `lower_priority` | 条件变化时中断更低优先级的兄弟节点 |
| `both` | 同时支持 self 和 lower_priority |

### Service（后台定期服务）

Service 附加在控制节点上，在节点活跃期间按 `interval_ms` 定期执行：
- `OnActivate`：节点激活时触发
- `OnTick`：按 interval_ms 间隔执行
- `OnDeactivate`：节点退出时触发

### SimpleParallel（并行执行）

- `finish_mode: "immediate"` — 主任务完成时立即结束
- `finish_mode: "delayed"` — 主任务完成后等待后台任务完成

### SubTree（子树引用）

通过 `tree_name` 参数引用另一棵已注册的行为树，最大递归深度 10 层。

### 事件驱动评估（脏 Key 机制）

1. 节点执行中修改 Blackboard → key 标记为脏
2. Runner Tick 时检查脏 key → 找到关联的条件装饰器
3. 条件装饰器重新评估 → 根据 abort_type 决定是否中断
4. 中断触发 → 调用相关节点的 OnExit 清理 → 重新选择子树

## JSON 配置格式

### 节点扩展字段

```json
{
  "type": "Selector",
  "description": "节点描述（可选，用于文档）",
  "decorators": [
    {
      "type": "BlackboardCheck",
      "abort_type": "lower_priority",
      "params": {"key": "has_target", "operator": "==", "value": true}
    }
  ],
  "services": [
    {
      "type": "SyncFeatureToBlackboard",
      "interval_ms": 500,
      "params": {"mappings": {"feature_key": "bb_key"}}
    }
  ],
  "children": [...]
}
```

### 复合树模式（多行为 Plan）

当一个 Plan 内部有多种行为分支时，使用 Selector + Service + Decorator(abort=both)：

```json
{
  "name": "daily_schedule",
  "root": {
    "type": "Selector",
    "services": [{
      "type": "SyncFeatureToBlackboard",
      "params": {"interval_ms": 500, "mappings": {"feature_schedule": "schedule"}}
    }],
    "children": [
      {
        "type": "MoveBehavior",
        "decorators": [{"type": "BlackboardCheck", "abort_type": "both",
          "params": {"key": "schedule", "operator": "==", "value": "MoveToBPointFormAPoint"}}]
      },
      {
        "type": "HomeIdleBehavior",
        "decorators": [{"type": "BlackboardCheck", "abort_type": "both",
          "params": {"key": "schedule", "operator": "==", "value": "StayInBuilding"}}]
      },
      {"type": "IdleBehavior"}
    ]
  }
}
```

工作原理：Service 同步 Feature → 脏 key → Decorator 重评估 → Abort 切换分支。最后一个无 Decorator 的分支作为默认回退。

## 目录结构

```
servers/scene_server/internal/common/ai/bt/
├── config/          # 配置类型定义 + JSON 加载器
├── context/         # BtContext 执行上下文（含 Blackboard 脏 key 追踪）
├── node/            # IBtNode / IConditionalDecorator / IService 接口
├── nodes/           # 所有节点实现（行为/基础/控制/装饰器/服务）
│   ├── factory.go              # 节点工厂
│   ├── behavior_nodes.go       # 行为节点
│   ├── behavior_helpers.go     # 行为节点工具函数
│   ├── sequence.go / selector.go / simple_parallel.go  # 控制节点
│   ├── decorator.go            # 装饰器
│   ├── blackboard_decorator.go / feature_decorator.go  # 条件装饰器
│   └── service_*.go            # 服务节点
├── runner/          # BtRunner 运行器（含事件驱动 Abort 评估）
└── trees/           # JSON 行为树配置（go:embed 自动嵌入）
```

## 调试建议

1. **启动日志**：检查 `[Scene] registered X behavior trees from config`
2. **Plan 触发**：检查 `[Executor] BT started, plan=xxx`
3. **Tick 执行**：检查 `[BtTickSystem] tree completed`
