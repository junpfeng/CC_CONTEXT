# 载具系统 GTA5 级提升（驾驶手感+渐进损伤+漂移特技）

## 核心需求
在现有大世界交通系统和 vehicle_driving 基础上，提升载具系统的广度和深度到 GTA5 级别。本期聚焦三个维度：驾驶手感、渐进式车辆损伤、漂移/特技系统。

## 调研上下文

### 已有基础设施（远比预期完善）

**物理模型（CarControl + ArcadeVehicleController）**：
- CarControl 已有：TCS/ABS/ESP 电子辅助、steeringInertia 过弯惯性、counterSteeringFactor 反打方向盘、maxAngularVelocity 角速度限制、SteeringHelper 转向辅助
- ArcadeVehicleController 已有：Spring-damper 悬挂（弹簧1200/阻尼75）、前后轮独立抓地力因子（前1.8/后2.0）、antiRollForce 防侧倾（100）、手刹力 0.6
- CarWheelController 已有：wheelSlipAmountForward/Sideways 滑移量追踪、camber/caster/toe 角度、powerMultiplier/brakingMultiplier
- VehiclePhysicDampComp 已有：方向阻尼（X500/Z200）、侧向速度因子 0.98、翻车检测（>80度）
- 重量转移：COMAssisterTypes 枚举存在（Off/Slight/Medium/Opposite），但实现大部分注释掉了
- 关键文件：`CarControl.cs`、`ArcadeVehicleController.cs`、`CarWheelController.cs`、`VehiclePhysicDampComp.cs`、`CarControllerConfig.cs`

**损伤系统（已有完整框架，但未充分启用）**：
- VehicleDamage：已有网格顶点位移变形系统（读写原始/损伤网格数据）、可拆卸部件追踪、车轮状态管理
- VehicleDisfeatureComp：4级损伤特效（轻烟→黑烟→小火→大火），配置驱动
- VehicleCollisionHandlerComp：碰撞检测+冷却（0.5s）、速度质量积阈值（16000）、火花/划痕特效、撞人检测（3s冷却）
- ExplosionComp：爆炸力场（玩家10K/物体100K）+ 音效
- CfgDamageStage：id/hp/canUse/destructEvent/disappearDistance/featureEffect/audio
- CfgVehiclePart：部件HP和修理费
- 服务端无损伤字段，损伤目前纯客户端
- 关键文件：`VehicleDamage.cs`、`VehicleDisfeatureComp.cs`、`VehicleCollisionHandlerComp.cs`、`ExplosionComp.cs`

**特技/VFX 系统（部分存在）**：
- VehicleStuntComp：已有腾空（0.5s/60km/h）、擦身（0.7s/60km/h）、尾气热浪检测
- SkidMarks：完整的网格轮胎痕系统（4096顶点/8+地面材质）
- CarSkidMarksManager：自动清理（30s超时）
- VehicleVFXComp：气流尾迹、速度线后处理、火焰+灯光
- CameraShakerComp/Config：相机震动系统
- 缺失：漂移角度/侧滑检测、漂移计分、手刹输入控制、空中旋转检测
- 关键文件：`VehicleStuntComp.cs`、`SkidMarks.cs`、`CarSkidMarksManager.cs`、`VehicleVFXComp.cs`

### GTA5 参考（E:\workspace\PRJ\GTA\GTA5\docs\）
- 24+ DriverPersonality 参数，LOD 4级降级
- 车辆模块 67 文件，与 RAGE 物理引擎深度集成
- 碰撞变形+武器损伤集成
- RoadSpeedZone（220最大同时区域）

### 关键认识
现有代码基础远超预期——不是"从零搭建"而是"激活+调优+补缺"。核心工作：
1. 物理：启用被注释的重量转移，调整抓地力曲线，降低侧向阻尼让车"滑得起来"
2. 损伤：VehicleDamage 网格变形已有但可能未接入碰撞流，需要打通碰撞→变形→性能衰减链路
3. 漂移：CarWheelController 已追踪 slip，只需在此基础上加漂移判定+计分+反馈

## 范围边界
- 做：汽车驾驶手感调优、渐进式碰撞损伤（变形+性能衰减+视觉特效）、漂移系统（检测+计分+反馈）、翻车恢复优化
- 不做：摩托车/船/直升机、征用动画、警察/通缉系统、车辆自定义改装、多人同乘、AI交通行为深化

## 初步理解
在已有组件基础上做"激活+调优+补缺"三步走：激活被注释/未接入的功能（重量转移、网格变形）、调优物理参数让手感接近GTA5、补缺漂移检测和损伤-性能联动。

## 待确认事项
见方案摘要中的待细化部分。

## 确认方案

核心思路：在已有完善基础上做"激活+调优+补缺"，而非重写。

### 锁定决策

**一、驾驶手感提升（纯客户端）**

服务端无改动。客户端修改 CarControl + ArcadeVehicleController：

