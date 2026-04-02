# 载具系统GTA5级提升 - 技术设计

## 1. 需求回顾

| ID | 标题 | 优先级 | 端 | 验收标准 |
|----|------|--------|----|----------|
| REQ-001 | 重量转移与抓地力曲线 | P0 | 客户端 | 加速后座感、刹车前倾、高速转弯内侧轮减载 |
| REQ-002 | 侧向阻尼与甩尾 | P0 | 客户端 | 高速急转弯车尾自然甩出、甩尾渐进非瞬间 |
| REQ-003 | 速度-转向衰减 | P1 | 客户端 | 低速转弯半径小、高速转向不突然失控 |
| REQ-004 | 碰撞网格变形链路 | P0 | 客户端 | 碰撞后外观可见变形或材质变暗 |
| REQ-005 | 损伤性能衰减 | P0 | 客户端 | HP<60%速度下降、HP<40%转向偏移、HP<20%爆胎 |
| REQ-006 | 损伤服务端同步 | P0 | 双端 | 他人可见烟/火特效、HP=0爆炸不可驾驶 |
| REQ-007 | 漂移检测与计分 | P0 | 客户端 | 拉手刹+转向触发漂移、有计分显示 |
| REQ-008 | 手刹强化与漂移反馈 | P0 | 客户端 | 后轮轮胎痕迹+烟雾、相机漂移感 |
| REQ-009 | 翻车恢复 | P1 | 双端 | 翻车后按键1s内翻正 |
| REQ-010 | 特技扩展 | P1 | 客户端 | 持续漂移3s触发特技、空中360旋转被检测 |

**技术约束**：物理计算 ≤2ms/帧（手机端）；损伤同步仅推送阶段变化不同步网格顶点；复用现有组件框架不引入新框架。

## 2. 架构设计

### 2.1 系统边界

**客户端改动（freelifeclient）**：
- `CarControl.cs` — 重量转移激活、刹车分配、转向衰减
- `CarWheelController.cs` — 抓地力曲线、手刹强化
- `VehiclePhysicDampComp.cs` — 侧向阻尼调整
- `VehicleCollisionHandlerComp.cs` — 碰撞→变形链路确认、碎片粒子
- `VehicleDamage.cs` — 网格变形（已有，确认接入）
- `VehicleDisfeatureComp.cs` — 损伤特效（已有4级，保留）
- 新增 `DriftDetectorComp.cs` — 漂移检测+计分
- 新增 `DamagePerformanceModifier.cs` — 损伤→性能衰减
- `VehicleStuntComp.cs` — 新增漂移特技/360旋转/两轮行驶检测
- `VehicleEngineComp.cs` — 性能衰减接口接入

**服务端改动（P1GoServer）**：
- `cvehicle/vehicle_status.go` — 新增 DamageHp/DamageStage 字段
- `vehicle/vehicle_ops.go` — 新增翻车恢复处理
- 新增损伤计算+爆炸回收定时器

**协议工程（old_proto）**：
- `scene/vehicle.proto` — 新增 VehicleDamageNtf、VehicleFlipReq

### 2.2 模块关系

```
输入层:
  VehicleInput (throttle/brake/steer/handbrake)
      │
物理层:
  CarControl ──► CarWheelController ──► WheelCollider
      │                │
      ├─ COMAssister   ├─ EvaluateGrip()    ◄── 新增
      │  (重量转移)     ├─ handBrakeTractionLoss
      │                └─ wheelSlipAmountSideways ──► DriftDetectorComp  ◄── 新增
      │
      ├─ VehiclePhysicDampComp (_rbLeftVelocityFactor)
      │
      └─ SteeringHelper (速度-转向衰减)
          
碰撞/损伤层:
  VehicleCollisionHandlerComp
      │
      ├─ VehicleDamage.OnCollision()  ──► 网格顶点变形
      │
      ├─ DamagePerformanceModifier    ◄── 新增
      │      │
      │      ├─► CarControl.maxspeed (衰减)
      │      ├─► CarControl.maxSteerAngle (偏移)
      │      └─► CarWheelController.gripFactor (归零=爆胎)
      │
      └─ VehicleDisfeatureComp  ──► 烟/火特效（已有）
          
同步层:
  VehicleDamageNtf ◄──── 服务端 VehicleStatusComp.DamageHp/Stage
  VehicleFlipReq  ────► 服务端验证 → 客户端力矩施加

特技层:
  DriftDetectorComp ──► VehicleStuntComp ──► UploadGameEventReq
```

### 2.3 数据流

```
[输入] throttle/brake/steer/handbrake
   │
   ▼
[CarControl.FixedUpdate]
   ├─ COMAssister 根据 angularVelocity 偏移重心
   ├─ Engine() 计算扭矩，应用 DamagePerformanceModifier.speedMultiplier
   ├─ Wheels() 分配轮胎力矩
   │     └─ CarWheelController.EvaluateGrip(slipAmount) 替代固定 gripFactor
   ├─ SteeringHelper 应用速度-转向衰减曲线
   └─ BrakeDistribution() 前70%/后30% 分配
   │
   ▼
[VehiclePhysicDampComp.FixedUpdate]
   └─ 侧向速度 *= _rbLeftVelocityFactor (0.85)
   │
   ▼
[碰撞发生] OnCollisionEnter
   ├─ VehicleCollisionHandlerComp.CustomCollisionEnter()
   │     ├─ _vehicleDamage.Initialize() + OnCollision() → 网格变形
   │     │     └─ 碎片粒子生成（新增）
   ├─ 发送 VehicleDamageReq（新增协议）→ 服务端
   │
   ▼
[服务端] 接收 VehicleDamageReq（新增 handler）
   ├─ 反作弊校验（单次伤害上限/频率限制/速度合理性）
   ├─ 计算 HP 减少，更新 DamageStage
   ├─ 广播 VehicleDamageNtf 给 AOI 内所有客户端
   └─ HP=0 → 设置不可驾驶 + 回收定时器
   │
   ▼
[客户端] 接收 VehicleDamageNtf
   ├─ DamagePerformanceModifier 应用性能衰减
   ├─ VehicleDisfeatureComp 更新烟/火特效
   └─ HP=0 → ExplosionComp 触发爆炸
```

## 3. 详细设计

<!-- 以下各节按 REQ 分组展开 -->

### 3.1 驾驶手感（REQ-001~003）

#### 3.1.1 重量转移实现（REQ-001）

**锁定决策**：启用 COMAssisterTypes 被注释的实现，加速时重心后移、刹车时前移、转弯时侧移。

**现状分析**：`CarControl.cs:829-850` 已有 COMAssister switch，但当前默认 `Off`。现有逻辑仅基于 `angularVelocity.y` 偏移 X 轴，未处理加速/刹车的前后偏移。

**实现方案**：

修改 `CarControl.OnFixedUpdate()` 中 COMAssister 逻辑块：

