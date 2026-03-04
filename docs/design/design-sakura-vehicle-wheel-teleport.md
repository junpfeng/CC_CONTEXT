# 设计文档：樱花场景 - 载具/武器轮盘/传送

## 1. 需求回顾

玩家进入樱花小镇场景后，需要支持：
1. **载具系统**：上车/下车/驾驶/换座/召唤/回收
2. **武器轮盘**：轮盘槽位选择 → 装备/卸下武器/装弹/技能
3. **地图传送**：配置点传送（已完成）+ 传送前清理状态（待补TODO）

### 樱花场景特殊性
- `IsMainScene()=false` — 无红名传送限制
- `EnablePolice=false`, `EnableWanted=false` — 无警察/通缉
- 私人场景（有 owner）
- NavMesh 名称：`"sakura"`
- 组件层面无限制：`PlayerVehicleComp`、`CommonWheelComp`、`EquipComp` 已在所有场景为玩家实体添加

---

## 2. 架构设计

### 2.1 系统边界

```
┌──────────────────────────────────────────────────┐
│ 场景通用层（所有场景共享）                           │
│                                                  │
│  传送系统    载具系统    武器轮盘系统                │
│  (teleport/) (vehicle/) (ui/common_wheel)        │
│      │          │           │                    │
│      ▼          ▼           ▼                    │
│  ┌─────────────────────────────────────┐         │
│  │ ECS 组件层                          │         │
│  │ PersonStatusComp  PlayerVehicleComp │         │
│  │ Transform         CommonWheelComp   │         │
│  │ EquipComp         BackpackComp      │         │
│  └─────────────────────────────────────┘         │
└──────────────────────────────────────────────────┘
```

**设计原则**：三个系统实现为**场景无关**的通用功能，不做场景类型判断。樱花场景自然获得这些能力。

### 2.2 模块分包

```
net_func/
├── player/
│   ├── teleport.go          # 已有，补 TODO
│   └── vehicle.go           # 新增：载具操作 handler
├── ui/
│   └── common_wheel.go      # 已有，补 onChooseCommonWheelSlot
└── temp/
    └── external.go          # 现有 stub，迁移到上述文件后删除对应 stub

ecs/com/
├── cplayer/
│   └── player_vehicle.go    # 已有，补字段 + LoadFromData
├── cvehicle/                # 新增目录
│   ├── vehicle_status.go    # 新增：载具实体状态组件
│   └── vehicle_owner.go     # 新增：载具实体归属组件
├── cperson/
│   └── person_status.go     # 已有，加 OnVehicle/OffVehicle 方法
├── cui/
│   └── common_wheel.go      # 已有，重构数据结构
└── cbackpack/
    └── equip.go             # 已有，补 SetWeapon/RemoveWeapon
```

---

## 3. 详细设计

### 3.1 载具系统

#### 3.1.1 新增组件

**VehicleStatusComp**（载具实体上）— 新增文件 `ecs/com/cvehicle/vehicle_status.go`

```go
type VehicleStatusComp struct {
    common.ComponentBase
    SeatList       []*VehicleSeat          // 座位列表
    DoorList       []*VehicleDoor          // 车门列表
    Speed          trans.Vec3              // 当前速度
    IsLock         bool                    // 是否锁车
    IsInParking    bool                    // 是否在停车场
    IsTrafficVehicle bool                  // 是否交通系统车辆
    NeedAutoVanish bool                    // 自动消失
    TouchedStamp   int64                   // 最后操作时间戳
    LeanAngle      trans.Vec3              // 摩托倾斜
    Rotator        trans.Vec3              // 自定义旋转
    AudioRadioCfgId int32                  // 电台频道
}

type VehicleSeat struct {
    Index       int32
    Passenger   uint64  // 乘客 entity ID, 0=空
    IsDriver    bool
}

type VehicleDoor struct {
    Index    int32
    IsOpen   bool
}
```

注册 `ComponentType`：在 `com_type.go` 的载具组件区域新增 `ComponentType_VehicleStatus`。

