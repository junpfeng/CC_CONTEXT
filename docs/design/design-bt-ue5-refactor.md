# 设计文档：基于 UE5 设计思想的行为树重构（第一期）

## 1. 概述

### 1.1 目标

将行为树从"大节点 + 小组合 + 硬编码驱动"重构为"小节点 + 大组合 + 黑板驱动"，对齐 UE5 行为树设计思想。

### 1.2 范围（第一期）

| 变更 | 说明 |
|------|------|
| 节点实例隔离 | 修复模板共享，每次 Run 创建独立节点树 |
| Decorator 节点族 | 实现 Inverter、Repeater、Timeout、Cooldown |
| 行为节点拆解 | 将 17 个行为节点拆解为原子节点的 JSON 组合 |
| JSON 树重写 | 所有 `*_entry.json`、`*_exit.json`、`*_main.json` 从单节点变为组合树 |
| 清理 | 删除 `behavior_nodes.go`、`behavior_helpers.go` |

### 1.3 不在范围

- BlackboardDecorator + AbortType 中断机制（第二期）
- Parallel 节点（第二期）
- Service 后台轮询节点（第二期）
- SubTree 引用机制（第二期）

---

## 2. 架构变更

### 2.1 节点实例隔离（深拷贝）

**当前问题**：`BtRunner.trees` 存储共享的根节点引用。`Run()` 直接使用 `r.trees[treeName]`，多个 entity 运行同一棵树时共享节点状态。

**方案**：存储 `NodeConfig` 模板，每次 `Run()` 时从 config 重建独立节点树。

#### BtRunner 结构变更

```go
// Before
type BtRunner struct {
    trees        map[string]node.IBtNode       // 共享根节点（问题根源）
    runningTrees map[uint64]*TreeInstance
    contexts     map[uint64]*context.BtContext
}

// After
type BtRunner struct {
    treeConfigs  map[string]*config.BTreeConfig // 树配置模板
    loader       *config.BTreeLoader            // 用于从 config 重建节点树
    runningTrees map[uint64]*TreeInstance
    contexts     map[uint64]*context.BtContext
}
```

#### Run() 方法变更

```go
func (r *BtRunner) Run(treeName string, entityID uint64) error {
    cfg, ok := r.treeConfigs[treeName]
    if !ok {
        return ErrTreeNotFound
    }

    // 从 config 重建独立节点树（每个 entity 独立实例）
    root, err := r.loader.BuildNode(&cfg.Root)
    if err != nil {
        return fmt.Errorf("build tree %s failed: %w", treeName, err)
    }

    // ... 创建 TreeInstance，使用独立的 root
}
```

#### 注册接口变更

```go
// Before: 注册根节点
func (r *BtRunner) RegisterTree(treeName string, root node.IBtNode)

// After: 注册配置（根节点不再存储）
func (r *BtRunner) RegisterTreeConfig(treeName string, cfg *config.BTreeConfig)
```

#### 性能考虑

- 节点树重建开销：每次 Run 重建约 5-15 个节点，远低于 ECS 帧循环开销
- Plan 切换频率：每个 NPC 几秒到几分钟切换一次 Plan，重建开销可忽略
- 无需对象池：节点是轻量 struct，GC 友好

### 2.2 Loader 接口调整

`BTreeLoader.buildNode` 当前是私有方法，需导出为公共方法以供 `BtRunner` 在运行时调用：

```go
// config/loader.go
// Before: func (l *BTreeLoader) buildNode(cfg *NodeConfig) (node.IBtNode, error)
// After:
func (l *BTreeLoader) BuildNode(cfg *NodeConfig) (node.IBtNode, error)
```

### 2.3 注册流程变更

```go
// trees/example_trees.go - RegisterTreesFromConfig 变更
// Before: 解析 JSON → 构建节点树 → registerFunc(name, root)
// After:  解析 JSON → registerConfigFunc(name, config)

func RegisterTreesFromConfig(registerFunc func(string, *config.BTreeConfig)) (int, error) {
    // 不再需要 factory 和 loader（注册时不构建节点）
    files, _ := treeConfigs.ReadDir(".")
    for _, file := range files {
        data, _ := treeConfigs.ReadFile(file.Name())
        var cfg config.BTreeConfig
        json.Unmarshal(data, &cfg)
        registerFunc(cfg.Name, &cfg)
    }
}
```

