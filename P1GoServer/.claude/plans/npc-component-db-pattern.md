# NPC 组件数据库存取通用方案

## 概述

本文档描述 NPC 组件持久化到数据库的通用模式，适用于需要保存状态的 NPC 组件。

## 架构流程

```
Component (数据)
    ↓ ToSaveProto()
Proto Message (序列化)
    ↓ TownNpcMgr.ToSaveXxxList()
DBSaveTownInfo (聚合)
    ↓ DbEntry.SaveTownInfo()
MongoDB (持久化)
```

## 实施步骤

### 步骤 1: 定义 Proto 消息

在对应的 proto 文件中定义组件数据结构（如 `npc.proto`）：

```protobuf
// 组件保存数据结构
message XxxCompInfo {
    int32 npc_cfg_id = 1;        // 必须：NPC配置ID作为关联键
    // ... 组件需要持久化的字段
}
```

在 `db_server.proto` 的 `DBSaveTownInfo` 中添加列表字段：

```protobuf
message DBSaveTownInfo {
    // ... 现有字段 ...
    repeated npc.XxxCompInfo xxx_comp_info = N;
}
```

### 步骤 2: 组件实现序列化方法

```go
// ToSaveProto 转换为数据库保存格式
func (c *XxxComp) ToSaveProto(npcCfgId int32) *proto.XxxCompInfo {
    return &proto.XxxCompInfo{
        NpcCfgId: npcCfgId,
        // ... 映射字段
    }
}

// LoadFromProto 从数据库数据恢复
func (c *XxxComp) LoadFromProto(data *proto.XxxCompInfo) {
    if data == nil {
        return
    }
    // ... 恢复字段
}
```

### 步骤 3: 状态变更时标记脏标记

```go
func (c *XxxComp) SetSomeField(value int) {
    c.someField = value
    c.SetSync() // 同步到客户端
    c.SetSave() // 标记需要保存到数据库
}
```

### 步骤 4: TownNpcMgr 集成导出/导入

在 `servers/scene_server/internal/ecs/res/town/town_npc.go` 中：

```go
// 添加临时存储字段
type TownNpcMgr struct {
    // ...
    savedXxxData map[int32]*proto.XxxCompInfo // npcCfgId -> 组件数据
}

// LoadXxxData 从DB数据加载（场景初始化时调用，在NPC创建之前）
func (m *TownNpcMgr) LoadXxxData(dataList []*proto.XxxCompInfo) {
    if m.savedXxxData == nil {
        m.savedXxxData = make(map[int32]*proto.XxxCompInfo)
    }
    for _, data := range dataList {
        if data == nil {
            continue
        }
        m.savedXxxData[data.NpcCfgId] = data
    }
}

// GetSavedXxxData 获取NPC保存的组件数据（NPC创建时调用）
func (m *TownNpcMgr) GetSavedXxxData(npcCfgId int32) (*proto.XxxCompInfo, bool) {
    if m.savedXxxData == nil {
        return nil, false
    }
    data, ok := m.savedXxxData[npcCfgId]
    return data, ok
}

// ToSaveXxxList 导出所有需要保存的组件数据（场景保存时调用）
func (m *TownNpcMgr) ToSaveXxxList() []*proto.XxxCompInfo {
    result := make([]*proto.XxxCompInfo, 0)

    for npcCfgId, npcInfo := range m.NpcMap {
        comp, ok := common.GetComponentAs[*cnpc.XxxComp](
            m.GetScene(), npcInfo.Entity.ID(), common.ComponentType_Xxx)
        if !ok || comp == nil {
            continue
        }
        // 只保存有数据的组件
        if !comp.HasData() {
            continue
        }
        result = append(result, comp.ToSaveProto(npcCfgId))
        comp.ClearSave()
    }
    return result
}
```

### 步骤 5: 场景保存流程集成

在 `servers/scene_server/internal/ecs/scene/save.go` 的 `saveTownInfo()` 中：

```go
func (s *scene) saveTownInfo() error {
    townInfo := &proto.DBSaveTownInfo{}

    // ... 现有逻辑 ...

    townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](s, common.ResourceType_TownNpcMgr)
    if ok && townNpcMgr != nil {
        townInfo.NpcPositions = townNpcMgr.ToSavePositions()
        townInfo.XxxCompInfo = townNpcMgr.ToSaveXxxList() // 新增
    }

    // ... 保存到数据库 ...
}
```

### 步骤 6: 场景加载流程集成

在 `scene_impl.go` 的 `townRosurceInit()` 中（NPC创建之前）：

```go
// 加载组件数据（在NPC创建之前加载）
if saveInfo.XxxCompInfo != nil {
    townNpcMgr.LoadXxxData(saveInfo.XxxCompInfo)
}
```

### 步骤 7: NPC 创建时恢复数据

在 `net_func/npc/town_npc.go` 的 `CreateTownNpc()` 中：

```go
// 尝试恢复保存的组件数据
if savedData, found := townNpcMgr.GetSavedXxxData(cfg.GetId()); found {
    comp, ok := common.GetComponentAs[*cnpc.XxxComp](
        s, entity.ID(), common.ComponentType_Xxx)
    if ok && comp != nil {
        comp.LoadFromProto(savedData)
    }
}
```

## 注意事项

1. **Proto 字段编号**: 在 `DBSaveTownInfo` 中添加新字段时，确保使用未被占用的字段编号
2. **增量保存**: 使用 `IsNeedSave()` 检查脏标记，只保存变更的数据
3. **加载顺序**: 确保 NPC 实体和组件已创建后再调用 `LoadXxxList()`
4. **空值处理**: `LoadFromProto()` 方法需要处理 nil 和空切片情况
5. **运行代码生成**: 修改 proto 文件后必须运行 `make orm` 重新生成代码

## 已实现的组件

| 组件 | Proto 消息 | DB字段名 | 状态 |
|-----|-----------|---------|------|
| TradeProxyComp | TradeProxyInfo | TradeProxyInfo | 已实现 |

## 相关文件

- `resources/proto/base/db_server.proto` - Proto 定义
- `servers/scene_server/internal/ecs/com/cnpc/` - NPC 组件
- `servers/scene_server/internal/ecs/res/town/town_npc.go` - NPC 管理器
- `servers/scene_server/internal/ecs/scene/save.go` - 场景保存逻辑
