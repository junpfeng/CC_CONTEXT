# 设计文档：载具车门开关协议

## 1. 需求回顾

在 P1GoServer 的 City/Sakura 场景下实现 `OpenVehicleDoorReq`（Cmd 1145）和 `CloseVehicleDoorReq`（Cmd 1144），参考 Rust 遗留工程逻辑。

## 2. 现有基础设施

| 组件 | 状态 | 位置 |
|------|------|------|
| Proto 消息 `OpenVehicleDoorReq` / `CloseVehicleDoorReq` | 已存在 | `common/proto/scene_pb.go` |
| Proto 枚举 `VehicleDoorStatus` (Close=0, Open=1, Damage=3) | 已存在 | `common/proto/scene_pb.go:165` |
| Proto 消息 `VehicleDoorInfo` (DoorIndex + Status) | 已存在 | `common/proto/scene_pb.go:73863` |
| Proto 消息 `VehicleStatus.DoorList` | 已存在 | `common/proto/scene_pb.go:75563` |
| 消息路由 SceneCellHandler | 已存在 | `common/proto/scene_service.go` (自动生成) |
| Handler 占位 | stub | `net_func/temp/external.go:299-307` |
| `VehicleHandler` 结构 | 已存在 | `net_func/vehicle/traffic_vehicle.go:11` |
| `VehicleStatusComp` | **缺少 DoorList** | `ecs/com/cvehicle/vehicle_status.go` |

## 3. 架构设计

### 3.1 请求处理流程

```
Client → SceneCellHandler(Cmd 1144/1145) → NetCallSceneMsg → Scene
  → TempExternalHandler.OpenVehicleDoor / CloseVehicleDoor
    → VehicleHandler.OpenVehicleDoor / CloseVehicleDoor
      → handleVehicleDoor(共享验证逻辑)
        → VehicleStatusComp.SetDoorStatus(doorIndex, status)
        → SetSync() 触发客户端同步
  → 返回 NullRes
```

### 3.2 场景限制

与 `OnVehicle` 一致，仅 City / Sakura 场景支持：
```go
switch h.scene.SceneType().(type) {
case *common.CitySceneInfo:
case *common.SakuraSceneInfo:
default:
    return error
}
```

## 4. 详细设计

### 4.1 扩展 VehicleStatusComp（组件层）

**文件**: `ecs/com/cvehicle/vehicle_status.go`

新增数据结构：
```go
type VehicleDoor struct {
    Index  int32
    Status proto.VehicleDoorStatus
}
```

新增字段：
```go
type VehicleStatusComp struct {
    // ... 现有字段
    DoorList []VehicleDoor
}
```

新增方法：
```go
// SetDoorStatus 设置车门状态
// 动态管理：门不存在时创建条目，状态相同时跳过
func (c *VehicleStatusComp) SetDoorStatus(doorIndex int32, status proto.VehicleDoorStatus)

// GetDoorStatus 获取车门状态，门不存在返回 Close
func (c *VehicleStatusComp) GetDoorStatus(doorIndex int32) proto.VehicleDoorStatus
```

更新 `ToProto()`：填充 `DoorList` 字段到 `proto.VehicleStatus`。

**设计决策 - 动态门管理**：Rust 代码从配置预填充门列表，Go 侧无门数量配置。采用动态策略：首次 SetDoorStatus 时创建条目。好处是不依赖配置，坏处是未操作过的门不会出现在同步数据中（状态默认 Close，不影响客户端）。

### 4.2 Handler 实现（业务层）

**新文件**: `net_func/vehicle/vehicle_door.go`

```go
// OpenVehicleDoor 处理开门请求
func (h *VehicleHandler) OpenVehicleDoor(req *proto.OpenVehicleDoorReq, playerEntity common.Entity) (*proto.NullRes, *proto_code.RpcError)

// CloseVehicleDoor 处理关门请求
func (h *VehicleHandler) CloseVehicleDoor(req *proto.CloseVehicleDoorReq, playerEntity common.Entity) (*proto.NullRes, *proto_code.RpcError)

// handleVehicleDoor 共享验证+执行逻辑（私有）
func (h *VehicleHandler) handleVehicleDoor(vehicleEntityID uint64, doorIndex int32, selfEntityID uint64, status proto.VehicleDoorStatus, playerEntity common.Entity) (*proto.NullRes, *proto_code.RpcError)
```

### 4.3 handleVehicleDoor 核心逻辑