**VehicleOwnerComp**（载具实体上）— 新增文件 `ecs/com/cvehicle/vehicle_owner.go`

```go
type VehicleOwnerComp struct {
    common.ComponentBase
    OwnerEntityId uint64 // 车主实体 ID
}
```

注册 `ComponentType_VehicleOwner`。

#### 3.1.2 补全 PlayerVehicleComp

在 `player_vehicle.go` 补充缺失字段和方法：

```go
type PlayerVehicleComp struct {
    common.ComponentBase
    VehicleList        []*PersonalVehicleInfo
    CurrentCallVehicle uint32  // 当前召唤出的载具 unique ID
    LastCallStamp      int64   // 上次召唤时间戳
    UniqueGenerator    uint32  // 载具唯一 ID 生成器
}
```

补全 `LoadFromData`：从 `DBSavePesonVehicleComp` 加载 `unique_generator` 和 `vehicleList`。

新增方法：
- `GetVehicleByUnique(uniqueId uint32) *PersonalVehicleInfo`
- `SetCurrentCallVehicle(uniqueId uint32)`
- `ClearCurrentCallVehicle()`
- `NextUniqueId() uint32`

#### 3.1.3 PersonStatusComp 辅助方法

在 `person_status.go` 新增：

```go
func (p *PersonStatusComp) OnVehicle(vehicleEntityId uint64, seat uint32) {
    p.DriveVehicleId = vehicleEntityId
    p.DriveVehicleSeat = seat
    p.SetSync()
}

func (p *PersonStatusComp) OffVehicle() {
    p.DriveVehicleId = 0
    p.DriveVehicleSeat = 0
    p.SetSync()
}

func (p *PersonStatusComp) CanOnVehicle() bool {
    return p.DriveVehicleId == 0
}
```

#### 3.1.4 载具实体生成

载具实体创建函数（`net_func/player/vehicle.go` 或独立工具包）：

```go
func SpawnPlayerVehicle(s common.Scene, owner common.Entity, vehicleInfo *PersonalVehicleInfo,
    position trans.Vec3, rotation trans.Vec3) (common.Entity, error) {
    // 1. 创建实体
    vehicleEntity := s.NewEntity()
    // 2. 添加 Transform
    // 3. 添加 VehicleStatusComp（从配置初始化座位/车门）
    // 4. 添加 VehicleOwnerComp（设置 owner entity ID）
    // 5. 添加 BaseStatusComp
    // 6. 更新 vehicleInfo.NowEntity = vehicleEntity.ID()
    return vehicleEntity, nil
}

func RecyclePlayerVehicle(s common.Scene, owner common.Entity, vehicleUnique uint32) error {
    // 1. 找到载具实体
    // 2. 所有乘客强制下车
    // 3. 保存载具状态到 PlayerVehicleComp
    // 4. 删除场景实体 s.RemoveEntity()
    // 5. 清除 PlayerVehicleComp.CurrentCallVehicle
    return nil
}
```

#### 3.1.5 核心 Handler 实现

**上车** `OnVehicle(req)`：
```
1. 验证：PersonStatusComp.CanOnVehicle()
2. 验证：目标座位可用（VehicleStatusComp.SeatList）
3. 驾驶座验证：VehicleOwnerComp.OwnerEntityId == 请求者
4. 旧乘客处理：如目标座位有人，先 OffVehicle() 旧乘客
5. 更新 VehicleStatusComp：设置座位乘客
6. 更新 PersonStatusComp.OnVehicle()
7. 同步位置：player.Transform = vehicle.Transform
```

**下车** `OffVehicle(req)`：
```
1. 验证：PersonStatusComp.DriveVehicleId != 0
2. PersonStatusComp.OffVehicle()
3. VehicleStatusComp：清除座位乘客
4. 设置 VehicleStatusComp.TouchedStamp
```

**驾驶** `DriveVehicle(req)` — 高频调用（每帧）：
```
1. 验证：当前实体是驾驶员
2. 更新 VehicleStatusComp：speed, lean_angle, rotator
3. 同步位置：载具 Transform + 所有乘客 Transform
```

