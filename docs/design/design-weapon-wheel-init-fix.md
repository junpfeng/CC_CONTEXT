# 武器轮盘初始化修复设计文档

## 1. 需求回顾

### Bug 描述

玩家在樱花校园场景中：
1. 打开武器轮盘，选择手枪后出现**连续不断的换弹动作**
2. 再次打开武器轮盘，除了近战和手枪槽位是空的之外，其他槽位出现**狙击步枪但无法选择**

### 根因分析

Go 版 `CreatePlayerEntity`（`enter.go:414-426`）中，`CommonWheelComp` 只做了 `InitFromConfig` + `LoadFromData`，**缺少 3 个 Rust 版的关键初始化函数**：

| Rust 函数 | 作用 | Go 现状 |
|-----------|------|---------|
| `on_backpack_update_to_common_wheel` | 清理背包中已不存在的 cellIndex 引用 | **未实现调用** — 组件方法 `OnBackpackUpdate` 已存在但未在入场流程中调用 |
| `on_enter_player_init_common_wheel` | 自动匹配空槽位 + 设置 bulletId + 自动装备 | **完全缺失** |
| `on_player_enter_init_backpack` | 按场景初始化背包（仅 Main 场景） | 非本 bug 直接原因，优先级 P3 |

#### 连续换弹的因果链

```
缺失 on_enter_player_init_common_wheel
→ 武器未设置 bulletId 属性
→ 玩家选择手枪 → onEquipItem 装备武器
→ 客户端请求换弹 → ChangeBulletClip
→ getWeaponAttribute(bulletIdKey) 返回 0
→ 返回错误 "weapon has no bullet_id"（enter.go:412-413）
→ 客户端收到错误后重试 → 无限循环
```

#### 狙击步枪出现在错误槽位的因果链

```
缺失 on_backpack_update_to_common_wheel
→ DB 保存的 BackpackCellIndex 指向旧的背包格子
→ 玩家背包物品发生变动（增/删/整理），cellIndex 已指向不同物品
→ 轮盘槽位仍引用旧 cellIndex → 显示为狙击步枪
→ 但实际物品与槽位配置不匹配 → 无法选择
```

#### LoadFromData 的 Cell Index 0 Bug

`CommonWheelComp.LoadFromData`（`cui/common_wheel.go:149`）使用 `slotProto.BackpackCellIndex != 0` 判断是否加载：

```go
case SlotDataBackpackItem:
    if slotProto.BackpackCellIndex != 0 {  // BUG: cell index 0 是有效值
        slot.BackpackCellIndex = slotProto.BackpackCellIndex
    }
```

Protobuf3 的 `int32` 默认值为 0，无法区分"未设置"和"index=0"。Cell index 0 是背包第一格，完全合法，但永远不会被加载。

---

## 2. 修复方案

### 2.1 修复清单

| 优先级 | 修复项 | 文件 | 说明 |
|--------|--------|------|------|
| P0 | 新增 `OnEnterPlayerInitCommonWheel` | `net_func/ui/common_wheel.go` | 自动匹配 + bulletId + 自动装备 |
| P0 | 在 `CreatePlayerEntity` 中调用初始化链 | `net_func/player/enter.go` | 调用清理 + 初始化函数 |
| P1 | 修复 `LoadFromData` cell index 0 bug | `ecs/com/cui/common_wheel.go` | 改用 proto 标记字段或 >= 0 判断 |
| P2 | 实现 `EquipComp.LoadFromData` | `ecs/com/cbackpack/equip.go` | 从 DB 恢复装备状态 |

### 2.2 详细设计

#### P0-1: `OnEnterPlayerInitCommonWheel`

在 `net_func/ui/common_wheel.go` 中新增导出函数，对标 Rust `on_enter_player_init_common_wheel`。

**函数签名：**

```go
func OnEnterPlayerInitCommonWheel(scene common.Scene, playerEntity common.Entity)
```

**逻辑分三阶段：**

**阶段 1：自动匹配空槽位**

