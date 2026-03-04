# 玩家大世界系统指南

本文档描述玩家在大世界场景（City Scene）中的核心系统：载具、武器轮盘、地图传送。

> **相关文档**：战斗系统（装备选择、射击、换弹）的详细流程见 [`Battle.md`](Battle.md)。

> **迁移方向**：Rust 工程（`server_old`）为历史参考实现，**后续所有开发在 Go 工程（`P1GoServer`）上进行**。
> Rust 代码仅用于理解业务逻辑和对齐行为，不再新增功能。

---

## 文档概述

| 内容 | 使用时机 |
|------|----------|
| 载具系统（Section 1） | 载具功能开发、乘坐/召唤实现 |
| 武器轮盘（Section 2） | 武器装备/切换开发、轮盘交互实现 |
| 地图传送（Section 3） | 传送功能扩展、新传送类型实现 |
| Go 实现状态（Section 4） | 评估优先级、追踪进度、Go 与 Rust 差异 |
| **[Battle.md](Battle.md)** | 射击扣弹、换弹、装备选择、组件间数据同步 |

### 代码位置速查

| 系统 | Rust 实现 | Go 工程 |
|------|-----------|---------|
| 载具核心 | `server_old/servers/scene/src/entity_comp/vehicle/` | `scene_server/internal/net_func/temp/external.go` (stub) + `net_func/vehicle/` |
| 载具组件 | `entity_comp/vehicle/vehicle_comp.rs` | `ecs/com/cvehicle/vehicle_status.go` + `ecs/com/cperson/person_status.go` |
| 载具召唤 | `entity_comp/residence_comp/func.rs` + `entity_comp/player_vehicle_comp/func.rs` | stub |
| 武器轮盘 | `entity_comp/backpack/common_wheel.rs` + `func.rs` | `ecs/com/cui/common_wheel.go` + `net_func/ui/common_wheel.go` |
| 装备系统 | `entity_comp/equip/equip.rs` + `func.rs` | `ecs/com/cbackpack/equip.go` |
| 传送核心 | `entity_comp/player/player.rs` | `net_func/player/teleport.go` |
| 传送-车库 | `entity_comp/residence_comp/func.rs` | stub |

> Go 路径省略公共前缀 `P1GoServer/servers/scene_server/internal/`
> Rust 路径省略公共前缀 `server_old/servers/scene/src/`

---

## 1. 载具系统