```csharp
// CarControl.cs — COMAssister 激活
// 将 COMAssister 默认值从 Off 改为 Medium
public COMAssisterTypes COMAssister = COMAssisterTypes.Medium;

// 在 switch 块后，补充基于线性加速度的前后偏移
Vector3 localAccel = transform.InverseTransformDirection(rb.velocity - _prevVelocity) / Time.fixedDeltaTime;
_prevVelocity = rb.velocity; // 新增字段 private Vector3 _prevVelocity;

float comShiftZ = 0f; // 前后偏移
float comShiftX = 0f; // 左右偏移（已有 locVel.y 逻辑）

// 加速 → 重心后移（Z 负方向），增加后轮抓地力
// 刹车 → 重心前移（Z 正方向），增加前轮锁定感
comShiftZ = Mathf.Clamp(-localAccel.z * comTransferRate, -maxComShiftZ, maxComShiftZ);

// 转弯 → 重心侧移（X 方向），内侧轮减载
comShiftX = Mathf.Clamp(-localAccel.x * comTransferRate, -maxComShiftX, maxComShiftX);

rb.centerOfMass = new Vector3(
    COM.localPosition.x + comShiftX,
    COM.localPosition.y,
    COM.localPosition.z + comShiftZ
);
```

**新增参数**（在 `CarControllerConfig.cs` 或 `CarControl` 中）：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `comTransferRate` | float | 0.002f | 加速度→COM偏移映射系数 |
| `maxComShiftZ` | float | 0.15f | 前后偏移上限(m) |
| `maxComShiftX` | float | 0.10f | 左右偏移上限(m) |

> 待细化：具体参数需运行时调试，上表为初始值，后续通过配置表化。

#### 3.1.2 抓地力曲线（REQ-001）

**锁定决策**：在 CarWheelController 中实现 `float EvaluateGrip(float slipAmount)` 替代固定 gripFactor。

**现状分析**：`CarWheelController.cs` 当前使用固定 `materialForwardStiffness`(1.2) 和 `materialSidewayStiffness`(1.2) 作为摩擦力系数，通过 `WheelFrictionCurve` 设置到 `WheelCollider`。

**实现方案**：

在 `CarWheelController` 中新增：

```csharp
// CarWheelController.cs — 抓地力曲线
// Pacejka 简化模型：低 slip 线性增长 → 峰值 → 下降
[Header("Grip Curve")]
public AnimationCurve gripCurve = new AnimationCurve(
    new Keyframe(0f, 0f),        // 无滑移 = 无侧向力
    new Keyframe(0.08f, 1.0f),   // 峰值抓地力（轮胎最佳工作点）
    new Keyframe(0.25f, 0.85f),  // 过峰衰减
    new Keyframe(1.0f, 0.7f)     // 完全打滑 → 残余摩擦
);

/// <summary>
/// 基于当前滑移量评估抓地力系数，替代固定 gripFactor
/// </summary>
public float EvaluateGrip(float slipAmount)
{
    float normalizedSlip = Mathf.Clamp01(Mathf.Abs(slipAmount));
    return gripCurve.Evaluate(normalizedSlip);
}
```

**集成点**：在 `CarWheelController` 的 FixedUpdate 中更新 WheelFrictionCurve：

```csharp
// 替换原固定 stiffness 赋值
float dynamicGrip = EvaluateGrip(totalSlip);
forwardFrictionCurve.stiffness = materialForwardStiffness * dynamicGrip;
sidewaysFrictionCurve.stiffness = materialSidewayStiffness * dynamicGrip;
wheelCollider.forwardFriction = forwardFrictionCurve;
wheelCollider.sidewaysFriction = sidewaysFrictionCurve;
```

> 待细化：曲线峰值 slip 点（0.08）和下降斜率需运行时迭代。

#### 3.1.3 侧向阻尼调整（REQ-002）

**锁定决策**：`_rbLeftVelocityFactor` 从 0.98 降到 ~0.85。

**现状分析**：`VehiclePhysicDampComp.cs:134` 默认 `_rbLeftVelocityFactor = 0.98f`，在 `OnClear()` 中也重置为 0.98f。该值在 FixedUpdate 中乘以侧向速度分量，0.98 意味着每帧仅衰减 2% 侧向速度，车辆几乎不会侧滑。

**实现方案**：

```csharp
// VehiclePhysicDampComp.cs
// 将默认值从 0.98 改为基于速度的动态阻尼
public float _rbLeftVelocityFactorLowSpeed = 0.95f;  // 低速保持较高抓地
public float _rbLeftVelocityFactorHighSpeed = 0.82f;  // 高速允许甩尾
public float _highSpeedThreshold = 80f; // km/h

// 在 FixedUpdate 中
float speedKmh = _vehicle.speed; // speed 已是 km/h
float t = Mathf.Clamp01(speedKmh / _highSpeedThreshold);
float dynamicFactor = Mathf.Lerp(_rbLeftVelocityFactorLowSpeed, _rbLeftVelocityFactorHighSpeed, t);
// 应用到侧向速度衰减
```

**效果**：低速（<30km/h）车辆稳定，高速（>80km/h）急转弯时侧向速度保留更多，产生渐进甩尾。

#### 3.1.4 速度-转向衰减（REQ-003）

**锁定决策**：低速增大 steerAngle，高速减小，在已有 SteeringHelper 基础上加速度-转向衰减曲线。

**现状分析**：`CarControl.cs:166-169` 已有 `steerAngleCurve`（AnimationCurve）和 `maxSteerAngle=40`/`highspeedsteerAngle=5`/`highspeedsteerAngleAtspeed=120`。`CarControllerConfig.cs:104` 也有 `steerAngleCurve`。

**实现方案**：

确认 `steerAngleCurve` 是否已在 `Wheels()` 中使用——如果 `steeringType == SteeringType.Curve` 已生效则只需调整曲线形状：

```csharp
// CarControl.cs — 确保使用 Curve 模式
public SteeringType steeringType = SteeringType.Curve;

// 重建默认曲线：低速40度，中速15度，高速5度
steerAngleCurve = new AnimationCurve(
    new Keyframe(0f, 40f, 0f, -0.3f),     // 静止：40度大转角
    new Keyframe(60f, 20f, -0.2f, -0.15f), // 60km/h：20度
    new Keyframe(120f, 8f, -0.08f, -0.05f),// 120km/h：8度
    new Keyframe(200f, 4f)                  // 极速：4度微调
);
```

**集成点**：在 `Wheels()` 方法的转向计算中，根据 `_vehicle.speed` 从曲线采样 `steerAngle`。已有 `SteeringHelper` 的线性/角速度修正保留不变。

#### 3.1.5 刹车分配（REQ-001/002）

**锁定决策**：前后轮独立刹车力比例（前70%/后30%），急刹时后轮更容易锁死甩尾。

**现状分析**：`CarWheelController.cs:126` 有 `brakingMultiplier`（Range 0-2），各轮独立。当前前后轮 brakingMultiplier 未区分。

**实现方案**：

在 `CarControl` 初始化时按前后轮设置 brakingMultiplier：

```csharp
// CarControl.Init() 或配置加载时
frontLeftWheelController.brakingMultiplier = 1.4f;  // 前轮 70% of 2.0 base
frontRightWheelController.brakingMultiplier = 1.4f;
rearLeftWheelController.brakingMultiplier = 0.6f;   // 后轮 30% of 2.0 base
rearRightWheelController.brakingMultiplier = 0.6f;
```

