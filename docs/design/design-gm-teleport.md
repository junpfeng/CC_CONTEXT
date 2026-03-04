# 传送系统迁移设计方案（Rust → Go）

## 1. 需求回顾

将 Rust 版传送系统完整迁移到 Go 版本。不仅是 GM 命令，而是整个传送机制。

## 2. Rust 传送系统全景

### 2.1 核心函数层级

```
调用者（各入口）
  │
  ├── teleport_player_by_server()         ← 带红名检查 + 客户端通知的包装器
  │     └── teleport_player_to_point_with_rotation()  ← 核心实现
  │           ├── off_vehicle()            ← 下车
  │           ├── clear_self_target_interact()  ← 清除交互
  │           ├── Transform 位置/旋转更新
  │           ├── Movement action 重置
  │           ├── teleport_cache 设置
  │           └── 构建 TeleportToPointNtf
  │
  └── set_entity_location()               ← 通用实体位置调度器
        ├── 如果是 Player → teleport_player_by_server()
        ├── 如果是 AI NPC → 发送 NpcTeleportToPointNtf
        └── 其他 → 直接设 Transform
```

### 2.2 所有入口点

| 入口 | Rust 函数 | 调用的核心函数 | 红名检查 | Flash |
|------|-----------|---------------|---------|-------|
| GM 指令 | `gm.rs "teleport"` | `teleport_player_by_server` | 是 | 否 |
| 配置传送 | `teleport()` handler | `teleport_player_by_server` | 是 | 否 |
| 复活重生 | `player_reborn()` | `teleport_player_to_point_with_rotation` | **否** | 否 |
| 进车库 | `enter_garage()` | `teleport_player_to_point_with_rotation` | **否** | **是** |
| 出车库 | `leave_garage()` | `teleport_player_to_point_with_rotation` | **否** | **是** |
| 寻宝换层 | `treasure_switch_floor()` | `teleport_player_by_server` | 是 | 否 |
| 实体传送 | `teleport_entity()` | `set_entity_location` | 视类型 | 否 |
| 批量实体 | `teleport_entity_patch()` | `set_entity_location` | 视类型 | 否 |
| 传送到警局 | `teleport_to_police_station()` | 未实现 | — | — |

### 2.3 核心行为（teleport_player_to_point_with_rotation）

**执行顺序**：
1. `off_vehicle()` — 强制下车
2. `clear_self_target_interact()` — 清除交互目标
3. `transform.location = new_loc` — 设新位置
4. `transform.rotation = rotation` — 设新旋转
5. `movement.action = Action::default()` — 重置动作为 idle
6. `player_comp.teleport_cache = Some(new_loc)` — 缓存传送目标（阻止传送中 action 处理）
7. 构建 `TeleportToPointNtf`（含完整 PlayerDataUpdate）

### 2.4 teleport_cache 机制

- 传送开始时设为 `Some(target_pos)`
- action handler 检测到 `teleport_cache.is_some()` 时忽略所有 action
- 客户端发 `TeleportFinish` 后清除
- 防止传送途中客户端发来的 action 干扰

## 3. Go 版现状与差距分析

### 3.1 差距总表

| # | 功能 | Go 状态 | 差距说明 |
|---|------|---------|---------|
| 1 | 核心传送 `TeleportPlayerToPoint` | ⚠️ 部分 | 缺 off_vehicle + clear_interaction（TODO 注释） |
| 2 | 配置传送 `Teleport` handler | ✅ 已有 | 功能完整 |
| 3 | 传送完成 `TeleportFinish` | ✅ 已有 | 功能完整 |
| 4 | teleport_cache 阻止 action | ✅ 已有 | action.go:208 已检查 |
| 5 | GM teleport 指令 | ❌ 缺失 | gm.go switch 无 "teleport" case |
| 6 | 复活重生 Reborn | ⚠️ 部分 | 未走 TeleportPlayerToPoint，缺 off_vehicle/cache/action重置 |
| 7 | 进/出车库 | 🔲 Stub | external.go 返回 "not implemented" |
| 8 | 通用实体传送 set_entity_location | ❌ 缺失 | 无统一调度器 |
| 9 | TeleportEntity/Patch | 🔲 Stub | external.go 返回 "not implemented" |
| 10 | NpcTeleportToPointNtf | ❌ 缺失 | Proto 已有，从未构建发送 |