---

## 3. Decorator 节点设计

### 3.1 基础装饰器

所有 Decorator 继承 `BaseNode`，通过 `cfg.Child` 指定单个子节点：

```json
{
  "type": "Inverter",
  "child": { "type": "CheckCondition", "params": {...} }
}
```

### 3.2 InverterNode

翻转子节点结果：Success → Failed，Failed → Success，Running 不变。

```go
type InverterNode struct {
    node.BaseNode
}

func (n *InverterNode) OnTick(ctx) BtNodeStatus {
    status := tickChild(n.child, ctx)
    switch status {
    case Success: return Failed
    case Failed:  return Success
    default:      return status
    }
}
```

**JSON 示例**：

```json
{
  "type": "Inverter",
  "child": {
    "type": "CheckCondition",
    "params": {"feature_key": "is_sleeping", "operator": "==", "value": true}
  }
}
```

### 3.3 RepeaterNode

重复执行子节点 N 次。

| 参数 | 类型 | 说明 |
|------|------|------|
| count | int | 重复次数（0 = 无限） |
| break_on_failure | bool | 子节点失败时是否中止（默认 true） |

```json
{
  "type": "Repeater",
  "params": {"count": 3, "break_on_failure": true},
  "child": { "type": "Wait", "params": {"duration_ms": 1000} }
}
```

### 3.4 TimeoutNode

子节点超时则强制失败。

| 参数 | 类型 | 说明 |
|------|------|------|
| timeout_ms | int64 | 超时时间（毫秒） |
| timeout_ms_key | string | 从黑板读取超时时间 |

```json
{
  "type": "Timeout",
  "params": {"timeout_ms": 5000},
  "child": { "type": "MoveTo", "params": {"target_key": "destination"} }
}
```

### 3.5 CooldownNode

子节点成功后进入冷却，冷却期间直接返回 Failed。

| 参数 | 类型 | 说明 |
|------|------|------|
| cooldown_ms | int64 | 冷却时间（毫秒） |
| cooldown_ms_key | string | 从黑板读取冷却时间 |

冷却状态需要存储在黑板中（节点是无状态的，重建后不保留）：
- 黑板 key：`_cooldown_{nodeID}_{timestamp}`

---

## 4. 行为节点拆解设计

### 4.1 拆解原则

1. **每个原子节点只做一件事**：获取数据 / 设置状态 / 查询路径 / 控制移动
2. **数据通过黑板传递**：前置节点写入黑板，后续节点从黑板读取
3. **条件通过 CheckCondition 或 Decorator 判断**：不在执行节点内部做条件分支
4. **失败传播由 Sequence 控制**：任一步骤失败，Sequence 整体失败

### 4.2 通用管道模式

拆解后的 JSON 树遵循统一模式：

```
Sequence
├── [可选] CheckCondition / SyncFeatureToBlackboard  (条件检查/数据准备)
├── [可选] GetScheduleData / GetCurrentTime           (获取运行时数据)
├── 核心操作节点 1                                     (路径查询/状态设置)
├── 核心操作节点 2
└── ...
```

### 4.3 新增原子节点

拆解过程中发现需要新增的原子节点：

| 节点 | Category | 说明 |
|------|----------|------|
| `SetDialogRoleId` | Dialog | 设置对话角色 ID（从 feature 或黑板读取） |
| `SetTradeStatus` | Specific | 设置交易状态（InTrade / None） |
| `ComputeBlackboard` | Blackboard | 黑板值计算（加减乘除，用于超时计算等） |

#### SetDialogRoleId

```go
// Params: role_id_feature_key (string) - 从 Feature 读取角色 ID
// Writes: DialogComponent.SetDialogRoleId
```

#### SetTradeStatus

```go
// Params: status (string) - "in_trade" / "none"
// Writes: NpcTradeProxyComponent.SetTradeStatus
```

#### ComputeBlackboard

用于黑板值之间的数学运算，替代行为节点中硬编码的超时计算：

```json
{
  "type": "ComputeBlackboard",
  "params": {
    "operation": "subtract",
    "left_key": "schedule_end_time",
    "right_key": "current_time",
    "output_key": "server_timeout"
  }
}
```

支持的操作：`add`、`subtract`、`multiply`、`divide`、`multiply_const`

### 4.4 行为节点拆解对照表

