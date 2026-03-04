# 小镇NPC位置存盘系统实施计划

## 概述

为小镇NPC添加位置和朝向的持久化存储功能，在NPC创建时恢复上次保存的位置，在场景保存时持久化当前位置。

## 设计原则

1. **复用现有机制**：使用 `SceneSaveSystem` 的 60 秒定时保存，不新建系统
2. **遵循现有模式**：使用 `SetSave()`/`IsNeedSave()` 脏标记机制
3. **最小侵入**：扩展 `TownNpcMgr`，不修改 NPC 核心组件
4. **事件驱动脏标记**：在关键事件时标记脏，而非定时检测位置差异

---

## 一、Proto 定义

**文件**: `resources/proto/base/db_server.proto`

```protobuf
// 小镇NPC位置数据（添加在文件适当位置）
message DBSaveTownNpcPosition {
    int32 npc_cfg_id = 1;         // NPC配置ID
    base.Vector3 position = 2;     // 位置
    base.Vector3 rotation = 3;     // 朝向
}

// 修改 DBSaveTownInfo，添加字段
message DBSaveTownInfo {
    // ... existing fields (1-19) ...
    repeated DBSaveTownNpcPosition npc_positions = 20;  // NPC位置数据
}
```

**执行步骤**:
1. 在 `db_server.proto` 中添加 `DBSaveTownNpcPosition` 消息定义
2. 在 `DBSaveTownInfo` 中添加 `npc_positions` 字段
3. 运行 `make proto` 生成 Go 代码

---

## 二、TownNpcMgr 扩展

**文件**: `servers/scene_server/internal/ecs/res/town/town_npc.go`

### 2.1 数据结构

```go
// NpcSavedPosition NPC保存的位置数据
type NpcSavedPosition struct {
    Position transform.Vec3
    Rotation transform.Vec3
}

type TownNpcMgr struct {
    common.ResourceBase

    NpcMap       map[int32]*TownNpcInfo
    PoliceNpcMap map[int32]*TownNpcInfo

    // 新增：位置持久化数据
    savedPositions map[int32]*NpcSavedPosition  // npcCfgId -> 位置数据
}
```

### 2.2 新增方法

```go
// LoadPositions 从DB数据加载NPC位置（场景初始化时调用）
func (m *TownNpcMgr) LoadPositions(data []*proto.DBSaveTownNpcPosition) {
    if m.savedPositions == nil {
        m.savedPositions = make(map[int32]*NpcSavedPosition)
    }
    for _, pos := range data {
        if pos == nil {
            continue
        }
        m.savedPositions[pos.NpcCfgId] = &NpcSavedPosition{
            Position: transform.Vec3{
                X: pos.Position.X,
                Y: pos.Position.Y,
                Z: pos.Position.Z,
            },
            Rotation: transform.Vec3{
                X: pos.Rotation.X,
                Y: pos.Rotation.Y,
                Z: pos.Rotation.Z,
            },
        }
    }
    m.Infof("LoadPositions: loaded %d npc positions", len(m.savedPositions))
}

// ToSavePositions 导出NPC位置数据（场景保存时调用）
func (m *TownNpcMgr) ToSavePositions() []*proto.DBSaveTownNpcPosition {
    result := make([]*proto.DBSaveTownNpcPosition, 0, len(m.NpcMap))

    for npcCfgId, npcInfo := range m.NpcMap {
        if npcInfo == nil || npcInfo.Entity == nil {
            continue
        }

        // 获取当前位置
        transformComp, ok := common.GetComponentAs[*ctrans.Transform](
            m.GetScene(), npcInfo.Entity.ID(), common.ComponentType_Transform)
        if !ok {
            continue
        }

        pos := transformComp.Position()
        rot := transformComp.Rotation()

        result = append(result, &proto.DBSaveTownNpcPosition{
            NpcCfgId: npcCfgId,
            Position: &proto.Vector3{X: pos.X, Y: pos.Y, Z: pos.Z},
            Rotation: &proto.Vector3{X: rot.X, Y: rot.Y, Z: rot.Z},
        })
    }

    m.Debugf("ToSavePositions: saved %d npc positions", len(result))
    return result
}

// GetSavedPosition 获取NPC保存的位置（NPC创建时调用）
func (m *TownNpcMgr) GetSavedPosition(npcCfgId int32) (*NpcSavedPosition, bool) {
    if m.savedPositions == nil {
        return nil, false
    }
    pos, ok := m.savedPositions[npcCfgId]
    return pos, ok
}

// MarkPositionDirty 标记位置数据需要保存
func (m *TownNpcMgr) MarkPositionDirty() {
    m.SetSave()
}
```