**召唤** `CallUpVehicle(req)`：
```
1. 验证：PlayerVehicleComp 中载具存在 + 未损毁
2. 先回收旧载具：RecyclePlayerVehicle()
3. SpawnPlayerVehicle() 创建新实体
4. 设置 CurrentCallVehicle + LastCallStamp
```

**回收** `CallBackVehicle(req)`：
```
1. RecyclePlayerVehicle()
```

#### 3.1.6 优先级分层

| 优先级 | 功能 | 说明 |
|--------|------|------|
| P0 | 上车/下车/驾驶 | 核心交互 |
| P0 | 召唤/回收 | 核心交互 |
| P1 | 换座 | 常用操作 |
| P2 | 车门/喇叭/停车/冲浪 | 可后续补充 |
| P3 | 交通载具/碰撞事件 | 樱花场景可能不需要 |

---

### 3.2 武器轮盘系统

#### 3.2.1 CommonWheelComp 重构

**关键发现**：Proto 已支持正确结构（`CommonWheelCompProto` → `CommonWheelProto[wheel_cfg_id]` → `CommonSlotProto[slot_cfg_id]`），但 Go 组件是扁平结构。

重构后结构：

```go
type CommonWheelComp struct {
    common.ComponentBase
    WheelMap map[int32]*CommonWheel // wheelCfgId → CommonWheel
}

type CommonWheel struct {
    WheelCfgId         int32
    SlotMap            map[int32]*CommonSlot // slotCfgId → CommonSlot
    NowActiveSlotIndex int32
}

type CommonSlot struct {
    SlotCfgId         int32
    SlotType          CommonSlotType
    BackpackCellIndex int32  // BackpackItem 类型时有效
    ItemCollectionId  int32  // ItemCollection 类型时有效
}

type CommonSlotType int
const (
    CommonSlotType_None           CommonSlotType = 0
    CommonSlotType_BackpackItem   CommonSlotType = 1
    CommonSlotType_ItemCollection CommonSlotType = 2
    CommonSlotType_Ability        CommonSlotType = 3
)
```

#### 3.2.2 LoadFromData / ToProto 重写

```go
func (c *CommonWheelComp) LoadFromData(saveData *proto.CommonWheelCompProto) {
    c.WheelMap = make(map[int32]*CommonWheel)
    for _, wheelProto := range saveData.WheelList {
        wheel := &CommonWheel{
            WheelCfgId:         wheelProto.WheelCfgId,
            NowActiveSlotIndex: wheelProto.NowActiveSlotIndex,
            SlotMap:            make(map[int32]*CommonSlot),
        }
        for _, slotProto := range wheelProto.SlotList {
            wheel.SlotMap[slotProto.SlotCfgId] = &CommonSlot{
                SlotCfgId:         slotProto.SlotCfgId,
                BackpackCellIndex: slotProto.BackpackCellIndex,
                ItemCollectionId:  slotProto.ItemCollectionId,
            }
        }
        c.WheelMap[wheelProto.WheelCfgId] = wheel
    }
}
```

#### 3.2.3 SelectWheelSlot 重写

```go
func (c *CommonWheelComp) SelectWheelSlot(wheelCfgId, slotCfgId int32) bool {
    wheel, ok := c.WheelMap[wheelCfgId]
    if !ok { return false }
    slot, ok := wheel.SlotMap[slotCfgId]
    if !ok { return false }
    if wheel.NowActiveSlotIndex == slotCfgId { return true }
    wheel.NowActiveSlotIndex = slotCfgId
    c.SetSync()
    return true
}
```

#### 3.2.4 onChooseCommonWheelSlot 实现

```go
func onChooseCommonWheelSlot(s common.Scene, entity common.Entity,
    slot *CommonSlot, isChangeItem bool) {

    slotCfg := config.GetCfgQuickActionSlotById(slot.SlotCfgId)
    if slotCfg == nil { return }

    switch slotCfg.GetOnChooseAction() {
    case config.EquipItemQuickActionType:
        // 1. 从 BackpackComp 获取 cell index 对应的物品
        // 2. EquipComp.SetWeapon(weapon, cellIndex)
        // 3. 触发旧武器卸载（弹药回收）
    case config.UnEquipCurItemQuickActionType:
        // 1. EquipComp.RemoveWeapon()
        // 2. 触发弹药回收
    case config.AddonToCurItemQuickActionType:
        // 1. 获取弹药 item_id
        // 2. 验证与当前武器兼容
        // 3. 触发换弹
    case config.CastAbilityQuickActionType:
        // 当前不实现
    }
}
```