#### 4.4.1 ChaseTarget（pursuit_entry）

**原始**：清路径 → 跑步 → NavMesh 寻路 → 设目标实体 → 设目标类型

```json
{
  "name": "pursuit_entry",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "SyncFeatureToBlackboard", "params": {
        "mappings": {"feature_pursuit_entity_id": "target_entity_id"}
      }},
      {"type": "ClearPath"},
      {"type": "StartRun"},
      {"type": "SetPathFindType", "params": {"type": "navmesh"}},
      {"type": "SetTargetEntity", "params": {"entity_id_key": "target_entity_id"}},
      {"type": "SetTargetType", "params": {"type": "player"}}
    ]
  }
}
```

#### 4.4.2 ClearPursuitState（pursuit_exit）

**原始**：停止移动 → 清寻路 → 清目标

```json
{
  "name": "pursuit_exit",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "StopMove"},
      {"type": "SetPathFindType", "params": {"type": "none"}},
      {"type": "SetTargetEntity", "params": {"entity_id": 0}},
      {"type": "SetTargetType", "params": {"type": "none"}}
    ]
  }
}
```

#### 4.4.3 StartDialog（dialog_entry）

**原始**：清对话特征 → 暂停 → 设暂停时间 → 设对话状态 → 设事件类型 → 设角色 ID

```json
{
  "name": "dialog_entry",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "ClearDialogEventFeature"},
      {"type": "SetDialogPause", "params": {"paused": true}},
      {"type": "GetCurrentTime", "params": {"output_key": "pause_time"}},
      {"type": "SetDialogPauseTime", "params": {"time_key": "pause_time"}},
      {"type": "SetDialogState", "params": {"state": "dialog"}},
      {"type": "SetDialogEventType", "params": {"event_type": "none"}},
      {"type": "SetDialogRoleId", "params": {"feature_key": "feature_dialog_role_id"}}
    ]
  }
}
```

#### 4.4.4 EndDialog（dialog_exit）

**原始**：清特征 → 恢复 → 计算对话时长 → 延长超时 → 设空闲状态

```json
{
  "name": "dialog_exit",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "ClearDialogEventFeature"},
      {"type": "SetDialogPause", "params": {"paused": false}},
      {"type": "UpdateOutFinishStampAfterDialog"},
      {"type": "SetDialogState", "params": {"state": "idle"}},
      {"type": "SetDialogEventType", "params": {"event_type": "none"}}
    ]
  }
}
```

#### 4.4.5 GoToSchedulePoint（move_entry）

**原始**：检查 pathfind_completed → 获取日程 → 获取特征点 → 路网寻路 → 设路点 → 开始移动

```json
{
  "name": "move_entry",
  "root": {
    "type": "Selector",
    "children": [
      {
        "type": "Sequence",
        "children": [
          {"type": "CheckCondition", "params": {
            "feature_key": "feature_args1", "operator": "==", "value": "pathfind_completed"
          }},
          {"type": "SetFeature", "params": {
            "feature_key": "feature_args1", "feature_value": ""
          }}
        ]
      },
      {
        "type": "Sequence",
        "children": [
          {"type": "SyncFeatureToBlackboard", "params": {
            "mappings": {
              "feature_start_point": "start_point",
              "feature_end_point": "end_point"
            }
          }},
          {"type": "GetScheduleKey", "params": {"output_key": "schedule_key"}},
          {"type": "SyncFeatureToBlackboard", "params": {
            "mappings": {
              "feature_rotx": "rot_x",
              "feature_roty": "rot_y",
              "feature_rotz": "rot_z"
            }
          }},
          {"type": "QueryRoadNetworkPath", "params": {
            "start_point_key": "start_point",
            "end_point_key": "end_point",
            "output_path_key": "road_path"
          }},
          {"type": "SetPointList", "params": {
            "key_source": "schedule_key",
            "path_key": "road_path",
            "rot_keys": ["rot_x", "rot_y", "rot_z"]
          }},
          {"type": "StartMove"},
          {"type": "SetPathFindType", "params": {"type": "roadnetwork"}},
          {"type": "SetTargetEntity", "params": {"entity_id": 0}},
          {"type": "SetTargetType", "params": {"type": "waypoint"}}
        ]
      }
    ]
  }
}
```

#### 4.4.6 StopMoving（move_exit / meeting_move_exit）