**与 ABS 交互**：ABS 检查 `wheelSlipAmountForward > ABSThreshold` 时减少刹车力矩，后轮分配少+低 brakingMultiplier 使其更易超过 ABSThreshold 锁死，配合降低的侧向阻尼产生甩尾。

### 3.2 渐进损伤（REQ-004~006）

#### 3.2.1 碰撞→变形链路（REQ-004）

**锁定决策**：VehicleCollisionHandlerComp 碰撞回调中调用 VehicleDamage 变形方法，传入碰撞点+力度。

**现状分析**：`VehicleCollisionHandlerComp.cs:547-552` **已接入** `_vehicleDamage.OnCollision(collision)`，条件是碰撞物 layer 匹配 `damageFilter`。`VehicleDamage.OnCollision()` 内部调用 `DamageMesh(impulse)` 进行顶点位移。链路已存在但需确认：
1. `_vehicleDamage` 是 `VehicleCollisionHandlerComp` 内 `new VehicleDamage()`（line 98），每次碰撞 `Initialize(_vehicle)` 再 `OnCollision`
2. `VehiclePrefabConfig.meshDeformation` 和 `damageFilter` 需确认 Prefab 上已开启
3. 轮子损伤（`DamageWheel`）被注释掉（line 797，2025/6/11 禁用），后续 REQ-005 爆胎需有条件恢复

**改动项**：
1. 确认所有车辆 Prefab 的 `meshDeformation=true` 和 `damageFilter` 包含所需 Layer
2. 新增碎片粒子：碰撞 impulse > 3.0 时在碰撞点生成 3-5 个轻量刚体碎片
3. 碎片规格：简单 cube mesh，随机大小 0.05-0.15m，2s 后通过对象池回收

```csharp
// VehicleCollisionHandlerComp.cs — CustomCollisionEnter() 末尾新增
if (impulse > 3.0f && isDamageCollision)
{
    SpawnDebrisParticles(collision.GetContact(0).point, collision.GetContact(0).normal, 
                         Mathf.Clamp((int)(impulse * 0.5f), 3, 5));
}

private void SpawnDebrisParticles(Vector3 point, Vector3 normal, int count)
{
    for (int i = 0; i < count; i++)
    {
        // 从对象池获取碎片预制体
        var debris = ObjectPoolUtility.Instance.LoadGameObjectSync(DebrisAssetKey);
        if (debris == null) continue;
        debris.transform.position = point + Random.insideUnitSphere * 0.2f;
        var debrisRb = debris.GetComponent<Rigidbody>();
        if (debrisRb != null)
            debrisRb.AddForce((normal + Random.insideUnitSphere) * 3f, ForceMode.Impulse);
        // 2s 后回收
        Timer.Register(2f, () => ObjectPoolUtility.Instance.Free(debris));
    }
}
```

#### 3.2.2 性能衰减系统（REQ-005）

**锁定决策**：引擎损伤(HP<60%)速度下降20%加速力下降30%；转向损伤(HP<40%)转向偏移±5度；车轮损伤(HP<20%)单轮抓地力归零。参数读取 CfgDamageStage。

**新增组件**：`DamagePerformanceModifier`（纯逻辑类，非 MonoBehaviour）

```csharp
// DamagePerformanceModifier.cs
namespace FL.Gameplay.Vehicle
{
    /// <summary>
    /// 根据损伤阶段计算性能衰减系数，由 CfgDamageStage 驱动
    /// </summary>
    public class DamagePerformanceModifier
    {
        private Vehicle _vehicle;
        
        // 当前生效的衰减值（从配置读取）
        public float SpeedMultiplier { get; private set; } = 1f;
        public float AccelMultiplier { get; private set; } = 1f;
        public float SteerOffsetDeg { get; private set; } = 0f;
        public float GripMultiplier { get; private set; } = 1f;
        public bool HasFlatTire { get; private set; } = false;
        public int FlatTireWheelIndex { get; private set; } = -1;
        
        public void Init(Vehicle vehicle) { _vehicle = vehicle; }
        
        /// <summary>
        /// 当 DamageStage 变化时调用，从 CfgDamageStage 读取衰减参数
        /// </summary>
        public void OnDamageStageChanged(int stageCfgId)
        {
            if (!ConfigLoader.DamageStageMap.TryGetValue(stageCfgId, out var cfg))
            {
                ResetAll();
                return;
            }
            SpeedMultiplier = 1f - cfg.speedPenaltyRate;
            GripMultiplier = 1f - cfg.gripPenaltyRate;
            HasFlatTire = cfg.gripPenaltyRate >= 1f;
            // 转向偏移和爆胎轮由服务端决定（VehicleDamageNtf 携带），
            // 确保多客户端一致。本地仅平滑过渡到目标值。

        /// <summary>
        /// 由 VehicleDamageNtf handler 调用，传入服务端决定的确定性值
        /// </summary>
        public void ApplyServerDeterminedValues(float steerOffsetDeg, int flatTireIndex)
        {
            _targetSteerOffset = steerOffsetDeg;
            FlatTireWheelIndex = flatTireIndex;
        }
        
        private float _targetSteerOffset;
        // 在 Update 中平滑过渡，避免跳变
        public void SmoothUpdate(float dt)
        {
            SteerOffsetDeg = Mathf.Lerp(SteerOffsetDeg, _targetSteerOffset, dt * 3f);
        }
        
        private void ResetAll() { SpeedMultiplier = 1f; SteerOffsetDeg = 0f; GripMultiplier = 1f; HasFlatTire = false; }
    }
}
```

**集成点**：

| 调用方 | 集成位置 | 方式 |
|--------|----------|------|
| `CarControl.maxspeed` | `Engine()` 方法中计算有效最大速度 | `effectiveMaxSpeed = rawMaxspeed * modifier.SpeedMultiplier` |
| `CarControl.maxEngineTorque` | `Engine()` 方法中计算有效扭矩 | `effectiveTorque = rawMaxEngineTorque * modifier.AccelMultiplier` |
| `CarControl` 转向 | `Wheels()` 方法中叠加偏移 | `steerAngle += modifier.SteerOffsetDeg` |
| `CarWheelController` | `EvaluateGrip()` | 如果是爆胎轮 `return 0f`，否则 `* modifier.GripMultiplier` |

**生命周期**：`DamagePerformanceModifier` 在 `VehicleEngineComp.Init()` 中创建，挂在 `Vehicle` 实例上。`VehicleDisfeatureComp.OnVehicleDamageStageChanged()` 事件回调中同步调用 `modifier.OnDamageStageChanged()`。

#### 3.2.3 视觉反馈（REQ-004）

**锁定决策**：碰撞点局部材质变暗（_DamageMap）；已有4级烟火保留；增加碎片粒子。

**材质变暗方案**：

> 待细化：需确认 Shader 管线。两种候选：

| 方案 | 优点 | 缺点 |
|------|------|------|
| _DamageMap UV 贴图 | 精确碰撞点变暗，GTA5 风格 | 需额外 RT，Shader 改动大 |
| Vertex Color 烘焙 | 无额外纹理开销，代码简单 | 精度受顶点密度限制 |