### 3.2 核心传送函数差距明细

**Go `TeleportPlayerToPoint`（teleport.go:142）对标 Rust**：

| 步骤 | Rust | Go | 差距 |
|------|------|-----|------|
| 下车 | `off_vehicle()` | TODO 注释(L176) | **需实现** |
| 清交互 | `clear_self_target_interact()` | TODO 注释(L181) | **需实现** |
| 设位置 | ✅ | ✅ `SetPosition` | 一致 |
| 设旋转 | ✅ | ✅ `SetRotation` | 一致 |
| 设传送标记 | ✅ | ✅ `SvrTeleportFlag` | 一致 |
| 重置动作 | ✅ | ✅ `Action{}` | 一致 |
| 设 cache | ✅ | ✅ `TeleportCache` | 一致 |
| 构建 Ntf | 9 组件 | 5 组件 + TODO | EquipComp/PersonInteract 为 TODO |

### 3.3 Reborn 差距明细

**Go `Reborn`（reborn.go:28）对标 Rust `player_reborn`**：

| 步骤 | Rust | Go | 差距 |
|------|------|-----|------|
| 检查死亡 | ✅ | ✅ `IsDead()` | 一致 |
| 设存活 | ✅ | ✅ `SetAlive()` | 一致 |
| 获取重生点 | ✅ | ✅ `GetRebornPoint()` | 一致 |
| 重置 PersonStatus | `re_init()` | ❌ 缺失 | **需添加** |
| 恢复血量 | `modify_attribute(health=100%)` | ❌ 缺失 | **需添加**（GAS 系统依赖） |
| 下车 | 通过核心函数 | ❌ 缺失 | **应调用 TeleportPlayerToPoint** |
| 清交互 | 通过核心函数 | ❌ 缺失 | 同上 |
| 设 cache | 通过核心函数 | ❌ 缺失 | 同上 |
| 重置动作 | 通过核心函数 | ❌ 缺失 | 同上 |
| 构建完整 Ntf | 通过核心函数 | 用 `GetPlayerMsg` | 路径不同但功能等价 |

## 4. 迁移设计方案

### 4.1 分层设计

按优先级分 3 层迁移：

**第一层：修复核心传送函数（基础）**
> 所有上层功能都依赖核心函数的正确性

**第二层：新增入口点（功能）**
> GM 指令、实体传送等

**第三层：修复已有入口（增强）**
> Reborn 对齐 Rust 行为

### 4.2 第一层：修复 TeleportPlayerToPoint

**文件**：`net_func/player/teleport.go`

#### 4.2.1 实现 off_vehicle（替换 L176-179 TODO）

传送前，如果玩家在载具上，强制下车。

**Go 现状**：无可直接复用的 off_vehicle 工具函数。`vehicle_ops.go` 中的 `OffVehicle()` 是 RPC handler，与传送场景不完全匹配（包含请求校验等）。需手动组合底层方法。

**完整操作链**（对标 Rust `off_vehicle()` + Go `vehicle_ops.go:99-137`）：

