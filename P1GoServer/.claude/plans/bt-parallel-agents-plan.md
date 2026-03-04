# 行为树实施并行Agent计划

## 概述

本文档定义行为树系统实施的并行Agent分配方案，最大化并行度以加速开发。

### 依赖关系图

```
┌─────────────────────────────────────────────────────────────────────┐
│                         并行组1（6个Agent同时执行）                    │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │ Agent A  │  │ Agent B  │  │ Agent C  │  │ Agent D  │            │
│  │ 系统集成  │  │ 路径控制  │  │ Feature  │  │ 日程节点  │            │
│  │          │  │  节点    │  │  节点    │  │          │            │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘            │
│       │             │             │             │                   │
│  ┌────┴─────┐  ┌────┴─────┐                                        │
│  │ Agent E  │  │ Agent F  │                                        │
│  │ 对话节点  │  │ 路网节点  │                                        │
│  └────┬─────┘  └────┬─────┘                                        │
│       │             │                                               │
└───────┼─────────────┼───────────────────────────────────────────────┘
        │             │
        └──────┬──────┘
               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    并行组2（等待组1全部完成）                          │
│                                                                      │
│                      ┌──────────┐                                   │
│                      │ Agent G  │                                   │
│                      │ Factory  │                                   │
│                      │ 集成     │                                   │
│                      └────┬─────┘                                   │
│                           │                                         │
└───────────────────────────┼─────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    并行组3（等待组2完成）                             │
│                                                                      │
│                      ┌──────────┐                                   │
│                      │ Agent H  │                                   │
│                      │ 端到端   │                                   │
│                      │ 验证     │                                   │
│                      └──────────┘                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 并行组1：节点实现（6个Agent并行）

### Agent A：系统集成

**任务**：修复行为树注册缺失问题

**修改文件**：
- `servers/scene_server/internal/ecs/scene/scene_impl.go`
- `servers/scene_server/internal/common/ai/bt/runner/runner.go`（添加日志）
- `servers/scene_server/internal/ecs/system/decision/executor.go`（添加日志）

**具体工作**：
1. 在 `initNpcAISystemsFromConfig` 中调用 `trees.RegisterTreesFromConfig`
2. 在 `BtRunner.HasTree` 添加调试日志
3. 在 `Executor.OnPlanCreated` 添加调试日志
4. 在 `BtRunner.RegisterTree` 添加注册日志

**产出**：
- 修改后的3个文件
- 启动时能看到 `[Scene] registered N behavior trees` 日志

**预计工作量**：小

---

### Agent B：路径控制节点

**任务**：实现移动和寻路相关节点

**新建文件**：
- `servers/scene_server/internal/common/ai/bt/nodes/path_control.go`

**实现节点**：
| 节点 | 功能 | 参数 |
|------|------|------|
| `SetPathFindType` | 设置寻路类型 | `type`: "None"/"RoadNetwork"/"NavMesh" |
| `SetTargetType` | 设置目标类型 | `type`: "None"/"WayPoint"/"Player", `entity_id`: 可选 |
| `ClearPath` | 清除当前路径 | 无 |
| `StartRun` | 开始奔跑状态 | 无 |
| `StartMove` | 开始移动 | 无 |
| `SetTargetEntity` | 设置目标实体 | `entity_id` 或 `entity_id_key` |

**依赖组件**：`NpcMoveComp`

**参考代码**：
```go
// executor.go 中的原始逻辑
npcMoveComp.SetPathFindType(cnpc.PathFindType_RoadNetwork)
npcMoveComp.SetTargetType(cnpc.TargetType_WayPoint)
npcMoveComp.Clear()
npcMoveComp.StartRun()
```

**预计工作量**：中

---

### Agent C：Feature/Transform节点

**任务**：实现Feature同步和Transform设置节点

**新建文件**：
- `servers/scene_server/internal/common/ai/bt/nodes/feature_sync.go`

**实现节点**：
| 节点 | 功能 | 参数 |
|------|------|------|
| `SyncFeatureToBlackboard` | Feature值同步到黑板 | `mappings`: map[feature_key]blackboard_key |
| `SetTransformFromFeature` | 从Feature设置位置和朝向 | `pos_keys`: [x,y,z], `rot_keys`: [x,y,z] |

**依赖组件**：`DecisionComp`, `TransformComp`

**参考代码**：
```go
// executor.go 中的原始逻辑
posX := decisionComp.GetFeatureFloat32(feature_posx)
posY := decisionComp.GetFeatureFloat32(feature_posy)
posZ := decisionComp.GetFeatureFloat32(feature_posz)
transformComp.SetPosition(trans.NewVec3(posX, posY, posZ))
```

**预计工作量**：小

---

### Agent D：日程节点

**任务**：实现日程数据读取相关节点

**新建文件**：
- `servers/scene_server/internal/common/ai/bt/nodes/schedule.go`

**实现节点**：
| 节点 | 功能 | 参数 |
|------|------|------|
| `GetScheduleData` | 从日程组件读取数据到黑板 | `output_keys`: map[field]blackboard_key |
| `GetScheduleKey` | 获取当前日程key | `output_key`: string |

**依赖组件**：`NpcScheduleComp`

**需要扩展**：`BtContext` 添加 `GetScheduleComp()` 方法

**参考代码**：
```go
// executor.go 中的原始逻辑
scheduleComp := common.GetEntityComponentAs[*cnpc.NpcScheduleComp](entity)
cfg := scheduleComp.GetCurrentCfg()
serverTimeout := cfg.ServerTimeout
clientTimeout := cfg.ClientTimeout
```

**预计工作量**：中

---

### Agent E：对话节点

**任务**：实现对话相关节点

**新建文件**：
- `servers/scene_server/internal/common/ai/bt/nodes/dialog.go`

**实现节点**：
| 节点 | 功能 | 参数 |
|------|------|------|
| `SetDialogOutFinishStamp` | 设置外出结束时间戳 | `timeout_key` 或 `value` |
| `SetTownNpcOutDuration` | 同步外出时长到客户端 | `duration_key` |
| `PausePath` | 暂停当前路径 | 无 |
| `ResumePath` | 恢复当前路径 | 无 |
| `PushDialogTask` | 推送对话任务 | 参数待定 |

**依赖组件**：`DialogComp`, `NpcMoveComp`

**需要扩展**：`BtContext` 添加 `GetDialogComp()` 方法

**参考代码**：
```go
// executor.go 中的原始逻辑
dialogComp.SetOutFinishStamp(time.Now().Add(timeout).Unix())
npcMoveComp.PausePath()
npcMoveComp.ResumePath()
```

**预计工作量**：中

---

### Agent F：路网节点

**任务**：实现路网寻路相关节点

**新建文件**：
- `servers/scene_server/internal/common/ai/bt/nodes/roadnetwork.go`

**实现节点**：
| 节点 | 功能 | 参数 |
|------|------|------|
| `QueryRoadNetworkPath` | 查询路网路径 | `start_point_key`, `end_point_key`, `output_path_key` |
| `SetPointList` | 设置路径点列表 | `key_source`, `path_key`, `rot_keys` |

**依赖资源**：`RoadNetworkMgr`

**需要扩展**：`BtContext` 添加路网资源访问方法

**参考代码**：
```go
// executor.go 中的原始逻辑
roadNetMgr := common.GetResourceAs[*resource.RoadNetMgr](scene)
pathList := roadNetMgr.QueryPath(startPoint, endPoint)
npcMoveComp.SetPointList(scheduleKey, pathList, rotation)
```

**预计工作量**：中

---

## 并行组2：集成（1个Agent）

### Agent G：Factory集成 + Context扩展

**前置条件**：Agent A-F 全部完成

**任务**：
1. 扩展 `BtContext` 添加新组件访问方法
2. 在 `NodeFactory` 注册所有新节点
3. 验证所有节点能正确创建

**修改文件**：
- `servers/scene_server/internal/common/ai/bt/context/context.go`
- `servers/scene_server/internal/common/ai/bt/nodes/factory.go`

**Context扩展**：
```go
// 新增方法
func (c *BtContext) GetScheduleComp() *cnpc.NpcScheduleComp
func (c *BtContext) GetDialogComp() *cdialog.DialogComp
func (c *BtContext) GetRoadNetMgr() *resource.RoadNetMgr
```

**Factory注册**：
```go
// 路径控制
f.Register("SetPathFindType", createSetPathFindType)
f.Register("SetTargetType", createSetTargetType)
f.Register("ClearPath", createClearPath)
f.Register("StartRun", createStartRun)
f.Register("StartMove", createStartMove)
f.Register("SetTargetEntity", createSetTargetEntity)