```json
{
  "name": "move_exit",
  "root": {"type": "StopMove"}
}
```

#### 4.4.7 StandAtSchedulePos（idle_entry）

**原始**：获取日程 → 计算超时 → 设 Transform → 设超时

```json
{
  "name": "idle_entry",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "GetScheduleData", "params": {
        "output_keys": {
          "server_timeout": "server_timeout",
          "client_timeout": "client_timeout"
        }
      }},
      {"type": "SetTransformFromFeature", "params": {
        "pos_keys": ["feature_posx", "feature_posy", "feature_posz"],
        "rot_keys": ["feature_rotx", "feature_roty", "feature_rotz"]
      }},
      {"type": "SetDialogOutFinishStamp", "params": {"timeout_key": "server_timeout"}},
      {"type": "SetTownNpcOutDuration", "params": {"duration_key": "client_timeout"}}
    ]
  }
}
```

#### 4.4.8 StandAtHomePos（home_idle_entry）

```json
{
  "name": "home_idle_entry",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "SetFeature", "params": {
        "feature_key": "feature_out_timeout", "feature_value": true
      }},
      {"type": "SetTransformFromFeature", "params": {
        "pos_keys": ["feature_posx", "feature_posy", "feature_posz"],
        "rot_keys": ["feature_rotx", "feature_roty", "feature_rotz"]
      }}
    ]
  }
}
```

#### 4.4.9 StandAtMeetingPos（meeting_idle_entry）

```json
{
  "name": "meeting_idle_entry",
  "root": {
    "type": "SetTransformFromFeature",
    "params": {
      "pos_keys": ["feature_meeting_posx", "feature_meeting_posy", "feature_meeting_posz"],
      "rot_keys": ["feature_meeting_rotx", "feature_meeting_roty", "feature_meeting_rotz"]
    }
  }
}
```

#### 4.4.10 GoToMeetingPoint（meeting_move_entry）

```json
{
  "name": "meeting_move_entry",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "FindNearestRoadPoint", "params": {"output_key": "nearest_point"}},
      {"type": "SyncFeatureToBlackboard", "params": {
        "mappings": {"feature_meeting_point_id": "meeting_point"}
      }},
      {"type": "QueryRoadNetworkPath", "params": {
        "start_point_key": "nearest_point",
        "end_point_key": "meeting_point",
        "output_path_key": "meeting_path"
      }},
      {"type": "SetPointList", "params": {
        "key_source": "gotoMeeting",
        "path_key": "meeting_path"
      }},
      {"type": "StartMove"},
      {"type": "SetPathFindType", "params": {"type": "roadnetwork"}},
      {"type": "SetTargetEntity", "params": {"entity_id": 0}},
      {"type": "SetTargetType", "params": {"type": "waypoint"}}
    ]
  }
}
```

#### 4.4.11 GoToInvestigatePos（investigate_entry）

```json
{
  "name": "investigate_entry",
  "root": {
    "type": "SetupNavMeshPathToFeaturePos",
    "params": {
      "pos_keys": ["feature_posx", "feature_posy", "feature_posz"],
      "rot_keys": ["feature_rotx", "feature_roty", "feature_rotz"]
    }
  }
}
```

#### 4.4.12 ClearInvestigateState（investigate_exit）

```json
{
  "name": "investigate_exit",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "SetInvestigatePlayer", "params": {"player_id": 0}},
      {"type": "SetFeature", "params": {
        "feature_key": "feature_release_wanted", "feature_value": false
      }},
      {"type": "SetFeature", "params": {
        "feature_key": "feature_pursuit_miss", "feature_value": false
      }}
    ]
  }
}
```

#### 4.4.13 ReturnToSchedule（transition 树）

```json
{
  "name": "pursuit_to_move_transition",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "SetupNavMeshPathToFeaturePos", "params": {
        "pos_keys": ["feature_posx", "feature_posy", "feature_posz"],
        "rot_keys": ["feature_rotx", "feature_roty", "feature_rotz"]
      }},
      {"type": "SetFeature", "params": {
        "feature_key": "feature_args1", "feature_value": "pathfind_completed"
      }}
    ]
  }
}
```

（`sakura_npc_control_to_move_transition` 结构相同）

#### 4.4.14 StartProxyTrade（proxy_trade_entry）

```json
{
  "name": "proxy_trade_entry",
  "root": {"type": "SetTradeStatus", "params": {"status": "in_trade"}}
}
```

