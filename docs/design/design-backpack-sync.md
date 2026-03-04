# 设计文档：跨服务器背包数据同步（Rust → Go）

## 1. 需求回顾

玩家从大世界（Rust Scene Server）切换到樱花校园（Go Scene Server）时，背包数据需要完整同步。

**核心问题**：
- Rust 服务器有完整的背包加载/保存功能
- Go 服务器的 `LoadFromData` 方法是空的（TODO）
- Go 服务器缺少 `ToSaveProto` 方法
- Go 服务器缺少物品反序列化方法

**验收标准**：
- 场景切换背包保留
- 断线重连数据恢复
- 物品属性完整同步
- 副本场景正确隔离

---

## 2. 架构设计

### 2.1 系统边界

```
┌──────────────────────────────────────────────────────────────┐
│                      数据持久化层                              │
│                    MongoDB + Redis                           │
│              DBSaveRoleInfo.role_backpack                    │
└────────────┬──────────────────────────────┬──────────────────┘
             │                              │
   ┌─────────▼──────────┐        ┌─────────▼─────────┐
   │  Rust Scene Server │        │  Go Scene Server  │
   │    (已有实现)       │        │   (本次实现)       │
   │                    │        │                   │
   │  ✅ 加载：         │        │  ➕ 加载：         │
   │  load_from_data   │        │  LoadFromData     │
   │                    │        │                   │
   │  ✅ 保存：         │        │  ➕ 保存：         │
   │  to_save_data     │        │  ToSaveProto      │
   │                    │        │                   │
   │  ✅ 序列化：       │        │  ➕ 序列化：       │
   │  ItemInBag        │        │  NewItemFromProto │
   └────────────────────┘        └───────────────────┘
```

### 2.2 核心流程

#### 场景进入流程（含背包加载）

1. LogicServer 从 MongoDB 加载玩家数据（含 `role_backpack`）
2. GoSceneServer 接收 `EnterSceneReq(roleInfo)`
3. 调用 `addPlayerEntity()` 创建玩家实体
4. 创建背包组件：`backpackComp = NewBackpackComp(cfg)`
5. 加载背包数据：`LoadFromData(roleInfo.RoleBackpack)`
   - 遍历 `ItemList`
   - 调用 `NewItemFromProto()` 加载物品
   - 添加到 `ItemMap`
   - 更新索引和大小
6. 标记同步：`SetSync()`
7. 返回进场响应（含背包数据）

#### 场景离开流程（含背包保存）

1. GoSceneServer 接收离开请求
2. 调用 `getPlayerSaveInfo(entity, sceneType, true)`
3. 收集所有组件数据（包括 Backpack）
4. 调用 `backpackComp.ToSaveProto()`
   - 遍历 `ItemMap`
   - 调用 `cell.Item.ToProto()` 序列化
5. 构建 `DBSaveRoleInfo`
6. 返回给 LogicServer 保存到 MongoDB

---

## 3. 详细设计

### 3.1 模块划分

```
P1GoServer/
├── common/citem/                    # 物品模块
│   ├── item.go                      # NewItemFromProto (新增)
│   ├── normal_item.go               # NewNormalItemFromProto (新增)
│   └── weapon.go                    # NewWeaponFromProto (新增)
│
└── servers/scene_server/internal/
    ├── ecs/com/cbackpack/
    │   └── backpack.go              # LoadFromData + ToSaveProto
    │
    └── net_func/player/
        └── enter.go                 # getPlayerSaveInfo (修改)
```

### 3.2 数据结构

#### BackpackComp（已有，需完善）

```go
type BackpackComp struct {
    common.ComponentBase
    Cfg             *config.CfgBackpackInit
    ItemMap         map[int32]*BackpackCell      // 格子索引 → 格子
    IteamListbyKey  map[int32][]*BackpackCell    // 物品ID → 格子列表
    CurrentSize     float64
    ShowCurrentSize float64
    IsWasmNtf       bool
    StaticChange    []ItemChangeEvent
}

// 新增方法
func (b *BackpackComp) LoadFromData(saveData *proto.DBSaveBackPackComponent)
func (b *BackpackComp) ToSaveProto() *proto.DBSaveBackPackComponent
```

#### IItem 接口

```go
type IItem interface {
    ToProto() *proto.ItemProto      // 已有
    GetItemID() int32               // 已有
    GetQuantity() int32             // 已有
}

// 新增工厂方法
func NewItemFromProto(itemProto *proto.ItemProto) IItem
```

### 3.3 接口定义

#### 1. BackpackComp.LoadFromData

```go
// LoadFromData 从数据库数据加载背包
// 参数: saveData - 数据库保存的背包数据
// 异常: 物品加载失败时记录日志并跳过
func (b *BackpackComp) LoadFromData(saveData *proto.DBSaveBackPackComponent) {
    if saveData == nil || saveData.BackpackInfo == nil {
        return
    }

    // 遍历保存的背包格子
    for _, cellData := range saveData.BackpackInfo.ItemList {
        if cellData.ItemInfo == nil {
            continue
        }

        // 从 proto 加载物品实例
        item := citem.NewItemFromProto(cellData.ItemInfo)
        if item == nil {
            log.Errorf("LoadFromData: failed to load item, cell=%d", cellData.CellIndex)
            continue
        }

        // 创建背包格子
        cell := &BackpackCell{
            CellIndex: cellData.CellIndex,
            Item:      item,
            IsLocked:  cellData.IsLock,
        }

        // 添加到背包
        b.ItemMap[cellData.CellIndex] = cell

        // 更新物品索引
        itemID := item.GetItemID()
        if b.IteamListbyKey[itemID] == nil {
            b.IteamListbyKey[itemID] = make([]*BackpackCell, 0)
        }
        b.IteamListbyKey[itemID] = append(b.IteamListbyKey[itemID], cell)
    }

    // 更新背包大小
    b.updateSize()

    // 标记需要同步给客户端
    b.SetSync()
}
```

