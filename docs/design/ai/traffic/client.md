# 客户端设计（freelifeclient）

> ⚠️ **注意**：本文档中的 JunctionDecisionFSM、TrafficLightSyncAdapter、LaneChangeFSM 等高级功能已迁移到大世界交通系统实现，见 [`big_world_traffic/`](../big_world_traffic/README.md)。小镇仅使用 TownTrafficMover 轻量方案。
>
> 总体设计方案见 [system-design.md](system-design.md)

## 现有代码基线

实现前必须了解的现有资源状态：

| 组件/类 | 文件 | 状态 | 说明 |
|---------|------|------|------|
| `VehicleAIComp` | `Entity/Vehicle/Comp/VehicleAIComp.cs` | **注释禁用** (Vehicle.cs:533) | 需取消注释并启用 |
| `VehicleAIPathPlanningComponent` | `Vehicle/VehicleAI/VehicleAIPathPlanningComponent.cs` | 已实现 | MonoBehaviour，管理 FSM 策略切换，FixedUpdate 驱动 |
| `VehicleAIMovementComponent` | `Vehicle/VehicleAI/VehicleAIMovementComponent.cs` | 已实现 | 驾驶执行层，持有 `currentVehicleStyle` |
| `VehicleDriverStyleData` | `Vehicle/VehicleAI/VehicleDriverStyle/VehicleDriverStyleData.cs` | 已实现 | ScriptableObject，4条曲线：`distanceSpeed`/`dirSpeed`/`distanceSteer`/`dirSteer` |
| `IVehicleFSMStrategy` | `Vehicle/VehicleAI/VehicleStrategyFSMs/BaseVehicleStrategy.cs` | 已实现 | 接口：`Setup/StartFsm/UpdateParam/UpdateFSM/StopAndResetFSM` |
| `RCCTrafficStrategyFSM` | `VehicleStrategyFSMs/RCCTrafficStrategyFSM.cs` | 已实现 | 实现 `IVehicleFSMStrategy<RCCTrafficActionStates>`，常规巡航 |
| `TrafficLightFSM` | `VehicleStrategyFSMs/TrafficLightFSM.cs` | 已实现 | **独立类**（非 IVehicleFSMStrategy），二值状态 `CanPass/Waiting` |
| `GiveWayFSM` | `VehicleStrategyFSMs/GiveWayFSM.cs` | 已实现 | **独立类**，状态：`NormalDriving/GiveWayToOther/OverTakeOther` |
| `RCCAIAvoidFSM` | `VehicleStrategyFSMs/RCCAIAvoidFSM.cs` | **空骨架** | 实现 `IVehicleFSMStrategy<AvoidActionStates>`，所有方法为空 |
| `CustomWaypoint` | `Entity/Monster/State/.../WaypointGraph.cs` | 已实现 | 字段：`Id/Pos/nexts/prevs/CurrentState`，无路口/车道信息 |
| `TrafficWaypointState` | 同上 | 已实现 | 枚举：`CanPass=0, Standby=1`（仅二值） |
| `VehicleHonkingComp` | `Entity/Vehicle/Comp/VehicleHonkingComp.cs` | 已注册 | Vehicle.cs:451 `this.AddComp<VehicleHonkingComp>()` |
| `VehicleAIContext` | `Vehicle/VehicleAI/VehicleAIContext.cs` | 已实现 | 单例，前方障碍检测（矩形 raycasting XZ平面） |
| `FastFsm<TState,TTrigger>` | Framework | 已实现 | 通用 FSM 框架，所有策略 FSM 基于此构建 |

> 以上路径均省略 `Assets/Scripts/Gameplay/Modules/BigWorld/` 前缀。

### 关键架构约束

1. **FSM 策略切换**：`VehicleAIPathPlanningComponent.FixedUpdate()` 轮询 `currentActiveFsmStrategy`，调用 `UpdateParam()` → `UpdateFSM()` → `ApplyStrategy()`。当前是单策略激活（直接赋值），**无优先级仲裁机制**。
2. **TrafficLightFSM 和 GiveWayFSM 是独立类**，不实现 `IVehicleFSMStrategy` 接口，被 `RCCTrafficStrategyFSM` 内部组合调用。
3. **Vehicle 组件注册**在 `Vehicle.OnInit()` 中通过 `this.AddComp<T>()`（Comp 体系），AI 子组件通过 `CarAI.Init()` 中 `gameObject.AddComponent<T>()`（Unity MonoBehaviour）。
4. **路点网络**是自研 `WaypointGraph`（非 Gley 插件），从 binary 加载，通过 Octree 索引。`CustomWaypoint` 当前无路口、车道信息。