**推荐方案**：Vertex Color（手机端性能优先）。碰撞时在 `DamageMesh()` 流程中同步修改碰撞区域顶点颜色为深色，Shader 中 `lerp(baseColor, damagedColor, vertexColor.r)` 混合。

**碎片粒子**：见 3.2.1 末尾 `SpawnDebrisParticles`，规格：3-5 个 cube，0.05-0.15m，2s 回收。

#### 3.2.4 服务端损伤同步（REQ-006）

**锁定决策**：新增 VehicleDamageNtf（vehicleEntityId, currentHp, damageStage），服务端推送。HP=0 触发爆炸+回收定时器。

**服务端改动**：

1. **VehicleStatusComp 扩展**（`cvehicle/vehicle_status.go`）：

```go
// 新增字段
type VehicleStatusComp struct {
    // ... 已有字段 ...
    DamageHp       int32  // 当前 HP，初始值从配置读取（如 1000）
    DamageMaxHp    int32  // 最大 HP
    DamageStage    int32  // 当前损伤阶段 CfgDamageStage.id
    IsDestroyed    bool   // HP=0 后标记
    DestroyTimer   int64  // 爆炸后回收倒计时（秒级时间戳）
}

SteerOffsetX100 int32  // 转向偏移*100（确定性计算：entityId+stage 哈希）
FlatTireIndex   int32  // 爆胎轮索引（确定性计算），-1=无爆胎

// ApplyDamage 应用碰撞伤害，返回是否阶段变化
func (c *VehicleStatusComp) ApplyDamage(damage int32, entityId uint64) (stageChanged bool) {
    if c.IsDestroyed { return false }
    c.DamageHp -= damage
    if c.DamageHp <= 0 {
        c.DamageHp = 0
        c.IsDestroyed = true
    }
    newStage := c.calcDamageStage()
    if newStage != c.DamageStage {
        c.DamageStage = newStage
        stageChanged = true
        // 确定性计算转向偏移和爆胎轮（用 entityId+stage 做哈希，多端一致）
        hash := int32((entityId*2654435761 + uint64(newStage)*40503) & 0xFFFFFFFF)
        cfg := config.GetDamageStageCfg(newStage)
        if cfg != nil && cfg.SteerPenaltyDeg > 0 {
            c.SteerOffsetX100 = (hash % (cfg.SteerPenaltyDeg * 200 + 1)) - cfg.SteerPenaltyDeg * 100
        }
        if cfg != nil && cfg.GripPenaltyRate >= 100 { // 爆胎
            c.FlatTireIndex = int32(hash & 0x3) // 0-3
        }
    }
    c.SetSync()
    return
}
```

2. **损伤上报（新增链路，非复用）**：

   > 注意：VehicleHashDamageInfo.SendDamageInfo() 仅做本地事件采集（PlayerManager.CollectLocalCrashData），不是网络协议。需新建完整的客户端→服务端损伤上报链路。

   **新增 VehicleDamageReq 协议**（客户端→服务端）：
   ```protobuf
   message VehicleDamageReq {
     uint64 vehicle_entity_id = 1;
     float collision_impulse = 2;    // 碰撞冲量
     float collision_speed = 3;      // 碰撞时速度(km/h)
   }
   ```

   **客户端发送时机**：`VehicleCollisionHandlerComp.CustomCollisionEnter()` 中，已有的碰撞冷却（0.5s）通过后，在变形+粒子之后发送 VehicleDamageReq。

   **服务端 handler**（`vehicle_ops.go` 新增 `OnVehicleDamage`）：
   - 反作弊校验：
     - 单次伤害上限 = MaxHP * 0.3（防一击秒杀）
     - 频率限制：同一辆车 0.5s 内只处理一次（与客户端冷却一致）
     - 速度合理性：collision_speed ≤ 车辆最大速度 * 1.5
   - 通过校验后：damage = min(impulse * damageFactor, MaxHP * 0.3)
   - 调用 `ApplyDamage(damage)` → 阶段变化时广播 `VehicleDamageNtf`
   - AI 交通车辆（无驾驶者）的损伤：由碰撞发起方客户端上报，服务端仅对有 TrafficVehicleComp 的实体计算损伤

3. **爆炸/报废流程**：
   - HP=0 → `IsDestroyed=true` → 广播 `VehicleDamageNtf(hp=0, stage=最终阶段)`
   - 启动回收定时器（30s），到期后 `scene.RemoveEntity(vehicleEntityId)`
   - 期间不可上车（`OnVehicle` 检查 `IsDestroyed`）

4. **AOI 全量同步（修复 CRITICAL-2）**：

   新玩家进入已损伤车辆 AOI 时，需从全量快照恢复损伤表现。
   - 在 `VehicleDataUpdate` proto（或 VehicleStatus sub-message）中新增损伤字段：
     ```protobuf
     message VehicleDamageInfo {
       int32 current_hp = 1;
       int32 max_hp = 2;
       int32 damage_stage = 3;
       bool is_destroyed = 4;
       int32 steer_offset_deg_x100 = 5; // 转向偏移*100（整型传输）
       int32 flat_tire_index = 6;       // 爆胎轮索引(-1=无爆胎)
     }
     ```
   - 服务端 `net_update/vehicle.go` 的 `getVehicleMsg` 中，从 VehicleStatusComp 读取损伤字段写入快照
   - 客户端收到全量 VehicleDataUpdate 时，初始化 VehicleDisfeatureComp + DamagePerformanceModifier 到对应阶段

5. **客户端接收 VehicleDamageNtf（增量）**：
   - 注册 `VehicleDamageNtf` handler
   - 更新 `VehicleStatusComp.stats.DamageStageCfgId` → 触发 `EventId.EVehicleDamageStageChange`
   - 已有 `VehicleDisfeatureComp` 监听此事件，自动更新烟/火特效
   - 同步调用 `DamagePerformanceModifier.OnDamageStageChanged()`
   - HP=0 → 触发 `ExplosionComp`（已有）

#### 3.2.5 配置表设计（REQ-005/006）

**CfgDamageStage 新增字段**：

| 字段 | 类型 | 说明 | 示例值 |
|------|------|------|--------|
| speedPenaltyRate | float | 速度衰减比（0~1） | Stage3=0.2, Stage4=0.5 |
| accelPenaltyRate | float | 加速力衰减比 | Stage3=0.3, Stage4=0.6 |
| steerPenaltyDeg | float | 转向随机偏移(度) | Stage2=0, Stage3=3, Stage4=5 |
| gripPenaltyRate | float | 抓地力衰减比 | Stage3=0, Stage4=0.3, Destroyed=1.0 |

**现有字段保留**：id, hp, canUse, destructEvent, disappearDistance, featureEffect, audio

**配置示例**：