遍历所有轮盘的所有槽位，对于 `DataType == SlotDataBackpackItem && BackpackCellIndex == -1` 的空槽位：
1. 读取槽位配置的 `requiredFlags`：`config.GetCfgQuickActionSlotById(slot.CfgId).GetRequiredFlags()`
2. 遍历背包 `backpackComp.ItemMap`，找到物品的 flags 包含 `requiredFlags` 中任一 flag 的物品
3. 用 `usedIndex map[int32]bool` 避免同一背包格子被多个槽位使用
4. 匹配成功则设置 `slot.BackpackCellIndex = cellIndex`

```go
// 伪代码
usedIndex := make(map[int32]bool)
// 先收集已占用的 cellIndex
for _, wheel := range wheelComp.WheelMap {
    for _, slot := range wheel.SlotMap {
        if slot.DataType == cui.SlotDataBackpackItem && slot.BackpackCellIndex >= 0 {
            usedIndex[slot.BackpackCellIndex] = true
        }
    }
}
// 自动匹配空槽位
for _, wheel := range wheelComp.WheelMap {
    for _, slot := range wheel.SlotMap {
        if slot.DataType != cui.SlotDataBackpackItem || slot.BackpackCellIndex >= 0 {
            continue
        }
        slotCfg := config.GetCfgQuickActionSlotById(slot.CfgId)
        if slotCfg == nil {
            continue
        }
        requiredFlags := slotCfg.GetRequiredFlags()
        if len(requiredFlags) == 0 {
            continue
        }
        // 在背包中找匹配物品
        for cellIdx, cell := range backpackComp.ItemMap {
            if usedIndex[cellIdx] || cell.Item == nil {
                continue
            }
            itemCfg := config.GetCfgItemBaseById(cell.Item.GetItemID())
            if itemCfg == nil {
                continue
            }
            itemFlags := itemCfg.GetItemFlags()
            if matchFlags(requiredFlags, itemFlags) {
                slot.BackpackCellIndex = cellIdx
                usedIndex[cellIdx] = true
                break
            }
        }
    }
}
```

**阶段 2：自动设置 bulletId**

对于每个已分配了 `BackpackCellIndex` 的武器槽位：
1. 从背包获取武器
2. 检查武器的 `bulletCurrent == 0` 且 `bulletId` 与可用弹药不匹配
3. 在背包中查找可用弹药（数量 > 0），设置为武器的 `bulletId`

```go
// 对标 Rust: 读取 gun_cfg.bullet_id 列表，查找背包有库存的弹药
// Go 中对应：读取武器属性 bulletIdKey，检查背包弹药库存
for cellIdx, cell := range backpackComp.ItemMap {
    weapon, isWeapon := cell.Item.(*citem.Weapon)
    if !isWeapon {
        continue
    }
    weaponProto := weapon.ToProtoWeapon()
    bulletCurrent, _ := getWeaponAttribute(weaponProto, bulletCurrentKey)
    if int32(bulletCurrent) != 0 {
        continue  // 已有弹药，跳过
    }
    bulletId, _ := getWeaponAttribute(weaponProto, bulletIdKey)
    // 检查 bulletId 对应的弹药是否在背包中有库存
    if int32(bulletId) > 0 && backpackComp.GetItemQuantity(int32(bulletId)) > 0 {
        continue  // bulletId 正确且有库存，跳过
    }
    // 需要修正 bulletId：从武器配置获取可用弹药列表
    // 注意：如果 Go 侧没有 gun_cfg.bullet_id 列表，
    // 则通过 free ammo flag 检查，将 bulletId 设为配置值
    newBulletId := findAvailableBulletId(backpackComp, weapon)
    if newBulletId > 0 {
        setWeaponAttribute(weaponProto, bulletIdKey, float64(newBulletId))
        syncWeaponAttributesToBackpack(playerEntity, weaponProto, cellIdx)
    }
}
```

> **注意**：Rust 中通过 `gun_data.gun_cfg.bullet_id` 获取弹药 ID 列表。需要确认 Go 侧是否有等价的配置接口。如果没有，可以从武器属性中读取已有的 bulletId 作为参考。

**阶段 3：自动装备当前活跃槽位**

对每个轮盘，如果有活跃槽位，调用 `onChooseCommonWheelSlot` 装备：

