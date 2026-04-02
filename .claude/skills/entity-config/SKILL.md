---
name: entity-config
description: 场景物体配置规范：entity/*.json 的格式、所有组件字段、map/*.json 的放置格式，以及新增 entity 类型的完整步骤。当涉及新增场景物体类型、修改 entity 配置、在地图中放置物体、理解 sync_policy 或组件字段含义时使用。
---

# 场景物体配置规范

配置文件位于 `freelifeclient/RawTables/`，客户端与服务器共享。完整说明见 `freelifeclient/RawTables/README.md`。

---

## entity 配置格式（`freelifeclient/RawTables/entity/<type>.json`）

```json
{
    "type": "berry-bush",
    "sync_policy": "on_interact",
    "prefabs": [
        {
            "id": "berry-bush-01",
            "components": [
                {
                    "type":"transform",
                    "data":{
                        "pos": [0, 0, 0],
                        "rot": [0, 0, 0],
                        "scale": [1, 1, 1]
                    }
                },
                {
                    "type":"item",
                    "data":{
                        "cfg_id": 1001,
                        "item_tags": 4
                    }
                },
                {
                    "type":"item_state",
                    "data":{
                        "state": 0
                    }
                }
            ]
        }
    ]
}
```

**关键规则**：
- 文件名 = `type` 值，使用 kebab-case（`born-point`，不是 `bornPoint`）
- `components` 是数组，每项含 `type`（组件类型标识）和 `data`（组件初始化数据）；不挂载的组件直接不写
- 一个 entity 可有多个 prefab（同类型不同外观），通过 `id` 区分

---

## sync_policy 取值

| 值 | 含义 | 服务器行为 | 典型用例 |
|---|---|---|---|
| `always` | 始终同步 | 地图加载时立即创建 Entity | 出生点、NPC |
| `on_interact` | 交互后同步 | 玩家触发后才创建 Entity | 树、矿石、采集物 |
| `on_state_change` | 状态变化时同步 | 加载时创建，低频同步 | 箱子（开/关） |
| `client_only` | 纯客户端 | 不创建 Entity | 草、花、装饰物 |

---

## 组件字段速查

组件统一写法：`{ "type":"<组件名>", "data":{ <字段> } }`

### `transform`（必须）
```json
{ "type":"transform", "data":{ "pos": [x, y, z], "rot": [x, y, z], "scale": [x, y, z] } }
```
> 地图 object 的 `pos`/`rot`/`scale` 会覆盖此处的默认值。

### `item`
```json
{ "type":"item", "data":{ "cfg_id": 2001, "item_tags": 0 } }
```
- `cfg_id`：对应 `freelifeclient/RawTables/item/itemBase/` 中的物品 ID
- `item_tags`：ItemTags 枚举位掩码（Proto 定义）

### `item_state`
```json
{ "type":"item_state", "data":{ "state": 0 } }
```
- `state`：初始状态值，0 为默认

### `physics`
```json
{ "type":"physics", "data":{ "mass": 1.0, "is_kinematic": false } }
```
- `is_kinematic: true` = 不受物理力影响（运动学刚体）

### `item_container`
```json
{ "type":"item_container", "data":{ "cell_count": 6 } }
```
- `cell_count`：背包/箱子的格子数量

---

## 服务器 Go 结构体对应关系

位于 `P1GoServer/common/config/entity.go`：

```
EntityDefCfg            ← entity/*.json 根对象
  └── EntityPrefabCfg   ← prefabs[]
        └── EntityComponentsCfg ← components
              ├── EntityTransformCfg     ← transform
              ├── EntityItemCfg          ← item
              ├── EntityItemStateCfg     ← item_state
              ├── EntityPhysicsCfg       ← physics
              └── EntityItemContainerCfg ← item_container
```

读取入口：`ConfigMgr.GetEntityDef(entityType string) (*EntityDefCfg, bool)`

---

## map 配置格式（`freelifeclient/RawTables/map/<mapid>.json`）

```json
{
    "map": "global",
    "levels": [
        {
            "type": "home",
            "type":"家园地图",
            "objects": [
                {
                    "type": "born-point",
                    "prefab_id": "1",
                    "pos": [18.11, 2.647, -373.241],
                    "rot": [0, 0, 0],
                    "scale": [1, 1, 1]
                }
            ]
        }
    ]
}
```

- `type`（level）：关卡类型，对应客户端场景资源
- `objects[].type`：引用 `entity/<type>.json`
- `objects[].prefab_id`：引用该 entity 中对应的 prefab id
- `objects[].pos/rot/scale`：覆盖 entity prefab 中 transform 的默认值

---

## 新增 entity 类型的步骤

### 第一步：创建 entity 配置文件

在 `freelifeclient/RawTables/entity/` 下新建 `<type>.json`，文件名使用 kebab-case。

选择合适的 `sync_policy`（参考上方表格），按需添加组件：

| 场景 | 必需组件 | 可选组件 |
|---|---|---|
| 纯出生点 | `transform` | — |
| 可采集物（树/矿） | `transform`, `item`, `item_state` | `physics` |
| 容器（箱子） | `transform`, `item`, `item_state`, `item_container` | — |
| 带物理的物体 | `transform`, `item`, `item_state`, `physics` | — |

### 第二步：在地图中放置

在对应 `freelifeclient/RawTables/map/<mapid>.json` 的 level 的 `objects` 数组中添加：

```json
{
    "type": "<你的type>",
    "prefab_id": "<entity中的prefab id>",
    "pos": [x, y, z],
    "rot": [0, 0, 0],
    "scale": [1, 1, 1]
}
```

### 第三步：确认服务器可解析

`entity.go` 中的 `EntityComponentsCfg` 覆盖了当前所有组件。如果新增了新组件，需要同时在服务器端新增对应 Go 结构体字段。

---

## 现有 entity 一览

| 文件 | sync_policy | 组件 |
|---|---|---|
| `born-point.json` | `always` | transform |
| `berry-bush.json` | `on_interact` | transform, item, item_state |
| `tree.json` | `on_interact` | transform, item, item_state, physics |
| `luggage.json` | `on_state_change` | transform, item, item_state, item_container |
