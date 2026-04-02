# 大世界交通系统 GTA5 式重构设计

> 基于 GTA5 原生交通系统思想，重构大世界交通系统架构。不参考小镇交通实现。

## 1. 需求回顾

- 交通车辆在大世界路网自主行驶（≥20辆）
- 路口信号灯决策正确（红停绿行黄视人格）
- 碰撞避让 6 态升级链工作正常
- 变道系统工作（超车、避障）
- 人格参数驱动差异化行为
- 无死锁、无穿模、无飞天

## 2. 架构设计

### 2.1 GTA5 四层架构

```
┌─────────────────────────────────────────────────┐
│                 调度层 TrafficSystem             │
│  Spawner · Despawner · DensityControl · LOD     │
├─────────────────────────────────────────────────┤
│              决策层 VehicleAI (per vehicle)      │
│  JunctionFSM · AvoidanceFSM · LaneChangeFSM    │
│  PersonalityDriver (参数化所有阈值)              │
├─────────────────────────────────────────────────┤
│              控制层 VehicleController            │
│  SpeedController · SteeringController           │
│  PathFollower (Catmull-Rom样条)                  │
├─────────────────────────────────────────────────┤
│              数据层 TrafficData                  │
│  TrafficRoadGraph · TrafficPathfinder           │
│  SignalLightCache · VehicleRegistry             │
└─────────────────────────────────────────────────┘
```

### 2.2 系统边界

| 层 | 工程 | 职责 |
|----|------|------|
| 数据层 | 客户端 | 路网图、寻路、信号灯缓存 |
| 决策层 | 客户端 | 所有 AI 决策本地执行，不依赖服务端 |
| 控制层 | 客户端 | 速度/转向/路径跟随 |
| 调度层-生成 | 服务端 | 密度管理、生成/回收决策、信号灯计时 |
| 调度层-LOD | 客户端 | AI LOD 降频 |

### 2.3 与现有系统的关系

**保留**：
- TrafficRoadGraph（路网数据结构）
- TrafficPathfinder（A* 寻路）
- PersonalityDriver（人格参数，需集成到 VehicleAI）
- 服务端 DensityManager / ServerRoadNetwork / TrafficLightSystem

**重构**：
- TownVehicleDriver → 拆分为 VehicleAI + VehicleController
- BigWorldTrafficSpawner → 简化，仅负责生成/回收调度
- JunctionDecisionFSM / AvoidanceUpgradeChain / LaneChangeController → 集成到 VehicleAI

**移除**：
- DrivingAIExternal（Gley 耦合，交通车辆不使用）
- Gley TrafficManager 对交通车辆的注册（改为自管理）

## 3. 详细设计

### 3.1 客户端类设计

#### GTA5TrafficSystem（调度层入口）

替代 BigWorldTrafficSpawner，职责：
- 管理所有交通车辆的生命周期
- 维护 VehicleRegistry（活跃车辆列表）
- 接收服务端生成/销毁指令
- AI LOD 管理（按距离降频）
- 信号灯状态缓存（接收 TrafficLightStateNtf）

```csharp
public class GTA5TrafficSystem : MonoBehaviour
{
    // 单例，场景级别
    private Dictionary<int, GTA5VehicleAI> _vehicles;
    private SignalLightCache _signalCache;
    private TrafficRoadGraph _roadGraph;      // 复用现有
    private TrafficPathfinder _pathfinder;    // 复用现有

    // 邻近车辆空间查询（50m 网格）
    private SpatialGrid<GTA5VehicleAI> _spatialGrid;

    // 服务端消息处理
    void OnTrafficVehicleSpawn(OnTrafficVehicleReq req);
    void OnTrafficVehicleDespawn(int entityId);
    void OnTrafficLightState(TrafficLightStateNtf ntf);

    // 空间查询：返回 pos 周围 radius 内同向车辆
    List<GTA5VehicleAI> QueryNearby(Vector3 pos, float radius);

    // LOD 更新
    void UpdateLOD(Vector3 playerPos);
}
```

**初始化流程**：
1. 场景加载完成 → `Init()` 获取 TrafficRoadGraph 和 TrafficPathfinder 引用
2. 注册协议回调：OnTrafficVehicleReq / TrafficLightStateNtf
3. 创建 SignalLightCache 和 SpatialGrid（50m 网格）
4. 等待服务端下发 openTraffic 标志后开始处理生成请求