#### 4.4.15 EndProxyTrade（proxy_trade_exit）

```json
{
  "name": "proxy_trade_exit",
  "root": {"type": "SetTradeStatus", "params": {"status": "none"}}
}
```

#### 4.4.16 EnterPlayerControl（sakura_npc_control_entry）

```json
{
  "name": "sakura_npc_control_entry",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "StopMove"},
      {"type": "SetSakuraControlEventType", "params": {"event_type": "none"}}
    ]
  }
}
```

#### 4.4.17 ExitPlayerControl（sakura_npc_control_exit）

```json
{
  "name": "sakura_npc_control_exit",
  "root": {
    "type": "Sequence",
    "children": [
      {"type": "SetSakuraControlEventType", "params": {"event_type": "none"}},
      {"type": "SetupNavMeshPathToFeaturePos", "params": {
        "pos_keys": ["feature_posx", "feature_posy", "feature_posz"],
        "rot_keys": ["feature_rotx", "feature_roty", "feature_rotz"]
      }}
    ]
  }
}
```

### 4.5 Main 树

`*_main.json` 树在当前业务中大部分是空操作（Plan 的主阶段由 ECS 系统驱动），保持简单结构：

```json
{"name": "idle_main", "root": {"type": "Log", "params": {"message": "idle main", "level": "debug"}}}
```

---

## 5. 迁移策略

### 5.1 迁移顺序

分 4 步，每步完成后验证构建和测试：

| 步骤 | 内容 | 风险 |
|------|------|------|
| **Step 1** | 节点实例隔离：重构 BtRunner + Loader 接口 | 低（不改变行为） |
| **Step 2** | 新增节点：Decorator × 4 + 原子节点 × 3 | 低（纯新增） |
| **Step 3** | 重写 JSON 树：用原子组合替换行为节点 | 高（行为等价性） |
| **Step 4** | 清理：删除 behavior_nodes.go / behavior_helpers.go + 更新测试 | 中（删除代码） |

### 5.2 行为等价性验证

Step 3 每重写一棵 JSON 树，需要验证：

1. 新 JSON 树的节点执行顺序与原行为节点 OnEnter 逻辑一致
2. 操作的 ECS 组件和调用参数完全一致
3. 失败路径行为一致（组件获取失败 → Sequence 中断 → 树失败）

---

## 6. 文件改动清单

### 修改文件

| 文件 | 变更 |
|------|------|
| `runner/runner.go` | 存储 config 替代 root；Run 时重建节点树 |
| `config/loader.go` | 导出 `BuildNode` 方法 |
| `trees/example_trees.go` | 注册配置替代注册节点；更新 RegisterTreesFromConfig |
| `nodes/factory.go` | 删除行为节点注册（17 个 createXxx + 4 个 alias） |
| `bt/trees/*.json` | 全部重写为原子组合 |
| `integration_test.go` | 更新节点注册测试、JSON 加载测试 |
| `integration_phased_test.go` | 适配新的注册接口 |

### 新增文件

| 文件 | 内容 |
|------|------|
| `nodes/decorator.go` | Inverter、Repeater、Timeout、Cooldown |
| `nodes/set_dialog_role_id.go` | SetDialogRoleId 原子节点 |
| `nodes/set_trade_status.go` | SetTradeStatus 原子节点 |
| `nodes/compute_blackboard.go` | ComputeBlackboard 计算节点 |

### 删除文件

| 文件 | 原因 |
|------|------|
| `nodes/behavior_nodes.go` | 所有行为节点被 JSON 组合替代 |
| `nodes/behavior_helpers.go` | 工具函数不再需要（逻辑移入原子节点） |

---

## 7. 风险和缓解

| 风险 | 缓解措施 |
|------|----------|
| 行为回归 | 逐棵树重写，每棵验证等价性 |
| 性能退化（节点重建开销） | Plan 切换频率低（秒级），重建 5-15 个节点可忽略 |
| JSON 膨胀 | 树结构扁平化（大部分是 Sequence + 叶子），可读性尚可 |
| Decorator 引入复杂度 | 第一期只实现最基础的 4 个，不含 AbortType |
| behavior_helpers 中的逻辑丢失 | 确认 setupNavMeshPath / getTransformFromFeatures 等已有等价原子节点 |