| id | hp | canUse | speedPenaltyRate | accelPenaltyRate | steerPenaltyDeg | gripPenaltyRate | featureEffect |
|----|-----|--------|------------------|------------------|-----------------|-----------------|---------------|
| 1 | 80% | true | 0 | 0 | 0 | 0 | 轻烟 |
| 2 | 60% | true | 0.1 | 0.15 | 0 | 0 | 黑烟 |
| 3 | 40% | true | 0.2 | 0.3 | 3 | 0.1 | 小火 |
| 4 | 20% | true | 0.4 | 0.5 | 5 | 0.3 | 大火 |
| 5 | 0% | false | 1.0 | 1.0 | 0 | 1.0 | 爆炸 |

### 3.3 漂移/特技（REQ-007~010）

#### 3.3.1 DriftDetector 组件设计（REQ-007）

**锁定决策**：基于 wheelSlipAmountSideways 新增 DriftDetector，漂移角度+速度+持续时间计分。

**新增组件**：`DriftDetectorComp`（继承 Comp，实现 IUpdate）

```csharp
namespace FL.Gameplay.Vehicle
{
    /// <summary>
    /// 漂移检测+计分组件，挂载在 Vehicle 实体上
    /// </summary>
    public class DriftDetectorComp : Comp, IUpdate
    {
        private Vehicle _vehicle;
        
        // 漂移状态
        public bool IsDrifting { get; private set; }
        public float DriftAngleDeg { get; private set; }  // 车身朝向与速度方向夹角
        public float DriftDuration { get; private set; }   // 当前漂移持续时间
        public float DriftScore { get; private set; }      // 当前漂移得分
        public int ComboCount { get; private set; }        // 连漂次数
        
        // 判定阈值
        private float _slipThreshold = 0.3f;       // 后轮侧滑量阈值
        private float _speedThresholdKmh = 40f;    // 最低速度
        private float _minDurationToStart = 0.3f;  // 持续时间门槛
        private float _comboWindowSec = 2f;         // 连漫窗口
        
        // 计分参数（从 CfgDriftScore 加载）
        private float _angleWeight = 1f;
        private float _speedWeight = 0.5f;
        private float _comboMultiplierStep = 0.5f;  // 每次连漫额外倍率
        
        // 内部状态
        private float _preSlipTimer;    // 滑移持续计时
        private float _comboTimer;       // 连漫窗口计时
        private float _lastDriftEndTime;
        
        public void OnUpdate(float deltaTime)
        {
            if (_vehicle.Driver == null || !_vehicle.Driver.IsLocalPlayer()) return;
            
            float rearSlip = GetAverageRearSlip();
            float speedKmh = _vehicle.speed;
            
            // 计算漂移角度：车身前方与速度方向夹角
            if (_vehicle.rb.velocity.sqrMagnitude > 1f)
            {
                Vector3 velocityDir = _vehicle.rb.velocity.normalized;
                Vector3 forwardDir = _vehicle.transform.forward;
                DriftAngleDeg = Vector3.Angle(forwardDir, velocityDir);
                // 限制有效区间 5-90 度
                DriftAngleDeg = Mathf.Clamp(DriftAngleDeg, 0f, 90f);
            }
            
            bool slipCondition = rearSlip > _slipThreshold 
                                 && speedKmh > _speedThresholdKmh
                                 && DriftAngleDeg > 5f;
            
            if (slipCondition)
            {
                _preSlipTimer += deltaTime;
                if (_preSlipTimer >= _minDurationToStart && !IsDrifting)
                    StartDrift();
                if (IsDrifting)
                    UpdateDriftScore(deltaTime);
            }
            else
            {
                if (IsDrifting)
                    EndDrift();
                _preSlipTimer = 0f;
            }
            
            // 连漫窗口衰减
            if (!IsDrifting && ComboCount > 0)
            {
                _comboTimer += deltaTime;
                if (_comboTimer > _comboWindowSec)
                {
                    FinalizeScore();
                    ComboCount = 0;
                }
            }
        }
        
        private float GetAverageRearSlip()
        {
            var cc = _vehicle.VehicleEngineComp.CurrentVehicleControl as CarControl;
            if (cc == null) return 0f;
            return (Mathf.Abs(cc.rearLeftWheelController.wheelSlipAmountSideways) 
                  + Mathf.Abs(cc.rearRightWheelController.wheelSlipAmountSideways)) * 0.5f;
        }
        
        private void StartDrift()
        {
            IsDrifting = true;
            DriftDuration = 0f;
            // 检查连漫
            if (Time.time - _lastDriftEndTime < _comboWindowSec)
                ComboCount++;
            else
                ComboCount = 1;
            _comboTimer = 0f;
        }
        
        private void UpdateDriftScore(float dt)
        {
            DriftDuration += dt;
            float comboMult = 1f + (ComboCount - 1) * _comboMultiplierStep;
            // 每帧积分 = 角度 * 角度权重 + 速度 * 速度权重
            float frameScore = (DriftAngleDeg * _angleWeight 
                              + _vehicle.speed * _speedWeight) * dt * comboMult;
            DriftScore += frameScore;
        }
        
        private void EndDrift()
        {
            IsDrifting = false;
            _lastDriftEndTime = Time.time;
            // UI 显示当前段得分（通过事件）
            EventManager.Dispatch(EventId.EVehicleDriftScoreUpdate, DriftScore, ComboCount);
        }
        
        private void FinalizeScore()
        {
            // 最终得分结算，上报服务端
            if (DriftScore > 0)
            {
                var req = new UploadGameEventReq();
                req.Event = GameEvent.Drift;
                req.Duration = (long)(DriftDuration * 1000);
                NetCmd.UploadGameEvent(req);
            }
            DriftScore = 0f;
            DriftDuration = 0f;
        }
    }
}
```

**注册**：在 Vehicle Controller 的 `OnInit` 中 `AddComp<DriftDetectorComp>()`。

#### 3.3.2 手刹强化（REQ-008）

**锁定决策**：手刹时后轮抓地力骤降到 20%。

**现状分析**：`CarWheelController.cs:131` 已有 `handBrakeTractionLoss = 0.25f`，在手刹激活时应用到侧向摩擦。

**实现方案**：

将 `handBrakeTractionLoss` 从 0.25 提升到 0.80（即保留 20% 抓地力），并与新的抓地力曲线系统联动：

```csharp
// CarWheelController.cs — 手刹时的抓地力处理
// 在 FixedUpdate 更新摩擦力时
if (canHandbrake && carControl.handbrakeInput > 0.1f)
{
    // 手刹激活：后轮侧向摩擦骤降
    sidewaysFrictionCurve.stiffness *= (1f - handBrakeTractionLoss); 
    // handBrakeTractionLoss = 0.80 → 保留 20%
    forwardFrictionCurve.stiffness *= (1f - handBrakeTractionLoss * 0.5f);
    // 前向摩擦也适度降低，防止后轮完全卡死
}
```

**配合侧向阻尼**：手刹降低后轮抓地力 → `wheelSlipAmountSideways` 增大 → 侧向阻尼 0.82 保留更多侧滑 → 自然甩尾。

#### 3.3.3 漂移反馈系统（REQ-008）

**锁定决策**：轮胎烟雾+相机FOV+震动+引擎声浪。

