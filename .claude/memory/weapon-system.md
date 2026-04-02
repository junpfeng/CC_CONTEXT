---
name: 武器系统
description: 武器初始化链、开火逻辑、弹药系统、CanOccupyHandsState 竞态问题
type: reference
---

## 配置表关系

武器涉及四张配置表：
- **ItemBase** (`RawTables/Data_Item/ItemBase.xlsx` → `cfg_itembase.bytes`) - 基础元数据
- **Item** (`cfg_item.bytes`) - 物品通用数据
- **Weapon** (`cfg_weapon.bytes` from `Weapon.xlsx`) - 武器特有数据（类型、耐久、动画）
- **Gun** (`cfg_gun.bytes`) - 枪械特有数据（射击模式、子弹类型、弹夹）

**weapon_base.json** (`RawTables/Weapon/weapon_base.json`) - 非打表系统，WeaponJsonConfigLoader 独立加载，提供后坐力/散射/伤害JSON配置。内部weapon_id（1001-7001）映射到cfg_id（90xxx）。

## 武器初始化链

```
Server WeaponProto
  → WeaponData.InitData()
    → RemoteWeapon.SetWeaponData(WeaponData)
      ├─ ConfigLoader.WeaponMap[cfgId]  ← 直接索引，缺失会 KeyNotFoundException
      ├─ new GunComp → OnAdd()
      │   ├─ ConfigLoader.GunMap.TryGetValue(cfgId)  ← 安全
      │   ├─ _remoteWeaponCfg.gunFireMode  ← 如果 GunMap 缺失会 NullRef
      │   └─ new TraditionalMagazineComp
      └─ GunComp.SetInitData(WeaponData)
          └─ _magazine.Init(gunComp, weaponData)
              ├─ GunProperty != null → 正常初始化
              └─ GunProperty == null → clipNum=0, capacity=0, bulletType=NormalBullet
```

## 弹药系统 (TraditionalMagazineComp)

- `CheckCanFire()` = `_clipNum > 0`（本地玩家）
- `CheckNeedToReload()` = `_clipNum <= 0`
- `CheckCanReload()`:
  - `_clipNum == _magazineCapacity` → false（满弹夹不换弹）
  - NormalBullet / InstantaneousBullet → true（无限弹药类型）
  - 其他类型 → 检查 ItemBase Flags 和背包弹药

**GunProperty 为 null 时的陷阱**：clipNum=0, capacity=0 → CheckCanReload 返回 false（0==0 判定满弹夹）

## CanOccupyHandsState 潜在竞态

**MoveState.OnWeaponChanged**:
1. 设置 `CanOccupyHandsState(false)`
2. 播放 ChangeWeapon 动画
3. 注册 `SetTransitionEndEvent(ChangeWeapon, OnWeaponChangeEnd)`

**OnWeaponChangeEnd**:
1. 检查 `_solvedArmsAnim` = `!IsPlaying(ChangeWeapon)`
2. 如果动画已停止 → **提前返回，不恢复 CanOccupyHandsState(true)**
3. 导致开火门控永久阻塞

**恢复途径**：进入其他状态（跳跃、蹲伏、游泳等）的 OnEnter 会重置为 true