**销毁流程**：
1. 场景切换 → `Dispose()` 按逆序执行
2. 遍历 `_vehicles` 逐辆销毁（先 AI → 再 Controller → 再 GameObject）
3. 注销协议回调
4. 清理 SpatialGrid / SignalLightCache / Pathfinder 缓存

**SpatialGrid 更新**：每帧 Update 中遍历活跃车辆更新网格位置，O(n) 复杂度。
查询范围：碰撞避让 30m、变道安全 30m（后方 20m + 前方 30m）。
LOD 联动：Minimal 级别车辆不参与查询（不更新网格位置）。

#### GTA5VehicleAI（决策层，per vehicle）

统一的车辆 AI 控制器，拥有三个子 FSM：

```csharp
public class GTA5VehicleAI : MonoBehaviour
{
    // 子系统（组合模式，非继承）
    private JunctionDecisionFSM _junctionFSM;
    private AvoidanceUpgradeChain _avoidanceFSM;
    private LaneChangeController _laneChangeFSM;
    private PersonalityDriver _personality;

    // 控制层输出
    private GTA5VehicleController _controller;

    // 决策输入
    private TrafficRoadGraph _roadGraph;
    private SignalLightCache _signalCache;

    // AI LOD 级别
    public enum AILod { Full, Reduced, Minimal }
    public AILod CurrentLod;

    void UpdateAI(float dt)
    {
        if (CurrentLod == AILod.Minimal) return; // 超远距离不更新

        // 1. 路口决策（最高优先级）
        _junctionFSM.Evaluate(dt, _personality, _signalCache);

        // 2. 碰撞避让
        _avoidanceFSM.Evaluate(dt, _personality, nearbyVehicles);

        // 3. 变道评估（路口内禁止）
        if (!_junctionFSM.IsInJunction)
            _laneChangeFSM.Evaluate(dt, _personality);

        // 4. 综合输出到控制层
        float targetSpeed = ComputeTargetSpeed();
        _controller.SetTargetSpeed(targetSpeed);
        _controller.SetLaneOffset(_laneChangeFSM.LateralOffset);
    }
}
```

#### GTA5VehicleController（控制层）

替代 TownVehicleDriver 的移动逻辑：

```csharp
public class GTA5VehicleController : MonoBehaviour
{
    // 路径跟随（复用 Catmull-Rom）
    private List<Vector3> _pathPoints;
    private int _currentSegment;
    private float _splineT;

    // 速度控制
    private float _currentSpeed;
    private float _targetSpeed;
    private float _maxSpeed;

    // 转向
    private float _laneOffset; // 变道横向偏移

    // Y 坐标修正
    private float _groundY;
    private int _raycastFrame;

    void UpdateMovement(float dt)
    {
        // 速度平滑趋近目标
        _currentSpeed = Mathf.MoveTowards(_currentSpeed, _targetSpeed, accel * dt);

        // 样条参数推进
        _splineT += (_currentSpeed * dt) / segmentLength;

        // Catmull-Rom 插值
        Vector3 pos = CatmullRom(p0, p1, p2, p3, _splineT);

        // 变道横向偏移
        pos += transform.right * _laneOffset;

        // Y 坐标 Raycast 修正（每 5 帧）
        if (Time.frameCount % 5 == _raycastFrame)
            CorrectGroundY(ref pos);

        // 弯道减速
        float curveAngle = Vector3.Angle(prevTangent, currTangent);
        if (curveAngle > 25f)
            _targetSpeed *= Mathf.Lerp(1f, 0.55f, (curveAngle - 25f) / 65f);

        transform.position = pos;
        transform.rotation = Quaternion.LookRotation(tangent);
    }
}
```

#### SignalLightCache（数据层）

客户端信号灯状态缓存：

```csharp
public class SignalLightCache
{
    // junction_id → entrance_idx → (command, remainingMs, updateTime)
    private Dictionary<int, Dictionary<int, LightState>> _states;

    // 从服务端通知更新
    void OnStateNtf(int junctionId, int entranceIdx, int command, int remainingMs);

    // AI 查询：某入口当前是什么灯
    LightCommand GetCommand(int junctionId, int entranceIdx);

    // 本地插值：基于 remainingMs 和 elapsed 推算当前状态
    LightCommand GetInterpolatedCommand(int junctionId, int entranceIdx);
}
```