> Section 1-3 描述的组件结构和业务流程均基于 **Rust 参考实现**。
> Go 当前结构可能与 Rust 存在差异，详见 [Section 4.5 Go 与 Rust 结构差异](#45-go-与-rust-结构差异)。

### 1.1 组件结构（Rust 参考）

```
VehicleStatusComp（载具实体上）
├── seat_list: Vec<VehicleSeat>        # 乘客座位（index + passenger entity ID + is_driver）
├── door_list: Vec<VehicleDoor>        # 车门状态
├── speed: Vec3                        # 当前速度
├── is_lock: bool                      # 锁车
├── is_in_parking: bool                # 停车场内
├── is_traffic_system: bool            # NPC 交通系统车辆
├── need_auto_vanish: bool             # 自动消失
├── touched_stamp: u64                 # 最后操作时间戳
├── surf_entity: HashMap<i32, u64>     # 车顶冲浪实体
├── part_map: HashMap<i32, VehiclePart># 部件损伤（引擎、轮胎等）
├── lean_angle: Vec3                   # 摩托车倾斜
├── rotator: Vec3                      # 自定义旋转
├── active_car_horn_list: Vec<i32>     # 按座位激活的喇叭
└── audio_radio_cfg_id: i32            # 电台频道

VehicleComp（载具实体上）
├── base_cfg: &CfgVehicleBase          # 静态配置
├── color_list: Vec<IVector3>          # 颜色（1-3 槽）
├── license_id: String                 # 车牌号
└── product_id: i32                    # 购买产品 ID

PlayerVehicleComp（玩家实体上）
├── vehicle_list: HashMap<u32, PersonVehicleInfo>  # 玩家拥有的所有载具
├── current_call_vehicle: u32          # 当前召唤出的载具 unique ID
├── last_call_stamp: u64               # 上次召唤时间戳
└── unique_generator: u32              # 载具唯一 ID 生成器

PersonVehicleInfo
├── unique_id: u32                     # 载具唯一 ID
├── vehicle_info: VehicleComp          # 配置信息
├── attribute_set: AttributeSet        # HP/损伤属性
├── now_entity: Option<Entity>         # 场景实体（None = 在车库中）
├── part_list: Vec<VehiclePart>        # 部件状态
├── is_dead: bool                      # 是否已损毁（需修理）
├── trunk_id: i32                      # 后备箱容量类型
└── park_info: Option<(i32, i32)>      # (house_id, spot_id) 停车位

VehicleOwnerComp（载具实体上，仅玩家车辆）
└── owner_entity_id: u64              # 车主实体 ID（用于驾驶座权限验证）

PersonStatusComp（玩家/NPC 实体上）
├── drive_vehicle_id: u64              # 正在驾驶的载具 entity ID（0 = 未驾驶）
├── drive_vehicle_seat: i32            # 座位 index
├── surf_vehicle_entity_id: u64        # 冲浪的载具 entity ID
├── interaction_entity_id: u64         # 交互的实体 ID（传送时需清除）
├── hold_entity_id: u64               # 持有的实体 ID
└── inventory_in_hand: ITownItem       # 手持物品
```

### 1.2 上车流程 `on_vehicle(entity, vehicle_entity, target_seat)`

**文件**: `entity_comp/vehicle/func.rs:140-292`

```
1. 验证
   ├── PersonStatusComp.can_on_vehicle() — 不能已经在车上
   ├── 驾驶座 + 非车主 → 拒绝 "not owner vehicle"
   └── VehicleStatusComp.change_passenger(target_seat, entity) → 获取旧乘客

2. 核心操作
   ├── 更新 VehicleStatusComp: 设置乘客、touched_stamp、is_dirty
   ├── 更新 PersonStatusComp: on_vehicle(vehicle_entity, seat)
   ├── 旧乘客处理: off_vehicle() + 传送到载具位置
   └── 同步位置: player.location/rotation = vehicle.location/rotation

3. 驾驶座特殊逻辑
   ├── NPC 交通车或有 creator_rule: 扣费 cost_list_force()
   ├── 特殊类型（直升机/飞机/船）: 发送 NetCacheMgr 事件
   └── 车主上驾驶座: remove_player_vehicle_map_icon()（隐藏地图图标）

4. 触发事件
   ├── TriggerEventHappenedIsLoadedIntoTransport
   └── TriggerEventHappenedSpecifyUnitIsLoadedIntoTransport
```

### 1.3 下车流程 `off_vehicle(entity)`

**文件**: `entity_comp/vehicle/func.rs:362-437`

```
1. 检查 PersonStatusComp.drive_vehicle_id（0 = 未上车，静默返回）
2. PersonStatusComp.off_vehicle() + off_vehicle_weapon()（清除载具武器）
3. VehicleStatusComp.passenger_leave_vehicle(entity) + touched_stamp
4. VehicleWeaponComp.leave_vehicle_weapon(entity)（清除武器操作者）
5. 如果是车主 + 驾驶座: add_player_vehicle_map_icon()（恢复地图图标）
6. 触发事件: SpecifyUnitGetOffVehicle + UnitGetOffVehicle
```

### 1.4 驾驶更新 `drive_vehicle(entity, position, rotation, speed, input, lean_angle, rotator)`

**文件**: `entity_comp/vehicle/func.rs:471-560`

```
1. 验证当前实体是驾驶员
2. 更新 VehicleStatusComp: speed、lean_angle、rotator、is_dirty
3. 同步位置: 载具 Transform + 所有乘客 Transform（距离 > 0.0001 时更新）
4. 存储输入: VehicleInputComp.data = input_proto
```

**每帧调用**，客户端发送驾驶输入，服务端同步所有乘客位置。

### 1.5 换座 `switch_vehicle_seat(entity, target_seat)`

**文件**: `entity_comp/vehicle/func.rs:294-360`

```
1. 验证当前在车上、目标座位不同
2. passenger_leave_vehicle(entity) — 离开当前座位
3. change_passenger(target_seat, entity) — 进入新座位
4. 更新 PersonStatusComp
5. 如有旧乘客被挤走: off_vehicle() 强制下车
```

### 1.6 强制拉出 `pull_from_vehicle(master, vehicle, seat)`

**文件**: `entity_comp/vehicle/func.rs:42-138`

```
1. 验证: 不能拉自己
2. passenger_leave_vehicle_by_seat(target_seat)
3. 发送 ForceOffVehicleInfo 事件
4. 被拉出实体: off_vehicle() + 传送到载具位置
5. 如果是 NPC: fsm_input(GetDraggedOut)
```

### 1.7 载具召唤 `call_up_vehicle(player, vehicle_unique, location, rotation)`

**文件**: `entity_comp/residence_comp/func.rs:209-269`

```
1. 验证: 载具存在于 PlayerVehicleComp + license_id 非空
2. spawn_player_vehicle_to_scene():
   ├── 先回收旧载具: recycle_player_vehicle_from_scene()
   ├── 验证载具未损毁（is_dead = false）
   ├── 创建 VehicleSpawnInfo → create_entity_for_spawn_info()
   ├── 设置 current_call_vehicle
   └── add_player_vehicle_map_icon()（显示地图标记）
3. 更新 last_call_stamp + enable_save_player()
```

### 1.8 载具回收 `call_back_vehicle(player)` / `recycle_player_vehicle_from_scene()`

**文件**: `entity_comp/player_vehicle_comp/func.rs:125-195`

```
1. remove_player_vehicle_map_icon()
2. all_passenger_off_vehicle_from_scene() — 所有乘客强制下车
3. 保存载具状态: attribute_set、part_list、is_dead
4. 更新 PlayerVehicleComp: update_vehicle_info() + clear_player_vehicle_entity()
5. 删除场景实体
```

### 1.9 其他载具操作

| 操作 | 文件位置 | 说明 |
|------|----------|------|
| 开/关车门 | func.rs:562-657 | 验证乘客+座位匹配，更新 door_list |
| 鸣笛 | func.rs:1019-1077 | 按座位追踪 active_car_horn_list |
| 停车 | func.rs:807-909 | 设 is_in_parking + AutoVanishComp 保护 |
| 车顶冲浪 | func.rs:911-971 | PersonStatusComp.on_surf_vehicle / off_surf_vehicle |
| 碰撞事件 | func.rs:718-785 | 触发 SpecificUnitCrashed + UnitCrashed |
| 电台切换 | func.rs:439-469 | 更新 audio_radio_cfg_id |
| 车库停车位 | player_vehicle_comp.rs:641-826 | 进入房产时从 PlayerVehicleComp 重建载具实体 |

### 1.10 网络消息码

| 消息码 | 请求 | 功能 |
|--------|------|------|
| 1140 | OnVehicleReq | 上车 |
| 1141 | OffVehicleReq | 下车 |
| 1142 | DriveVehicleReq | 驾驶更新 |
| 1143 | PullFromVehicleReq | 强制拉出 |
| 1144 | CloseVehicleDoorReq | 关车门 |
| 1145 | OpenVehicleDoorReq | 开车门 |
| 1147 | SwitchVehicleSeatReq | 换座位 |
| 1150 | LockVehicleDoorReq | 锁车门 |
| 1151 | UnlockVehicleDoorReq | 解锁车门 |
| 1155 | StartCarHornReq | 鸣笛开始 |
| 1156 | StopCarHornReq | 鸣笛结束 |
| 1952 | CallUpVehicleReq | 召唤载具 |
| 1953 | CallBackVehicleReq | 收回载具 |
| 1954 | InsuranceVehicleReq | 载具保险 |
| 1955 | GetAllSelfVehicleReq | 获取所有载具 |

---

## 2. 武器轮盘系统

### 2.1 组件结构（Rust 参考）

```
CommonWheelComp（玩家实体上）
├── wheel_list: HashMap<i32, CommonWheel>   # 轮盘配置ID → 轮盘实例
└── need_update: bool                       # 脏标记（同步到客户端）

CommonWheel
├── cfg: &CfgQuickActionPanel               # 轮盘配置
├── slot_map: HashMap<i32, CommonSlot>      # 槽位配置ID → 槽位
└── now_active_slot_index: i32              # 当前选中的槽位

CommonSlot
├── cfg: &CfgQuickActionSlot                # 槽位配置（含 on_choose_action）
└── info: CommonSlotType                    # 槽位数据

CommonSlotType（枚举）
├── BackpackItem { backpack_cell_index }    # 背包物品引用
├── ItemCollection { item_id_op }           # 弹药/消耗品集合
├── Ability                                 # 技能槽
└── None                                    # 空槽

EquipComp（玩家实体上）
├── now_weapon: Option<Weapon>              # 当前装备武器
├── now_weapon_index: Option<i32>           # 武器在背包中的 cell index
├── throw_item_cell_list: Vec<ThrowItemCell># 投掷物槽位
├── now_throw_item_index: i32               # 活跃投掷物（-1 = 无）
├── is_dirty: bool                          # 同步脏标记
└── need_save: bool                         # 持久化脏标记

Weapon
├── weapon_cfg: &CfgWeapon                  # 武器配置
├── weapon_gun_data_op: Option<GunData>     # 枪械数据（远程武器才有）
└── attributes: AttributeSet               # 动态属性（弹药ID、弹药数量等）

GunData
├── gun_cfg: &CfgGun                       # 枪械配置（兼容弹药列表）
└── gun_appendix_mgr: GunAppendixMgr       # 配件管理器（瞄准镜、消音器等）
```

### 2.2 核心流程：轮盘槽位选择

**入口**: `select_common_wheel_slot(world, player, wheel_cfg_id, slot_cfg_id, is_change_item)`
**文件**: `entity_comp/backpack/func.rs:620-651`

```
1. 验证
   ├── CommonWheelComp.select_wheel_slot(wheel_id, slot_id)
   │   ├── 查找轮盘和槽位
   │   ├── check_valid() 验证槽位有效
   │   ├── 如果已是当前选中 → 返回 true（跳过）
   │   └── 设置 now_active_slot_index + need_update
   └── 获取 slot_info

2. 动作分发: on_choose_common_wheel_slot(world, player, slot_info, is_change_item)
   └── 根据 slot_info.cfg.on_choose_action（QuickActionType）分支
```

### 2.3 QuickActionType 动作处理

#### EquipItem — 装备武器

```
slot_info.get_backpack_cell_index() → 获取背包 cell index
    ↓
BackPackComp.get_anything_by_cell_index_ref(cell) → 获取 ItemInBag::Weapon
    ↓
EquipComp.set_weapon(weapon.clone(), Some(cell))
    ├── 返回旧武器 Some((old_weapon, old_index))
    └── 设置 is_dirty + need_save
    ↓
on_trigger_unload_weapon(old_weapon, old_index, is_change_item=true)
    ├── on_weapon_unload_recycle_bullet() — 回收子弹到背包
    │   ├── 读取 weapon.attributes[BULLETID] + [BULLETCURRENT]
    │   ├── 跳过免费弹药（PISTOLFREE 标记）
    │   ├── 创建 ItemInBag 弹药堆叠
    │   ├── backpack.add_anything_list_force(ammo, true)
    │   └── 同步武器属性回背包副本（bullet_current = 0）
    └── bp_unload_weapon() — 触发 GAS 卸载效果
    ↓
on_trigger_equip_weapon(weapon_id)
    └── bp_equip_weapon() — 触发 GAS 装备效果（动画、属性等）
```

#### UnEquipCurItem — 卸下当前武器

```
EquipComp.remove_weapon() → 返回 Some((weapon, index))
    ↓
on_trigger_unload_weapon(weapon, index, is_change_item)
    └── 同上回收流程
```

#### AddonToCurItem — 装弹/换弹

```
slot_info.get_item_collection_id() → 弹药 item_id
    ↓
EquipComp.get_weapon_ref() → 当前武器
    ↓
验证: weapon.gun_cfg.bullet_id.contains(&item_id) — 弹药兼容性
    ↓
bp_weapon_reload(world, player, weapon_id, item_id) — 触发换弹蓝图
```

#### CastAbility — 施放技能

当前未实现（空分支）。

### 2.4 轮盘初始化 `on_enter_player_init_common_wheel`

**文件**: `entity_comp/backpack/func.rs:348-447`

**触发时机**: 玩家进入场景

```
1. 遍历所有轮盘的所有槽位
2. BackpackItem 类型槽位:
   ├── 无 cell index → 从背包中按 required_flags 搜索首个匹配物品
   ├── 有 cell index → 验证背包中物品仍存在
   └── 用 HashSet 追踪已使用的 index（防重复分配）
3. 枪械自动装弹:
   ├── 检查武器 bullet_current == 0
   └── 从背包找兼容弹药 → 设置 weapon.attributes[BULLETID]
4. 激活各轮盘的默认槽位:
   └── on_choose_common_wheel_slot(default_slot, is_change_item=true)
```

### 2.5 背包变更同步 `on_backpack_update_to_common_wheel`

**文件**: `entity_comp/backpack/func.rs:286-346`

**触发时机**: 背包物品被删除/交易/出售

```
1. 遍历轮盘所有 BackpackItem 槽位
2. 如 backpack_cell_index 指向的物品已不存在 → slot.remove_item()
3. 如被移除的是当前选中槽位 → 切换到默认槽位
4. 如被移除的是装备中的武器 → 卸下武器 + 回收弹药
```

### 2.6 配件管理

**文件**: `entity_comp/equip/func.rs`

| 操作 | 函数 | 说明 |
|------|------|------|
| 从背包装配件 | `add_weapon_appendix_from_back_to_equipped_weapon()` | 从背包取出 → 验证兼容 → 安装到武器 |
| 卸下配件到背包 | `remove_weapon_appendix_to_backpack()` | 从武器移除 → 放回背包 |
| 验证配件 | `weapon.check_insert_appendix(cell, id)` | 检查配件模板 + 兼容性 |

### 2.7 关键属性 Key

| 属性常量 | 含义 | 操作 |
|----------|------|------|
| `ITEM_PROPERTY_BULLETID` | 当前装填的弹药类型 ID | 装弹时设置，卸载时读取回收 |
| `ITEM_PROPERTY_BULLETCURRENT` | 当前弹药数量 | 射击递减，卸载时归零+回收 |
| `EQUIP_AMMO_PISTOLFREE` | 免费弹药标记 | 跳过回收逻辑 |

---

## 3. 地图传送系统

### 3.1 传送类型总览

| 类型 | 触发方式 | 位置来源 | Flash 效果 | 实现状态 |
|------|----------|----------|------------|----------|
| 配置点传送 | UI 菜单选择 | CfgTeleport 配表 | 无 | Go + Rust 都完成 |
| 复活传送 | 死亡后点击复活 | SpawnPointManager 动态计算 | 有 | Go 部分完成 |
| 进入车库 | 房产场景内点击 | 房屋配置 garage 坐标 | 有 | 仅 Rust |
| 离开车库 | 车库内点击返回 | 房屋配置 house 坐标 | 有 | 仅 Rust |
| 警局传送 | 被逮捕后 | — | — | 两端都未实现 |

### 3.2 核心函数 `teleport_player_to_point_with_rotation()`

**Rust**: `entity_comp/player/player.rs:469-545`
**Go**: `net_func/player/teleport.go:143-239`

```
1. 下车处理（Go 版 TODO）
   └── off_vehicle(entity) — 如果在载具上先下车

2. 获取组件包
   ├── PlayerComp         # teleport_cache
   ├── Transform          # 位置/朝向
   ├── Movement           # 动作状态
   ├── PersonStatusComp   # 状态标记
   ├── PersonInteractionComp  # 交互目标（Go 版 TODO）
   ├── BaseStatusComp     # 生命/存活
   ├── EquipComp          # 装备（Go 版 TODO）
   ├── MovementComp       # 移动信息
   └── PlayerRevivalComp  # 复活数据

3. 清除交互（Go 版 TODO）
   └── clear_self_target_interact()

4. 更新位置
   ├── transform.location = new_position
   ├── transform.rotation = new_rotation
   └── Go 版: transform.SvrTeleportFlag = true

5. 重置动作
   └── movement.action = Action::default()

6. 缓存传送位置
   └── player_comp.teleport_cache = Some(new_position)

7. 构建通知消息
   └── TeleportToPointNtf { PlayerDataUpdate, need_show_flash }
```

### 3.3 配置点传送 `teleport(req)`

**Rust**: `scene_service/service_for_scene.rs:5261-5277`
**Go**: `net_func/player/teleport.go:15-80`

```
1. 查配置: GetCfgTeleportById(req.cfg_id) → position + rotation
2. 红名检查（仅主世界）:
   └── WantedComp.IsRedName() → true 时拒绝传送
3. 调用核心函数
4. 发送 TeleportToPointNtf 到客户端
5. 记录日志
```

**配置结构**（`cfg_teleport.go`，由 `teleport.xlsx` 生成）:
```
CfgTeleport {
    id: int32              # 传送点 ID
    position: Vector3      # 目标坐标
    rotation: Vector3      # 目标朝向
    buyingPosition: Vector3 # 试衣传送坐标
    buyingRotation: Vector3 # 试衣朝向
}
```

### 3.4 传送完成确认 `teleport_finish(req)`

**Rust**: `scene_service/service_for_scene.rs:4493-4517`
**Go**: `net_func/player/teleport.go:83-140`

```
1. 获取 PlayerComp.teleport_cache
   └── None → 警告 "not in teleport state"
2. 验证客户端位置与缓存位置的距离
   └── distance_squared > 10.0 → 警告（允许 ~3.16m 误差，不拒绝）
3. 清除 teleport_cache
4. Go 版: SvrTeleportFlag = false
```

**移动屏蔽**: Go 版在 `action.go` 中检查 `SvrTeleportFlag`，传送期间拒绝所有 MoveReq。

### 3.5 复活传送 `reborn(req)` / `teleport_to_nearest_reborn_point(req)`

**Rust**: `scene_service/service_for_scene.rs:547-578`
**Go**: `net_func/ui/reborn.go:28-62`

```
1. 验证玩家已死亡
2. 设置存活: BaseStatusComp.SetAlive()
3. 获取重生点: SpawnPointManager.GetSpawnPointByUser()
4. 更新 Transform
5. 返回 TeleportToPointNtf（need_flash = true）
```

**Go 与 Rust 差异**: Go 用简化的 `GetPlayerMsg()` 构建消息，Rust 逐组件构建。

### 3.6 车库传送（仅 Rust）

**进入车库** `enter_garage()` — `entity_comp/residence_comp/func.rs:939-970`:
```
1. 验证场景类型 = Possession
2. get_house_enter_garage_position(possession_cfg_id) → 车库入口坐标
3. teleport_player_to_point_with_rotation(position, rotation, need_flash=true)
```

**离开车库** `leave_garage()` — `entity_comp/residence_comp/func.rs:906-937`:
```
1. 验证场景类型 = Possession
2. get_garage_enter_house_position(possession_cfg_id) → 房屋出口坐标
3. teleport_player_to_point_with_rotation(position, rotation, need_flash=true)
```

> `return_possession()` 是 `leave_garage()` 的服务层包装。

### 3.7 客户端-服务端交互时序

```
Client                          Server
  |                               |
  |--- TeleportReq(cfg_id) ----→ |
  |                               | 验证 + 计算位置
  |                               | 更新组件 + 设缓存
  | ←-- TeleportToPointNtf ------ |
  |                               |
  | [播放 Flash 动画]              |
  | [移动到目标位置]               |
  |                               |
  |--- TeleportFinishReq(pos) -→ |
  |                               | 验证位置 + 清缓存
  |                               | SvrTeleportFlag = false
  |                               |
  | [恢复移动能力]                 |
```

---

## 4. Go 实现状态与开发指南

> **原则**：Rust（`server_old`）仅作为业务逻辑参考，所有新功能和待实现功能均在 Go（`P1GoServer`）上开发。

### 4.1 当前 Go 实现进度

| 功能 | Go 状态 | 待实现要点 |
|------|---------|------------|
| **载具** | | |
| 组件结构 | ⚠️ 部分 | 缺少 `current_call_vehicle`/`last_call_stamp`/`unique_generator` 等字段，见 [4.5](#45-go-与-rust-结构差异) |
| 网络路由 | ✅ 已注册 | 消息码 1140-1156, 1952-1957 |
| 上/下/驾驶/换座 | ❌ 待实现 | 参考 Rust `vehicle/func.rs`，handler 在 `external.go` |
| 召唤/回收 | ❌ 待实现 | 参考 Rust `player_vehicle_comp/func.rs` + `residence_comp/func.rs` |
| 车门开关 | ✅ 完成 | `vehicle/vehicle_door.go`，支持 City+Sakura 场景，含 NPC AI 控制权检查 |
| 喇叭/停车 | ❌ 待实现 | 优先级较低 |
| **武器轮盘** | | |
| CommonWheelComp | ⚠️ 需重构 | Go 为扁平列表，缺少 wheelCfgId 层级和 SlotType 枚举，见 [4.5](#45-go-与-rust-结构差异) |
| CommonWheelComp.LoadFromData | ✅ 已修复 | 修复 proto3 零值陷阱（BackpackCellIndex `!= 0` guard 跳过 index 0）、OnBackpackUpdate 清理过期引用 |
| EquipComp | ⚠️ 部分 | 基础字段已有，LoadFromData 已实现（ThrowItemList 深拷贝），RemoveWeapon 已改为 slice deletion |
| 轮盘初始化 | ✅ 已实现 | `initPlayerCommonWheel`（enter.go）：清理过期引用→自动匹配槽位+设弹药→自动装备武器，对标 Rust `on_enter_player_init_common_wheel` |
| 背包变更同步 | ✅ 已实现 | `OnBackpackUpdate`（common_wheel.go）：清理已删除物品的槽位引用，对标 Rust `on_backpack_update_to_common_wheel` |
| 槽位选择验证 | ⚠️ 部分 | `SelectWheelSlot` 忽略 `wheelCfgId` 参数，结构对齐后需重写 |
| 动作执行 | ✅ 已实现 | `onChooseCommonWheelSlot` 分发逻辑（EquipItem/UnEquipCurItem/AddonToCurItem），详见 [Battle.md](Battle.md) Section 2 |
| 弹药回收 | ✅ 已实现 | `onWeaponUnloadRecycleBullet`（common_wheel.go），详见 [Battle.md](Battle.md) Section 2.2 |
| 换弹 | ✅ 已实现 | `ChangeBulletClip`（common_wheel.go），含免费弹药支持，详见 [Battle.md](Battle.md) Section 4 |
| 射击扣弹 | ✅ 已实现 | `HandleShotData` + `weaponFire`（shot.go），含属性同步，详见 [Battle.md](Battle.md) Section 3 |
| 背包增量同步 | ✅ 已实现 | `ToSyncProto` 支持脏 cell 增量推送（IsFull=false），详见 [Battle.md](Battle.md) Section 6 |
| 配件管理 | ❌ 待实现 | 参考 Rust `equip/func.rs` |
| **传送** | | |
| 配置点传送 | ✅ 完成 | 含红名检查 |
| 传送完成确认 | ✅ 完成 | 含位置验证 + SvrTeleportFlag |
| 复活传送 | ⚠️ 部分 | 需补充逐组件构建（当前用简化 GetPlayerMsg） |
| 车库传送 | ❌ 待实现 | 依赖房产场景系统，参考 Rust `residence_comp/func.rs` |
| 传送时下车 | ❌ 待实现 | teleport.go 中 TODO，需载具系统先就绪 |
| 传送时清交互 | ❌ 待实现 | teleport.go 中 TODO，PersonStatusComp.InteractionEntityId 已有 |

### 4.2 Go 开发注意事项

**载具系统**:
- 座位管理逻辑较复杂：上车时旧乘客被挤出、换座时的乘客交换
- 地图图标联动：车主上驾驶座隐藏、下车或非车主恢复
- 召唤前必须先回收旧载具：`spawn` 前调 `recycle`
- 损毁载具不能召唤：需检查 `is_dead`
- VehicleWeaponComp 在下车时需清理操作者
- 停车场 AutoVanish 保护逻辑
- Go 组件用 ECS 模式，注意与 Rust 的 `world.get_mut` 对应为 `common.GetComponentAs`
- Rust→Go 移植时必须完整对比构造函数：Rust `init_vehicle_status` 按 seatNum 初始化 door_list，Go `NewVehicleStatusComp` 需同步初始化 DoorList
- Rust `set_door_status` 对未知 doorIndex 静默返回（不 append），Go 侧必须对齐，否则 DoorList 可被恶意客户端无限增长
- 车门操作 handler 模式：`TempExternalHandler` 委托 `vehicle.VehicleHandler`，支持 City+Sakura 场景类型
- Sakura 场景需额外检查 NPC AI 控制权（`SakuraNpcControlComp.IsControlled()` + `GetControlRoleId() == PlayerComp.RoleId`）

**武器轮盘**:
- Go 中装备武器应深拷贝（背包只读 → 装备可写），对应 Rust 的 clone
- 卸载武器时子弹回收：免费弹药（PISTOLFREE）跳过回收
- 背包物品删除时需同步清理轮盘引用
- 轮盘初始化时用 map 防止重复分配同一物品
- GAS 蓝图调用（bp_equip_weapon / bp_unload_weapon）需要 Go 侧等价实现

**传送系统**:
- 传送前必须先下车（待载具系统实现后补充）
- 传送前必须清除交互状态（Go 已有 `PersonStatusComp.InteractionEntityId`，置零即可）
- SvrTeleportFlag 期间屏蔽移动请求
- 位置验证允许 ~3.16m 误差（distance_squared > 10.0）
- Flash 效果控制：配置点传送无 Flash，复活/车库传送有 Flash

### 4.3 系统间依赖

```
载具系统 ←→ 传送系统
  └── 传送前需下车（off_vehicle）
  └── 召唤载具需传送坐标

武器轮盘 ←→ 载具系统
  └── 下车时清除载具武器（off_vehicle_weapon）
  └── 载具有独立武器系统（VehicleWeaponComp）

武器轮盘 ←→ 背包系统
  └── 轮盘槽位引用背包 cell index
  └── 背包变更时同步清理轮盘
  └── 弹药回收写回背包

传送系统 ←→ 通缉系统
  └── 红名玩家禁止传送（主世界）
```

### 4.4 Go 与 Rust 结构差异

> 以下列出 Go 当前组件结构与 Rust 参考的**关键差异**，开发时需先补齐结构再实现逻辑。

#### PlayerVehicleComp

| 字段 | Rust | Go 当前 | 说明 |
|------|------|---------|------|
| `vehicle_list` | `HashMap<u32, PersonVehicleInfo>` | `[]*PersonalVehicleInfo` | Go 用 slice，缺少按 unique_id 索引 |
| `current_call_vehicle` | ✅ `u32` | ❌ 缺失 | 追踪当前召唤出的载具 |
| `last_call_stamp` | ✅ `u64` | ❌ 缺失 | 召唤冷却 |
| `unique_generator` | ✅ `u32` | ❌ 缺失 | ID 生成器 |

Go 的 `PersonalVehicleInfo` 额外有 `VehicleCfgId`、`BaseInfo`（Rust 放在嵌套的 `VehicleComp` 中），但缺少 `trunk_id`、`park_info`。

#### CommonWheelComp（差异最大）

| 维度 | Rust | Go 当前 |
|------|------|---------|
| 轮盘层级 | `HashMap<i32, CommonWheel>`（按 wheelCfgId 分组） | `[]*CommonWheelSlot`（扁平列表，无轮盘分组） |
| 槽位结构 | `CommonSlot { cfg, info: CommonSlotType }` | `CommonWheelSlot { SlotIndex, ItemInfo }` |
| 槽位类型 | 枚举 `BackpackItem/ItemCollection/Ability/None` | 无枚举，只有 `*proto.ItemProto` |
| 配置引用 | `&CfgQuickActionSlot`（含 `on_choose_action`） | ❌ 无配置引用 |
| 活跃槽位 | 每个 CommonWheel 各自 `now_active_slot_index` | 全局一个 `NowActiveSlotIndex` |
| `SelectWheelSlot` | 按 `wheelCfgId` 查找轮盘再查槽位 | 忽略 `wheelCfgId`，遍历全局列表 |

**Go 重构方向**：需引入 `wheelCfgId` 层级、`CommonSlotType` 枚举、配置引用，才能实现 `onChooseCommonWheelSlot` 动作分发。

#### PersonStatusComp

Go 版比 Rust 多出 `InventoryInHand`、`InteractionEntityId`、`HoldEntityId` 三个字段，这些在 Rust 中分散在其他组件。其中 `InteractionEntityId` 与传送时"清除交互"TODO 直接相关。

### 4.5 Rust 参考代码索引

> 实现 Go 功能时，对照以下 Rust 文件理解完整业务逻辑。

| Go 待实现功能 | Rust 参考文件 | 关键函数 |
|---------------|---------------|----------|
| 上车/下车/换座 | `entity_comp/vehicle/func.rs` | `on_vehicle()`, `off_vehicle()`, `switch_vehicle_seat()` |
| 驾驶更新 | `entity_comp/vehicle/func.rs` | `drive_vehicle()` |
| 载具召唤 | `entity_comp/residence_comp/func.rs` + `player_vehicle_comp/func.rs` | `call_up_vehicle()`, `spawn_player_vehicle_to_scene()` |
| 载具回收 | `entity_comp/player_vehicle_comp/func.rs` | `recycle_player_vehicle_from_scene()` |
| 轮盘动作执行 | `entity_comp/backpack/func.rs` | `on_choose_common_wheel_slot()`, `on_trigger_equip_weapon()` |
| 弹药回收 | `entity_comp/backpack/func.rs` | `on_weapon_unload_recycle_bullet()` |
| 配件管理 | `entity_comp/equip/func.rs` | `add_weapon_appendix_by_item()` |
| 轮盘初始化 | `entity_comp/backpack/func.rs` | `on_enter_player_init_common_wheel()` |
| 车库传送 | `entity_comp/residence_comp/func.rs` | `enter_garage()`, `leave_garage()` |

---

## 5. 经验教训（武器轮盘修复案例）

### 5.1 Proto3 零值陷阱

**问题**：`LoadFromData` 中 `if cellIndex != 0` 守卫会跳过 `BackpackCellIndex = 0` 的合法值（proto3 int32 默认值为 0，与有效的背包第 0 格重叠）。

**解法**：移除 `!= 0` 守卫，让 proto3 默认值正常写入。对于确实需要区分"未设置"和"值为 0"的字段，使用语义保证（如 `NowActiveSlotIndex` 的 `slotCfgId` 永远 > 0，可安全保留 `!= 0` 守卫）。

**审查规则**：所有 `LoadFromData`/`LoadFromProto` 中的 `!= 0` 守卫都需要审查是否存在 proto3 零值陷阱。

### 5.2 AttributeSet.SetValue 可失败

**问题**：`AttributeSet.SetValue(key, value)` 在 key 未预初始化时返回 `false`（静默失败）。武器的 `bulletIdKey` (192) 不一定在 DB proto 中有记录，`LoadProto` 只初始化 DB 中存在的 key。

**解法**：SetValue 之前检查返回值，失败时用 `Initialize` 创建条目：

```go
if !weapon.AttributeSet.SetValue(bulletIdKey, float64(bid)) {
    weapon.AttributeSet.Initialize(bulletIdKey, float64(bid))
}
```

**审查规则**：所有 `AttributeSet.SetValue` 调用必须检查返回值，或在调用前确保 `HasAttribute` 为 true。

### 5.3 Rust→Go 初始化函数迁移清单

Rust 玩家进入场景时有 3 个关键初始化函数，Go 侧必须全部对标实现：

| Rust 函数 | Go 对标 | 说明 |
|-----------|---------|------|
| `on_enter_player_init_common_wheel` | `initPlayerCommonWheel`（enter.go） | 轮盘槽位绑定+自动装弹+自动装备 |
| `on_backpack_update_to_common_wheel` | `OnBackpackUpdate`（common_wheel.go） | 背包变更时清理过期轮盘引用 |
| `on_player_enter_init_backpack` | 已有 | 背包初始化（已实现） |

**教训**：缺少任何一个初始化函数都会导致严重 bug。迁移时应完整搜索 Rust `player.rs` 中的 `on_enter_player_*` 和 `on_*_init_*` 调用，确保无遗漏。

### 5.4 循环依赖解决方案

**问题**：`net_func/player`（enter.go）→ `net_func/ui`（common_wheel.go）→ `net_func/player`（其他文件），形成包级循环依赖。

**解法**：将初始化逻辑直接内联到 `enter.go`（调用方），避免跨包调用。当功能只在一个入口点使用时，内联比提取新包更简单。

**替代方案**（未来如需复用）：提取到独立包 `net_func/weapon_init/` 打破循环。