### 2.3 修改 NewTownNpcMgr

```go
func NewTownNpcMgr(scene common.Scene) *TownNpcMgr {
    return &TownNpcMgr{
        ResourceBase:   common.NewResourceBase(scene, common.ResourceType_TownNpcMgr),
        NpcMap:         make(map[int32]*TownNpcInfo),
        PoliceNpcMap:   make(map[int32]*TownNpcInfo),
        savedPositions: make(map[int32]*NpcSavedPosition),  // 新增
    }
}
```

---

## 三、场景保存集成

**文件**: `servers/scene_server/internal/ecs/scene/save.go`

### 3.1 修改 saveTownInfo()

```go
func (s *scene) saveTownInfo() error {
    townInfo := &proto.DBSaveTownInfo{}

    // ... existing code ...

    // 新增：保存NPC位置
    townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](s, common.ResourceType_TownNpcMgr)
    if ok && townNpcMgr != nil {
        townInfo.NpcPositions = townNpcMgr.ToSavePositions()
    }

    // ... rest of existing code ...
}
```

---

## 四、场景初始化集成

**文件**: `servers/scene_server/internal/ecs/scene/scene_impl.go`

### 4.1 修改 townRosurceInit()

```go
func (s *scene) townRosurceInit(saveInfo *proto.DBSaveTownInfo) error {
    // ... existing code ...

    // 新增：加载NPC位置数据到TownNpcMgr
    townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](s, common.ResourceType_TownNpcMgr)
    if ok && townNpcMgr != nil && saveInfo.NpcPositions != nil {
        townNpcMgr.LoadPositions(saveInfo.NpcPositions)
    }

    // ... rest of existing code ...
}
```

---

## 五、NPC创建时使用保存的位置

**文件**: `servers/scene_server/internal/net_func/npc/town_npc.go`

### 5.1 修改 CreateTownNpc()

```go
func CreateTownNpc(s common.Scene, cfg *config.CfgTownNpc) common.Entity {
    // ... existing code to create entity ...

    // 新增：尝试使用保存的位置
    townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](s, common.ResourceType_TownNpcMgr)
    if ok && townNpcMgr != nil {
        if savedPos, found := townNpcMgr.GetSavedPosition(cfg.GetId()); found {
            // 使用保存的位置
            transformComp, ok := common.GetComponentAs[*ctrans.Transform](
                s, entity.ID(), common.ComponentType_Transform)
            if ok {
                transformComp.SetPosition(savedPos.Position)
                transformComp.SetRotation(savedPos.Rotation)
                s.Infof("[CreateTownNpc] restored position for npc %d: pos=(%v,%v,%v)",
                    cfg.GetId(), savedPos.Position.X, savedPos.Position.Y, savedPos.Position.Z)
            }
        }
    }

    // ... rest of existing code ...
}
```

---

## 六、脏标记触发点

**文件**: `servers/scene_server/internal/ecs/system/npc_move/npc_move.go`

### 6.1 路径完成时标记脏

在 NPC 路径完成的处理逻辑中添加脏标记：

```go
// 当 NPC 路径完成时
if npcMoveComp.IsFinish {
    // 标记位置需要保存
    townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](s.Scene(), common.ResourceType_TownNpcMgr)
    if ok && townNpcMgr != nil {
        townNpcMgr.MarkPositionDirty()
    }
}
```

### 6.2 其他触发点（可选）

