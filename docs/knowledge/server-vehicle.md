# P1GoServer 载具系统

> 服务器端载具系统知识图谱，涵盖 ECS 数据结构、网络协议、权限模型、交通载具管理、持久化与商业系统。

## 目录

- [1. 架构总览与职责划分](#1-架构总览与职责划分)
- [2. ECS 数据结构](#2-ecs-数据结构)
- [3. 网络协议](#3-网络协议)
- [4. 载具生命周期](#4-载具生命周期)
- [5. 座位与乘员管理](#5-座位与乘员管理)
- [6. 交通载具系统](#6-交通载具系统)
- [7. 持久化与商业](#7-持久化与商业)
- [8. 关键文件索引](#8-关键文件索引)

---

## 1. 架构总览与职责划分

服务器是**状态仲裁者**，不是物理模拟者。物理完全由客户端计算，服务器信任客户端提交的位置数据。

### 服务器权威（验证+决策）

| 方面 | 说明 |
|------|------|
| 座位管理 | 验证上/下车请求，维护谁在哪个座位 |
| 车门/喇叭 | 验证操作者身份和位置后更新状态并广播 |
| 车辆锁定 | `IsLock` 阻止非车主上车 |
| 交通载具生成/回收 | 验证场景类型，创建 ECS 实体，空闲自动回收 |
| 场景校验 | 仅 City/Sakura 场景允许载具操作 |
| 驾驶员身份验证 | 高频位置更新前验证调用者是否为驾驶员 |
| 乘客位置同步 | 驾驶员提交位置后，服务器同步所有乘客 Transform |
| 所有权/车库 | 持久化到 MongoDB |
| 商店/租赁 | 配置驱动的购买和租赁逻辑 |
| NPC 控制权 | 验证 NPC 是否被当前玩家控制 |
| 网络广播 | dirty flag 机制推送 Transform + BaseInfo + Status |

### 服务器信任客户端（不做二次计算）

| 方面 | 说明 |
|------|------|
| 物理模拟 | **不运行 PhysX**，碰撞/翻车/WheelCollider 完全客户端 |
| 移动位置 | 接受客户端 position/rotation，仅验证驾驶员身份 |
| 车辆 HP/损坏 | 损坏阶段是配置驱动的视觉效果，不持久化 HP |
| 燃油消耗 | 参数存在于配置表，无服务器 tick 扣减 |
| 视觉/特效 | 外观、VFX、LOD 完全客户端侧 |

---

## 2. ECS 数据结构

```
Vehicle Entity (scene_server ECS)
├── Transform              — 位置旋转（由驾驶员客户端提交）
├── TrafficVehicleComp     — VehicleCfgId, 颜色, TouchedStamp, IsTrafficSystem, NeedAutoVanish
└── VehicleStatusComp      — SeatList, DoorList, HornList, IsLock, DriverId

Player Entity
├── PersonStatusComp       — DriveVehicleId, DriveVehicleSeat, CanOnVehicle()
└── PlayerVehicleComp      — 个人载具库存（持久化 MongoDB）
```

### TrafficVehicleComp

| 字段 | 类型 | 说明 |
|------|------|------|
| VehicleCfgId | int | 载具配置 ID |
| ColorList | []int | 颜色配置列表 |
| TouchedStamp | int64 | 最后被玩家触碰的时间戳 |
| IsTrafficSystem | bool | 是否为交通系统 NPC 车辆 |
| NeedAutoVanish | bool | 是否启用自动消失 |

### VehicleStatusComp

| 字段 | 类型 | 说明 |
|------|------|------|
| SeatList | []SeatInfo | 座位列表（索引 0=驾驶席） |
| DoorList | []DoorInfo | 车门状态列表 |
| ActiveCarHornList | []HornInfo | 正在鸣笛的座位列表 |
| IsLock | bool | 车辆锁定状态 |
| DriverId | uint64 | 当前驾驶员实体 ID |

### PlayerVehicleComp（玩家侧）

| 字段 | 说明 |
|------|------|
| PesonVehicleList | 玩家拥有的载具列表 |
| NowEntity | 当前场景中的载具实体 ID（0=未生成） |

---

## 3. 网络协议

### 客户端 → 服务器

| 协议 | 功能 | 频率 | 验证项 |
|------|------|------|--------|
| `OnTrafficVehicle` | 生成交通载具 | 低频 | 场景类型（City/Sakura） |
| `OnVehicle` | 上车 | 低频 | 座位可用、车辆未锁、场景类型 |
| `OffVehicle` | 下车 | 低频 | 无严格校验（容错） |
| `DriveVehicle` | 提交驾驶位置 | **每帧** | 驾驶员身份 |
| `OpenVehicleDoor` | 开门 | 低频 | 门索引、操作者位置、NPC 控制权 |
| `CloseVehicleDoor` | 关门 | 低频 | 同上 |
| `StartCarHorn` | 按喇叭 | 低频 | 操作者在座位上 |
| `StopCarHorn` | 停止喇叭 | 低频 | 操作者在座位上 |
| `PullFromVehicle` | 强制弹出乘客 | 低频 | 操作者位置（车内/车外） |

### 服务器 → 客户端

- **dirty flag 广播**: Transform + VehicleBaseInfo + VehicleStatus
- **ForceOffVehicle 事件**: 乘客被弹出时广播（含 from/to 座位、内/外指示）
- **SnapshotMgr 缓存**: Transform 通过快照管理器分发

---

## 4. 载具生命周期

### 生成流程 (vehicle_spawn.go)

```
客户端请求 OnTrafficVehicle(cfgId, location, rotation, colors)
  → 服务器验证场景类型
  → 创建 ECS Entity
  → 挂载 Transform + TrafficVehicleComp + VehicleStatusComp
  → 从 CfgVehicleBase 读取默认座位数初始化 SeatList
  → 返回实体 ID 给客户端
```

### 回收流程 (traffic_vehicle_system.go)

```
traffic_vehicle_system 每帧 Tick
  → 遍历所有 TrafficVehicleComp
  → 条件: NeedAutoVanish=true && 无人乘坐 && 距上次触碰 > 10s
  → 销毁 ECS Entity
```

### 网络更新 (net_update/vehicle.go)

```
每帧检查 dirty flag
  → Transform 变化 → 推送位置旋转
  → VehicleBaseInfo 变化 → 推送配置信息
  → VehicleStatus 变化 → 推送座位/门/喇叭/锁状态
```

---

## 5. 座位与乘员管理

### 上车流程 (OnVehicle)

```
客户端请求 OnVehicle(vehicleEntityId, seatIndex)
  → 验证: 场景类型、载具存在、未锁定
  → 检查目标座位是否为空
  → 如果目标座位有人 → 交换（弹出原乘客）
  → 更新 VehicleStatusComp.SeatList[seatIndex]
  → 更新玩家 PersonStatusComp (DriveVehicleId, DriveVehicleSeat)
  → 标记 dirty → 广播
```

### 下车流程 (OffVehicle)

```
客户端请求 OffVehicle
  → 清空座位 SeatList 中该玩家
  → 清空玩家 PersonStatusComp 载具相关字段
  → 容错: 玩家不在车上也返回成功
```

### 强制弹出 (PullFromVehicle)

```
客户端请求 PullFromVehicle(vehicleId, seatIndex)
  → 验证操作者位置（车内/车外）
  → 弹出目标座位乘客
  → 广播 ForceOffVehicle 事件
```

### 驾驶同步 (DriveVehicle)

```
客户端每帧提交 DriveVehicle(position, rotation)
  → 验证: 调用者 == 驾驶员
  → 更新载具 Transform
  → 同步所有乘客 Transform = 载具 Transform
  → 刷新 TouchedStamp（防止自动回收）
```

---

## 6. 交通载具系统

服务器端交通载具（NPC 车辆）的管理：

| 特性 | 说明 |
|------|------|
| 标识 | `IsTrafficSystem=true` |
| 生成 | 客户端请求，服务器创建 ECS 实体 |
| 回收 | 自动：无人乘坐 + 10s 未触碰 → 销毁 |
| 占用保护 | 有乘客时不会被自动回收 |
| 场景限制 | 仅 City/Sakura 世界允许 |
| 不持久化 | 不写入 PlayerVehicleComp，不关联 NowEntity |

---

## 7. 持久化与商业

### 车辆所有权（MongoDB）

- `PlayerVehicleComp` 存储在玩家 Role 文档中
- `PesonVehicle` 结构: id, name, desc, icon 等元数据
- `NowEntity` 关联当前场景实体（0=未生成）

### 商店/租赁（配置驱动）

| 配置 | 说明 |
|------|------|
| `CfgVehicleShop` | 载具商店条目 |
| `CfgVehicleShopRefreshGroup` | 商店刷新组 |
| `CfgVehicleRent` | 租赁列表 + 价格 |
| `CfgVehicleProduct` | 载具制造/生产 |

---

## 8. 关键文件索引

### ECS 组件

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/ecs/com/cvehicle/traffic_vehicle.go` | TrafficVehicleComp 定义 |
| `servers/scene_server/internal/ecs/com/cvehicle/vehicle_status.go` | VehicleStatusComp 定义 |
| `servers/scene_server/internal/ecs/com/cplayer/player_vehicle.go` | 玩家载具库存组件 |
| `servers/scene_server/internal/ecs/com/define/vehicle_entity.go` | 载具实体定义 |
| `servers/scene_server/internal/ecs/com/define/interface/ciplayer/ivehicle.go` | 载具接口 |

### 生命周期与系统

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/ecs/spawn/vehicle_spawn.go` | 载具生成 |
| `servers/scene_server/internal/ecs/system/traffic_vehicle/traffic_vehicle_system.go` | 交通载具 Tick（自动回收） |
| `servers/scene_server/internal/ecs/system/net_update/vehicle.go` | 网络更新推送 |

### 网络处理

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/net_func/vehicle/vehicle_ops.go` | 上车/下车/驾驶/弹出 |
| `servers/scene_server/internal/net_func/vehicle/vehicle_door.go` | 车门操作 |
| `servers/scene_server/internal/net_func/vehicle/vehicle_horn.go` | 喇叭操作 |
| `servers/scene_server/internal/net_func/vehicle/traffic_vehicle.go` | 交通载具生成请求 |

### 协议与配置

| 文件 | 说明 |
|------|------|
| `common/proto/vehicle_pb.go` | Protobuf 载具消息定义 |
| `common/config/cfg_vehicle.go` | 载具主配置 |
| `common/config/cfg_vehiclebase.go` | 载具基础属性 |
| `common/config/cfg_vehicleshop.go` | 商店配置 |
| `common/config/cfg_vehiclerent.go` | 租赁配置 |

---

**相关文档**: 客户端载具系统详见 [`client-vehicle.md`](client-vehicle.md)
