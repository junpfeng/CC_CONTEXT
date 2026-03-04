# 小镇NPC位置存盘 - 并行Agent执行计划

## 依赖分析

```
┌─────────────────────────────────────────────────────────────────┐
│                      Phase 1: 基础层（顺序）                      │
│                                                                  │
│  Proto 定义 ──────────────→ TownNpcMgr 扩展                      │
│  (db_server.proto)          (town_npc.go)                       │
│                                                                  │
│  必须先完成，其他所有任务都依赖这两个                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Phase 2: 集成层（可并行）                       │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Agent B    │  │   Agent C    │  │   Agent D    │          │
│  │  场景保存    │  │  场景加载    │  │ NPC创建+脏标记│          │
│  │  save.go     │  │ scene_impl   │  │ town_npc.go  │          │
│  │              │  │              │  │ npc_move.go  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Agent 分配

### 串行阶段：Agent A（基础层）

**必须先完成**，其他 Agent 依赖其产出。

| 任务 | 文件 | 描述 |
|------|------|------|
| 1.1 | `resources/proto/base/db_server.proto` | 添加 `DBSaveTownNpcPosition` 消息 |
| 1.2 | 运行 `make proto` | 生成 Go 代码 |
| 1.3 | `servers/scene_server/internal/ecs/res/town/town_npc.go` | 扩展 TownNpcMgr |

**详细任务**:
```
Agent A 任务清单:
- [ ] 在 db_server.proto 中添加 DBSaveTownNpcPosition 消息定义
- [ ] 在 DBSaveTownInfo 中添加 npc_positions 字段
- [ ] 运行 make proto 生成代码
- [ ] 在 town_npc.go 中添加 NpcSavedPosition 结构
- [ ] 在 TownNpcMgr 中添加 savedPositions 字段
- [ ] 实现 LoadPositions() 方法
- [ ] 实现 ToSavePositions() 方法
- [ ] 实现 GetSavedPosition() 方法
- [ ] 实现 MarkPositionDirty() 方法
- [ ] 修改 NewTownNpcMgr() 初始化新字段
- [ ] 编译验证 town_npc.go
```

---

### 并行阶段：Agent B/C/D（集成层）

**Agent A 完成后**，以下 3 个 Agent 可以并行执行。

#### Agent B: 场景保存

| 任务 | 文件 | 描述 |
|------|------|------|
| 2.1 | `servers/scene_server/internal/ecs/scene/save.go` | 修改 saveTownInfo() |

**详细任务**:
```
Agent B 任务清单:
- [ ] 阅读 save.go 了解现有保存逻辑
- [ ] 在 saveTownInfo() 中添加 NPC 位置保存代码
- [ ] 编译验证
```

**代码模板**:
```go
// 在 saveTownInfo() 中添加
townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](s, common.ResourceType_TownNpcMgr)
if ok && townNpcMgr != nil {
    townInfo.NpcPositions = townNpcMgr.ToSavePositions()
}
```

---

#### Agent C: 场景加载

| 任务 | 文件 | 描述 |
|------|------|------|
| 3.1 | `servers/scene_server/internal/ecs/scene/scene_impl.go` | 修改 townRosurceInit() |

**详细任务**:
```
Agent C 任务清单:
- [ ] 阅读 scene_impl.go 了解 townRosurceInit() 位置
- [ ] 在 townRosurceInit() 中添加 NPC 位置加载代码
- [ ] 编译验证
```

**代码模板**:
```go
// 在 townRosurceInit() 中，TownNpcMgr 创建后添加
townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](s, common.ResourceType_TownNpcMgr)
if ok && townNpcMgr != nil && saveInfo.NpcPositions != nil {
    townNpcMgr.LoadPositions(saveInfo.NpcPositions)
}
```

---

#### Agent D: NPC创建 + 脏标记

| 任务 | 文件 | 描述 |
|------|------|------|
| 4.1 | `servers/scene_server/internal/net_func/npc/town_npc.go` | 修改 CreateTownNpc() |
| 4.2 | `servers/scene_server/internal/ecs/system/npc_move/npc_move.go` | 路径完成时标记脏 |

**详细任务**:
```
Agent D 任务清单:
- [ ] 阅读 town_npc.go 中 CreateTownNpc() 函数
- [ ] 在 NPC 创建后，添加位置恢复逻辑
- [ ] 阅读 npc_move.go 了解路径完成检测位置
- [ ] 在路径完成时添加 MarkPositionDirty() 调用
- [ ] 编译验证
```

**代码模板 (CreateTownNpc)**:
```go
// 在实体创建后，添加到 TownNpcMgr 之前
if savedPos, found := townNpcMgr.GetSavedPosition(cfg.GetId()); found {
    transformComp, ok := common.GetComponentAs[*ctrans.Transform](
        s, entity.ID(), common.ComponentType_Transform)
    if ok {
        transformComp.SetPosition(savedPos.Position)
        transformComp.SetRotation(savedPos.Rotation)
    }
}
```

**代码模板 (npc_move.go)**:
```go
// 在路径完成处理中
if npcMoveComp.IsFinish {
    townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](
        s.Scene(), common.ResourceType_TownNpcMgr)
    if ok && townNpcMgr != nil {
        townNpcMgr.MarkPositionDirty()
    }
}
```

---

## 执行时序图

```
时间线 ──────────────────────────────────────────────────────────→

Agent A │████████████████████████│
        │ Proto + TownNpcMgr     │
        │                        │
                                 │
                                 ▼ (Agent A 完成后启动)
                                 │
Agent B │                        │████████│
        │                        │ save.go│
        │                        │        │
Agent C │                        │████████│
        │                        │scene_impl
        │                        │        │
Agent D │                        │████████████│
        │                        │town_npc.go │
        │                        │npc_move.go │
                                 │            │
                                 └────────────┴─→ 合并验证
```

---

## 执行命令

### 阶段 1: 启动 Agent A（基础层）

```
启动 Agent A:
- 类型: general-purpose
- 任务: Proto 定义 + TownNpcMgr 扩展
- 依赖: 无
```

### 阶段 2: 启动 Agent B/C/D（并行）

**等待 Agent A 完成后**，同时启动:

```
启动 Agent B:
- 类型: general-purpose
- 任务: 修改 save.go
- 依赖: Agent A 完成

启动 Agent C:
- 类型: general-purpose
- 任务: 修改 scene_impl.go
- 依赖: Agent A 完成

启动 Agent D:
- 类型: general-purpose
- 任务: 修改 town_npc.go + npc_move.go
- 依赖: Agent A 完成
```

### 阶段 3: 合并验证

```
所有 Agent 完成后:
- 运行 make build APPS='scene_server'
- 验证编译通过
- 运行相关测试
```

---

## 总结

| 阶段 | Agent 数量 | 执行方式 | 任务 |
|------|------------|----------|------|
| Phase 1 | 1 (Agent A) | 串行 | Proto + TownNpcMgr |
| Phase 2 | 3 (B/C/D) | 并行 | save.go / scene_impl.go / town_npc+npc_move |
| Phase 3 | - | 合并 | 编译验证 |

**最大并行度**: 3 个 Agent（Phase 2）

**总 Agent 数**: 4 个（1 串行 + 3 并行）
