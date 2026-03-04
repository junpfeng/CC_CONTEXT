# 武器轮盘业务逻辑实现设计

## 1. 需求概述

将 Rust 服务器中武器轮盘 4 个协议的业务逻辑迁移到 Go（P1GoServer）。

| 协议号 | 名称 | 待实现逻辑 |
|--------|------|-----------|
| 2220 | AddItemToCommonWheel | 存数据后**自动选中该槽位** |
| 2221 | AddItemCollectToCommonWheel | 存数据后**自动选中该槽位** |
| 2222 | RemoveItemFromCommonWheel | 移除活跃武器槽位时**卸下武器 + 回收子弹** |
| 2223 | SelectCommonWheelSlot | 实现 EquipItem / UnEquipCurItem / AddonToCurItem |

**不涉及**：协议修改、配置修改、数据库修改。

---

## 2. 涉及文件

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `ecs/com/cbackpack/equip.go` | **修改** | 添加 SetWeapon/RemoveWeapon/GetActiveWeapon 方法 + 背包索引字段 |
| `net_func/ui/common_wheel.go` | **修改** | 实现 onChooseCommonWheelSlot 完整逻辑 + 修改 3 个 handler |

> 路径省略公共前缀 `P1GoServer/servers/scene_server/internal/`

---

## 3. EquipComp 增强设计

### 3.1 新增字段

```go
type EquipComp struct {
    common.ComponentBase
    ThrowItemList            []*proto.ThrowItemCellInfo
    ActiveThrowItemCellIndex int32
    WeaponList               []*proto.WeaponCellInfo
    ActiveWeaponCellIndex    int32
    NowWeaponBackpackIndex   int32  // ← 新增：当前武器在背包中的 cell index（-1=无）
}
```

`NowWeaponBackpackIndex` 对应 Rust 的 `now_weapon_index`，用于：
- 卸下武器时回写属性到背包副本
- 回收子弹时定位背包中的武器

### 3.2 新增方法

#### SetWeapon

```go
// SetWeapon 装备武器，返回被替换的旧武器及其背包索引
// 对标 Rust: equip_comp.set_weapon(weapon.clone(), Some(cell_index))
func (e *EquipComp) SetWeapon(weapon *proto.WeaponProto, backpackCellIndex int32) (
    oldWeapon *proto.WeaponProto, oldBackpackIndex int32,
)
```

逻辑：
1. 先调用 RemoveWeapon() 取出旧武器
2. 将新武器存入 WeaponList[0]
3. 设置 ActiveWeaponCellIndex = 0, NowWeaponBackpackIndex = backpackCellIndex
4. SetSync() + SetSave()

#### RemoveWeapon

```go
// RemoveWeapon 卸下当前武器，返回被卸下的武器及其背包索引
// 对标 Rust: equip_comp.remove_weapon()
func (e *EquipComp) RemoveWeapon() (weapon *proto.WeaponProto, backpackIndex int32)
```

逻辑：
1. 检查 ActiveWeaponCellIndex 有效性
2. 取出 WeaponList[ActiveWeaponCellIndex]
3. 清空槽位，ActiveWeaponCellIndex = -1, NowWeaponBackpackIndex = -1
4. SetSync() + SetSave()

#### GetActiveWeapon

```go
// GetActiveWeapon 获取当前装备的武器（只读）
func (e *EquipComp) GetActiveWeapon() *proto.WeaponProto
```

### 3.3 构造函数更新

```go
func NewEquipComp() *EquipComp {
    return &EquipComp{
        ...
        NowWeaponBackpackIndex: -1,  // ← 新增
    }
}
```

---

## 4. onChooseCommonWheelSlot 实现设计

### 4.1 EquipItem（装备武器）

对标 Rust `on_choose_common_wheel_slot` 的 EquipItem 分支。

