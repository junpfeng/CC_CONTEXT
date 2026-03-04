# 战斗系统指南：装备选择、射击、换弹

本文档描述玩家武器相关的核心战斗流程：装备选择、开枪射击、弹药管理。

> **数据流核心**：BackpackComp（存储真相）↔ EquipComp（运行时状态）↔ 客户端（显示），CommonWheelComp 是 UI 层引用索引。
> **同步原则**：EquipComp 是运行时活跃副本（可原地修改），每次修改后必须同步回 BackpackComp 保证一致性。

---

## 文档概述

| 内容 | 使用时机 |
|------|----------|
| 组件结构（Section 1） | 理解数据模型、字段含义 |
| 装备选择（Section 2） | 轮盘选择武器、装备/卸载流程 |
| 射击流程（Section 3） | 开枪扣弹、属性同步 |
| 换弹流程（Section 4） | 弹药回收与装填 |
| 进入场景初始化（Section 5） | 玩家登录时轮盘/装备初始化链 |
| 数据同步模型（Section 6） | 组件间数据流、增量同步机制 |
| 经验教训（Section 7） | 已踩的坑和修复方案 |

### 代码位置速查

| 系统 | Go 工程 |
|------|---------|
| 射击处理 | `damage/shot.go` |
| 装备组件 | `ecs/com/cbackpack/equip.go` |
| 背包组件 | `ecs/com/cbackpack/backpack.go` + `backpack_func.go` |
| 轮盘组件 | `ecs/com/cui/common_wheel.go` |
| 轮盘动作处理 | `net_func/ui/common_wheel.go` |
| 进入场景初始化 | `net_func/player/enter.go` |

> Go 路径省略公共前缀 `P1GoServer/servers/scene_server/internal/`

---

## 1. 组件结构

### 1.1 EquipComp — 装备栏（运行时活跃武器）

**文件**: `ecs/com/cbackpack/equip.go`

```
EquipComp（玩家实体上）
├── WeaponList               []*WeaponCellInfo   # 武器格子列表（当前只用 [0]）
├── ActiveWeaponCellIndex    int32               # 当前激活武器索引（0 或 -1=无武器）
├── NowWeaponBackpackIndex   int32               # 武器来源的背包 cellIndex（-1=无）
├── ThrowItemList            []*ThrowItemCellInfo # 投掷物格子列表
└── ActiveThrowItemCellIndex int32               # 当前激活投掷物索引
```

**关键方法**：