```go
for _, wheel := range wheelComp.WheelMap {
    slot, ok := wheel.SlotMap[wheel.NowActiveSlotIndex]
    if !ok {
        continue
    }
    onChooseCommonWheelSlot(scene, playerEntity, slot, true)
}
```

这一步确保玩家进入场景时，活跃槽位的武器被正确装备到 `EquipComp`。

#### P0-2: 在 `CreatePlayerEntity` 中调用初始化链

修改 `enter.go`，在所有 `AddComponent` 调用**之后**添加初始化调用：

```go
// 添加所有组件到实体（现有代码）
playerEntity.AddComponent(playerComp)
// ... 其他组件 ...
playerEntity.AddComponent(commonWheelComp)
// ... 其他组件 ...

// === 新增：轮盘初始化链（对标 Rust player.rs:628-629） ===

// Step 1: 清理背包中已不存在的引用
existingCells := make(map[int32]bool, len(backpackComp.ItemMap))
for cellIdx := range backpackComp.ItemMap {
    existingCells[cellIdx] = true
}
needReselect := commonWheelComp.OnBackpackUpdate(existingCells)
if len(needReselect) > 0 {
    for _, wheelCfgId := range needReselect {
        wheel := commonWheelComp.GetWheel(wheelCfgId)
        if wheel != nil {
            wheel.NowActiveSlotIndex = wheel.DefaultSlotCfgId
        }
    }
}

// Step 2: 自动匹配 + bulletId + 自动装备
ui.OnEnterPlayerInitCommonWheel(scene, playerEntity)

return playerEntity
```

**import 变更**：`enter.go` 需新增 `import "mp/servers/scene_server/internal/net_func/ui"`。

**循环依赖分析**：`net_func/player` 导入 `net_func/ui` — 二者平级，不存在反向依赖。已确认 `net_func/ui` 不导入 `net_func/player`。

#### P1: 修复 `LoadFromData` Cell Index 0 Bug

**方案**：在 proto 中添加 `has_backpack_cell_index` bool 标记字段。

但修改 proto 影响范围大。更简单的方案：**使用 -1 作为"未设置"标记值**，在 proto 序列化/反序列化时偏移：

**实际采用方案**：修改 `LoadFromData` 和 `ToProto`，使用 `+1/-1` 偏移：
- 存储时：`slotProto.BackpackCellIndex = slot.BackpackCellIndex + 1`（0 变 1，-1 变 0）
- 加载时：`slot.BackpackCellIndex = slotProto.BackpackCellIndex - 1`（1 变 0，0 变 -1）
- 判断是否有数据：`slotProto.BackpackCellIndex != 0`（proto 默认值 0 = 运行时 -1 = 未设置）

```go
// LoadFromData 修复
case SlotDataBackpackItem:
    // 存储格式: cellIndex + 1（0=未设置，1=index 0, 2=index 1, ...）
    if slotProto.BackpackCellIndex != 0 {
        slot.BackpackCellIndex = slotProto.BackpackCellIndex - 1
    }

// ToProto 修复
case SlotDataBackpackItem:
    if slot.BackpackCellIndex >= 0 {
        slotProto.BackpackCellIndex = slot.BackpackCellIndex + 1
    }
```

同理修复 `ItemCollectionId` 和 `NowActiveSlotIndex`。

**兼容性**：旧数据中 `BackpackCellIndex` 已经是 raw cellIndex（不含偏移），初次加载后 P0 的自动匹配会重新填充正确值。下次保存时使用新格式。

#### P2: 实现 `EquipComp.LoadFromData`

当前 `EquipComp.LoadFromData` 是空实现（TODO）。参考 proto 定义实现：

```go
func (e *EquipComp) LoadFromData(saveData *proto.DBSaveEquipMentComponent) {
    if saveData == nil {
        return
    }
    if len(saveData.WeaponList) > 0 {
        e.WeaponList = saveData.WeaponList
    }
    e.ActiveWeaponCellIndex = saveData.ActiveWeaponCellIndex
    e.NowWeaponBackpackIndex = saveData.NowWeaponBackpackIndex
    if len(saveData.ThrowItemList) > 0 {
        e.ThrowItemList = saveData.ThrowItemList
    }
    e.ActiveThrowItemCellIndex = saveData.ActiveThrowItemCellIndex
}
```