```go
// 检查玩家是否在载具上，如果是则强制下车
personStatusComp, _ := common.GetComponentAs[*cperson.PersonStatusComp](s, entityId, common.ComponentType_PersonStatus)
if personStatusComp != nil && personStatusComp.DriveVehicleId != 0 {
    vehicleEntity, ok := s.GetEntity(personStatusComp.DriveVehicleId)
    if ok {
        // 1. 从载具座位列表移除乘客
        vehicleStatusComp, ok := vehicleEntity.GetComponent(common.ComponentType_VehicleStatus).(*cvehicle.VehicleStatusComp)
        if ok && vehicleStatusComp != nil {
            vehicleStatusComp.PassengerLeave(entityId)
        }

        // 2. 更新载具触碰时间戳（防止载具被过早回收）
        trafficComp, ok := vehicleEntity.GetComponent(common.ComponentType_TrafficVehicle).(*cvehicle.TrafficVehicleComp)
        if ok && trafficComp != nil {
            trafficComp.UpdateTouchedStamp(mtime.NowSecondTickWithOffset())
        }
    } else {
        // 载具实体已不存在，仅清理人物状态
        log.Warningf("TeleportPlayerToPoint: vehicle entity %d not found, clearing person status only, entityID=%d",
            personStatusComp.DriveVehicleId, entityId)
    }
    // 3. 清除人物的载具关联状态（DriveVehicleId + DriveVehicleSeat + SetSync）
    personStatusComp.OffVehicle()
}
```

**与 Rust 的差异说明**：
- Rust 版还处理了 VehicleWeaponComp 和 DriverIcon 通知，Go 版载具武器系统仅有 Proto 定义无实际实现，暂不处理
- Rust 版触发了 ForceOffVehicle 事件，传送场景的强制下车是服务器内部操作，不需要事件通知，暂不触发

参考：`vehicle_ops.go:99-137` OffVehicle handler 的完整流程。

#### 4.2.2 实现 clear_interaction（替换 L181-210 TODO）

传送前，清除交互目标状态。**必须双向清理**：清除自己的交互引用 + 通知对端移除自己。

**Go 现状**：无现成的双向清理函数。参考模式：`net_func/object/interact.go` 的 `StopInteract`（L96-106）。

**完整实现**（对标 Rust `clear_self_target_interact()`）：

```go
// 清除交互状态（双向清理）
personInteractComp, ok := common.GetComponentAs[*cinteraction.PersonInteractionComp](
    s, entityId, common.ComponentType_PersonInteraction)
if ok && personInteractComp != nil && personInteractComp.TargetEntity != 0 {
    targetEntityId := personInteractComp.TargetEntity

    // 1. 清除目标侧对自己的引用
    targetEntity, targetOk := s.GetEntity(targetEntityId)
    if targetOk {
        // 目标是场景物件（交互点列表）
        objInteractComp, objOk := common.GetEntityComponentAs[*cinteraction.SceneObjectInteractComp](
            targetEntity, common.ComponentType_ObjInteract)
        if objOk && objInteractComp != nil {
            for _, point := range objInteractComp.InteractPointList {
                if point.OccupyEntity == entityId {
                    point.OccupyEntity = 0
                    point.InteractStatus = 0
                }
            }
            objInteractComp.SetSync()
        }

        // 目标是 NPC/玩家（PersonInteractionComp）
        targetPersonInteract, personOk := common.GetEntityComponentAs[*cinteraction.PersonInteractionComp](
            targetEntity, common.ComponentType_PersonInteraction)
        if personOk && targetPersonInteract != nil && targetPersonInteract.TargetEntity == entityId {
            targetPersonInteract.TargetEntity = 0
            targetPersonInteract.NoActionType = 0
            targetPersonInteract.SetSync()
        }
    }

    // 2. 清除自己侧的交互状态
    personInteractComp.TargetEntity = 0
    personInteractComp.NoActionType = 0
    personInteractComp.SetSync()
}
```

**关键点**：
- 先清对端再清自己，避免先清自己后找不到 targetEntityId
- 目标实体可能已不存在（被销毁），此时仅清本地即可
- Object 和 Person 两种目标类型都需处理
- 每侧清理后都必须 `SetSync()` 标记脏数据同步

#### 4.2.3 涉及文件

| 文件 | 改动 |
|------|------|
| `net_func/player/teleport.go` | 替换 TODO 为实际实现 |

新增 import：`cperson`、`cvehicle`、`cinteraction` 组件包、`mtime`（时间戳）、`log`（日志）。

### 4.3 第二层：新增 GM teleport 指令

**文件**：`net_func/gm/gm.go` + `net_func/gm/town.go`