**轮胎痕迹**：`SkidMarks` 系统已有（`CarSkidMarksManager`），漂移时 `totalSlip > threshold` 自动生成痕迹。痕迹宽度通过 `wheelWidth` 控制（已有），漂移时无需额外改动。

**轮胎烟雾**：

```csharp
// 在 DriftDetectorComp.UpdateDriftScore() 中，漂移期间每帧更新烟雾
private void UpdateDriftSmoke()
{
    var cc = _vehicle.VehicleEngineComp.CurrentVehicleControl as CarControl;
    if (cc == null) return;
    // 后轮位置生成烟雾
    SpawnOrUpdateSmoke(cc.rearLeftWheelController, DriftAngleDeg, _vehicle.speed);
    SpawnOrUpdateSmoke(cc.rearRightWheelController, DriftAngleDeg, _vehicle.speed);
}
```

烟雾规格：使用 `VehicleWheelParticleWrapper` 已有粒子系统，漂移时增大 `emissionRate`，与角度和速度正相关。

**相机效果**：

```csharp
// 漂移时通知相机系统
if (IsDrifting)
{
    CameraManager.SetFOVOffset(5f * Mathf.Clamp01(DriftAngleDeg / 45f)); // 最大+5度
    CameraManager.SetLateralOffset(
        Mathf.Sign(DriftAngleDeg) * 0.3f * Mathf.Clamp01(DriftAngleDeg / 45f));
    // CameraShakerComp 低频震动
    _vehicle.GetComp<CameraShakerComp>()?.Shake(0.02f, 0.5f); // 低幅值长持续
}
else
{
    CameraManager.SetFOVOffset(0f);
    CameraManager.SetLateralOffset(0f);
}
```

**音效**：漂移时通过 `AudioManager.Play3DAudioAt("vehicle_drift_tire_squeal", _vehicle.gameObject)` 播放轮胎啸叫，结束时停止。

#### 3.3.4 翻车恢复（REQ-009）

**锁定决策**：按键施加翻转力矩，1s 内恢复正位。新增 VehicleFlipReq 协议。

**现状分析**：`VehiclePhysicDampComp.cs` 已有 `IsVehicleTurnOver()`（>80度且全轮离地）和 `VehicleTurnOverFSM`（被注释掉的 fsm.Update）。已有 `VehicleRollBackControl()`（被注释）和 `VehicleRCSControl()`（空中姿态控制）。

**客户端实现**：

```csharp
// VehiclePhysicDampComp.cs — 新增翻车恢复方法
public void RequestFlipRecovery()
{
    if (!IsVehicleTurnOver()) return;
    // 发送服务端验证请求
    var req = new VehicleFlipReq { VehicleEntityId = _vehicle.NetId };
    NetCmd.VehicleFlip(req);
}

// 收到服务端 VehicleFlipRes(approved=true) 后执行分帧翻正协程
public async UniTaskVoid ExecuteFlipRecoveryAsync(CancellationToken ct)
{
    if (_vehicle == null || _vehicle.rb == null) return;
    _vehicle.rb.angularVelocity = Vector3.zero;
    // 轻微抬起防止卡地面
    _vehicle.rb.AddForce(Vector3.up * _vehicle.rb.mass * 3f, ForceMode.Impulse);
    
    float elapsed = 0f;
    float maxTime = 2f; // 最大翻正时间
    while (elapsed < maxTime)
    {
        ct.ThrowIfCancellationRequested();
        Vector3 currentUp = _vehicle.transform.up;
        float angle = Vector3.Angle(currentUp, Vector3.up);
        if (angle < 5f) break; // 已基本翻正
        
        // 每帧施加修正力矩
        Vector3 torqueAxis = Vector3.Cross(currentUp, Vector3.up).normalized;
        float torqueMag = _vehicle.rb.mass * angle * 0.3f;
        _vehicle.rb.AddTorque(torqueAxis * torqueMag);
        _vehicle.rb.angularVelocity *= 0.9f; // 阻尼防过冲
        
        elapsed += Time.fixedDeltaTime;
        await UniTask.Yield(PlayerLoopTiming.FixedUpdate, ct);
    }
    // 超时强制 teleport 到正位
    if (Vector3.Angle(_vehicle.transform.up, Vector3.up) > 15f)
    {
        var pos = _vehicle.transform.position + Vector3.up * 0.5f;
        var rot = Quaternion.LookRotation(_vehicle.transform.forward, Vector3.up);
        _vehicle.rb.velocity = Vector3.zero;
        _vehicle.rb.angularVelocity = Vector3.zero;
        _vehicle.transform.SetPositionAndRotation(pos, rot);
    }
}

// VehicleFlipRes handler：approved=false 时显示冷却剩余
public void OnVehicleFlipRes(VehicleFlipRes res)
{
    if (res.Approved)
        ExecuteFlipRecoveryAsync(_vehicle.DestroyCts.Token).Forget();
    else
        ShowCooldownHint(res.CooldownRemainMs);
}
```

**服务端处理**（`vehicle_ops.go`）：

```go
func (h *VehicleHandler) OnVehicleFlip(req *proto.VehicleFlipReq) (*proto.NullRes, *proto_code.RpcError) {
    // 1. 验证玩家是否在该车上
    // 2. 验证车辆是否翻车（可信任客户端，或检查服务端记录的最后朝向）
    // 3. 冷却检查（防频繁调用，10s CD）
    // 4. 广播翻车恢复事件给 AOI 内玩家
    return &proto.NullRes{}, nil
}
```

#### 3.3.5 特技扩展（REQ-010）

**锁定决策**：新增漂移特技(>3s)、360旋转、两轮行驶检测。

**在 VehicleStuntComp 中新增检测**：

```csharp
// VehicleStuntComp.cs — 新增检测算法

// 1. 漂移特技：持续漂移 > 3s
private float _driftStuntTimer;
private void CheckDriftStunt(float deltaTime)
{
    var driftComp = _thisVehicle.GetComp<DriftDetectorComp>();
    if (driftComp != null && driftComp.IsDrifting)
    {
        _driftStuntTimer += deltaTime;
        if (_driftStuntTimer > 3f)
        {
            UploadStuntEvent(GameEvent.DriftStunt, (long)(_driftStuntTimer * 1000));
            _driftStuntTimer = 0f; // 重置，下一个 3s 周期
        }
    }
    else
    {
        _driftStuntTimer = 0f;
    }
}

// 2. 360度旋转：累计 yaw 旋转 >= 360
private float _rotationAccumDeg;
private float _lastYaw;
private void CheckSpinStunt(float deltaTime)
{
    float currentYaw = _thisVehicle.transform.eulerAngles.y;
    float delta = Mathf.DeltaAngle(_lastYaw, currentYaw);
    _lastYaw = currentYaw;
    
    // 空中旋转：仅全轮离地时计算（排除地面漂移转向误触发）
    bool isAirborne = !_thisVehicle.VehicleEngineComp.IsAleastOneWheelGrounded();
    if (isAirborne)
    {
        _rotationAccumDeg += Mathf.Abs(delta);
        _spinTimer += deltaTime;
        if (_rotationAccumDeg >= 360f && _spinTimer < 3f) // 3s内完成360度才算特技
        {
            UploadStuntEvent(GameEvent.Spin360, 0);
            _rotationAccumDeg -= 360f;
        }
    }
    else
    {
        _rotationAccumDeg = 0f;
        _spinTimer = 0f;
    }
}

// 3. 两轮行驶：侧倾 > 45度且未翻车且有轮接地
private float _twoWheelTimer;
private bool _twoWheelReported; // 防止连续上报
private void CheckTwoWheelStunt(float deltaTime)
{
    float roll = Mathf.Abs(_thisVehicle.transform.eulerAngles.z);
    if (roll > 180f) roll = 360f - roll;
    
    bool isTwoWheel = roll > 45f && roll < 80f 
                      && _thisVehicle.VehicleEngineComp.IsAleastOneWheelGrounded();
    if (isTwoWheel)
    {
        _twoWheelTimer += deltaTime;
        if (_twoWheelTimer > 1f && !_twoWheelReported)
        {
            UploadStuntEvent(GameEvent.TwoWheelDrive, (long)(_twoWheelTimer * 1000));
            _twoWheelReported = true;
        }
    }
    else
    {
        if (_twoWheelReported && _twoWheelTimer > 1f)
        {
            // 结束时上报最终持续时间
            UploadStuntEvent(GameEvent.TwoWheelDrive, (long)(_twoWheelTimer * 1000));
        }
        _twoWheelTimer = 0f;
        _twoWheelReported = false;
    }
}
```