### 3.2 FSM 改造要点

#### JunctionDecisionFSM 改造

- **移除**：对 Gley WaypointEvents 的依赖
- **新增**：直接查询 SignalLightCache 获取灯态
- **新增**：人格参数驱动黄灯决策（personality.RunsAmberLights）
- **新增**：死锁防护：等待超时 5s 后进入强制通过模式，同一路口通过令牌机制控制（同时只放行一个方向），超时车辆按随机 0~2s 延迟排队申请令牌

#### AvoidanceUpgradeChain 改造

- **保留**：6 态升级链逻辑
- **改造**：阈值全部从 PersonalityDriver 读取（不硬编码）
- **改造**：对向来车过滤用 dot product（已有，确认保留）
- **新增**：蠕行速度保留 0.5 m/s（EmergencyBrake 态），当距离 < 1.5m 完全停车（0 m/s）；前方障碍消除（距离 > 8m）时恢复 Decelerate → Idle

#### LaneChangeController 改造

- **保留**：5 态 FSM
- **改造**：安全检查增加速度预测（t+2s 位置估算）
- **改造**：变道积极性从 PersonalityDriver.WillChangeLanes 读取

### 3.3 服务端改造

#### TrafficLightSystem 接入

当前 TrafficLightSystem 代码已完整但未初始化。需要：

1. 场景加载时调用 `InitJunctions()` 加载路口配置
2. 每帧 Tick 后调用 `GetChangedNtfs()` 广播状态变化
3. 新玩家进入 AOI 时调用 `GetAllNtfs()` 同步全量状态

#### 路口配置来源

服务端从 ServerRoadNetwork 的路口数据提取（与客户端 TrafficRoadGraph 共享同一份 road_traffic.json 源数据）：
- junction_id、入口数量、入口方向
- 默认 2 相位，可配置表覆盖
- 服务端启动时解析 road_traffic.json 中的 junctions 字段，生成 JunctionConfig 列表

#### DensityManager 补全

完成 `trySpawnOneVehicle()` 的 TODO，调用实际生成逻辑。

### 3.4 消息流序列图

```
[场景加载]
  服务端 DensityManager ──→ OnTrafficVehicleReq ──→ 客户端 GTA5TrafficSystem
  服务端 TrafficLightSystem ──→ TrafficLightStateNtf(全量) ──→ 客户端 SignalLightCache

[车辆生成]
  GTA5TrafficSystem.OnTrafficVehicleSpawn()
    → 实例化 Vehicle GameObject
    → AddComponent<GTA5VehicleAI> + <GTA5VehicleController>
    → AI.Init(personality, roadGraph, signalCache, spatialGrid)
    → Controller.Init(pathPoints, maxSpeed)
    → 注册到 _vehicles 和 _spatialGrid

[运行时每帧]
  GTA5TrafficSystem.Update()
    → UpdateLOD(playerPos)          // 更新各车 AI LOD 级别
    → 遍历 _vehicles: ai.UpdateAI(dt)  // 决策
    → 遍历 _vehicles: ctrl.UpdateMovement(dt) // 执行

[信号灯变化]
  服务端 TrafficLightSystem.Tick() → GetChangedNtfs()
    → 广播 TrafficLightStateNtf ──→ 客户端 SignalLightCache.OnStateNtf()
    → JunctionDecisionFSM 下次 Evaluate 时查询最新状态

[车辆销毁]
  服务端超距/超时 → 客户端 GTA5TrafficSystem.OnTrafficVehicleDespawn()
    → 从 _spatialGrid 和 _vehicles 移除
    → Destroy AI → Destroy Controller → Destroy GameObject
```