// Feature/Transform
f.Register("SyncFeatureToBlackboard", createSyncFeatureToBlackboard)
f.Register("SetTransformFromFeature", createSetTransformFromFeature)

// 日程
f.Register("GetScheduleData", createGetScheduleData)
f.Register("GetScheduleKey", createGetScheduleKey)

// 对话
f.Register("SetDialogOutFinishStamp", createSetDialogOutFinishStamp)
f.Register("SetTownNpcOutDuration", createSetTownNpcOutDuration)
f.Register("PausePath", createPausePath)
f.Register("ResumePath", createResumePath)
f.Register("PushDialogTask", createPushDialogTask)

// 路网
f.Register("QueryRoadNetworkPath", createQueryRoadNetworkPath)
f.Register("SetPointList", createSetPointList)
```

**验证**：
- [ ] 编译通过
- [ ] 所有节点能通过Factory创建
- [ ] 从JSON配置加载不报错

**预计工作量**：中

---

## 并行组3：验证（1个Agent）

### Agent H：端到端验证

**前置条件**：Agent G 完成

**任务**：
1. 创建集成测试
2. 运行端到端验证
3. 修复发现的问题

**新建文件**：
- `servers/scene_server/internal/common/ai/bt/integration_test.go`

**测试场景**：
1. `home_idle` Plan完整流程
2. `idle` Plan完整流程
3. `move` Plan完整流程

**验收标准**：
- [ ] `home_idle` 行为树执行完成，日志正确
- [ ] `idle` 行为树执行完成，日志正确
- [ ] `move` 行为树执行完成，日志正确

**预计工作量**：中

---

## Agent执行命令

### 启动并行组1（6个Agent同时）

```bash
# 在一个终端窗口执行，启动所有6个Agent
claude --prompt "执行Agent A任务：系统集成修复" &
claude --prompt "执行Agent B任务：路径控制节点实现" &
claude --prompt "执行Agent C任务：Feature/Transform节点实现" &
claude --prompt "执行Agent D任务：日程节点实现" &
claude --prompt "执行Agent E任务：对话节点实现" &
claude --prompt "执行Agent F任务：路网节点实现" &
wait
```

### 启动并行组2（等待组1完成）

```bash
claude --prompt "执行Agent G任务：Factory集成 + Context扩展"
```

### 启动并行组3（等待组2完成）

```bash
claude --prompt "执行Agent H任务：端到端验证"
```

---

## 任务清单汇总

### Agent A - 系统集成
- [ ] 修改 scene_impl.go 调用 RegisterTreesFromConfig
- [ ] 添加 BtRunner.HasTree 日志
- [ ] 添加 BtRunner.RegisterTree 日志
- [ ] 添加 Executor.OnPlanCreated 日志
- [ ] 验证启动日志

### Agent B - 路径控制节点
- [ ] 实现 SetPathFindTypeNode
- [ ] 实现 SetTargetTypeNode
- [ ] 实现 ClearPathNode
- [ ] 实现 StartRunNode
- [ ] 实现 StartMoveNode
- [ ] 实现 SetTargetEntityNode
- [ ] 单元测试

### Agent C - Feature节点
- [ ] 实现 SyncFeatureToBlackboardNode
- [ ] 实现 SetTransformFromFeatureNode
- [ ] 单元测试

### Agent D - 日程节点
- [ ] 实现 GetScheduleDataNode
- [ ] 实现 GetScheduleKeyNode
- [ ] 单元测试

### Agent E - 对话节点
- [ ] 实现 SetDialogOutFinishStampNode
- [ ] 实现 SetTownNpcOutDurationNode
- [ ] 实现 PausePathNode
- [ ] 实现 ResumePathNode
- [ ] 实现 PushDialogTaskNode
- [ ] 单元测试

### Agent F - 路网节点
- [ ] 实现 QueryRoadNetworkPathNode
- [ ] 实现 SetPointListNode
- [ ] 单元测试

### Agent G - 集成
- [ ] 扩展 BtContext（GetScheduleComp, GetDialogComp, GetRoadNetMgr）
- [ ] 在 NodeFactory 注册所有新节点
- [ ] 验证从JSON加载

### Agent H - 验证
- [ ] 创建集成测试文件
- [ ] 测试 home_idle 流程
- [ ] 测试 idle 流程
- [ ] 测试 move 流程

---

## 总结

| 并行组 | Agent数量 | 预计耗时 | 依赖 |
|--------|----------|----------|------|
| 组1 | 6 | 2-3小时 | 无 |
| 组2 | 1 | 1小时 | 组1完成 |
| 组3 | 1 | 1小时 | 组2完成 |
| **总计** | **8** | **4-5小时** | - |

**最大并行度**：6个Agent
**总Agent数**：8个
**关键路径**：组1任意一个 → 组2 → 组3