## 1. 驾驶人格组件（DriverPersonalityComp）

**位置**：新增 `VehicleDriverPersonalityComp`，继承 `Comp` 基类。

```csharp
// 命名空间: FL.VehicleModule
public class VehicleDriverPersonalityComp : Comp
{
    // 从服务端接收的人格参数
    public DriverPersonalityType PersonalityType;
    public float MaxCruiseSpeed;
    public float MaxAcceleratorInput;
    public float CornerSpeedModifier;
    public float StopDistanceCars;
    public float SlowDistanceCars;
    public float StopDistancePeds;
    public bool RunsAmberLights;
    public bool RunsStopSigns;
    public bool RollsThroughStopSigns;
    public uint GreenLightDelayMs;
    public bool WillChangeLanes;
    public uint LaneChangeCooldownMs;
    public bool UseTurnIndicators;
    public float DriverAbility;
    public float Aggressiveness;
}
```

**与 AnimationCurve 的兼容方式**：

现有 `VehicleDriverStyleData`（ScriptableObject）用 4 条 AnimationCurve 控制速度和转向。人格参数不替代曲线，而是作为**曲线输出的调制因子**：

```csharp
// VehicleAIMovementComponent 中的速度计算
// 现有曲线: distanceSpeed(距离→速度系数) + dirSpeed(方向→速度系数)
float curveSpeed = driverStyle.distanceSpeed.Evaluate(distRatio) * driverStyle.dirSpeed.Evaluate(dirAngle / 180f);
float personalityFactor = personality != null
    ? personality.MaxCruiseSpeed / DefaultCruiseSpeed
    : 1.0f;
float finalSpeed = curveSpeed * personalityFactor * speedZoneModifier;
```

调制映射关系：
- `CornerSpeedModifier` → `dirSpeed` 曲线输出的乘数（转弯减速）
- `MaxAcceleratorInput` → 油门输入上限 clamp
- `DriverAbility` → `distanceSteer`/`dirSteer` 曲线精度系数（高技术 = 更精确跟踪路径）

**注入方式**：收到 `VehiclePersonalityNtf` 时初始化。无人格数据时 fallback 到默认值（所有乘数 = 1.0）。

**Controller 注册**：在 `Vehicle.OnInit()` (Vehicle.cs:533 附近) 中 `this.AddComp<VehicleDriverPersonalityComp>()`，同时取消注释 `VehicleAIComp` 的注册。

## 2. 信号灯适配层 + FSM 增强

### 2.1 路点信号状态扩展

现有 `CustomWaypoint.CurrentState` 为二值枚举 `TrafficWaypointState { CanPass=0, Standby=1 }`。需扩展为完整信号状态以映射服务端 `TrafficLightCommand`：

```csharp
// WaypointGraph.cs 中扩展
public enum TrafficWaypointState
{
    CanPass = 0,         // 绿灯/通行
    Standby = 1,         // 红灯/停车
    Amber = 2,           // 黄灯
    PedestrianCrossing = 3, // 行人通行
    Arrow = 4,           // 方向箭头（合并 proto TLC_FILTER_LEFT/RIGHT/MIDDLE，客户端不区分方向）
}
// 映射：TLC_STOP→Standby, TLC_AMBER→Amber, TLC_GO→CanPass,
//       TLC_FILTER_*→Arrow, TLC_PED_WALK→PedestrianCrossing, TLC_PED_DONTWALK→Standby
```

### 2.2 信号灯同步适配器（新增 TrafficLightSyncAdapter）

**数据流**：
```
Before:  本地无信号灯逻辑（CustomWaypoint.CurrentState 由路点数据静态设置）
After:   服务端 TrafficLightStateNtf → TrafficLightSyncAdapter → CustomWaypoint.CurrentState
```