#### 3.2.5 EquipComp 补全

新增方法：

```go
// SetWeapon 装备武器，返回旧武器信息
func (e *EquipComp) SetWeapon(weapon *proto.WeaponCellInfo, cellIndex int32) *proto.WeaponCellInfo {
    old := e.GetActiveWeapon()
    // 设置新武器到 WeaponList
    e.ActiveWeaponCellIndex = cellIndex
    e.SetSync()
    e.SetSave()
    return old
}

// RemoveWeapon 卸下当前武器
func (e *EquipComp) RemoveWeapon() *proto.WeaponCellInfo {
    old := e.GetActiveWeapon()
    e.ActiveWeaponCellIndex = -1
    e.SetSync()
    e.SetSave()
    return old
}

// GetActiveWeapon 获取当前装备的武器
func (e *EquipComp) GetActiveWeapon() *proto.WeaponCellInfo
```

补全 `LoadFromData`：从 `DBSaveEquipMentComponent` 加载武器列表和投掷物。

#### 3.2.6 轮盘初始化

玩家进入场景时（`enter.go`），在 `LoadFromData` 之后，需补充初始化逻辑：

```
1. 如果 WheelMap 为空（首次进入），从配置表初始化默认轮盘结构
2. 遍历 BackpackItem 类型槽位：
   - 无 cell index → 从背包搜索首个匹配物品
   - 有 cell index → 验证背包中物品存在
3. 激活各轮盘的默认槽位
```

#### 3.2.7 弹药回收

```go
func onWeaponUnloadRecycleBullet(s common.Scene, entity common.Entity,
    weapon *proto.WeaponProto, cellIndex int32) {
    // 1. 读取 weapon.Attributes 中的 BULLETID 和 BULLETCURRENT
    // 2. 跳过免费弹药（PISTOLFREE 标记）
    // 3. 创建弹药物品
    // 4. BackpackComp.AddItem(bulletId, bulletCount)
    // 5. 武器属性 bullet_current = 0
}
```

---

### 3.3 传送系统

#### 3.3.1 现状

传送系统已基本完成，樱花场景无阻塞。需补充的 TODO 项：

| TODO | 依赖 | 实现方式 |
|------|------|----------|
| 传送前下车 | 载具系统 | 调用 OffVehicle 逻辑 |
| 传送前清交互 | 无 | `PersonStatusComp.InteractionEntityId = 0` |
| 装备组件同步 | EquipComp | 传送消息中包含 EquipComp 数据 |

#### 3.3.2 TeleportPlayerToPoint 补全

```go
// 在 teleport.go:TeleportPlayerToPoint 中补充：

// 1. 下车处理（载具系统就绪后）
if personStatusComp.DriveVehicleId != 0 {
    offVehicle(s, entity) // 调用下车逻辑
}

// 2. 清除交互
personStatusComp.InteractionEntityId = 0
personStatusComp.SetSync()

// 3. 装备信息同步（补充到 TeleportToPointNtf 消息中）
```

---

## 4. 事务性设计

### 4.1 载具上车事务

```
验证阶段（只读，不修改状态）：
  1. CanOnVehicle() 检查
  2. 座位可用性检查
  3. 车主权限检查

执行阶段（按序修改状态）：
  1. 旧乘客下车（如有）
  2. 更新 VehicleStatusComp 座位
  3. 更新 PersonStatusComp
  4. 同步 Transform

回滚：
  - 旧乘客下车失败 → 拒绝上车，不修改任何状态
  - 执行阶段中间失败 → 按反序恢复（实际上载具操作原子性由单线程保证）
```

### 4.2 载具召唤事务