```
slot.BackpackCellIndex → cellIndex
  ├─ cellIndex >= 0（槽位有物品）
  │   ├─ backpack.ItemMap[cellIndex] → cell
  │   ├─ weapon, ok := cell.Item.(*citem.Weapon)  // 类型断言
  │   ├─ weaponProto := weapon.ToProtoWeapon()     // 转 proto
  │   ├─ oldWeapon, oldIdx := equip.SetWeapon(weaponProto, cellIndex)
  │   ├─ if oldWeapon != nil:
  │   │   └─ onTriggerUnloadWeapon(oldWeapon, oldIdx, isChangeItem)
  │   └─ equip.SetSync()  // 通知客户端（替代 bp_equip_weapon）
  │
  └─ cellIndex < 0（槽位无物品）
      ├─ weapon, idx := equip.RemoveWeapon()
      └─ if weapon != nil:
          └─ onTriggerUnloadWeapon(weapon, idx, isChangeItem)
```

### 4.2 UnEquipCurItem（卸下当前武器）

```
weapon, idx := equip.RemoveWeapon()
if weapon != nil:
    onTriggerUnloadWeapon(weapon, idx, isChangeItem)
```

### 4.3 AddonToCurItem（装弹/换弹）

```
slot.ItemCollectionId → ammoItemId
  ├─ ammoItemId <= 0 → return
  ├─ equip.GetActiveWeapon() → weapon
  ├─ weapon == nil → return
  ├─ weapon.WeaponGunData == nil → return（非枪械）
  ├─ gunCfg := config.GetCfgGunById(weapon.WeaponGunData.GunId)
  ├─ gunCfg == nil → return
  ├─ !contains(gunCfg.GetBulletId(), ammoItemId) → return（弹药不兼容）
  └─ 设置武器的 BULLETID 属性为 ammoItemId
     + SetSync()（通知客户端触发换弹）
```

> Rust 在此调用 `bp_weapon_reload()` 触发 GAS 蓝图。Go 暂无等价机制，
> 改为直接设置 BULLETID 属性并通过 SetSync() 通知客户端。

---

## 5. 武器卸下与子弹回收设计

### 5.1 onTriggerUnloadWeapon

对标 Rust `on_trigger_unload_weapon`。

```go
func onTriggerUnloadWeapon(
    scene common.Scene,
    playerEntity common.Entity,
    weapon *proto.WeaponProto,     // 被卸下的武器
    backpackIndex int32,           // 武器在背包中的 cell index
    needRecycleBullet bool,        // 是否回收子弹
)
```

逻辑：
```
if needRecycleBullet:
    onWeaponUnloadRecycleBullet(scene, playerEntity, weapon, backpackIndex)
else if backpackIndex >= 0:
    syncWeaponAttributesToBackpack(playerEntity, weapon, backpackIndex)
```

### 5.2 onWeaponUnloadRecycleBullet

对标 Rust `on_weapon_unload_recycle_bullet`。

```
1. 获取 BackpackComp
2. 从 weapon.Attributes 读取 BULLETID → bulletId
3. bulletId <= 0 → return（无弹药）
4. 检查 PISTOLFREE 标记 → 如果是免费弹药，跳过回收
5. 从 weapon.Attributes 读取 BULLETCURRENT → bulletCount
6. bulletCount <= 0 → return（无剩余弹药）
7. 将 weapon 上的 BULLETCURRENT 设为 0（防止重复回收）
8. backpack.AddItem(bulletId, bulletCount)（弹药放回背包）
9. if backpackIndex >= 0:
    syncWeaponAttributesToBackpack(playerEntity, weapon, backpackIndex)
```

### 5.3 syncWeaponAttributesToBackpack

将装备武器的属性同步回背包中的副本。

```
backpack.ItemMap[backpackIndex] → cell
weapon, ok := cell.Item.(*citem.Weapon)
if ok && weapon.AttributeSet != nil:
    更新 AttributeSet 中的弹药相关属性
backpack.SetSync() + backpack.SetSave()
```

### 5.4 PISTOLFREE 检查

Rust 通过 `GAMEPLAYFLAG_ENTITY_FEATURE_EQUIP_AMMO_PISTOLFREE` 检查实体是否拥有免费弹药标记。

Go 中此标记值为 `config.ENTITY_FEATURE_EQUIP_AMMO_PISTOLFREEGAMEPLAYFLAG = 281`。
具体检查机制依赖 GAS 系统的 GameplayFlag 查询，先实现为 helper 函数预留扩展点。

---

## 6. Handler 改动设计

### 6.1 AddItemToCommonWheel（2220）