> **注意**：实现后，P0 阶段 3 的自动装备可能与 LoadFromData 恢复的装备状态冲突。需要在 `OnEnterPlayerInitCommonWheel` 中检查 `EquipComp` 是否已有武器，避免重复装备。

---

## 3. 涉及文件列表

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `servers/scene_server/internal/net_func/ui/common_wheel.go` | 新增函数 | `OnEnterPlayerInitCommonWheel` + `matchFlags` 辅助函数 |
| `servers/scene_server/internal/net_func/player/enter.go` | 修改 | 添加初始化链调用 + import ui 包 |
| `servers/scene_server/internal/ecs/com/cui/common_wheel.go` | 修改 | 修复 `LoadFromData` 和 `ToProto` 的 index 偏移 |
| `servers/scene_server/internal/ecs/com/cbackpack/equip.go` | 修改 | 实现 `LoadFromData` |

---

## 4. 辅助函数

需要新增以下辅助函数（在 `net_func/ui/common_wheel.go` 中）：

```go
// matchFlags 检查物品 flags 是否包含 requiredFlags 中的任一 flag
func matchFlags(requiredFlags []int32, itemFlags []config.CfgConstGameplayFlag) bool {
    for _, reqFlag := range requiredFlags {
        for _, itemFlag := range itemFlags {
            if int32(itemFlag) == reqFlag {
                return true
            }
        }
    }
    return false
}
```

需要导出 `getWeaponAttribute` 和 `setWeaponAttribute`（当前是小写未导出），或在 `OnEnterPlayerInitCommonWheel` 中内联使用。

---

## 5. 执行顺序

```
1. P1: 修复 LoadFromData cell index 0 bug（基础修复，后续依赖正确的数据加载）
2. P0-1: 实现 OnEnterPlayerInitCommonWheel（核心修复）
3. P0-2: 修改 enter.go 调用初始化链（接入点）
4. P2: 实现 EquipComp.LoadFromData（增强修复）
5. 构建验证 + 测试
```

---

## 6. 风险与注意事项

### 6.1 数据兼容性

- **LoadFromData 偏移变更**：旧数据不含 +1 偏移，首次加载后旧 cellIndex 可能错误偏移。
  - 缓解：P0 的自动匹配会在初始化时重新扫描并修正所有空槽位。即使旧数据加载错误，OnBackpackUpdate 会清理无效引用，自动匹配会重新填充。
  - 建议：在 `LoadFromData` 中添加版本检测逻辑，或直接跳过偏移（让自动匹配兜底）。

### 6.2 性能影响

- `OnEnterPlayerInitCommonWheel` 在玩家入场时执行一次，遍历轮盘槽位 × 背包物品。
- 典型规模：轮盘 ~3 个 × 槽位 ~8 个 × 背包 ~100 物品 = ~2400 次比较，可忽略。

### 6.3 自动装备与 EquipComp.LoadFromData 冲突

- 如果 P2 实现了 `EquipComp.LoadFromData`，玩家入场时装备状态已从 DB 恢复。
- P0 阶段 3 的自动装备会再次调用 `onChooseCommonWheelSlot`，可能产生"先卸载 DB 恢复的武器，再装备轮盘活跃槽位的武器"。
- Rust 版同样有这个行为（先 LoadFromData 恢复，再 `on_choose_common_wheel_slot` 重新装备），属于预期行为。

### 6.4 `onChooseCommonWheelSlot` 未导出

当前 `onChooseCommonWheelSlot` 是小写未导出函数。`OnEnterPlayerInitCommonWheel` 在同一个 `ui` 包内，可以直接调用，无需导出。

### 6.5 Sakura 场景特殊性

- 樱花校园和小镇使用不同的 `CfgInitPerson` 配置（通过 `sceneCfg.GetPlayerInit()`）。
- 轮盘初始化由场景配置驱动（`initPersonCfg.GetInitCommonWheel()`），不同场景的轮盘结构可能不同。
- 修复逻辑是通用的，不区分场景类型。