**TrafficLightSyncAdapter**：
- 监听 `TrafficLightStateNtf`，按 `junction_id + entrance_index` 定位路口入口路点
- 更新对应 `CustomWaypoint.CurrentState` 为扩展枚举值
- 路口路点定位依赖 `CustomWaypoint` 新增的 `JunctionId` + `EntranceIndex` 字段（见第3节）
- 信号灯视觉效果（红绿灯模型切换）由 `TrafficLightSyncAdapter` 直接驱动场景中的灯光对象

> **注意**：项目路点系统是自研 `WaypointGraph`（非 Gley 插件）。Gley 的 `TrafficLightsIntersection` 仅用于 Gley TrafficSystem 注册车辆场景，信号灯逻辑不经过 Gley。

### 2.3 TrafficLightFSM 增强

现有 `TrafficLightFSM` 是独立类（非 `IVehicleFSMStrategy`），被 `RCCTrafficStrategyFSM` 内部组合调用，仅有 `CanPass/Waiting` 二值判断。

**改造方案**（两种选择，推荐方案A）：

**方案A**：保持独立类，扩展内部状态：
```
TrafficLightFSM 状态（从 2 → 5）：
  CanPass    → 绿灯/箭头通行
  Waiting    → 红灯停车等待
  Amber      → 黄灯决策（RunsAmberLights ? CanPass : Waiting）
  PedWait    → 行人通行停车
  GreenDelay → 绿灯起步延迟（GreenLightDelayMs 后切 CanPass）
```

**方案B**：重构为 `IVehicleFSMStrategy` 实现，参与优先级仲裁（更大改动，见第3节）。

**状态转移触发规则**（审查修复 M-4）：
- FSM 状态转移**仅响应 `TrafficLightStateNtf.command` 字段变化**，不依赖 `remaining_ms` 倒计时到零
- `remaining_ms` 仅用于 UI 表现（倒计时显示），不参与行为决策
- 原因：网络延迟导致客户端与服务端不同步，依赖 remaining_ms 会产生"客户端绿灯但服务端已红灯"的危险窗口

**人格参数注入点**：
- `RunsAmberLights` → Amber 状态转移决策
- `GreenLightDelayMs` → GreenDelay 持续时间
- `MaxCruiseSpeed` → CanPass 时速度上限（加速通过绿灯取决于巡航速度余量）

## 3. 路口决策 FSM（新增 JunctionDecisionFSM）

新增 `IVehicleFSMStrategy<JunctionDecisionStates>` 实现，基于 `FastFsm<TState, TTrigger>` 构建。

### 3.1 FSM 优先级框架

**现状**：`VehicleAIPathPlanningComponent.FixedUpdate()` 直接操作 `currentActiveFsmStrategy` 单一引用（:79），策略切换由外部 `SetStrategy()` 调用硬编码。`TrafficLightFSM` 和 `GiveWayFSM` 是独立类，被 `RCCTrafficStrategyFSM` 内部组合使用，不参与策略层竞争。

**改造**：在 `VehicleAIPathPlanningComponent` 中引入优先级仲裁：

```csharp
// VehicleAIPathPlanningComponent 新增
private List<IVehicleFSMStrategy> _sortedStrategies; // 按优先级降序

// FixedUpdate 中替换当前单策略逻辑
foreach (var strategy in _sortedStrategies)
{
    if (strategy.ShouldActivate(this)) // IVehicleFSMStrategy 新增方法
    {
        if (currentActiveFsmStrategy != strategy)
        {
            currentActiveFsmStrategy?.OnDeactivate(); // 新增
            currentActiveFsmStrategy = strategy;
            strategy.OnActivate(); // 新增
        }
        break;
    }
}
```

**优先级（高 → 低）**：
| # | FSM | 改造量 | 说明 |
|---|-----|--------|------|
| 1 | `JunctionDecisionFSM` | **新增** | 路口决策（服务端指令驱动） |
| 2 | `RCCAIAvoidFSM` | **补全实现** | 紧急碰撞规避（已有骨架） |
| 3 | `LaneChangeFSM` | **新增** | 变道（P1） |
| 4 | `RCCTrafficStrategyFSM` | **已有** | 常规巡航（内含 TrafficLightFSM + GiveWayFSM 组合） |

> **设计决策**：`TrafficLightFSM` 和 `GiveWayFSM` 保持为 `RCCTrafficStrategyFSM` 的内部组件（不升级为独立策略），避免大规模重构。路口信号灯场景由 `JunctionDecisionFSM` 的 `WaitForLights` 状态委托 `TrafficLightFSM` 处理。