| 方法 | 说明 |
|------|------|
| `SetWeapon(weapon, backpackIdx)` | 先 RemoveWeapon，再设新武器，返回旧武器 |
| `RemoveWeapon()` | 卸下武器，返回 (weapon, backpackIdx)，清空 WeaponList |
| `GetActiveWeapon()` | 只读获取当前武器 proto |
| `ToProto()` | **深拷贝** WeaponList（见 [7.2](#72-equipcomptoproto-必须深拷贝)） |
| `LoadFromData(saveData)` | 从 DB 加载 ThrowItemList（武器通过轮盘初始化链加载） |

### 1.2 BackpackComp — 背包（数据真相源）

**文件**: `ecs/com/cbackpack/backpack.go` + `backpack_func.go`

```
BackpackComp（玩家实体上）
├── ItemMap         map[int32]*BackpackCell   # cellIndex → 格子
├── IteamListbyKey  map[int32][]*BackpackCell # itemID → 格子列表（快速查找）
├── dirtyCells      map[int32]struct{}        # 变化的 cellIndex（增量同步用）
├── isAllDirty      bool                     # 下次同步强制全量
├── StaticChange    []ItemChangeEvent        # 物品变化事件（任务/成就用）
└── IsWasmNtf       bool                     # 是否需要通知

BackpackCell
├── CellIndex  int32       # 格子索引
├── Item       citem.IItem # 物品（可能是 *citem.Weapon 或 *citem.NormalItem）
└── IsLocked   bool        # 是否锁定
```

**关键方法**：

| 方法 | 说明 |
|------|------|
| `AddItem(itemID, quantity)` | 添加物品，自动合并堆叠，触发 markCellDirty |
| `RemoveItem(itemID, quantity)` | 扣减物品，跨多格子扣减，触发 markCellDirty |
| `GetItemQuantity(itemID)` | 查询物品总数量 |
| `ToSyncProto(isAll)` | 增量/全量同步协议（见 [Section 6](#6-数据同步模型)） |
| `markCellDirty(cellIndex)` | 标记格子为脏 + SetSync() |

### 1.3 Weapon 物品类型

**文件**: `common/citem/weapon.go`

```
Weapon（实现 IItem 接口）
├── Cfg          *config.CfgWeapon    # 武器配置
├── AttributeSet *AttributeSet        # 动态属性集
│   └── Attributes map[int32]*Attribute  # key → {BaseValue, CurValue}
└── GunData      *proto.GunDataProto  # 枪械数据（远程武器才有）
```

**关键属性 Key**（存在 `AttributeSet` 中）：

| 常量 | Key 值 | 含义 |
|------|--------|------|
| `BULLETID` | 192 | 当前装填的弹药类型 item_id |
| `BULLETCURRENT` | 191 | 当前弹匣中的弹药数量 |
| `BULLETVOLUME` | 190 | 弹匣容量上限 |

### 1.4 CommonWheelComp — 轮盘 UI 索引

**文件**: `ecs/com/cui/common_wheel.go`

```
CommonWheelComp（玩家实体上）
└── WheelMap  map[int32]*CommonWheel  # wheelCfgId → 轮盘

CommonWheel
├── SlotMap            map[int32]*CommonSlot  # slotCfgId → 槽位
├── SlotOrder          []int32               # 有序槽位列表
├── NowActiveSlotIndex int32                 # 当前选中槽位
└── DefaultSlotCfgId   int32                 # 默认槽位

CommonSlot
├── CfgId             int32
├── DataType          CommonSlotDataType     # BackpackItem / ItemCollection / Ability / None
├── BackpackCellIndex int32                  # 引用的背包格子（-1=空）
├── ItemCollectionId  int32                  # 弹药集合 ID（-1=空）
└── OnChooseAction    CfgConstQuickActionType # 选中时的动作类型
```

**OnChooseAction 类型**：

| 类型 | 含义 | 行为 |
|------|------|------|
| `EquipItemQuickActionType` | 装备物品 | 从背包读武器 → 装到 EquipComp |
| `UnEquipCurItem` | 卸下当前 | 从 EquipComp 卸下 → 弹药回收 |
| `AddonToCurItem` | 装配弹药 | 设置武器的 bulletId 属性 |
| `CastAbility` | 技能 | 未实现 |

---

## 2. 装备选择流程

### 2.1 装备武器（EquipItem）

**入口**: `UIHandler.ChooseCommonWheelSlot` → `onChooseCommonWheelSlot` → `onEquipItem`

**文件**: `net_func/ui/common_wheel.go`

```
客户端: ChooseCommonWheelSlotReq(wheelCfgId, slotCfgId)
    │
    ▼
1. wheelComp.SelectWheelSlot(wheelCfgId, slotCfgId)  // 更新选中索引
    │
    ▼
2. slot.OnChooseAction == EquipItem ?
    │
    ▼
3. onEquipItem(scene, playerEntity, slot, isChangeItem)
    │
    ├── slot.BackpackCellIndex >= 0 ?  ─── 有武器 ──→ 装备流程
    │                                                    │
    │                                        ┌───────────┘
    │                                        ▼
    │                                   a. equipComp.RemoveWeapon()  // 先卸旧
    │                                        │
    │                                        ▼
    │                                   b. onTriggerUnloadWeapon(oldWeapon, oldIdx, isChangeItem)
    │                                        │   └── 回收弹药（如需要）
    │                                        ▼
    │                                   c. backpackComp.ItemMap[cellIndex]  // 从背包读武器
    │                                        │
    │                                        ▼
    │                                   d. weapon.ToProtoWeapon()  // 转为 proto
    │                                        │
    │                                        ▼
    │                                   e. equipComp.SetWeapon(weaponProto, cellIndex)
    │
    └── slot.BackpackCellIndex < 0 ?  ─── 无武器 ──→ 卸载流程
                                                       │
                                                       ▼
                                                  onUnEquipCurItem()
```

**关键设计**：先卸后装。`onEquipItem` 先调 `RemoveWeapon()` + `onTriggerUnloadWeapon()`（同步旧武器回背包），再从背包读取新武器。这确保即使是"重新装备同一把武器"，背包中的数据也是最新的。

### 2.2 卸下武器（UnEquipCurItem）

```
onUnEquipCurItem(scene, playerEntity, isChangeItem)
    │
    ▼
equipComp.RemoveWeapon() → (weapon, backpackIndex)
    │
    ▼
onTriggerUnloadWeapon(scene, playerEntity, weapon, backpackIndex, isChangeItem)
    │
    ├── isChangeItem == true → onWeaponUnloadRecycleBullet()  // 回收弹药
    │                              │
    │                              ▼
    │                         1. 读 weapon.bulletId + bulletCurrent
    │                         2. 免费弹药？ → 跳过回收
    │                         3. weapon.bulletCurrent = 0
    │                         4. syncWeaponAttributesToBackpack()  // 先清零再加弹药
    │                         5. backpackComp.AddItem(bulletId, ammoCount)
    │
    └── isChangeItem == false → syncWeaponAttributesToBackpack()  // 仅同步属性
```

**弹药回收顺序至关重要**：先将武器 `bulletCurrent` 清零并同步回背包，再 `AddItem` 添加弹药。否则背包中武器副本的弹药数不归零，下次装备时会重复计算。

### 2.3 选择弹药（AddonToCurItem）

```
onAddonToCurItem(scene, playerEntity, slot)
    │
    ▼
1. 从 slot.ItemCollectionId 读弹药 itemId
    │
    ▼
2. 验证: gunCfg.BulletId 包含该弹药?
    │
    ▼
3. setWeaponAttribute(weapon, bulletIdKey, ammoItemId)
    │
    ▼
4. syncWeaponAttributesToBackpack()  // 同步 bulletId 到背包
    │
    ▼
5. 触发客户端换弹动画
```

### 2.4 轮盘槽位移除时自动卸武器

**文件**: `net_func/ui/common_wheel.go:unequipWeaponOnSlotRemove`

当 `RemoveItemFromWheel` 移除的槽位恰好是当前活跃槽位且 `OnChooseAction == EquipItem`，自动触发 `RemoveWeapon` + `onTriggerUnloadWeapon(needRecycleBullet=true)`。

---

## 3. 射击流程

### 3.1 核心流程

**入口**: `HandleShotData`（客户端 ShotData 请求）

**文件**: `damage/shot.go`

```
Client: ShotData(shotData)
    │
    ▼
HandleShotData(scene, shooterEntity, unique, shotData)
    │
    ├── equipComp = GetComponentAs[EquipComp]
    ├── weaponID, weaponProto = getActiveWeapon(equipComp)
    │
    ├── isPlayer?
    │   │
    │   ▼
    │   weaponFire(equipComp, weaponProto)
    │   │   └── weapon.Attributes[BULLETCURRENT].CurrentValue -= 1
    │   │   └── equipComp.SetSync() + SetSave()
    │   │   └── 返回 false 如果弹药 <= 0
    │   │
    │   ▼
    │   syncWeaponToBackpack(scene, entityID, weaponProto, backpackIndex)
    │   │   └── 遍历 weapon.Attributes → bpWeapon.AttributeSet.Set*(key, value)
    │   │   └── backpackComp.SetSync() + SetSave()
    │   │
    │   ▼
    │   CheckManager.AddShotInfo(entityID, weaponID, unique)
    │
    ▼
addSceneEvent(scene, SceneEvent::Shot)  // 广播
```

### 3.2 weaponFire 扣弹逻辑

```go
func weaponFire(equipComp, weapon) bool {
    for _, attr := range weapon.Attributes {
        if attr.Key == BULLETCURRENT {
            if attr.CurrentValue <= 0 { return false }  // 无弹药
            attr.CurrentValue -= 1.0                     // 原地修改 proto
            equipComp.SetSync() + SetSave()
            return true
        }
    }
    return true  // 无弹药属性（近战武器），允许攻击
}
```

**注意**：`weaponFire` **原地修改** `WeaponProto.Attributes` 中的 `CurrentValue`。这是 EquipComp 中的运行时副本，不是背包中的 `citem.Weapon`。修改后需 `syncWeaponToBackpack` 同步回背包。

### 3.3 syncWeaponToBackpack（射击后同步）

**文件**: `damage/shot.go`

同步 EquipComp 中武器的**所有属性**回背包中的武器副本（`citem.Weapon.AttributeSet`）。

```go
func syncWeaponToBackpack(scene, entityID, weapon, backpackIndex) {
    bpWeapon := backpackComp.ItemMap[backpackIndex].Item.(*citem.Weapon)
    for _, attr := range weapon.Attributes {
        bpWeapon.AttributeSet.SetBaseValue(attr.Key, attr.BaseValue)
        bpWeapon.AttributeSet.SetValue(attr.Key, attr.CurrentValue)
    }
    backpackComp.SetSync() + SetSave()
}
```

注意：这里同步的是 `*citem.Weapon`（Go 对象），不是 `*proto.WeaponProto`。背包 `ItemMap` 中的 `Item` 是 `citem.IItem` 接口，实际类型是 `*citem.Weapon`。

---

## 4. 换弹流程

### 4.1 ChangeBulletClip（客户端请求）

**入口**: `UIHandler.ChangeBulletClip`

**文件**: `net_func/ui/common_wheel.go`

```
Client: ChangeBulletClipReq
    │
    ▼
1. 获取 EquipComp.GetActiveWeapon()
    │
    ▼
2. 读取武器属性:
    ├── bulletId   = weapon.Attributes[192]  // 弹药类型
    └── clipSize   = weapon.Attributes[190]  // 弹匣容量
    │
    ▼
3. 免费弹药？
    │
    ├── YES → setWeaponAttribute(BULLETCURRENT, clipSize)
    │         syncWeaponAttributesToBackpack()
    │         equipComp.SetSync() + SetSave()
    │         return
    │
    └── NO  ↓
    │
    ▼
4. 卸弹: 将当前弹药放回背包
    │   bulletCurrent = weapon.Attributes[191]
    │   if bulletCurrent > 0:
    │       backpackComp.AddItem(bulletId, bulletCurrent)
    │
    ▼
5. 清零: setWeaponAttribute(BULLETCURRENT, 0)
    │
    ▼
6. 装弹: 从背包取弹药
    │   available = backpackComp.GetItemQuantity(bulletId)
    │   reloadAmount = min(clipSize, available)
    │   backpackComp.RemoveItem(bulletId, reloadAmount)
    │   setWeaponAttribute(BULLETCURRENT, reloadAmount)
    │
    ▼
7. 同步:
    syncWeaponAttributesToBackpack(playerEntity, weapon, backpackIndex)
    equipComp.SetSync() + SetSave()
```

### 4.2 syncWeaponAttributesToBackpack（换弹用）

**文件**: `net_func/ui/common_wheel.go`

与 `shot.go` 中的 `syncWeaponToBackpack` 类似，但仅同步弹药相关属性（`bulletId` 和 `bulletCurrent`）。

```go
func syncWeaponAttributesToBackpack(playerEntity, weapon, backpackIndex) {
    bpWeapon := backpackComp.ItemMap[backpackIndex].Item.(*citem.Weapon)
    // 只同步 bulletId + bulletCurrent
    syncAttr(bpWeapon, weapon, bulletIdKey)
    syncAttr(bpWeapon, weapon, bulletCurrentKey)
    backpackComp.SetSync() + SetSave()
}
```

### 4.3 免费弹药机制

物品配置中带 `ENTITY_FEATURE_EQUIP_AMMO_PISTOLFREEGAMEPLAYFLAG` 标记的弹药为免费弹药：

- **换弹时**：直接装满弹匣，不从背包扣减
- **卸载武器时**：不回收弹药到背包
- **判定函数**：`isFreeAmmo(bulletId)` / `isFreeBullet(bulletId)`

---

## 5. 进入场景初始化

### 5.1 初始化链

**文件**: `net_func/player/enter.go:initPlayerCommonWheel`

**调用时机**: `addPlayerEntity` 末尾，所有组件 `LoadFromData` 完成后。

```
addPlayerEntity()
    │
    ├── backpackComp.LoadFromData(saveData)
    ├── equipComp.LoadFromData(saveData)
    ├── wheelComp.InitFromConfig(wheelCfgIds)  // 从配置创建结构
    ├── wheelComp.LoadFromData(saveData)        // 覆盖保存的状态
    │
    ▼
initPlayerCommonWheel(scene, wheelComp, backpackComp, equipComp)
    │
    ├── Phase 1: 清理过期引用
    │   ├── 收集背包中实际存在的 cellIndex
    │   ├── wheelComp.OnBackpackUpdate(existingCells)  // 清理已删除物品的槽位
    │   └── 受影响轮盘重置为默认槽位
    │
    ├── Phase 2: 自动匹配空槽位
    │   ├── 收集已占用的 cellIndex（防重复分配）
    │   ├── 遍历空的 BackpackItem 槽位
    │   └── 按 requiredFlags 从背包匹配第一个合适物品
    │
    ├── Phase 3: 自动设弹药类型
    │   ├── 遍历轮盘中的武器
    │   ├── 如果 bulletCurrent == 0 且是枪械
    │   └── 从配置获取兼容弹药 → 设 bulletId 属性
    │
    └── Phase 4: 自动装备活跃武器
        ├── 遍历每个轮盘的 NowActiveSlotIndex
        ├── 如果 OnChooseAction == EquipItem
        └── equipComp.SetWeapon(weapon.ToProtoWeapon(), cellIndex)
```

### 5.2 关键注意点

1. **Phase 2 的 usedIndex 去重**：防止同一背包物品被分配到多个槽位
2. **Phase 3 弹药选择优先级**：优先免费弹药 → 背包中有库存的弹药
3. **Phase 4 直接 SetWeapon**：初始化时不走完整的 `onEquipItem` 流程（无需回收旧弹药）
4. **AttributeSet.SetValue 可失败**：如果 key 不存在需 fallback 到 `Initialize`（见 [7.3](#73-attributesetsetvalue-可失败)）

---

## 6. 数据同步模型

### 6.1 三层数据模型

```
┌─────────────────────────────────────────────────┐
│                  客户端显示                        │
│  EquipmentCompProto + BackpackProto              │
└──────────────────┬──────────────────────────────┘
                   │ 网络推送（SetSync 触发）
                   │
┌──────────────────┴──────────────────────────────┐
│              EquipComp（运行时）                    │
│  WeaponList[0].Weapon（*proto.WeaponProto）       │
│  ← 原地修改 Attributes（weaponFire/ChangeBullet） │
│  ← 深拷贝 ToProto（解决 Equal 缓存问题）           │
└──────────────────┬──────────────────────────────┘
                   │ syncWeaponToBackpack
                   │ syncWeaponAttributesToBackpack
                   │
┌──────────────────┴──────────────────────────────┐
│            BackpackComp（数据真相源）               │
│  ItemMap[cellIndex].Item（*citem.Weapon）          │
│  ← AttributeSet 存储所有属性                       │
│  ← 增量同步：dirtyCells + isAllDirty               │
└─────────────────────────────────────────────────┘
```

### 6.2 增量同步机制（BackpackComp）

```
物品变化 → triggerItemChangeEvent(cellIndex)
              │
              ├── SetSave()
              ├── markCellDirty(cellIndex)
              │       ├── dirtyCells[cellIndex] = struct{}{}
              │       └── SetSync()
              └── StaticChange.append(event)

同步时刻 → ToSyncProto(isAll)
              │
              ├── isAll || isAllDirty → 全量（IsFull=true，所有 ItemMap）
              └── else → 增量（IsFull=false，仅 dirtyCells）
                          ├── cell 存在 → 发送当前数据
                          └── cell 不存在 → 墓碑（ItemInfo=nil）
                          └── 清空 dirtyCells + isAllDirty
```

### 6.3 EquipComp 深拷贝同步

**问题**：网络层使用 `proto.Equal()` 对比新旧 proto 来判断是否需要推送。如果 `ToProto()` 返回 EquipComp 中 `WeaponList` 的直接引用，`weaponFire()` 原地修改 `Attributes` 后，缓存中的"旧值"和新返回的"新值"指向同一底层数据，`Equal()` 永远返回 `true`，变更永远不推送。

**解法**：`EquipComp.ToProto()` 深拷贝 `WeaponList` 和所有 `AttributeProto`，确保每次返回独立的 proto 实例。

### 6.4 两种 Weapon 同步函数对比

| 函数 | 位置 | 同步范围 | 用途 |
|------|------|---------|------|
| `syncWeaponToBackpack` | `damage/shot.go` | **所有属性** | 射击后同步 |
| `syncWeaponAttributesToBackpack` | `net_func/ui/common_wheel.go` | **仅弹药属性** (bulletId + bulletCurrent) | 换弹/卸载后同步 |

两者都是：EquipComp 中的 `*proto.WeaponProto` → 背包中的 `*citem.Weapon.AttributeSet`。

---

## 7. 经验教训

### 7.1 EquipComp ↔ BackpackComp 必须双向同步

**问题**：`weaponFire()` 原地修改 EquipComp 中的武器属性（弹药 -1），如果不同步回 BackpackComp：
1. 背包中武器的弹药数停留在旧值
2. 客户端收到背包同步数据时，武器轮盘显示的弹药数与实际不一致
3. 重新装备同一武器时，读到的是背包中的旧值

**修复**：每次 `weaponFire` 后调 `syncWeaponToBackpack`，每次换弹/卸载后调 `syncWeaponAttributesToBackpack`。

### 7.2 EquipComp.ToProto 必须深拷贝

**问题**：网络缓存层用 `proto.Equal()` 判断变更。如果 `ToProto()` 返回原始引用，原地修改不会被检测到。

**表现**：开枪扣弹后客户端不刷新弹药数，因为 EquipComp 的 SetSync 有效但缓存 Equal 返回 true，跳过推送。

**修复**：`ToProto()` 中逐字段深拷贝 WeaponCellInfo 和 AttributeProto。

### 7.3 AttributeSet.SetValue 可失败

**问题**：`AttributeSet.SetValue(key, value)` 在 key 未预初始化时返回 `false`（静默失败）。武器从 DB 加载时只初始化 DB 中存在的属性，新增属性（如 bulletId=192）可能不在 DB 中。

**修复**：
```go
if !weapon.AttributeSet.SetValue(bulletIdKey, float64(bid)) {
    weapon.AttributeSet.Initialize(bulletIdKey, float64(bid))
}
```

**审查规则**：所有 `AttributeSet.SetValue` 调用必须检查返回值。

### 7.4 装备武器时先卸后装

**问题**：`onEquipItem` 如果先从背包读新武器再卸旧武器，可能读到旧武器属性未回写的背包数据（特别是重新装备同一把武器时）。

**修复**：先 `RemoveWeapon()` + `onTriggerUnloadWeapon()`（同步旧武器回背包），再从背包读取新武器。这保证背包中始终是最新数据。

### 7.5 Proto3 零值陷阱（CommonWheel.LoadFromData）

**问题**：`if cellIndex != 0` 守卫会跳过 `BackpackCellIndex = 0` 的合法值（背包第 0 格）。

**修复**：移除 `!= 0` 守卫，让 proto3 默认值正常写入。

### 7.6 BackpackComp 增量同步

**问题**：`ToProto()` 硬编码 `IsFull=true`，每次同步全量数据，客户端全量替换导致武器轮盘重建。同时 `triggerItemChangeEvent()` 只调 `SetSave()` 不调 `SetSync()`，AddItem 路径不触发客户端同步。

**修复**：
1. 新增 `dirtyCells` + `isAllDirty` 脏追踪
2. `triggerItemChangeEvent` 调 `markCellDirty(cellIndex)`（含 SetSync）
3. 新增 `ToSyncProto(isAll)` 支持增量同步（IsFull=false + 仅脏 cell）
4. 调用方改用 `ToSyncProto`

---

## 8. 组件交互总图

```
┌────────────────────┐
│  CommonWheelComp   │  UI 层
│  SlotMap           │
│  BackpackCellIndex ├──────── 引用 ────────┐
│  NowActiveSlot     │                      │
└────────┬───────────┘                      │
         │ 选择/装备/换弹                     │
         ▼                                   ▼
┌────────────────────┐      ┌────────────────────┐
│    EquipComp       │      │   BackpackComp     │
│ (运行时活跃副本)    │      │  (存储数据真相)     │
│                    │      │                    │
│ WeaponList[0]      │      │ ItemMap[cellIdx]   │
│  └─ WeaponProto    │      │  └─ *citem.Weapon  │
│     └─ Attributes  │◄────►│     └─ AttributeSet│
│                    │ sync │                    │
│ NowWeaponBackpack  │──────│ ← 指向来源格子      │
│ Index              │      │                    │
└────────┬───────────┘      └────────────────────┘
         │
         │ weaponFire / ChangeBulletClip
         │ (原地修改 Attributes)
         │
         ▼
┌────────────────────┐
│   damage/shot.go   │
│ HandleShotData     │
│  → weaponFire      │  BULLETCURRENT -= 1
│  → syncToBackpack  │  全属性同步回背包
└────────────────────┘
```

---

## 9. 网络消息码

| 消息码 | 请求 | 功能 | Handler |
|--------|------|------|---------|
| — | `ChooseCommonWheelSlotReq` | 选择轮盘槽位（装备/卸载/换弹药类型） | `UIHandler.ChooseCommonWheelSlot` |
| — | `AddItemToCommonWheelReq` | 添加物品到轮盘槽位 | `UIHandler.AddItemToCommonWheel` |
| — | `RemoveItemFromCommonWheelReq` | 从轮盘槽位移除物品 | `UIHandler.RemoveItemFromCommonWheel` |
| — | `ChangeBulletClipReq` | 换弹（卸旧弹→装新弹） | `UIHandler.ChangeBulletClip` |
| — | `ShotData` | 射击 | `HandleShotData` |

---

## 10. Rust 对标索引

| Go 函数 | Rust 对标 | 说明 |
|---------|-----------|------|
| `initPlayerCommonWheel` | `on_enter_player_init_common_wheel` | 进入场景轮盘初始化 |
| `OnBackpackUpdate` | `on_backpack_update_to_common_wheel` | 背包变更清理轮盘 |
| `onEquipItem` | `select_common_wheel_slot` (EquipItem 分支) | 装备武器 |
| `onWeaponUnloadRecycleBullet` | `on_weapon_unload_recycle_bullet` | 弹药回收 |
| `ChangeBulletClip` | `bp_weapon_reload` (WeaponReload 蓝图) | 换弹 |
| `weaponFire` | `weapon_fire` | 射击扣弹 |
| `syncWeaponToBackpack` | `weapon.attributes = weapon_info.attributes.clone()` | 射击后属性同步 |