#### 3.3.6 配置表设计（REQ-007）

**新增 CfgDriftScore 表**：

| 字段 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| id | int | 主键 | 1 |
| slipThreshold | float | 后轮侧滑判定阈值 | 0.3 |
| speedThresholdKmh | float | 最低速度 | 40 |
| minDurationSec | float | 最短漂移时间 | 0.3 |
| comboWindowSec | float | 连漫窗口 | 2.0 |
| angleWeight | float | 角度计分权重 | 1.0 |
| speedWeight | float | 速度计分权重 | 0.5 |
| comboMultiplierStep | float | 每次连漫额外倍率增量 | 0.5 |
| driftStuntDurationSec | float | 漂移特技触发时长 | 3.0 |
| spin360BonusScore | int | 360旋转奖励分 | 500 |
| twoWheelBonusScorePerSec | int | 两轮行驶每秒奖励 | 200 |

## 4. 接口契约

### 4.1 协议变更

在 `old_proto/scene/vehicle.proto` 末尾新增：

```protobuf
// 服务端→客户端：车辆损伤状态通知（阶段变化时广播）
message VehicleDamageNtf {
  uint64 vehicle_entity_id = 1;  // 载具实体 ID
  int32 current_hp = 2;          // 当前 HP
  int32 max_hp = 3;              // 最大 HP
  int32 damage_stage = 4;        // 当前损伤阶段（CfgDamageStage.id）
  bool is_destroyed = 5;         // 是否已报废
  int32 steer_offset_deg_x100 = 6; // 转向偏移*100（服务端确定性计算，解决多端一致）
  int32 flat_tire_index = 7;       // 爆胎轮索引（-1=无爆胎，服务端确定性计算）
}

// 客户端→服务端：翻车恢复请求
message VehicleFlipReq {
  uint64 vehicle_entity_id = 1;  // 载具实体 ID
}

// 服务端→请求者：翻车恢复回复
message VehicleFlipRes {
  uint64 vehicle_entity_id = 1;
  bool approved = 2;
  int32 cooldown_remain_ms = 3;  // 剩余冷却时间(ms)，approved=false 时有效
}

// 服务端→AOI 内其他玩家：翻车恢复广播
message VehicleFlipNtf {
  uint64 vehicle_entity_id = 1;
}

// 客户端→服务端：损伤上报
message VehicleDamageReq {
  uint64 vehicle_entity_id = 1;
  float collision_impulse = 2;
  float collision_speed = 3;
}

// VehicleDamageNtf 新增字段（修复 HIGH-2/4 多端一致性）
// 在已有 VehicleDamageNtf 基础上追加：
//   int32 steer_offset_deg_x100 = 6;  // 服务端确定性计算的转向偏移*100
//   int32 flat_tire_index = 7;         // 爆胎轮索引，-1=无爆胎
```

**复用协议**：`DriveVehicleReq` 已有 `VehicleInput.handbrake` 字段，手刹输入不需新增协议。

### 4.2 配置表变更

**CfgDamageStage（修改）**：

| 字段 | 类型 | 新增 | 说明 |
|------|------|------|------|
| id | int | 否 | 主键 |
| hp | int | 否 | HP 阈值百分比 |
| canUse | bool | 否 | 是否可驾驶 |
| speedPenaltyRate | float | **是** | 速度衰减比 0~1 |
| accelPenaltyRate | float | **是** | 加速力衰减比 0~1 |
| steerPenaltyDeg | float | **是** | 转向偏移度数 |
| gripPenaltyRate | float | **是** | 抓地力衰减比 0~1 |
| destructEvent | string | 否 | 毁坏事件 |
| disappearDistance | float | 否 | 消失距离 |
| featureEffect | string | 否 | 特效资源路径 |
| audio | string | 否 | 音效事件名 |

**CfgDriftScore（新增）**：见 3.3.6 表结构。

### 4.3 跨组件接口

**新增公共方法签名**：

```csharp
// CarWheelController — 新增
public float EvaluateGrip(float slipAmount);
// 基于 slip 的抓地力评估，返回 0~1 系数

// DamagePerformanceModifier — 新增类
public void Init(Vehicle vehicle);
public void OnDamageStageChanged(int stageCfgId);
// 属性：SpeedMultiplier, AccelMultiplier, SteerOffsetDeg, GripMultiplier, HasFlatTire

// DriftDetectorComp — 新增 Comp
// 属性：IsDrifting, DriftAngleDeg, DriftDuration, DriftScore, ComboCount
// 事件：EventId.EVehicleDriftScoreUpdate(float score, int combo)

// VehiclePhysicDampComp — 新增
public void RequestFlipRecovery();
public void ExecuteFlipRecovery();

// VehicleCollisionHandlerComp — 新增
private void SpawnDebrisParticles(Vector3 point, Vector3 normal, int count);
```

## 5. 事务性设计

### 5.1 损伤同步一致性

**问题**：客户端碰撞频繁，服务端 HP 计算需防止并发竞态。

**方案**：
- 服务端 `ApplyDamage()` 在 ECS 单线程 Tick 中执行，无并发问题
- 客户端碰撞上报有 0.5s 冷却（已有 `_coolDownTimeout`），限制上报频率
- 服务端每次 HP 变化广播当前绝对值（非增量），客户端直接覆盖本地状态，保证最终一致
- 客户端网格变形是纯本地表现，不需要与服务端同步（锁定决策：不同步网格顶点）

### 5.2 爆炸回收原子性

**问题**：HP=0 后需要同步完成"标记不可驾驶 + 驱逐乘客 + 广播 + 启动回收定时器"。