#### 2. BackpackComp.ToSaveProto

```go
// ToSaveProto 转换为数据库保存格式
func (b *BackpackComp) ToSaveProto() *proto.DBSaveBackPackComponent {
    cellList := make([]*proto.DBSaveBackpackCell, 0, len(b.ItemMap))

    for cellIndex, cell := range b.ItemMap {
        cellList = append(cellList, &proto.DBSaveBackpackCell{
            CellIndex: cellIndex,
            ItemInfo:  cell.Item.ToProto(),
            IsLock:    cell.IsLocked,
        })
    }

    return &proto.DBSaveBackPackComponent{
        BackpackInfo: &proto.DBSaveBackpack{
            ItemList: cellList,
        },
    }
}
```

#### 3. citem.NewItemFromProto

```go
// NewItemFromProto 从 proto 创建物品实例
func NewItemFromProto(itemProto *proto.ItemProto) IItem {
    if itemProto == nil {
        return nil
    }

    // 根据 ItemProto 的 oneof 类型创建对应的物品实例
    switch data := itemProto.Data.(type) {
    case *proto.ItemProtoNormal:
        return NewNormalItemFromProto(data)
    case *proto.ItemProtoWeapon:
        return NewWeaponFromProto(data)
    // 其他物品类型...
    default:
        log.Errorf("NewItemFromProto: unknown item type")
        return nil
    }
}
```

#### 4. 在 getPlayerSaveInfo 中添加背包保存

```go
// enter.go:760+ (在 Statistics 保存之后)

common.SetSaveComponentProto(entity, common.ComponentType_Statistics,
    func(proto *proto.DBSaveRoleGrowthData) { res.RoleGrowthData = proto },
    func(comp *com.StatisticsComp) *proto.DBSaveRoleGrowthData { return comp.ToSaveProto() },
    isAll,
)

// 新增：保存背包数据
common.SetSaveComponentProto(entity, common.ComponentType_Backpack,
    func(proto *proto.DBSaveBackPackComponent) { res.RoleBackpack = proto },
    func(comp *cbackpack.BackpackComp) *proto.DBSaveBackPackComponent { return comp.ToSaveProto() },
    isAll,
)
```

---

## 4. Rust 参考实现

### 4.1 功能对标

| 功能点 | Rust 实现 | Go 实现计划 |
|--------|----------|------------|
| 加载背包 | `load_from_data` | `LoadFromData` |
| 保存背包 | `to_save_data` | `ToSaveProto` |
| 加载物品 | `ItemInBag::load_from_proto` | `NewItemFromProto` |
| 副本隔离 | `if is_dungeon { skip }` | 场景类型判断 |

### 4.2 副本场景隔离（参考）

**Rust 实现**（user_data_sync.rs:118-122）：
```rust
let role_backpack = if is_dungeon {
    player.info.role_backpack.clone()  // 副本不保存变化
} else {
    Some(backpack_comp.to_save_data())  // 正常场景保存
};
```

**Go 对标**（如需实现副本隔离）：
```go
switch sceneType.(type) {
case *common.DungeonSceneInfo:
    // 副本场景：不保存背包变化
    // res.RoleBackpack 保持原值
case *common.CitySceneInfo, *common.SakuraSceneInfo:
    // 正常场景：保存背包变化
    common.SetSaveComponentProto(entity, common.ComponentType_Backpack, ...)
}
```

---

## 5. 事务性设计

### 5.1 数据一致性

**加载时**：
- 加载前背包为空（新建组件）
- 加载过程中不响应客户端请求
- 加载完成后统一同步给客户端

**保存时**：
- 保存时玩家已从场景移除（无并发修改）
- 所有组件数据同时收集（快照一致性）
- 数据库原子性写入

### 5.2 错误容错

- 物品加载失败：跳过该物品，继续加载其他物品
- 背包数据为 nil：使用初始空背包
- 格子索引冲突：覆盖旧数据，记录警告
- 序列化失败：该物品不保存，记录错误

### 5.3 幂等性

- `LoadFromData`：多次调用结果相同（清空后重新加载）
- `ToSaveProto`：纯函数，无状态修改，多次调用返回相同结果

---

## 6. 风险与缓解

| 风险 | 严重性 | 缓解措施 |
|------|--------|----------|
| 物品类型识别错误 | 高 | 单元测试覆盖所有物品类型，参考 Rust 实现 |
| Rust/Go 序列化差异 | 高 | 集成测试验证跨服务器同步 |
| 数据版本兼容 | 中 | 容错处理：未知类型跳过 + 日志记录 |
| 副本场景误保存 | 中 | 场景类型判断 + 单元测试 |

---

## 7. 文件修改清单

| 文件路径 | 修改类型 | 内容 |
|---------|---------|------|
| `cbackpack/backpack.go` | 实现 + 新增 | 实现 `LoadFromData`，新增 `ToSaveProto` |
| `citem/item.go` | 新增 | 新增 `NewItemFromProto` 工厂方法 |
| `citem/normal_item.go` | 新增 | 新增 `NewNormalItemFromProto` |
| `citem/weapon.go` | 新增 | 新增 `NewWeaponFromProto` |
| `net_func/player/enter.go` | 修改 | 在 `getPlayerSaveInfo` 中添加背包保存 |
