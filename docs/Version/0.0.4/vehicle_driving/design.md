# 玩家自由驾驶车辆 — 技术设计

## 1. 需求回顾

| REQ | 标题 | 优先级 | 端 |
|-----|------|--------|-----|
| 001 | 交通车辆征用交互提示 | P0 | C |
| 002 | 征用上车流程 | P0 | C+S |
| 003 | 控制权切换（AI→玩家） | P0 | C |
| 004 | 物理驾驶操控 | P0 | C+S |
| 005 | 相机切换 | P0 | C |
| 006 | 下车流程 | P0 | C+S |
| 007 | 车辆距离回收 | P1 | C+S |

## 2. 架构设计

### 2.1 系统边界

**核心发现：绝大部分机制已存在，主要工作是串联流程而非新建系统。**

| 模块 | 状态 | 改动 |
|------|------|------|
| InteractSurfVehicleComp | 已有交互 FSM | 扩展：交通车辆触发条件 |
| PlayerGetOnVehicleComp | 已有上车检测 | 扩展：支持交通车辆征用 |
| GetOnCarState/DrivingCarState | 已有驾驶状态机 | 基本复用，微调 |
| Vehicle.OnTrafficControlChanged | 已有控制权切换 | 复用：征用时调用 |
| DriverGetOffCarState | 已有下车流程 | 基本复用 |
| CameraManager | 已有 VehicleMode | 复用 |
| vehicle_ops.go | 已有 On/Off/Pull/Drive | 扩展：交通车辆征用支持 |
| TrafficVehicleComp | 已有交通标记 | 新增：回收定时器 |

### 2.2 核心流程（时序）

```
[玩家靠近交通车辆]
  Client: PlayerGetOnVehicleComp.OnUpdate 检测附近车辆（含交通车辆）
  Client: InteractSurfVehicleComp → ShowTips 状态，显示征用提示

[玩家按键征用]
  Client: → PullFromVehicleReq（如有NPC驾驶员）+ OnVehicleReq
  Server: PullFromVehicle → 移除NPC乘客 → OnVehicle → 玩家占座
  Server: TrafficVehicleComp.IsPlayerCommandeered = true（标记脱离交通）
  Client: ← OnVehicleRes 成功
  Client: → GetOnCarState.OnEnter()（禁用角色碰撞、同步座椅位置）
  Client: Vehicle.OnTrafficControlChanged(false) → UnregisterVehicle + TurnOnWheelSupport
  Client: → DrivingCarState.OnEnter()（绑定输入、初始化IK）
  Client: CameraManager.SwitchCameraMode(VehicleMode)

[驾驶中]
  Client: InputsComp 采集输入 → WheelCollider 物理驱动
  Client: 每帧/定频 → DriveVehicleReq（位置、旋转、速度、输入）
  Server: DriveVehicle → 更新 Transform + 同步乘客 + 刷新 TouchedStamp

[玩家按键下车]
  Client: → OffVehicleReq
  Server: OffVehicle → 清除玩家驾驶状态 → 启动回收定时器
  Client: ← OffVehicleRes 成功
  Client: → DriverGetOffCarState.OnEnter()（恢复碰撞、相机切回步行）
  Client: 车辆保留在原地（不归还交通系统）

[距离回收]
  Server: 定时轮询（5s间隔）→ 玩家-车辆XZ平方距离 > 150² → scene.RemoveEntity
  Client: ← Entity销毁通知 → 客户端销毁 GameObject
```

### 2.3 车辆状态流转

```
Traffic（AI驾驶）→ [征用] → PlayerDriving（玩家驾驶）→ [下车] → Abandoned（遗弃）→ [距离>150m] → Recycled（回收销毁）
                                                        ↑                              |
                                                        └──── [玩家重新上车] ←──────────┘（距离内可再上车）
```

## 3. 服务端设计

### 3.1 征用流程（vehicle_ops.go）

现有 `PullFromVehicle` + `OnVehicle` 已覆盖基础流程。需补充：

**vehicle_ops.go 扩展**：

**空车直接上车**：客户端检测到交通车辆无驾驶员时，跳过 PullFromVehicle，直接发 OnVehicleReq。

**有人车征用原子性**：在 `OnVehicle` 内部处理征用（而非分两步）：
- `OnVehicle` 增加逻辑：若目标座位有 NPC 乘客，先内部调用座位替换（`ChangePassenger` 已支持），一步完成 NPC 移除+玩家占座
- 客户端不再需要先发 PullFromVehicleReq 再发 OnVehicleReq，统一为单个 OnVehicleReq
- 这避免了两步请求之间的竞态问题

**OnVehicle 中检测 TrafficVehicleComp**：若为交通车辆：
1. 设置 `NeedAutoVanish = false`（**关键**：阻止 TrafficVehicleSystem 的 10 秒自动消失）
2. 标记 `IsPlayerCommandeered = true`
3. 记录 `OwnerPlayerEntityID = playerEntityID`
- 标记后交通系统不再对该车辆下发 AI 指令

