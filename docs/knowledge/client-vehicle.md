# Freelife Client 载具系统

> 客户端载具系统完整知识图谱，涵盖实体架构、物理控制、玩家交互、AI 驾驶、网络同步、视觉效果及辅助子系统。

## 目录

- [1. 架构总览](#1-架构总览)
- [2. 载具实体与组件](#2-载具实体与组件)
- [3. 物理与控制](#3-物理与控制)
- [4. 玩家-载具交互](#4-玩家-载具交互)
- [5. 载具 AI 系统](#5-载具-ai-系统)
- [6. 网络同步](#6-网络同步)
- [7. 视觉与特效](#7-视觉与特效)
- [8. 辅助子系统](#8-辅助子系统)
- [9. 配置表](#9-配置表)
- [10. 关键文件索引](#10-关键文件索引)

---

## 1. 架构总览

载具系统采用 **Entity(Controller) + Component** 架构，与 NPC 系统共享 `Controller` 基类。

```
┌──────────────────────────────────────────────────────────┐
│                  VehicleManager (单例)                     │
│       生命周期管理、Spawn/Despawn、全局字典维护               │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │              Vehicle (Controller)                   │  │
│  │      Rigidbody, VehicleData, speed, Driver          │  │
│  │                                                    │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  │  │
│  │  │ Engine Comp │  │ Inputs Comp │  │ Seat Comp │  │  │
│  │  │(物理/控制)   │  │(输入采集)    │  │(座位管理)  │  │  │
│  │  └──────┬──────┘  └─────────────┘  └───────────┘  │  │
│  │         │                                          │  │
│  │  ┌──────▼──────────────────────────────────┐       │  │
│  │  │ IVehicleControl 多态                     │       │  │
│  │  │ Car│Motorcycle│Bicycle│Boat│Aircraft│Heli│       │  │
│  │  └─────────────────────────────────────────┘       │  │
│  │                                                    │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │  │
│  │  │NetTransf │ │ Status   │ │ 辅助组件          │   │  │
│  │  │(网络同步) │ │(HP/燃油)  │ │(Radio/Stunt/...) │   │  │
│  │  └──────────┘ └──────────┘ └──────────────────┘   │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

**数据流**: 玩家输入 / AI 决策 → InputsComp → EngineComp → IVehicleControl → WheelCollider / Rigidbody → 物理模拟

**载具类型**: Car（汽车）、Motorcycle（摩托车）、Bicycle（自行车）、Boat（船）、Aircraft（飞机）、Helicopter（直升机）

**设计特点**:
- 物理模型基于 **Rigidbody + WheelCollider**，非 Arcade 模式
- 不同载具类型在 `IVehicleControl` 层分支，共享通用物理阻尼
- 每帧最多 Spawn 1 辆载具（节流）
- 对象池回收，不直接 Destroy

## 2. 载具实体与组件

### 2.1 实体基类

`Vehicle` 继承 `Controller`，核心属性：
- `VehicleData` — 载具数据容器
- `Rigidbody rb` — 物理刚体
- `speed` — 当前速度
- `Driver` — 当前驾驶员引用

组件基类 `Comp`（接口 `IComp`, `IReference`），生命周期：`OnCreate()` → `OnAdd(owner)` → `OnEnable()` → `OnClear()`

### 2.2 核心组件清单

| 组件 | 职责 |
|------|------|
| `VehicleEngineComp` | 物理引擎调度，按载具类型创建对应 Control |
| `VehicleInputsComp` | 输入采集（玩家/网络代理/AI） |
| `VehicleSeatComp` | 座位管理（Empty→Registered→Occupied） |
| `VehicleNetTransformComp` | 网络位置同步，MarkerState 权限控制 |
| `VehicleStatusComp` | HP/燃油/损坏阶段/水伤检测 |
| `VehiclePhysicDampComp` | 物理阻尼/翻车检测/空中 RCS 稳定 |
| `VehicleAIComp` | AI 控制器挂载 |
| `VehicleAppearanceComp` | 外观定制（MPB 材质/颜色/LOD） |
| `VehicleCollisionHandlerComp` | 碰撞处理（车-车/车-人/车-环境） |
| `VehicleDisfeatureComp` | 损坏视觉效果（烟/火/玻璃碎裂） |
| `VehicleVFXComp` | 速度特效（气流拖尾/速度线/火焰） |

### 2.3 辅助组件清单

| 组件 | 职责 |
|------|------|
| `VehicleRadioComp` | 车载广播频道切换 |
| `VehicleHonkingComp` | 喇叭音效 + 1s keepalive |
| `VehicleBagComp` | 后备箱库存（网格系统） |
| `VehicleGoodComp` | 货物模型动态挂载 |
| `VehicleParkingComp` | 停车区进出检测 |
| `VehicleStuntComp` | 特技检测（飞跃/擦身/吃尾气） |
| `VehicleSkillComp` | 载具技能（NOS 氮气加速，暂禁用） |
| `VehicleProximityComp` | 30m 近距检测，供 NPC 躲避 |
| `VehicleUIComp` | 载具 HUD 调试面板 |
| `VehicleMonitorComp` | 性能监控 |
| `VehicleAbilityComp` | GAS 能力系统集成 |
| `VehicleInteractToOtherComp` | 载具间交互 |
| `VehiclePackageComp` | 包裹/配送系统 |
| `VehicleMemberRescueTransferPointComp` | 救援转移点 |

## 3. 物理与控制

### 3.1 输入管线

```
InputManager.GetVehicleInputsMalloc()
  → VehicleInputsComp (每帧采集)
    ├── PlayerRealInputs (本地玩家)
    ├── NetProxyInputs (网络代理)
    └── AI Inputs (AI 驱动)
  → VehicleEngineComp.OnFixedUpdate()
    → IVehicleControl.OnFixedUpdate()
      → CarWheelController / Rigidbody
```

**离散输入**: H 键切换灯光、Left Shift 加速

### 3.2 多类型控制分发

`VehicleEngineComp` 根据 `VehiclePrefabConfig.vehicleType` 枚举，工厂模式创建对应控制器：

| 类型 | 控制器 | 特点 |
|------|--------|------|
| Car | `CarControl` | WheelCollider 四轮物理 |
| Motorcycle | `MotorcycleControl` | 两轮平衡 |
| Bicycle | `BicycleControl` | 人力驱动 |
| Boat | `BoatControl` | 水面浮力 |
| Aircraft | `AircraftControl` | 飞行力学 |
| Helicopter | `HelicopterControl` | 旋翼升力 |

统一接口 `IVehicleControl`，各类型独立实现物理逻辑。

### 3.3 车轮系统 (CarWheelController)

- 封装 Unity `WheelCollider` + 缓存 `WheelHit`
- 可配置弹簧/阻尼参数
- 每 FixedUpdate 更新接地状态
- 支持动态轮胎尺寸和模式切换
- 模拟禁用时切换为松散轮代理 GameObject

### 3.4 物理阻尼 (VehiclePhysicDampComp)

- **速度阻尼**: X/Z=500/200, Y=0.2, 左侧=0.98
- **翻车检测**: 80° 阈值，比较车轮与车身 Up 方向
- **RCS 空中稳定**: 施加扭矩校正空中姿态
- **排除类型**: Traffic / Helicopter / Boat / Motorcycle 不应用

### 3.5 载具状态 (VehicleStatusComp)

- HP / 燃油追踪，集成 GAS（Gameplay Ability System）
- 多阶段损坏（视觉退化）
- 水伤检测（非船类型）
- 引擎音频生命周期（启动→怠速→熄火）
- 销毁事件广播

## 4. 玩家-载具交互

### 4.1 上车流程

```
PlayerGetOnVehicleComp 检测附近载具
  → 计算路径点 (trace points → 车门位置)
  → 预注册座位 (防竞态: Empty → Registered)
  → 移动到上车点
  → DrivingComp.EnterCar(vehicle, doorPosition)
  → 状态切换 → GetOnCarState
```

**特殊处理**: 直升机/飞机/船跳过路径寻路，直接挂载

**中断条件**: 跳跃、切换武器、交互、瞄准、移动输入

### 4.2 上车状态机 (GetOnCarState)

子状态流转：`OpenVehicleDoor → PullPeople → EnterVehicle → AttackDriver → ChangeSeat → CloseVehicleDoor`

- Timeline 驱动上车动画，0.5s 位置平滑插值
- 处理车门被阻挡、上车失败、弹出等异常
- 上车完成后将玩家 parent 设为座位 Transform

### 4.3 驾驶状态 (DrivingCarState)

- 驾驶座位 = 座位索引 0（位置 FL）
- 相机偏移 (-0.4, 0.4, 2.0) 用于驾驶视角
- 子状态: Drive → Reversing → Still
- 摩托车特殊 IK：踏板/把手

### 4.4 乘客状态 (PassengerCarState)

- 非驾驶座位（索引 1+）
- 可攻击驾驶员、下车、换座
- 禁用胶囊碰撞和地面检测
- 1s 冷却防止频繁换座

### 4.5 下车流程 (DriverGetOffCarState)

子状态: `ChangeSeat → ExitVehicle → CloseVehicleDoor`
- 等待地面接触后才完成（防穿地）
- 跳跃/攻击中阻止下车

### 4.6 座位系统 (VehicleSeatComp + Seat)

| 座位状态 | 说明 |
|----------|------|
| Empty | 空座 |
| Registered | 已预定（玩家移动中） |
| Occupied | 已就座 |

- `SyncVehicleSeatFromUpdateData()` 同步服务器占用状态
- `IsEnterPointBlocked()` 检测上车点障碍物
- Seat[0].User = 驾驶员；支持 NPC 和玩家
- 座位高度影响动画混合（Low/Standard/High/Motorcycle/Car）

## 5. 载具 AI 系统

### 5.1 架构：多层 FSM

```
VehicleAIComp
  → IVehicleAI (CarAI)
    ├── VehicleAIMovementComponent (运动执行)
    └── VehicleAIPathPlanningComponent (路径规划 + 策略管理)
         └── IVehicleFSMStrategy (策略 FSM)
              └── BaseVehicleAIActionFSM_V2<T> (动作 FSM)
```

### 5.2 策略类型

| 策略 FSM | 行为 |
|----------|------|
| `RCCTrafficStrategyFSM` | 交通巡航（GoToWayPoint → InWayPoint） |
| `EscapeStrategyFSM` | 随机路点逃跑 |
| `ChaseTargetPathFindingMethodFSM` | 追踪目标寻路 |
| `GiveWayFSM` | 碰撞避让 |
| `TrafficLightFSM` | 红绿灯遵守 |
| `RCCAIAvoidFSM` | 紧急障碍规避 |

### 5.3 寻路方式

| 方式 | 说明 |
|------|------|
| Waypoint | 导航网格无关的路点网络（Traffic/Escape 主用） |
| Navmesh | A* 导航（A* Pathfinding Pro: Seeker, AIPath） |
| None | 直线移动 |

### 5.4 驾驶风格 (VehicleDriverStyleData)

ScriptableObject 配置，使用 AnimationCurve 调节：
- `distanceSpeed` / `dirSpeed` — 速度调制
- `distanceSteer` / `dirSteer` — 转向调制

### 5.5 AI vs 玩家控制切换

- `isControledByChaseAI` 标志切换
- `EndAIControl()` 清除所有策略
- AI 仅在 `MarkerState` 为 LocalNpc 时执行物理

## 6. 网络同步

### 6.1 网络权限状态机 (VehicleNetMarkFSM)

8 种 MarkerState 控制谁拥有载具物理权限：

| 状态 | 权限方 | 同步方向 | 物理模式 | 场景 |
|------|--------|----------|----------|------|
| Player | 本地玩家 | ↑ 上行 | 主动物理 | 玩家驾驶 |
| Ped | 远程玩家 | ↓ 下行 | Kinematic | 远程玩家驾驶 |
| LocalNpc | 本地 NPC | ↑ 上行 | 主动物理 | 本地交通 NPC |
| RemoteNpc | 远程 NPC | ↓ 下行 | Kinematic | 远端交通 NPC |
| LocalNoDriver | 最近玩家 | ↑ 上行 | 主动物理 | 无人车近处 |
| RemoteNoDriver | 远程控制 | ↓ 下行 | Kinematic | 无人车远处 |
| None | 无 | 无同步 | — | 销毁/超远 |
| RollBackFix | (废弃) | — | — | 位置纠正 |

所有状态经由 **None** 枢纽中转。回滚距离阈值 = **10m**。

### 6.2 位置同步 (VehicleNetTransformComp)

- **SmoothDamp 插值**: dampingTime = 0.2s
- **Bezier 曲线**: `UseBeizer` 标志启用更平滑的位置混合
- **速度外推**: 跟踪 `currentVelocity` 预测下一帧位置
- 数据源: `VehicleData.Transform` (Position + EulerAngle)

### 6.3 网络消息 (VehicleNetHandle)

处理服务器推送的载具数据更新：
- 基础信息、座位占用、移动状态
- 位置旋转快照
- 损坏状态、货物变更

## 7. 视觉与特效

### 7.1 外观定制 (VehicleAppearanceComp)

- **MaterialPropertyBlock (MPB)** 实例化材质
- Shader 属性: `_BaseColor1`, `_BaseColor2`, `_Smoothness`
- RGB 通道独立映射颜色
- 可拆卸部件状态: `vehiclePartProtoMap`

### 7.2 LOD 系统

| 平台 | LOD0 | LOD1 | LOD2 |
|------|------|------|------|
| PC | 60m | 80m | 100m |
| Mobile | 40m | 60m | 100m |

### 7.3 损坏视觉 (VehicleDisfeatureComp)

| 损坏阶段 | 效果 |
|----------|------|
| Stage 1 | 白色烟雾 (`CarSmokeHolder`) |
| Stage 2 | 黑色浓烟 (`CarSmokeBlackHolder`) |
| Stage 3+ | 火焰效果（小/大变体） |

玻璃碎裂独立处理，粒子系统懒加载。

### 7.4 速度特效 (VehicleVFXComp)

| 效果 | 速度范围 | 实现 |
|------|----------|------|
| 气流拖尾 | 60-120 km/h | TrailRenderer 开关 |
| 速度线 | 100-200 km/h | URP Volume 后处理 |
| 火焰 | 高速 | 动态灯光 (`flameLight`) |

## 8. 辅助子系统

| 子系统 | 组件 | 核心机制 |
|--------|------|----------|
| 广播 | `VehicleRadioComp` | 监听频道变更信号，本地玩家在车内时触发 `SwitchRadio` |
| 喇叭 | `VehicleHonkingComp` | 双状态追踪（本地/网络），1s keepalive 重发防音频中断 |
| 后备箱 | `VehicleBagComp` | 网格库存系统，支持物品增删改 |
| 货物 | `VehicleGoodComp` | 动态 Spawn 货物模型到挂载点，监听数据变更 |
| 停车 | `VehicleParkingComp` | 碰撞区进出检测，发送 Enter/Leave 通知服务器 |
| 特技 | `VehicleStuntComp` | 3 种特技：飞跃(>0.5s空中+60km/h)、擦身(>1s近距)、吃尾气 |
| 技能 | `VehicleSkillComp` | NOS 氮气加速 FSM（当前禁用） |
| 碰撞 | `VehicleCollisionHandlerComp` | ~2000 行，车-车/车-人/车-环境碰撞、血迹/碎片生成 |
| 近距检测 | `VehicleProximityComp` | 30m 半径每 1s 查询，多阶段警报，供 NPC 躲避 |
| 载具 HUD | `VehicleUIComp` | 调试面板 (F1 切换) |

## 9. 配置表

自动生成于 `Config/Gen/`，**禁止手动编辑**。

| 配置 | 说明 |
|------|------|
| `CfgVehicle` | 主配置（id, vehicleType, trunkInfo, vanishAfterDead） |
| `CfgVehicleBase` | 基础属性 |
| `CfgVehicleParameter` | 物理/操控参数 |
| `CfgVehicleCarType` | 车型分类 |
| `CfgVehicleBrand` | 品牌 |
| `CfgVehicleColor` | 颜色定制 |
| `CfgVehiclePart` | 车辆部件 |
| `CfgVehicleAppendix` | 扩展属性 |
| `CfgVehicleFunction` | 功能/能力 |
| `CfgVehicleCreateRule` | 生成规则 |
| `CfgVehiclePoolGroup` | 对象池分组 |
| `CfgVehicleShop` | 商店 |
| `CfgVehicleRent` | 租赁 |
| `CfgVehicleProduct` | 制造 |
| `CfgPlayVehicle` | 玩法配置 |
| `CfgAudioVehicle` | 引擎/驾驶音效 |
| `CfgCarTyreConfigs` | 轮胎配置 |

## 10. 关键文件索引

> 路径均相对于 `Assets/Scripts/Gameplay/Modules/BigWorld/`

### 实体与组件

| 类别 | 路径 |
|------|------|
| Vehicle 实体 | `Managers/Vehicle/Vehicle.cs` |
| VehicleManager | `Managers/EntityManager/VehicleManager.cs` |
| EngineComp | `Entity/Vehicle/Comp/VehicleEngineComp.cs` |
| InputsComp | `Entity/Vehicle/Comp/VehicleInputsComp.cs` |
| SeatComp | `Entity/Vehicle/Comp/VehicleSeatComp.cs` |
| NetTransformComp | `Entity/Vehicle/Comp/VehicleNetTransformComp.cs` |
| StatusComp | `Entity/Vehicle/Comp/VehicleStatusComp.cs` |
| PhysicDampComp | `Entity/Vehicle/Comp/VehiclePhysicDampComp.cs` |
| AIComp | `Entity/Vehicle/Comp/VehicleAIComp.cs` |
| AppearanceComp | `Entity/Vehicle/Comp/VehicleAppearanceComp.cs` |
| CollisionHandler | `Entity/Vehicle/Comp/VehicleCollisionHandlerComp.cs` |
| DisfeatureComp | `Entity/Vehicle/Comp/VehicleDisfeatureComp.cs` |
| VFXComp | `Entity/Vehicle/Comp/VehicleVFXComp.cs` |

### 数据

| 类别 | 路径 |
|------|------|
| VehicleData | `Entity/Vehicle/Data/VehicleData.cs` |
| BaseInfoData | `Entity/Vehicle/Data/VehicleBaseInfoData.cs` |
| SeatInfoData | `Entity/Vehicle/Data/VehicleSeatInfoData.cs` |
| StatusData | `Entity/Vehicle/Data/VehicleStatusData.cs` |
| InputData | `Entity/Vehicle/Data/VehicleInputData.cs` |
| DoorInfoData | `Entity/Vehicle/Data/VehicleDoorInfoData.cs` |

### 控制器

| 类别 | 路径 |
|------|------|
| 控制器目录 | `Managers/Vehicle/VehicleControl/` |
| CarControl | `Managers/Vehicle/VehicleControl/CarControl.cs` |
| CarWheelController | `Managers/Vehicle/VehicleBody/CarWheelController.cs` |
| VehicleBodyManager | `Managers/Vehicle/VehicleBody/VehicleBodyManager.cs` |

### AI 系统

| 类别 | 路径 |
|------|------|
| CarAI | `Managers/Vehicle/VehicleAI/CarAI.cs` |
| 寻路组件 | `Managers/Vehicle/VehicleAI/VehicleAIPathPlanningComponent.cs` |
| 策略 FSM 目录 | `Managers/Vehicle/VehicleAI/VehicleStrategyFSMs/` |
| 驾驶风格 | `Managers/Vehicle/VehicleDriverStyle/` |

### 玩家交互

| 类别 | 路径 |
|------|------|
| 上车组件 | `Entity/Player/Comp/PlayerGetOnVehicleComp.cs` |
| 冲浪组件 | `Entity/Player/Comp/PlayerSurfVehicleComp.cs` |
| 驾驶状态 | `Entity/Player/State/DrivingCarState.cs` |
| 乘客状态 | `Entity/Player/State/PassengerCarState.cs` |
| 上车状态 | `Entity/Player/State/GetOnCarState.cs` |
| 下车状态 | `Entity/Player/State/DriverGetOffCarState.cs` |
| DrivingComp | `Entity/Player/Comp/DrivingComp.cs` |
| SeatHelper | `Managers/Vehicle/VehicleSeatHelper.cs` |

### 相机

| 类别 | 路径 |
|------|------|
| 载具跟随 | `Managers/Camera/CameraFollowVehicleComp.cs` |
| 载具相机配置 | `Managers/Camera/VehicleCameraConfig.cs` |
| 第一人称载具 | `Managers/Camera/FirstPersonVehicleMode.cs` |

### 网络

| 类别 | 路径 |
|------|------|
| NetHandle | `Managers/Vehicle/VehicleNetHandle.cs` |
| NetMarkFSM | `Managers/Vehicle/CarNetMarkFSM.cs` |

### 编辑器工具

| 类别 | 路径 (相对 Assets/Scripts/) |
|------|------|
| 配置工具 | `Tools/VehicleConfigTool.cs` |
| 测试窗口 | `Tools/VehicleTesterEditorWindow.cs` |
| 参数可视化 | `Tools/VehicleParameterVisionableWindow.cs` |
| 驾驶风格编辑 | `Tools/VehicleDriverStyleDataEditor.cs` |

---

**相关文档**: 服务器端载具系统详见 [`server-vehicle.md`](server-vehicle.md) — 涵盖 ECS 数据结构、网络协议、权限模型、交通载具管理、持久化与商业