#### 4.3.1 命令格式

```
/ke* gm teleport <x> <y> <z>
```

与 Go 版其他 GM 命令保持空格分隔惯例。

#### 4.3.2 handleTeleportGM 函数

```go
func handleTeleportGM(
    s common.Scene,
    params []string,
    playerEntity common.Entity,
    playerInfo *resource.PlayerInfo,
) (*proto.NullRes, *proto_code.RpcError)
```

执行步骤：
1. 校验 `len(params) >= 3`
2. 解析 x, y, z（复用 `set_npc_pos` 的 parseFloat 模式）
3. 调用 `player.TeleportPlayerToPoint(s, playerEntity, pos, Vec3{}, false)`
4. 发送 `TeleportToPointNtf` 给客户端
5. 返回成功

**红名检查说明（有意偏离 Rust 行为）**：Go 版 GM teleport 直接调用 `TeleportPlayerToPoint`，跳过红名检查。Rust 版 GM 调用 `teleport_player_by_server` 会经过红名检查——如果 GM 操作者恰好处于红名状态，Rust 版会拒绝传送。Go 版的设计是有意改进：GM 命令不应受红名限制。Go 版红名检查仅在 `Teleport()` 配置传送 handler 中执行，与 GM 无关。

#### 4.3.3 gm.go switch 新增

```go
case "teleport":
    return handleTeleportGM(h.scene, parts[1:], h.playerEntity, playerInfo)
```

### 4.4 第二层：新增 SetEntityLocation 通用调度器

**新增文件**：`net_func/player/entity_teleport.go`

Rust 的 `set_entity_location` 是通用实体位置设置器，按实体类型分派：

```go
func SetEntityLocation(s common.Scene, entityId uint64, position, rotation trans.Vec3, needFlash bool) {
    entity, ok := s.GetEntity(entityId)
    if !ok {
        log.Warningf("SetEntityLocation: entity %d not found", entityId)
        return
    }

    // 1. 如果是玩家 → 走玩家传送流程
    playerComp, ok := common.GetComponentAs[*com.PlayerComp](s, entityId, common.ComponentType_PlayerBase)
    if ok && playerComp != nil {
        ntf, err := TeleportPlayerToPoint(s, entity, position, rotation, needFlash)
        if err != nil {
            log.Warningf("SetEntityLocation: TeleportPlayerToPoint failed, entityID=%d, err=%v", entityId, err)
            return
        }
        sendTeleportNtfToClient(s, playerComp.AccountId, ntf)
        return
    }

    // 2. 如果是 AI NPC → 发 NpcTeleportToPointNtf
    // （根据实际需要后续补充）

    // 3. 其他实体 → 直接设 Transform
    transformComp, ok := common.GetComponentAs[*com.Transform](s, entityId, common.ComponentType_Transform)
    if ok && transformComp != nil {
        transformComp.SetPosition(position.X, position.Y, position.Z)
        transformComp.SetRotation(rotation.X, rotation.Y, rotation.Z)
        transformComp.SetSync()
    } else {
        log.Warningf("SetEntityLocation: transform comp not found, entityID=%d", entityId)
    }
}
```

#### 4.4.1 提取 sendTeleportNtfToClient

从 `Teleport()` handler（teleport.go:63-77）提取客户端通知逻辑为独立函数，供 GM teleport 和 SetEntityLocation 复用：

```go
func sendTeleportNtfToClient(s common.Scene, accountId uint64, ntf *proto.TeleportToPointNtf) {
    playerMgr, ok := common.GetResourceAs[*resource.PlayerManager](s, common.ResourceType_PlayerManager)
    if !ok || playerMgr == nil {
        log.Warningf("sendTeleportNtfToClient: playerMgr not found, accountId=%d", accountId)
        return
    }
    playerInfo := playerMgr.GetPlayerInfo(accountId)
    if playerInfo == nil || playerInfo.GatewayInfo == nil {
        log.Warningf("sendTeleportNtfToClient: playerInfo or gatewayInfo nil, accountId=%d", accountId)
        return
    }
    session := s.GetProxyEntry().GetProxy()
    if session == nil {
        log.Warningf("sendTeleportNtfToClient: proxy session nil, accountId=%d", accountId)
        return
    }
    client := proto.NewSceneServer(session)
    client.TeleportToPointNtf(ntf, &rpc.MsgTypeServerToClient{
        AccountId:     accountId,
        GatewayUnique: playerInfo.GatewayInfo.ServerUnique,
    })
}
```

