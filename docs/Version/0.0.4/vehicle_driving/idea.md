# 玩家自由驾驶车辆（GTA5 风格）

## 核心需求
深化大世界交通系统，玩家角色征用汽车后，参考 GTA5 的设计，可以自由操纵车辆。

## 调研上下文

### 现有基础设施

**协议层（已存在，无需新增）**：
- `OnVehicleReq/OffVehicleReq` — 上车/下车
- `DriveVehicleReq` — 驾驶输入上报（位置、旋转、速度、VehicleInput）
- `PullFromVehicleReq` — 强制拉人下车（征用）
- `VehicleInput` — 油门/刹车/转向/手刹/离合/推进
- `VehiclePersonalityNtf` — 人格参数

**服务端（P1GoServer）**：
- `vehicle_ops.go` — OnVehicle/OffVehicle/PullFromVehicle 网络函数已实现
- `PlayerVehicleComp` — 玩家车辆容器
- `PersonStatusComp` — is_driving/drive_vehicle_id/vehicle_seat_index
- `VehicleStatusComp` — 座位/车门/锁定/输入状态
- `TrafficVehicleComp` — 交通系统车辆标记

**客户端（freelifeclient）**：
- `PlayerGetOnVehicleComp` — 监听上车输入、检测附近车辆
- `InteractSurfVehicleComp` — 车辆交互 FSM（提示显示）
- `PlayerInteractWithVehicleComp` — 上车/改装/停车完整流程
- `DrivingCarState` — 驾驶状态机
- `TrafficManager` — DotsCity DOTS Job 驱动的交通模拟
- `GTA5VehicleController` — AI 路径跟随（Catmull-Rom 样条）
- 物理模型：Rigidbody + WheelCollider，支持 Car/Motorcycle/Bicycle/Boat 等

**交通系统（已完成6阶段）**：
- 路网适配 + A*寻路、信号灯系统、驾驶人格、碰撞闪避、变道系统、动态密度
- 交通车辆纯客户端 DotsCity ECS 框架，`ExternalDisableNetTransform=true` + `rb.isKinematic=true`

### 关键技术现状
| 问题 | 现状 |
|------|------|
| 征用逻辑 | `PullFromVehicle()` 已实现基础流程 |
| 移动控制权 | 服务端权威，客户端上报 DriveVehicleReq |
| 交通车辆类型 | 独立 Entity（TrafficVehicleComp），非 NPC |
| 物理模型 | WheelCollider 物理（非 Arcade） |
| AI→玩家控制切换 | 需要从 DotsCity ECS kinematic 切换到 Rigidbody 物理 |

### 核心挑战
1. **控制权切换**：交通车辆是 DotsCity ECS kinematic 模式，征用后需切换到 Rigidbody 物理驱动
2. **上下车动画**：需要配合车门位置的上下车动画过渡
3. **相机切换**：步行相机 → 车辆跟随相机的平滑过渡
4. **交通系统联动**：征用后车辆从交通系统注销，下车后是否归还

## 范围边界
- 做：交通车辆征用上车、物理驾驶、相机切换、下车、距离回收
- 不做：征用动画、车辆损坏/爆炸、车辆武器、警察追击、多人同乘、摩托车/船/直升机

## 初步理解
玩家在大世界中接近交通车辆 → 显示交互提示 → 触发征用（瞬间切换）→ 玩家上车 → 切换为玩家操控（WheelCollider 物理驾驶）→ 自由驾驶 → 下车后车辆留在原地，离远回收。

## 确认方案

核心思路：打通"AI 交通车辆 → 玩家可操控车辆"闭环，复用现有协议和基础设施，核心工作是控制权切换（DotsCity ECS kinematic → Rigidbody 物理）和上下车全流程串联。

### 锁定决策

**服务端**：
- 无新增协议，全复用 `OnVehicleReq/OffVehicleReq/DriveVehicleReq/PullFromVehicleReq`
- 征用时：PullFromVehicle 移除 NPC 乘客 → OnVehicle 玩家上车 → 服务端标记车辆脱离交通系统
- 下车时：OffVehicle → 车辆保留在场景，设定回收定时器（玩家离开一定距离后销毁实体）
- 数据不持久化，征用车辆为临时状态（内存）

**客户端**：
- 征用为瞬间切换，不做征用动画（后续迭代）
- 控制权切换核心流程：
  1. 从 DotsCity ECS 注销车辆（停止 AI 路径跟随）
  2. `ExternalDisableNetTransform=false`，`rb.isKinematic=false`，启用 Rigidbody 物理
  3. 玩家输入通过 InputsComp → WheelCollider 驱动
  4. 定期上报 DriveVehicleReq 同步服务端
- 使用现有 WheelCollider 物理模型，通过调参接近 GTA5 手感
- 相机：步行相机 → 车辆跟随相机平滑过渡（CfgVehicleBase 已有 cameraDistance/upCameraOffset 参数）
- 下车时：角色放置在车门旁，恢复步行相机和步行状态
- 下车后车辆留在原地，玩家离开一定距离后回收

**主要技术决策**：
- 物理模型：复用 WheelCollider（不改 Arcade），调参优化手感
- 征用动画：本期不做，瞬间切换
- 回收策略：距离触发回收（非时间），GTA5 风格

**技术细节**：
- 控制权切换接口：在车辆 Entity 上新增方法 `SwitchToPlayerControl()` / `SwitchToTrafficControl()`，封装 ECS 注销、物理切换、输入绑定
- 回收距离阈值：配置化，建议默认 150m（XZ 平面距离，用平方距离比较）
- 服务端回收：定时轮询玩家-车辆距离，超阈值后 RemoveEntity（必须同时调 scene.RemoveEntity 防幽灵）

### 待细化
- WheelCollider 调参具体数值（需运行时测试迭代）
- 上车时玩家角色的位置对齐细节（车门侧 vs 直接传送到座位）
- 交通系统注销/回收的具体 API 调用链（需读 DotsCity 源码确认）

### 验收标准
- AC-01：玩家靠近交通车辆，显示上车/征用交互提示
- AC-02：按键后瞬间征用（NPC 移除），玩家进入驾驶座
- AC-03：驾驶中可自由操控（油门/刹车/转向/手刹），车辆物理响应正常
- AC-04：相机切换到车辆跟随视角，驾驶中视角跟随平滑
- AC-05：按键下车，角色回到步行状态，相机恢复步行视角
- AC-06：下车后车辆留在原地，玩家离远后车辆被回收