**现状**：仅调用 `wheelComp.AddItemToWheel()`

**改动**：添加成功后自动选中槽位并触发装备

```go
if wheelComp.AddItemToWheel(wheelCfgId, slotCfgId, cellIndex) {
    // ← 新增：自动选中该槽位（对标 Rust 的 select_common_wheel_slot）
    if wheelComp.SelectWheelSlot(wheelCfgId, slotCfgId) {
        slotInfo := wheelComp.GetSlotInfo(wheelCfgId, slotCfgId)
        if slotInfo != nil {
            onChooseCommonWheelSlot(scene, playerEntity, slotInfo, true)
        }
    }
}
```

### 6.2 AddItemCollectToCommonWheel（2221）

同上模式：添加成功后自动选中。

### 6.3 RemoveItemFromCommonWheel（2222）

**现状**：移除后重置到默认槽位

**改动**：移除前检查是否为活跃武器槽位，如果是则卸下武器 + 回收子弹

```go
// 记录移除前的活跃状态
wheel := wheelComp.GetWheel(wheelCfgId)
wasActive := wheel != nil && wheel.NowActiveSlotIndex == slotCfgId

oldCellIndex, removed := wheelComp.RemoveItemFromWheel(wheelCfgId, slotCfgId)

if removed && wasActive && oldCellIndex >= 0 {
    // ← 新增：卸下武器逻辑
    检查背包中 oldCellIndex 的物品是否为武器
    如果是 → equip.RemoveWeapon() → onTriggerUnloadWeapon(needRecycle=true)
}

// 重置到默认槽位（已有逻辑保留）
```

---

## 7. 属性操作辅助函数

```go
// getWeaponAttribute 从 WeaponProto.Attributes 中读取指定 key 的值
func getWeaponAttribute(weapon *proto.WeaponProto, key int32) (float64, bool)

// setWeaponAttribute 设置 WeaponProto.Attributes 中指定 key 的值
func setWeaponAttribute(weapon *proto.WeaponProto, key int32, value float64)
```

常量引用：
```go
bulletIdKey      = int32(config.GAS_ATTRIBUTE_ITEM_PROPERTY_BULLETIDGAMEPLAYFLAG)      // 192
bulletCurrentKey = int32(config.GAS_ATTRIBUTE_ITEM_PROPERTY_BULLETCURRENTGAMEPLAYFLAG)  // 191
```

---

## 8. 数据流图

### 装备武器（EquipItem from wheel）

```
Client → SelectCommonWheelSlotReq(wheelId, slotId)
            │
            ▼
    wheelComp.SelectWheelSlot()  → 更新活跃槽位
            │
            ▼
    onChooseCommonWheelSlot(EquipItem)
            │
            ├─ backpack.ItemMap[cellIndex] → citem.Weapon
            ├─ weapon.ToProtoWeapon() → WeaponProto
            ├─ equip.SetWeapon(weaponProto, cellIndex)
            │   └─ 返回旧武器 → onTriggerUnloadWeapon(回收子弹)
            └─ equip.SetSync() → 客户端收到 EquipmentCompProto 更新
```

### 卸下武器（UnEquipCurItem from wheel）

```
Client → SelectCommonWheelSlotReq
            │
            ▼
    onChooseCommonWheelSlot(UnEquipCurItem)
            │
            ├─ equip.RemoveWeapon() → 返回武器 + backpackIndex
            ├─ onTriggerUnloadWeapon()
            │   ├─ 读取 BULLETID + BULLETCURRENT
            │   ├─ 检查 PISTOLFREE → 跳过/回收
            │   ├─ backpack.AddItem(bulletId, count) → 弹药回背包
            │   └─ syncWeaponAttributes → 更新背包副本
            └─ equip.SetSync()
```

---

## 9. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| GAS 蓝图效果缺失 | 客户端可能缺少装备/卸下动画 | 通过 SetSync() 同步状态，客户端自行处理动画 |
| PISTOLFREE 检查机制不确定 | 可能错误回收免费弹药 | 实现为独立 helper 函数，预留 GAS 集成点 |
| 背包副本属性同步 | 不同步会导致再次装备时弹药数据错误 | syncWeaponAttributesToBackpack 确保一致性 |