### 3.5 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `Traffic/GTA5TrafficSystem.cs` | 调度层入口 |
| 新建 | `Traffic/GTA5VehicleAI.cs` | 决策层统一控制器 |
| 新建 | `Traffic/GTA5VehicleController.cs` | 控制层（路径跟随+速度+转向） |
| 新建 | `Traffic/SignalLightCache.cs` | 信号灯缓存 |
| 新建 | `Traffic/SpatialGrid.cs` | 邻近车辆空间查询网格 |
| 改造 | `Traffic/JunctionDecisionFSM.cs` | 解耦 Gley，接入 SignalLightCache |
| 改造 | `Traffic/AvoidanceUpgradeChain.cs` | 阈值参数化 |
| 改造 | `Traffic/LaneChangeController.cs` | 安全检查增强 |
| 改造 | `Traffic/PersonalityDriver.cs` | 补充缺失参数字段，增加默认兜底 |
| 改造 | `Vehicle.cs` | 交通车辆初始化改为 GTA5TrafficSystem |
| 改造 | 服务端 `traffic_light_system.go` | 补全初始化和广播 |
| 改造 | 服务端 `density_manager.go` | 补全生成逻辑 |
| 废弃 | `Traffic/DrivingAIExternal.cs` | Gley 耦合，不再用于交通车辆 |
| 废弃 | `Traffic/BigWorldTrafficSpawner.cs` | 功能迁移到 GTA5TrafficSystem |

## 4. 事务性设计

交通系统无跨服务事务需求。信号灯状态由服务端单点计时，客户端只读。

## 5. 接口契约

### 5.1 协议复用（零新增）

| 协议 | 用途 |
|------|------|
| TrafficLightStateNtf | 信号灯状态通知（JunctionId, EntranceIdx, Command, RemainingMs） |
| OnTrafficVehicleReq | 交通车辆生成通知 |
| VehiclePersonalityNtf | 人格参数下发 |

### 5.2 服务端→客户端数据流

1. 玩家进入场景 → 服务端下发 AOI 内所有信号灯状态
2. 信号灯变化 → 广播 TrafficLightStateNtf
3. 密度管理触发 → 下发 OnTrafficVehicleReq 生成/销毁

## 6. 验收测试方案

### TC-001 交通车辆基本行驶

前置条件：已登录大世界场景（Miami）
操作步骤：
1. [script-execute] 查询活跃交通车辆数量
2. [验证] 车辆数 ≥ 10
3. [script-execute] 采样 3 辆车的位置和速度，间隔 2s 重复 3 次
4. [验证] 车辆位置持续变化、速度 > 0、Y 坐标合理（40~120）

### TC-002 路口信号灯决策

前置条件：已登录，有活跃交通车辆
操作步骤：
1. [script-execute] 找到最近的有信号灯路口及其停车线位置
2. [script-execute] 每 1s 采样路口前 20m 内车辆的速度和灯态，持续 15s
3. [验证] 红灯期间：停车线前车辆速度 < 0.5 m/s
4. [验证] 绿灯变化后 3s 内：至少一辆车速度 > 2 m/s

### TC-003 碰撞避让

前置条件：已登录，有活跃交通车辆
操作步骤：
1. [script-execute] 查找 2 辆前后跟行的车辆
2. [验证] 后车与前车保持安全距离（≥3m）
3. [验证] 无车辆重叠（穿模）

### TC-004 无飞天/穿地

前置条件：已登录，有活跃交通车辆
操作步骤：
1. [script-execute] 采样所有车辆 Y 坐标，每 3s 一次，共 5 次
2. [验证] 所有 Y 在 [40, 120] 范围内
3. [验证] 相邻采样 Y 差值 < 5m（无突变）

### TC-005 人格差异化

前置条件：已登录，有活跃交通车辆
操作步骤：
1. [script-execute] 读取 3 辆车的人格类型和当前速度
2. [验证] 不同人格类型的车辆速度有差异

## 7. 风险缓解

| 风险 | 缓解 |
|------|------|
| 服务端信号灯未初始化 | 客户端容错：无信号灯数据时默认绿灯通过 |
| Y 坐标 Raycast 失败 | 保留最后有效 Y，渐变而非跳变 |
| 大量车辆同时寻路 | 分帧计算，单帧最多 500 节点 |
| 路口死锁 | 5s 超时 + 随机延迟打破对称 |
| 变道碰撞 | 安全检查 + 执行中持续监测 |
| 人格参数未下发 | PersonalityDriver 内置默认参数（Normal 型），未收到 VehiclePersonalityNtf 时自动使用 |
| Raycast 帧集中 | _raycastFrame 按 entityId % 5 散列，避免同帧全车 Raycast |