### 3.2 IVehicleFSMStrategy 接口扩展

```csharp
// BaseVehicleStrategy.cs 中扩展
public interface IVehicleFSMStrategy
{
    void Setup();
    void StartFsm();
    void UpdateParam(VehicleAIPathPlanningComponent controller);
    void UpdateFSM();
    void OnDestroyFsm();
    void StopAndResetFSM();
    // 新增
    int Priority { get; }                                        // 优先级（数值越小越高）
    bool ShouldActivate(VehicleAIPathPlanningComponent ctx);     // 是否应激活
    void OnActivate();                                           // 被仲裁器选中时
    void OnDeactivate();                                         // 被更高优先级抢占时
}
```

### 3.3 JunctionDecisionFSM 状态

```
JunctionDecisionFSM 状态（FastFsm<JunctionDecisionStates, JunctionDecisionTriggers>）：
  NotOnJunction → ShouldActivate() = false，不参与仲裁
  Approaching → 接近路口（路点检测），上报 VehicleApproachJunctionReq
  WaitForLights → 收到 JC_WAIT_FOR_LIGHTS，委托 TrafficLightFSM
  WaitForTraffic → 收到 JC_WAIT_FOR_TRAFFIC，等待交通间隙
  GiveWay → 收到 JC_GIVE_WAY，强制让行
  Go → 收到 JC_GO，通行 → 通过后回到 NotOnJunction
```

### 3.4 路口检测与路点扩展

**路口检测**：基于 `WaypointGraph` 前瞻 N 个路点（N 从 `CfgTrafficSceneProfile.JunctionLookahead` 读取），检查是否标记为路口入口。

**`CustomWaypoint` 新增字段**（WaypointGraph.cs）：
```csharp
public int JunctionId = -1;       // 所属路口 ID（-1=非路口）
public int EntranceIndex = -1;    // 路口入口编号
```

**EntranceIndex 计算规则**：
- Miami：从 RoadPoint.cycle 字段推导——`cycle & 0x3` 为入口方向编号（0-3），按路口内唯一性分配
- S1Town：同一 junction_id 的所有入口路点，按 `listIndex` 升序编号（0, 1, 2...）
- 生成时机：在 `RoadPointsToTrafficWaypoints()` 转换阶段计算并写入 CustomWaypoint

**数据映射链路**（审查修复 M-5）：
```
GleyNav.RoadPoint (JSON)
  → RoadPointsToTrafficWaypoints() / TrafficWaypointsConverter
    → CustomWaypoint (runtime)
      字段映射:
        RoadPoint.junction_id_int → CustomWaypoint.JunctionId
        RoadPoint.cycle → CustomWaypoint.EntranceIndex（计算，见上）
        RoadPoint.OtherLanes → CustomWaypoint.AdjacentLaneWaypoints
        RoadPoint.neighbors → CustomWaypoint.nexts
        RoadPoint.prev → CustomWaypoint.prevs
```

**序列化影响**：`CustomWaypoint.ToBinary/FromBinary` 需同步扩展，Houdini 导出工具需输出这两个字段。

## 4. 碰撞躲避增强

**现状**：`RCCAIAvoidFSM` 已存在但为空骨架（实现 `IVehicleFSMStrategy<AvoidActionStates>`），状态枚举 `NavmeshFinding/WayPointFinding` 已定义。障碍检测已有 `VehicleAIContext` 单例提供 `GetAForwardDynamicObjectBehindMe()`（矩形 raycasting XZ平面）。

**补全实现**：

```
RCCAIAvoidFSM 状态（重新定义）：
  Idle         → ShouldActivate() 检测前方障碍（复用 VehicleAIContext）
  Swerve       → 侧闪躲避，向侧方偏移，持续最多 SwerveDurationMs（从 CfgTrafficSceneProfile 读取，City=2500ms / Town=1500ms）
  EmergencyStop → 无法侧闪时紧急制动
  Escalation   → 与玩家持续碰撞 >3s → 鸣笛(VehicleHonkingComp) → >5s → 尝试绕行(Navmesh)
```