1. **重量转移激活**：启用 COMAssisterTypes 被注释的实现，加速时重心后移（后轮抓地力增加）、刹车时重心前移（前轮锁定）、转弯时重心侧移（内侧轮减载）
2. **轮胎抓地力曲线**：当前 gripFactor 是固定值（前1.8/后2.0），改为基于 slip 的曲线——低 slip 线性增长、峰值后下降（模拟轮胎饱和）。在 CarWheelController 中实现 `float EvaluateGrip(float slipAmount)` 替代固定因子
3. **降低侧向阻尼**：VehiclePhysicDampComp._rbLeftVelocityFactor 从 0.98 降到 ~0.85，让车在高速转弯时能"甩尾"
4. **转向响应优化**：低速时增大 steerAngle（泊车灵活），高速时减小（稳定），已有 SteeringHelper 基础上加速度-转向衰减曲线
5. **刹车分配**：前后轮独立刹车力比例（前70%/后30%），急刹时后轮更容易锁死甩尾

**二、渐进式损伤系统（客户端为主，服务端轻量同步）**

1. **碰撞->网格变形链路**：VehicleCollisionHandlerComp 碰撞回调中调用 VehicleDamage 的变形方法（当前可能未接入），传入碰撞点+力度
2. **性能衰减**：
   - 引擎损伤（HP<60%）：maxSpeed 下降 20%，加速力下降 30%
   - 转向损伤（HP<40%）：steerAngle 随机偏移+-5度
   - 车轮损伤（HP<20%）：单轮抓地力归零（爆胎效果）
   - 性能衰减参数读取 CfgDamageStage 配置，不硬编码
3. **视觉反馈增强**：
   - 碰撞点局部材质变暗（_DamageMap UV 贴图，Shader 混合）
   - 已有的4级烟火特效保留
   - 碰撞时火花+划痕特效已有，增加碎片粒子（轻量，3-5个刚体碎片，2s后销毁）
4. **服务端同步**：新增 `VehicleDamageNtf`（vehicleEntityId uint64, currentHp int32, damageStage int32）— 服务端推送
5. **爆炸/报废**：HP=0 时触发 ExplosionComp（已有），爆炸后车辆不可驾驶，服务端设定回收定时器

**三、漂移/特技系统（纯客户端）**

1. **漂移检测**：在 CarWheelController 已有的 wheelSlipAmountSideways 基础上，新增 `DriftDetector` 组件：
   - 漂移判定：后轮侧滑量 > 阈值（~0.3）且车速 > 40km/h 且持续 > 0.3s
   - 漂移角度：车身朝向与速度方向的夹角（5 deg~90 deg 有效区间）
   - 漂移计分：角度x速度x持续时间，连漂（2s内接续）倍率递增
2. **手刹强化**：当前 handBrakesPower=0.6，增加手刹时后轮抓地力骤降到 20%（配合降低的侧向阻尼，拉手刹就能甩尾）
3. **漂移反馈**：
   - 轮胎痕迹（SkidMarks 已有）：漂移时自动触发，痕迹宽度随角度变化
   - 轮胎烟雾：漂移时在后轮生成烟雾粒子（速度+角度控制密度）
   - 相机：漂移时 FOV 微增（+5 deg）+ 轻微侧偏 + CameraShakerComp 低频震动
   - 引擎声浪：漂移时 RPM 拉高，轮胎啸叫音效叠加
4. **翻车恢复**：当前翻车检测 >80 deg 已有，增加"按键翻正"功能（施加一个翻转力矩，1s 内恢复正位）
5. **特技扩展**：在 VehicleStuntComp 基础上新增：
   - 漂移特技（持续漂移 >3s）
   - 360度旋转（空中或地面）
   - 两轮行驶（侧倾 >45 deg 且未翻车）

**协议变更（最小）**：
- 新增 `VehicleDamageNtf`（vehicleEntityId uint64, currentHp int32, damageStage int32）— 服务端推送
- 新增 `VehicleFlipReq`（vehicleEntityId uint64）— 翻车恢复请求
- 复用 `DriveVehicleReq` 的 VehicleInput（已有 handbrake 字段）

**配置表变更**：
- CfgDamageStage 新增字段：speedPenaltyRate（速度衰减比）、steerPenaltyDeg（转向偏移度）、gripPenaltyRate（抓地力衰减比）
- 新增 CfgDriftScore 表：漂移计分参数（角度权重、速度权重、连漂倍率、特技奖励分）

### 待细化
- 重量转移具体参数（COM 偏移量 vs 加速度映射曲线）——需运行时调试
- 抓地力曲线具体形状（峰值 slip 点、下降斜率）——需运行时迭代
- 损伤材质 Shader 的具体实现方式（_DamageMap 方案 vs vertex color 方案）——需确认 Shader 管线
- 漂移计分的具体数值平衡——需运行时测试

### 验收标准
- AC-01：编译通过（Go + Unity 双端）
- AC-02：驾驶中明显感受到重量感——加速后座感、刹车前倾、高速转弯侧倾
- AC-03：高速急转弯时车尾会自然甩出（非瞬间侧滑，有渐进过程）
- AC-04：碰撞后车辆外观可见变化（网格变形或材质变暗）
- AC-05：多次碰撞后车辆性能明显下降（速度/转向变差）
- AC-06：HP 归零后车辆爆炸，不可继续驾驶
- AC-07：拉手刹+转向可以触发漂移，后轮产生轮胎痕迹和烟雾
- AC-08：漂移时有计分显示（角度+速度+持续时间）
- AC-09：翻车后按键可以翻正车辆
- AC-10：其他玩家能看到车辆的损伤阶段特效（烟/火）