### 4.5 第二层：实现 TeleportEntity / TeleportEntityPatch

**文件**：`net_func/temp/external.go` → 移到新文件或就地实现

```go
func (h *TempExternalHandler) TeleportEntity(req *proto.TeleportEntityReq) {
    position := trans.Vec3{X: req.Position.X, Y: req.Position.Y, Z: req.Position.Z}
    rotation := trans.Vec3{}
    if req.Rotation != nil {
        rotation = trans.Vec3{X: req.Rotation.X, Y: req.Rotation.Y, Z: req.Rotation.Z}
    }
    player.SetEntityLocation(h.scene, req.EntityId, position, rotation, false)
}

func (h *TempExternalHandler) TeleportEntityPatch(req *proto.TeleportEntityPatchReq) {
    for _, r := range req.ReqList {
        position := trans.Vec3{X: r.Position.X, Y: r.Position.Y, Z: r.Position.Z}
        rotation := trans.Vec3{}
        if r.Rotation != nil {
            rotation = trans.Vec3{X: r.Rotation.X, Y: r.Rotation.Y, Z: r.Rotation.Z}
        }
        player.SetEntityLocation(h.scene, r.EntityId, position, rotation, false)
    }
}
```

### 4.6 第三层：修复 Reborn 对齐 Rust

**文件**：`net_func/ui/reborn.go`

当前 Reborn 直接操作 Transform 而不走 `TeleportPlayerToPoint`，导致缺失：
- off_vehicle
- clear_interaction
- teleport_cache 设置
- Movement action 重置

**修复方案**：Reborn 改为调用 `TeleportPlayerToPoint`：

```go
func (h *UIHandler) Reborn(req *proto.RebornReq) (*proto.TeleportToPointNtf, *proto_code.RpcError) {
    // ... 前置检查不变 ...
    baseStatusComp.SetAlive()

    // 获取重生点
    spawnPointMgr, ok := common.GetResourceAs[*spawnpoint.SpawnPointManager](h.scene, common.ResourceType_SpawnPointManager)
    if !ok || spawnPointMgr == nil {
        return nil, proto_code.NewErrorMsg("Reborn: spawn point manager not found")
    }
    rebornPos, rebornRot := spawnPointMgr.GetRebornPoint()

    // 调用核心传送函数（含 off_vehicle + clear_interact + cache + action 重置）
    ntf, rpcErr := player.TeleportPlayerToPoint(h.scene, h.playerEntity, rebornPos, rebornRot, false)
    if rpcErr != nil {
        return nil, rpcErr
    }
    return ntf, nil
}
```

**注意事项**：
- Rust 的 reborn 还包含 `re_init()` PersonStatus 和恢复血量（GAS 系统），但 Go 版 GAS 系统尚未迁移，这两步暂不实现，保持现状
- `RebornReq.Position` 字段：Proto 定义了 position 字段供客户端指定偏好重生点，Rust 版通过 `get_respawn_point(world, entity, sel_position)` 支持位置偏好选择。Go 版 `SpawnPointManager.GetRebornPoint()` 不接受位置参数（纯随机选择），当前 Go 实现也完全忽略 req.Position。本次迁移保持现状（忽略 req.Position），位置偏好重生作为后续优化项

## 5. 涉及文件总表