- **日程切换时**：在 `DecisionComp` 状态变化时
- **NPC 停止移动时**：在 `StopMove()` 调用时
- **场景关闭时**：在 `scene.Stop()` 中强制保存

---

## 七、数据流程图

```
┌─────────────────────────────────────────────────────────────────┐
│                        场景初始化                                │
│                                                                  │
│  1. dbEntry.GetTownIfno() 获取 DBSaveTownInfo                   │
│  2. townRosurceInit() 初始化资源                                 │
│  3. TownNpcMgr.LoadPositions() 加载位置缓存                      │
│  4. CreateTownNpc() 创建NPC                                      │
│     └─→ GetSavedPosition() 获取保存的位置                        │
│     └─→ Transform.SetPosition/SetRotation() 设置位置             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        运行时                                    │
│                                                                  │
│  NPC 移动、状态切换...                                           │
│       │                                                          │
│       ▼                                                          │
│  路径完成 / 状态切换 → TownNpcMgr.MarkPositionDirty()           │
│       │                                    │                     │
│       │                                    ▼                     │
│       │                              SetSave() 设置脏标记        │
└───────┼─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│                   定时保存（每60秒）                              │
│                                                                  │
│  SceneSaveSystem.Update()                                       │
│       │                                                          │
│       ▼                                                          │
│  scene.Save() → saveTownInfo()                                  │
│       │                                                          │
│       ├─→ TownNpcMgr.ToSavePositions() 收集所有NPC当前位置       │
│       │                                                          │
│       └─→ dbEntry.SaveTownInfo(townInfo) 写入DB                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 八、实施步骤

### Phase 1: Proto 定义
- [ ] 修改 `db_server.proto` 添加消息定义
- [ ] 运行 `make proto` 生成代码

### Phase 2: TownNpcMgr 扩展
- [ ] 添加 `NpcSavedPosition` 结构
- [ ] 添加 `savedPositions` 字段
- [ ] 实现 `LoadPositions()` 方法
- [ ] 实现 `ToSavePositions()` 方法
- [ ] 实现 `GetSavedPosition()` 方法
- [ ] 实现 `MarkPositionDirty()` 方法
- [ ] 修改 `NewTownNpcMgr()` 初始化新字段

### Phase 3: 场景集成
- [ ] 修改 `save.go` 的 `saveTownInfo()` 添加位置保存
- [ ] 修改 `scene_impl.go` 的 `townRosurceInit()` 添加位置加载

### Phase 4: NPC 创建集成
- [ ] 修改 `CreateTownNpc()` 使用保存的位置

### Phase 5: 脏标记触发
- [ ] 在路径完成时添加脏标记
- [ ] （可选）在其他关键点添加脏标记

### Phase 6: 测试验证
- [ ] 编译通过
- [ ] 单元测试
- [ ] 集成测试：验证 NPC 位置保存和恢复

---

## 九、注意事项

1. **首次运行**：DB 中无位置数据时，NPC 使用默认位置（日程起点）
2. **NPC 数量**：小镇 NPC 数量有限（通常几十个），全量保存性能可接受
3. **位置精度**：使用 `float32`，足够满足游戏需求
4. **向后兼容**：新字段为 repeated，旧数据兼容

---

## 十、文件修改清单

| 文件 | 修改类型 | 描述 |
|------|----------|------|
| `resources/proto/base/db_server.proto` | 修改 | 添加 NPC 位置 proto 定义 |
| `servers/scene_server/internal/ecs/res/town/town_npc.go` | 修改 | 扩展 TownNpcMgr |
| `servers/scene_server/internal/ecs/scene/save.go` | 修改 | 添加 NPC 位置保存 |
| `servers/scene_server/internal/ecs/scene/scene_impl.go` | 修改 | 添加 NPC 位置加载 |
| `servers/scene_server/internal/net_func/npc/town_npc.go` | 修改 | NPC 创建时使用保存位置 |
| `servers/scene_server/internal/ecs/system/npc_move/npc_move.go` | 修改 | 路径完成时标记脏 |