```
1. 场景类型检查（City/Sakura）

2. 确定操作者 masterEntity：
   - selfEntityID == 0 || selfEntityID == playerEntity.ID()
     → masterEntity = playerEntity（玩家自己操作）
   - selfEntityID != playerEntity.ID()
     → masterEntity = scene.GetEntity(selfEntityID)
     → 验证 AI 控制权限（见 4.4）

3. 验证操作者驾驶状态（参考 Rust 逻辑）：
   - 获取 masterEntity 的 PersonStatusComp
   - 如果 masterEntity 在某辆车上（DriveVehicleId != 0）：
     - 必须在目标载具上（DriveVehicleId == vehicleEntityID）
     - 否则返回错误 "already on other vehicle"

4. 获取载具实体 + VehicleStatusComp

5. 调用 SetDoorStatus(doorIndex, status)

6. 返回 NullRes
```

### 4.4 AI 控制权限检查

当 `selfEntityID` 不是玩家自身时，需验证玩家对该 NPC 有控制权：

```go
func (h *VehicleHandler) checkAiControl(playerEntity common.Entity, npcEntityID uint64) bool {
    // 获取 NPC 实体
    npcEntity, ok := h.scene.GetEntity(npcEntityID)
    if !ok { return false }

    // 获取 SakuraNpcControlComp（Sakura 场景控制组件）
    controlComp, ok := common.GetComponentAs[*csakura.SakuraNpcControlComp](
        h.scene, npcEntity.ID(), common.ComponentType_SakuraNpcControl)
    if !ok || !controlComp.IsControlled() { return false }

    // 获取玩家 RoleId
    playerComp, ok := common.GetComponentAs[*cplayer.PlayerComp](
        h.scene, playerEntity.ID(), common.ComponentType_PlayerBase)
    if !ok { return false }

    // 验证控制者是当前玩家
    return controlComp.GetControlRoleId() == playerComp.RoleId
}
```

### 4.5 TempExternalHandler 接入

**文件**: `net_func/temp/external.go`

将 stub 替换为委托调用（与 OnVehicle/OffVehicle 模式一致）：

```go
func (h *TempExternalHandler) OpenVehicleDoor(req *proto.OpenVehicleDoorReq) (*proto.NullRes, *proto_code.RpcError) {
    vehicleHandler := vehicle.NewVehicleHandler(h.scene, h.ctx)
    return vehicleHandler.OpenVehicleDoor(req, h.playerEntity)
}

func (h *TempExternalHandler) CloseVehicleDoor(req *proto.CloseVehicleDoorReq) (*proto.NullRes, *proto_code.RpcError) {
    vehicleHandler := vehicle.NewVehicleHandler(h.scene, h.ctx)
    return vehicleHandler.CloseVehicleDoor(req, h.playerEntity)
}
```

## 5. 文件改动清单

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `ecs/com/cvehicle/vehicle_status.go` | 修改 | 新增 VehicleDoor 结构、DoorList 字段、SetDoorStatus/GetDoorStatus 方法、更新 ToProto |
| `net_func/vehicle/vehicle_door.go` | **新增** | OpenVehicleDoor/CloseVehicleDoor/handleVehicleDoor/checkAiControl |
| `net_func/temp/external.go` | 修改 | OpenVehicleDoor/CloseVehicleDoor 从 stub 改为委托 VehicleHandler |

## 6. 与 Rust 实现的差异

| 项目 | Rust | Go（本设计） |
|------|------|-------------|
| 门列表管理 | 预填充，门不存在时静默返回 | 动态创建，首次操作时创建条目 |
| AI 控制检查 | `check_is_ai_control` 通用函数 | `checkAiControl` 基于 SakuraNpcControlComp |
| 驾驶座位检查 | 检查 door_index == drive_vehicle_seat | 仅检查是否在目标载具（简化，座位-门对应关系由客户端保证） |
| 同步方式 | is_dirty 标记 | SetSync() 标记 |

**关于座位-门对应检查的简化说明**：Rust 代码检查 `door_index != person_status.drive_vehicle_seat`，但这个逻辑看起来是限制"只能操作自己座位对应的门"。这个限制过于严格（乘客应能操作自己那侧的门），且客户端已有这个约束。Go 侧简化为只检查"是否在目标载具上"。

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| 无门数量配置 | 客户端发任意 doorIndex 都会创建条目 | 门状态仅为 int32→status 映射，内存开销极小；且客户端有模型约束不会发无效索引 |
| City 场景无 SakuraNpcControlComp | AI 控制检查在非 Sakura 场景会失败 | checkAiControl 做了安全检查，GetComponentAs 返回 false 时直接拒绝，不会 panic |