### 3.2 驾驶输入处理

现有 `DriveVehicle` 处理已完备（vehicle_ops.go:225-289），无需改动：
- 验证驾驶员身份 → 更新 Transform → 同步乘客 → 刷新 TouchedStamp

### 3.3 车辆回收

**TrafficVehicleComp 扩展**（traffic_vehicle.go）：
```go
// 新增字段
IsPlayerCommandeered    bool      // 是否被玩家征用
AbandonedAt             int64     // 下车时间戳（0=未遗弃）
OwnerPlayerEntityID     uint64    // 征用者 EntityID
LastRecycleCheckAt      int64     // 上次回收检测时间戳（节流用）
```

**复用 TrafficVehicleSystem.Update() 扩展**（traffic_vehicle_system.go）：
在现有 `ShouldVanish` 检查之后，追加征用车辆回收逻辑：
```go
// 已有：ShouldVanish + IsUsing 保护（处理普通交通车辆）

// 新增：征用车辆距离回收
if trafficComp.IsPlayerCommandeered && trafficComp.AbandonedAt > 0 {
    // 每 5 秒检测一次（独立时间戳节流）
    if currentTime - trafficComp.LastRecycleCheckAt < 5 { continue }
    trafficComp.LastRecycleCheckAt = currentTime
    ownerEntity := s.Scene().GetEntity(trafficComp.OwnerPlayerEntityID)
    if ownerEntity == nil {
        // 征用者离线，立即回收
        s.Scene().RemoveEntity(entityID)
        continue
    }
    // XZ 平方距离 > 150²
    dx := vehiclePos.X - ownerPos.X
    dz := vehiclePos.Z - ownerPos.Z
    if dx*dx + dz*dz > 22500 {
        s.Scene().RemoveEntity(entityID)
    }
}
```
不新建 System，复用现有 TrafficVehicleSystem，减少注册和维护成本。

### 3.4 下车时标记遗弃

**vehicle_ops.go OffVehicle 扩展**：
- 下车时检测 `IsPlayerCommandeered`：若为 true，设置 `AbandonedAt = now`
- 重新上车时清除 `AbandonedAt`

## 4. 客户端设计

### 4.1 交互检测与提示

**PlayerGetOnVehicleComp 扩展**：
- 现有 `OnUpdate` 每 0.5s 检测附近车辆 → 需包含交通车辆（检查 `isControlledByTraffic`）
- 交通车辆检测到后发送 `PlayerNearestHasVehicle` 事件

**InteractSurfVehicleComp**：
- 现有 ShowTips FSM 已支持通用车辆提示，无需大改
- 交通车辆提示文本："征用车辆"（区别于自有车辆的"上车"）

### 4.2 控制权切换

**核心方法已存在**：`Vehicle.OnTrafficControlChanged(false)` (Vehicle.cs:794-807)
- 调用 `TrafficManager.Instance.UnregisterVehicle(VehicleTrafficComponent)` — 从 DotsCity 注销
- 调用 `VehicleEngineComp.TurnOnWheelSupport()` — 恢复 WheelCollider 物理
- 设置 `isControlledByTraffic = false`

**触发时机**：在 `GetOnCarState.OnEnter()` 中，检测到目标车辆 `isControlledByTraffic == true` 时调用。

**新增 SwitchToPlayerControl() 封装**（Vehicle.cs）：
```csharp
public void SwitchToPlayerControl()
{
    if (!isControlledByTraffic) return;
    OnTrafficControlChanged(false);  // 已有：注销+物理恢复
    ExternalDisableNetTransform = false;  // 启用网络同步
    rb.isKinematic = false;  // 确保物理启用
}
```

### 4.3 物理驾驶

**已有完整链路**：
- `DrivingCarState.OnEnter()` → 初始化引擎、IK、输入绑定
- `InputsComp` 采集玩家输入 → `VehicleEngineComp` → WheelCollider 驱动
- `VehicleNetTransformComp` 定频上报 `DriveVehicleReq`

无需新增代码，控制权切换后自动工作。

### 4.4 相机切换

**已有完整链路**：
- 上车：`CameraManager.SwitchCameraMode(VehicleMode)` — 在 GetOnCarState 后自动触发
- 驾驶中：支持 V 键切换第一/第三人称（VehicleMode ↔ FirstPersonVehicleMode）
- 下车：`CameraManager.SwitchCameraMode(DefaultPersonMode)` — DriverGetOffCarState.OnEnter():85

无需新增代码。

### 4.5 下车流程

**已有完整链路**：`DriverGetOffCarState`
- `OnEnter()`：`DriverDontControlAnymore()` → 相机切回 → 设置碰撞
- `HandleOffCarRequest()`：发送 `OffVehicleReq`
- `OnExit()`：`ExitCarFinish()` 清理状态

**征用车辆下车后不归还交通系统**：车辆保持 `isControlledByTraffic = false`，等服务端回收。

### 4.6 车辆回收响应

服务端 `RemoveEntity` 后，客户端通过现有 Entity 销毁通知自动处理 GameObject 销毁。无需额外代码。

