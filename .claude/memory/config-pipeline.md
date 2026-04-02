---
name: 配置表生成管线
description: Excel 打表流程、关键配置表映射、ItemBase 格式、批量添加工具
type: reference
---

## 流程

```
策划编辑 Excel (RawTables/)
  → 运行 RawTables/_tool/generate.exe
  → 生成:
    - C# 代码: Assets/Scripts/Gameplay/Config/Gen/ (禁止手动编辑)
    - 二进制: Assets/PackResources/Config/Data/*.bytes
    - Go 服务器: P1GoServer/bin/config/ (通过打表工具拷贝)
```

## 关键配置表

| 表名 | Excel来源 | 二进制文件 | ConfigLoader字典 |
|------|-----------|------------|-----------------|
| ItemBase | Data_Item/ItemBase.xlsx | cfg_itembase.bytes | ItemBaseMap |
| Item | Data_Item/Item.xlsx | cfg_item.bytes | ItemMap |
| Weapon | Data_Weapon/Weapon.xlsx | cfg_weapon.bytes | WeaponMap |
| Gun | Data_Weapon/Gun.xlsx | cfg_gun.bytes | GunMap |

## 配置加载顺序 (GameInitialize.cs)

```csharp
ConfigCenter.Init();        // 加载所有 bytes 配置到 ConfigLoader
ConfigBuilder.BuildConfig(); // 构建运行时配置索引
WeaponJsonConfigLoader.Init(); // 加载 weapon_base.json（独立于打表系统）
```

## ItemBase Excel 格式

数据从第5行开始（前4行为表头），列顺序：
Id, Name, DisplayName, Description, Tips, WheelIconAssetFlag, IconAssetFlag,
UnitAssetFlag, UnitEntityFlag, ItemFlags, IsStackable, MaxStackCount,
ActionArray, UseEffect, InitBehavior

## 批量添加 ItemBase 条目

使用 `RawTables/_tool/add_itembase_entries.py`（需要 openpyxl）:
1. 修改脚本中的 `ENTRIES_TO_ADD` 列表
2. 运行 `python add_itembase_entries.py`
3. 运行 `generate.exe` 重新生成二进制

## 武器 ItemFlags 格式

`2010001|{weapon_type_flag}|{item_id}|2011001|88`

武器类型标记：
- Rifle: 2011005
- Shotgun: 2011030
- Smg: 2011031
- Pistol: 2011004
- Sniper: 2011006

## 注意事项

- ConfigLoader 字典直接索引（`Map[id]`）缺失会 KeyNotFoundException
- 安全访问用 `TryGetValue`
- 新增武器物品需同时在 ItemBase、Weapon、Gun 三张表中有条目
- weapon_base.json 是独立于打表系统的 JSON 配置，cfg_id 映射在其中维护