- **人格影响**：`Aggressiveness` 影响侧闪灵敏度和碰撞容忍时间
- **路径切换**：Swerve 失败时通过 `VehicleAIPathPlanningComponent` 切换到 Navmesh 绕行（现有 `VehiclePathFindMethod.Navmesh` + A* Pathfinding 已可用）

## 5. AI LOD 表现降级

**现状**：项目中无现有 AI LOD 系统，需完全新增。

新增 `VehicleAILodComp`（继承 `Comp`），在 `Vehicle.OnInit()` 中注册：

| LOD | AI 更新 | 物理 | 动画 | 网络同步 |
|-----|---------|------|------|---------|
| FULL | 每帧 | 完整 WheelCollider | 完整 | 每帧 |
| TIMESLICE | 每 3 帧 | 完整 | 简化 | 每 3 帧 |
| DUMMY | 每 10 帧 | 保留碰撞/重力 | 最简 | 每 10 帧 |
| SUPER_DUMMY | 每 30 帧 | Kinematic 路径跟随 | 无 | 按需 |

**LOD 距离阈值（按场景配置化）**：

| LOD 边界 | City/Sakura | S1Town | 说明 |
|---------|------------|--------|------|
| FULL → TIMESLICE | 50m | 30m | 小镇地图小，50m 覆盖过多 |
| TIMESLICE → DUMMY | 150m | 80m | |
| DUMMY → SUPER_DUMMY | 300m | 150m | 300m 可能覆盖小镇全图 |

> 阈值从 `CfgTrafficSceneProfile` 配置表读取（或扩展 `CfgSceneInfo`），不硬编码。

**实现要点**：
- LOD 计算纯客户端（本地玩家与 AI 车辆距离），无需服务端参与
- 接入点：在 `VehicleAIPathPlanningComponent.FixedUpdate()` 入口处查询 LOD 等级，跳帧时 early return
- SUPER_DUMMY 模式下切换 Rigidbody 为 Kinematic，直接插值到路径点（`WaypointGraph.GetContinuousWaypointsInDirection` 已可用）
- 车辆引擎现有 `VehicleEngineComp.TurnOffWheelSupport()` / `TurnOnWheelSupport()` 可用于 LOD 切换时控制轮胎物理

## 6. 变道与鸣笛行为

### 6.1 变道 FSM（新增 LaneChangeFSM）

新增 `IVehicleFSMStrategy<LaneChangeStates>` 实现，优先级介于 `RCCAIAvoidFSM` 和 `RCCTrafficStrategyFSM` 之间。

- 前提：`VehicleDriverPersonalityComp.WillChangeLanes = true`，冷却时间已过
- 触发：前方慢车检测（复用 `VehicleAIContext.GetAForwardDynamicObjectBehindMe()`）+ 相邻车道可用
- 执行：打转向灯 → 检查盲区 → 平滑变道
- 取消：变道过程中遇障碍 → 回到原车道

**路点网络扩展需求**（`CustomWaypoint` 新增字段）：
```csharp
public int LaneIndex = -1;                        // 车道编号（0=最内侧，-1=未标注）
public List<int> AdjacentLaneWaypoints = new();    // 相邻车道对应路点 ID 列表
```

> **序列化注意**：`ToBinary/FromBinary` 需扩展，Houdini 导出工具需支持多车道路点关联。变道路径用贝塞尔曲线在当前路点与目标车道路点间插值。

### 6.2 鸣笛交互

基于现有 `VehicleHonkingComp`（已在 Vehicle.OnInit:451 注册）扩展 AI 鸣笛逻辑：

- 绿灯后前车不动 → 延迟后鸣笛催促（基于 `GreenLightDelayMs` 判断前车是否超时未起步）
- 收到他车鸣笛 → 根据 `Aggressiveness` 决定是否响应让路（低攻击性=让路，高攻击性=忽略）
- 遇行人 → 间隔鸣笛（间隔时间与 `Aggressiveness` 反相关）
- 鸣笛通过现有 `VehicleHonkingComp` 触发 + 服务端 `StartCarHorn/StopCarHorn` 协议同步
- 鸣笛逻辑不独立成 FSM，作为各 FSM 状态中的行为动作调用

## 7. 实现前置条件与优先级

### 需启用的现有代码

1. **取消注释** `Vehicle.cs:533-534` 的 `VehicleAIComp` 注册
2. **补全** `RCCAIAvoidFSM` 空骨架实现