## 5. 接口契约

### 5.1 协议复用清单

| 消息 | 方向 | 用途 |
|------|------|------|
| PullFromVehicleReq/Res | C→S | 征用（拉NPC下车） |
| OnVehicleReq/Res | C→S | 玩家上车 |
| DriveVehicleReq | C→S | 驾驶中位置/输入上报 |
| OffVehicleReq/Res | C→S | 玩家下车 |
| VehicleInfoUpload | S→C | 车辆状态同步（已有） |

### 5.2 跨工程调用链

**征用上车（统一为单个 OnVehicleReq）**：
```
Client: PlayerGetOnVehicleComp.DetectNearbyVehicle()
  → InteractSurfVehicleComp.ShowTips（空车显示"上车"，有人车显示"征用"）
  → [按键] PlayerInteractWithVehicleComp.OnGetOnVehicle()
  → NetCmd.OnVehicle(req) → [Proto] → Server: VehicleHandler.OnVehicle()
    → 若座位有NPC：ChangePassenger 内部替换（原子性，NPC移除+玩家占座）
    → 若空车：直接占座
    → 检测 TrafficVehicleComp → NeedAutoVanish=false, IsPlayerCommandeered=true
  → Client: GetOnCarState.OnEnter() → Vehicle.SwitchToPlayerControl()
  → DrivingCarState.OnEnter() → CameraManager.SwitchCameraMode(VehicleMode)
```

**下车回收**：
```
Client: [按键] DriverGetOffCarState.HandleOffCarRequest()
  → NetCmd.OffVehicle(req) → [Proto] → Server: VehicleHandler.OffVehicle()
    → TrafficVehicleComp.AbandonedAt = now
  → Client: DriverGetOffCarState.OnEnter() → CameraManager.SwitchCameraMode(DefaultPersonMode)
  → Server: TrafficVehicleRecycleSystem.Tick() → 距离>150² → scene.RemoveEntity()
  → Client: Entity销毁通知 → GameObject.Destroy()
```

## 6. 事务性设计

**征用原子性**：PullFromVehicle + OnVehicle 在同一个网络请求链中处理。若 OnVehicle 失败，NPC 已被移除的情况下：
- 服务端回滚：将 NPC 重新放回座位（或直接销毁交通车辆）
- 简化方案（推荐）：PullFromVehicle 成功后 OnVehicle 极少失败（座位已空），不做额外回滚

**下车+回收**：非事务性，下车和回收是独立操作，时间解耦。

## 7. 错误处理

| 场景 | 处理 |
|------|------|
| 目标车辆已被其他玩家征用 | OnVehicle 返回座位被占错误，客户端提示 |
| 征用时车辆已销毁 | OnVehicle 返回车辆不存在，客户端关闭提示 |
| 物理初始化异常 | SwitchToPlayerControl 中 try-catch，失败则强制下车 |
| 回收时玩家正在上车 | 回收检测排除 is_driving 状态的车辆 |
| 玩家离线 | 服务端 OffVehicle + 立即回收 |
| 玩家切场景 | ownerEntity 在原场景为 nil → 立即回收（与离线逻辑一致） |
| 空车征用 | 无NPC驾驶员，跳过替换，直接占座 |

## 8. 验收测试方案

### [TC-001] 征用上车
前置条件：已登录大世界，场景内有交通车辆行驶
操作步骤：
1. [MCP] 移动玩家到交通车辆附近（GM传送或步行）
2. [验证] screenshot-game-view 确认出现交互提示UI
3. [MCP] script-execute 模拟按键触发征用
4. [验证] screenshot-game-view 确认玩家已在驾驶座
5. [验证] script-execute 读取 PersonStatusComp.is_driving == true

### [TC-002] 物理驾驶
前置条件：TC-001 完成，玩家在驾驶座
操作步骤：
1. [MCP] script-execute 模拟油门输入
2. [验证] screenshot-game-view 确认车辆在移动
3. [MCP] script-execute 模拟转向输入
4. [验证] screenshot-game-view 确认车辆转向
5. [验证] console-get-logs 无异常错误

### [TC-003] 相机验证
前置条件：TC-001 完成
操作步骤：
1. [验证] script-execute 读取当前 CameraMode 为 VehicleMode
2. [验证] screenshot-game-view 确认车辆跟随视角

### [TC-004] 下车
前置条件：TC-001 完成，玩家在驾驶座
操作步骤：
1. [MCP] script-execute 模拟下车按键
2. [验证] screenshot-game-view 确认角色在车旁步行状态
3. [验证] script-execute 读取 CameraMode 为 DefaultPersonMode
4. [验证] script-execute 确认车辆仍存在于场景中

### [TC-005] 距离回收
前置条件：TC-004 完成，玩家已下车
操作步骤：
1. [MCP] GM传送玩家到200m外
2. [等待] 5-10秒（回收 Tick 间隔）
3. [验证] script-execute 确认车辆 Entity 已不存在
4. [验证] console-get-logs 无幽灵实体警告