```
验证阶段：
  1. 载具存在 + 未损毁
  2. 位置有效

执行阶段：
  1. 回收旧载具（包含所有乘客下车）
  2. 创建新载具实体
  3. 更新 PlayerVehicleComp

回滚：
  - 旧载具回收成功但新载具创建失败 → 旧载具已回收到车库，新载具不在场景，状态一致
  - 关键操作记录日志
```

### 4.3 并发安全

所有操作在 Scene 的单线程 Tick 中执行，无需额外加锁。跨 Scene 操作通过 RPC 异步完成。

---

## 5. 接口契约

### 5.1 协议工程

**当前不需要新增协议消息**。所有需要的消息码已定义：
- 载具：1140-1156, 1952-1957（已注册 handler）
- 武器轮盘：`SelectCommonWheelSlotReq`（已有）
- 传送：`TeleportReq`/`TeleportFinishReq`/`TeleportToPointNtf`（已有）

Proto 数据结构已支持：
- `CommonWheelCompProto` → `CommonWheelProto` → `CommonSlotProto`（已有 wheelCfgId 分层）
- `DBSavePesonVehicleComp`（已有 unique_generator）
- `VehicleDataUpdateCache`（已有完整的载具数据同步结构）

### 5.2 配置工程

**当前不需要新增配置表**。已有：
- `CfgTeleport`：传送点配置
- `CfgQuickActionPanel` + `CfgQuickActionSlot`：轮盘配置
- `CfgWeapon` + `CfgGun` + `CfgGunAppendix`：武器配置
- `CfgVehicleBase`：载具基础配置（待确认 Go 侧是否已有）

### 5.3 数据库

**已有 Proto 定义，需要补全 Go 组件的 LoadFromData**：
- `DBSavePesonVehicleComp`：unique_generator + vehicleList
- `DBSavePersonalVehicle`：vehicle_unique + vehicle_comp + attributes + partList + trunkId + is_dead + parkInfo
- `DBSaveEquipMentComponent`：待确认字段
- `CommonWheelCompProto`：wheel_list（已有完整结构）

---

## 6. 风险和缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 载具配置表 `CfgVehicleBase` Go 侧可能未加载 | 载具实体无法初始化座位/车门 | Phase 4 前确认，必要时补配置加载 |
| CommonWheelComp 重构影响数据库兼容性 | 现有玩家数据加载失败 | Proto 结构未变（已有 wheelCfgId），只改 Go 组件；LoadFromData 对齐 Proto 即可 |
| 樱花场景 NavMesh 不支持载具 | 载具生成位置不合理 | 载具位置由客户端发送，服务端不做寻路，风险低 |
| GAS/Blueprint 未移植 | 武器装备/卸下无视觉效果 | 服务端逻辑正常，视觉效果由客户端处理，不阻塞功能 |
| 载具驾驶帧同步性能 | DriveVehicle 每帧调用，多乘客同步 | Transform 更新使用 SetSync，由 NetUpdateSystem 批量同步 |

---

## 7. 实现优先级与依赖

```
                    ┌─────────────────┐
                    │ 3.3 传送 TODO   │ ← 最简单，可先独立交付
                    │ (清交互部分)     │
                    └────────┬────────┘
                             │ 依赖载具系统完成"下车"
                    ┌────────┴────────┐
                    │ 3.1 载具系统    │ ← 工作量最大
                    │ (P0: 上下车/召唤)│
                    └─────────────────┘

    ┌─────────────────────────────────────┐
    │ 3.2 武器轮盘                        │ ← 与载具独立，可并行
    │ (重构 CommonWheelComp + 动作分发)    │
    └─────────────────────────────────────┘
```

**建议实现顺序**：
1. **传送 TODO**（清交互）— 0.5 天
2. **载具核心**（组件定义 + 上下车 + 召唤回收）— 与武器轮盘并行
3. **武器轮盘**（重构 + 动作分发 + 装备/卸下）— 与载具并行
4. **传送 TODO**（下车）— 载具完成后补充
5. **载具 P1/P2**（换座/车门等）— 后续补充