### CustomWaypoint 全部新增字段汇总

```csharp
// WaypointGraph.cs - CustomWaypoint 类
public int JunctionId = -1;                        // 路口 ID
public int EntranceIndex = -1;                     // 路口入口编号
public int LaneIndex = -1;                         // 车道编号
public List<int> AdjacentLaneWaypoints = new();    // 相邻车道路点
```

### 实现建议顺序

1. **P0**：`VehicleDriverPersonalityComp` + 协议接收 → `TrafficLightFSM` 状态扩展 + `TrafficLightSyncAdapter`
2. **P0**：FSM 优先级仲裁框架（`IVehicleFSMStrategy` 扩展 + `VehicleAIPathPlanningComponent` 改造）
3. **P0**：`JunctionDecisionFSM` + `CustomWaypoint` 路口字段
4. **P0**：`RCCAIAvoidFSM` 补全
5. **P1**：`VehicleAILodComp` + `LaneChangeFSM` + `CustomWaypoint` 车道字段 + 鸣笛交互

## 8. S1Town 客户端适配

### 8.1 初始化路径

S1Town 走轻量方案，跳过 DotsCity，在 `LoadScene.cs` 中走独立分支：

```
Town 场景初始化流程：
LoadScene → Define.openTraffic = true
  → TrafficManager.OnEnterScene(sceneCfgId=22)
    → GleyNav.Init("road_traffic_fl.json")  // 加载路点
    → RoadPointsToTrafficWaypoints()        // 转换为 TrafficWaypoint
  → 跳过 CityManager.ChangeCity()          // 不加载 DotsCity
  → VehicleAIPathPlanningComponent 直接使用 WaypointGraph 驱动
```

> **已完成改动**（见 [verification-todo.md](verification-todo.md)）：LoadScene.cs 已修改 Town 分支 + scene.xlsx 已启用。

### 8.2 数据格式适配

S1Town 的 `road_traffic_fl.json` 是 nodes+links 图结构，缺少 Miami 数据的部分字段：

| 缺失字段 | 影响 | 适配方案 |
|---------|------|---------|
| `neighbors` / `prev` | 路点寻路 | 从 links 数组的 from/to 反推，构建邻接表 |
| `OtherLanes` | 变道（P1） | 从 links.lanes 信息推导平行车道路点对应关系 |
| `cycle` | 信号灯相位 | S1Town 路口多为无灯路口，默认 cycle=0，有灯路口在 CfgJunction 中配置 |
| `road_type` | 限速 | 从 links.road_id 映射 |

**转换方案**：在 GleyNav 加载层增加格式检测，若 JSON 包含 `nodes` + `links` 顶层字段则走图结构解析分支，转换为 `List<RoadPoint>` 后统一进入后续管线。

### 8.3 场景参数差异

碰撞躲避和路口决策的核心参数需按场景缩放：

| 参数 | City/Sakura | S1Town | 来源 |
|------|------------|--------|------|
| 碰撞检测距离 | 9m | 6m | VehicleAIContext |
| 侧闪最大时长 | 2500ms | 1500ms | RCCAIAvoidFSM |
| 路口前瞻路点数 | N=5 | N=3 | JunctionDecisionFSM |
| 路口决策超时 | 3s | 2s | JunctionDecisionFSM |

> 这些参数从 `CfgTrafficSceneProfile` 配置表读取，客户端在场景初始化时缓存。

### 8.4 无灯路口处理

S1Town 大量路口无信号灯（junction_id 有值但无 CfgJunction 配置）。JunctionDecisionFSM 需增加无灯路口路径：

```
Approaching → 查 CfgJunction（按 JunctionId 索引）
  有配置 → WaitForLights（现有流程）
  无配置（无灯路口） → 检查 CfgJunction.IsGiveWay 标记
    是 → GiveWay（让行，等待交通间隙后通过）
    否 → 减速通过（无需上报服务端，仅客户端本地减速）
```

> **IsGiveWay 字段来源**：定义在 `CfgJunction` 配置表中（需扩展，见 [protocol.md](protocol.md) §4）。
> 无灯路口也需要 CfgJunction 配置行（EntranceCount + IsGiveWay），只是不关联 CfgJunctionPhase 相位数据。