**方案**：
- `ApplyDamage()` 检测 HP=0 后，在同一帧内：
  1. `IsDestroyed = true` + `SetSync()`
  2. 遍历 `SeatList`，对所有乘客调用 `PassengerLeave()` → `PersonStatusComp.OffVehicle()`
  3. 广播 `VehicleDamageNtf(hp=0, is_destroyed=true)` + 强制下车事件
  4. 设置 `DestroyTimer = mtime.NowSecondTickWithOffset() + 30`
- 回收 System 在 Tick 中检查 `DestroyTimer` 到期 → `scene.RemoveEntity()`
- 回收前再次检查是否有玩家上车（防极端时序），有则延迟回收

### 5.3 翻车恢复防滥用

**方案**：
- 服务端维护 `lastFlipTime` 字段，10s 冷却
- 客户端 UI 显示翻车恢复按钮时带冷却计时
- 服务端不信任客户端翻车判定，仅做冷却限制（翻车状态依赖物理模拟，服务端无物理引擎）

## 6. 验收测试方案

### AC-01 → TC-001 编译通过

| 项 | 内容 |
|----|------|
| 前置 | 所有代码改动完成 |
| 步骤 | 1. `P1GoServer/` 下 `make build` 2. Unity MCP `console-get-logs` 检查 CS 错误 |
| 预期 | Go 编译 0 error；Unity 编译 0 CS error |

### AC-02 → TC-002 重量感体验

| 项 | 内容 |
|----|------|
| 前置 | 登录大世界，上车 |
| 步骤 | 1. 急加速观察车辆后仰（相机视角） 2. 急刹车观察前倾 3. 高速转弯观察侧倾 |
| 预期 | 加速有明显"后座感"（重心后移导致后轮下压）；刹车有"点头"感；转弯时内侧悬挂伸展 |
| 验证方式 | MCP screenshot-game-view 截图 + 主观体验 |

### AC-03 → TC-003 渐进甩尾

| 项 | 内容 |
|----|------|
| 前置 | 车辆行驶至 80km/h 以上 |
| 步骤 | 1. 高速急打方向（不拉手刹） 2. 观察车尾运动轨迹 |
| 预期 | 车尾渐进甩出（非瞬间侧滑），有侧滑→回正→再侧滑的自然摆动 |
| 验证方式 | MCP 连续截图对比车辆朝向变化 |

### AC-04 → TC-004 碰撞变形

| 项 | 内容 |
|----|------|
| 前置 | 驾驶车辆对撞墙壁或其他车辆 |
| 步骤 | 1. 30km/h 轻撞 → 观察 2. 60km/h 重撞 → 观察 3. 多次撞击后整体观察 |
| 预期 | 碰撞点网格可见变形；重撞有碎片粒子飞溅；碰撞区域材质变暗 |
| 验证方式 | MCP screenshot-game-view 截图对比撞前/撞后 |

### AC-05 → TC-005 性能衰减

| 项 | 内容 |
|----|------|
| 前置 | 多次撞击使 HP 降至不同阶段 |
| 步骤 | 1. HP>60%：记录满油门极速 2. HP<60%：再次记录极速 3. HP<40%：观察转向 4. HP<20%：观察轮胎 |
| 预期 | HP<60% 极速下降约 10-20%；HP<40% 转向有随机偏移；HP<20% 某轮爆胎（抓地力归零） |
| 验证方式 | MCP script-execute 读取运行时 speed 和 DamagePerformanceModifier 属性 |

### AC-06 → TC-006 爆炸报废

| 项 | 内容 |
|----|------|
| 前置 | 持续撞击使 HP=0 |
| 步骤 | 1. HP 归零 → 观察爆炸 2. 尝试重新上车 |
| 预期 | 触发 ExplosionComp 爆炸效果；玩家被弹出；无法再次上车；30s 后车辆消失 |
| 验证方式 | MCP screenshot + gameobject-find 确认车辆实体销毁 |

### AC-07 → TC-007 漂移触发

| 项 | 内容 |
|----|------|
| 前置 | 行驶至 50km/h 以上 |
| 步骤 | 1. 拉手刹 + 打方向 2. 观察后轮 |
| 预期 | 后轮产生轮胎痕迹（SkidMarks）和烟雾粒子；车辆进入漂移状态 |
| 验证方式 | MCP screenshot-game-view 确认痕迹和烟雾可见 |

### AC-08 → TC-008 漂移计分

| 项 | 内容 |
|----|------|
| 前置 | 触发漂移状态 |
| 步骤 | 1. 维持漂移 2. 中断后 2s 内再次漂移（测试连漫） |
| 预期 | UI 显示漂移得分（角度+速度+持续时间）；连漫时倍率递增 |
| 验证方式 | MCP script-execute 读取 DriftDetectorComp 运行时数据 |

### AC-09 → TC-009 翻车恢复

| 项 | 内容 |
|----|------|
| 前置 | 使车辆翻车（>80度侧翻） |
| 步骤 | 1. 翻车后按恢复键 2. 计时 |
| 预期 | 车辆在 1s 内恢复正位，可继续驾驶 |
| 验证方式 | MCP 连续截图确认翻正过程 |

### AC-10 → TC-010 多人损伤同步

| 项 | 内容 |
|----|------|
| 前置 | 两个客户端在同一 AOI |
| 步骤 | 1. 玩家 A 撞车至 Stage3 2. 玩家 B 观察 A 的车辆 |
| 预期 | B 看到 A 的车辆烟/火特效与 A 本地一致 |
| 验证方式 | 两端分别 MCP screenshot 对比 |

## 7. 风险与缓解

| # | 风险 | 影响 | 概率 | 缓解措施 |
|---|------|------|------|----------|
| R1 | 重量转移参数需多轮调试 | 驾驶手感不达标 | 高 | 所有 COM 偏移参数配置化，支持运行时热调；先用保守值上线，后续微调 |
| R2 | 抓地力曲线形状不理想 | 操控手感生硬或过滑 | 高 | AnimationCurve 可视化调整；准备 3 套预设曲线（偏稳/平衡/偏滑）快速切换 |
| R3 | 网格变形未在所有 Prefab 启用 | 部分车型碰撞无变形 | 中 | 编码前扫描所有车辆 Prefab 的 meshDeformation/damageFilter 配置；编写检查脚本 |
| R4 | 顶点变形性能开销 | 低端手机帧率下降 | 中 | 变形仅在碰撞帧执行（非每帧）；高多边形车型使用 Fast 模式（一帧到位不插值） |
| R5 | 损伤 Shader 改动影响其他材质 | 非车辆物体变暗 | 低 | Vertex Color 方案仅对车辆 Shader 变体生效，使用 keyword 开关 |
| R6 | 漂移计分数值平衡 | 得分过高或过低 | 高 | 参数全部配置表驱动（CfgDriftScore），运行时可调不需重编 |
| R7 | 翻车恢复被利用刷特技 | 利用反复翻车获取奖励 | 低 | 服务端 10s 冷却 + 翻车恢复不计入特技得分 |
| R8 | 损伤同步带宽 | AOI 内大量车辆频繁损伤 | 低 | 仅同步阶段变化（最多 5 次），不同步每帧 HP；碰撞冷却 0.5s 限频 |