| 文件 | 改动类型 | 内容 |
|------|---------|------|
| `net_func/player/teleport.go` | **修改** | 实现 off_vehicle + clear_interaction；提取 sendTeleportNtfToClient |
| `net_func/player/entity_teleport.go` | **新增** | SetEntityLocation 通用调度器 |
| `net_func/gm/gm.go` | **修改** | switch 新增 `case "teleport"` |
| `net_func/gm/town.go` | **修改** | 新增 handleTeleportGM |
| `net_func/temp/external.go` | **修改** | TeleportEntity/TeleportEntityPatch 从 stub 改为实际实现 |
| `net_func/ui/reborn.go` | **修改** | 改为调用 TeleportPlayerToPoint |

**不涉及**：协议工程（Proto 已全部定义）、配置工程、DB。

## 6. 暂不迁移的功能

以下 Rust 功能因依赖系统在 Go 中尚未实现，本次暂不迁移：

| 功能 | 原因 | 当前处理 |
|------|------|---------|
| 进/出车库 (EnterGarage/ReturnPossession) | 依赖 Possession 场景系统（未迁移） | 保留 stub |
| 寻宝换层 (TreasureSwitchFloor) | 依赖寻宝玩法系统（未迁移） | 保留 stub |
| 传送到警局 (TeleportToPoliceStation) | Rust 版本也未实现 | 保留 stub |
| 传送到最近重生点 (TeleportToNearestRebornPoint) | 与 Reborn 功能重叠 | 保留 stub |
| Reborn 恢复血量 | 依赖 GAS 属性系统（未迁移） | 暂不添加 |
| Reborn PersonStatus.ReInit | 依赖 PersonStatus 完整初始化（未确认） | 暂不添加 |
| NPC 传送通知 (NpcTeleportToPointNtf) | 暂无 NPC 传送需求 | SetEntityLocation 预留分支 |

## 7. 风险评估

| 风险 | 级别 | 缓解措施 |
|------|------|---------|
| off_vehicle：Go 版无 VehicleWeaponComp 实现，跳过了武器组件清理 | 低 | Go 版载具武器仅有 Proto 定义无实际逻辑，暂无影响 |
| off_vehicle：传送场景未触发 ForceOffVehicle 事件 | 低 | 传送是服务器内部操作，不需要事件通知外部系统；如后续有系统依赖此事件可补充 |
| clear_interaction：双向清理可能遗漏某些交互类型 | 中 | 已覆盖 Object（InteractPointList）和 Person（PersonInteractionComp）两种类型，与 Rust 对齐；目标实体不存在时仅清本地 |
| Reborn 改为走 TeleportPlayerToPoint 可能引入行为变化 | 低 | 新增了 off_vehicle、clear_interaction、teleport_cache、action 重置，都是 Rust 版应有的正确行为 |
| Reborn 忽略 req.Position | 低 | Go 版 SpawnPointManager 不支持位置偏好选择，与当前 Go 行为一致，后续可扩展 |
| GM teleport 跳过红名检查（与 Rust 行为差异） | 低 | 有意改进：GM 命令不应受红名限制，已在文档中明确标注 |
| TeleportEntity 从 stub 改为实际实现，外部调用者可能有预期差异 | 低 | 与 Rust 行为完全对齐 |

## 8. 与 Rust 的有意行为差异

| 差异点 | Rust 行为 | Go 行为（本次设计） | 原因 |
|--------|-----------|-------------------|------|
| GM 红名检查 | GM teleport 经过红名检查，红名状态拒绝传送 | GM teleport 跳过红名检查 | GM 命令不应受限 |
| off_vehicle 武器组件 | 清理 VehicleWeaponComp | 跳过 | Go 版无实际实现 |
| off_vehicle 事件触发 | 触发 SpecifyUnitGetOffVehicle + UnitGetOffVehicle | 不触发 | 传送是内部操作 |
| Reborn 位置偏好 | 支持客户端指定偏好位置 | 忽略，纯随机 | SpawnPointManager 不支持位置参数 |
| Reborn PersonStatus.ReInit | 执行 | 跳过 | GAS 系统未迁移 |
| Reborn 恢复血量 | 执行 modify_attribute(health=100%) | 跳过 | GAS 系统未迁移 |
