# 载具系统 GTA5 级提升 - 设计审查报告

**审查日期**: 2026-04-01
**设计文档**: `docs/version/0.0.4/vehicle_system_gta5/design.md`
**结论**: **CONDITIONAL PASS** (2 CRITICAL + 4 HIGH 需修复后通过)

---

## 严重问题（必须修改）

### CRITICAL-1: 损伤上报链路不存在，设计假设错误

**章节**: 3.2.4 服务端损伤同步 / 2.3 数据流

**问题**: 设计文档第 103 行描述 `VehicleHashDamageInfo.SendDamageInfo() → 服务端`，暗示已有客户端到服务端的损伤上报协议。但实际代码验证：
- `VehicleHashDamageInfo.SendDamageInfo()` 仅调用 `PlayerManager.CollectLocalCrashData()` 进行本地数据采集上传（UpLoadEventClient），**不是网络协议发送**
- P1GoServer 中 grep `DamageInfo|SendDamage` 无任何匹配 -- 服务端无损伤接收处理
- 设计声称"接收客户端上报的碰撞信息（已有 SendDamageInfo 调用链）"是错误的

**影响**: 整个损伤同步架构的核心链路（客户端碰撞→服务端HP计算→广播VehicleDamageNtf）没有基础设施支撑。需要新建：
1. 一个客户端→服务端的损伤上报协议（如 `VehicleDamageReq`）
2. 服务端的损伤接收和校验 handler

**建议**:
1. 新增 `VehicleDamageReq` 协议（collision_impulse float, hit_position Vector3, hit_target_entity_id uint64）
2. 服务端在 vehicle_ops.go 新增 `OnVehicleDamage` handler，校验碰撞合理性后调用 `ApplyDamage()`
3. 明确标注此为新建链路，非复用

### CRITICAL-2: VehicleDataUpdate 缺少损伤字段，新玩家进入 AOI 无法获取损伤状态

**章节**: 3.2.4 / 4.1

**问题**: 设计仅新增了 `VehicleDamageNtf` 推送阶段变化，但未修改 `VehicleDataUpdate`（载具快照）。当新玩家进入已损伤车辆的 AOI 时，全量同步的 `VehicleDataUpdate` 不包含 `damage_hp`/`damage_stage`/`is_destroyed`，新玩家看到的车辆没有损伤表现。

现有同步流程（`net_update/vehicle.go:getVehicleMsg`）仅同步 Transform + TrafficVehicleComp + VehicleStatusComp，VehicleStatusComp 当前无损伤字段。

**建议**:
1. 在 `VehicleDataUpdate` proto 中新增 `VehicleDamageInfo damage_info = 27;`（含 hp/max_hp/stage/is_destroyed）
2. 在 `VehicleStatusComp.ToProto()` 中输出损伤字段
3. 在 `net_update/vehicle.go` 的 `getVehicleMsg` 中同步损伤数据
4. 或者将损伤字段直接加入已有的 `VehicleStatus` proto message

---

## HIGH 问题（强烈建议修改）

### HIGH-1: 损伤计算在客户端发起存在信任问题，但服务端无物理引擎无法独立计算

**章节**: 3.2.4 / 5.1

**问题**: 设计描述"服务端校验碰撞速度合理性"，但服务端没有物理引擎，无法验证碰撞是否真实发生。恶意客户端可伪造碰撞数据快速摧毁他人车辆。设计未明确：
- 服务端校验的具体规则（速度上限？频率限制？单次伤害上限？）
- 被碰撞方和碰撞方的伤害如何分别计算
- 交通系统 AI 车辆（无驾驶者）被碰撞时谁上报损伤

**建议**:
1. 明确服务端反作弊策略：单次伤害上限（如 maxDamagePerHit = MaxHP * 0.3）、碰撞频率限制（已有 0.5s CD）、累计伤害速率上限
2. 明确 AI 交通车辆的损伤处理：由碰撞发起方客户端上报，还是服务端忽略 AI 车辆损伤
3. 两车对撞时，两个客户端各自上报自己的损伤，服务端取较合理值

### HIGH-2: DamagePerformanceModifier 的 SteerOffsetDeg 使用 Random 导致每次阶段变化偏移不一致

**章节**: 3.2.2

**问题**: `SteerOffsetDeg = Random.Range(-cfg.steerPenaltyDeg, cfg.steerPenaltyDeg)` 在每次 `OnDamageStageChanged` 调用时随机生成。这意味着：
1. 同一辆车在不同客户端上偏移方向/大小不同（多人不一致）
2. 每次收到 VehicleDamageNtf 都会重新随机，驾驶体验跳变
3. 对于驾驶者来说，转向偏移突然改变非常影响操控

**建议**:
1. 偏移方向由服务端决定（在 VehicleDamageNtf 中携带 steer_offset_deg 字段），或基于 vehicleEntityId + damageStage 做确定性哈希
2. 偏移值在阶段变化时平滑过渡（lerp 到新值），而非瞬间跳变
3. 非驾驶者客户端无需计算转向偏移（纯表现无意义）

### HIGH-3: 翻车恢复缺 VehicleFlipRes，请求-确认链路不完整

**章节**: 3.3.4 / 4.1

**问题**: 设计定义了 `VehicleFlipReq` 和 `VehicleFlipNtf`，但链路不清晰：
1. `VehicleFlipNtf` 有 `approved` 字段，是给请求者的回复（应该叫 Res）还是给 AOI 内其他人的通知？命名应遵循项目约定（Req/Res/Ntf）
2. 如果 `approved=false`（CD 中），客户端如何处理？设计未描述
3. `ExecuteFlipRecovery()` 施加一次性 Impulse 力矩，但翻车角度各异，固定力矩不一定能 1s 内翻正所有情况（如车顶朝下 180 度 vs 侧翻 90 度）
4. 翻正过程中车辆可能卡在障碍物上

**建议**:
1. 将 `VehicleFlipNtf` 拆分为：`VehicleFlipRes`（给请求者，含 approved + cooldown_remain_ms）+ `VehicleFlipNtf`（给 AOI 内其他人，通知翻正动画）
2. 翻正用分帧协程而非单次 Impulse，每帧检查角度并施加修正力矩，超时(2s)后强制 teleport 到正位
3. 客户端收到 `approved=false` 时显示 CD 剩余时间

### HIGH-4: 爆胎轮随机选择导致多端不一致

**章节**: 3.2.2

**问题**: `FlatTireWheelIndex = Random.Range(0, 4)` 在每个客户端独立随机，驾驶者看到左前轮爆胎，其他玩家可能看到右后轮爆胎（虽然其他玩家看不到抓地力效果，但如果后续加爆胎视觉效果会不一致）。

**建议**: 爆胎轮索引由服务端决定，在 VehicleDamageNtf 中携带 `flat_tire_index` 字段；或基于 entityId + stage 确定性计算。

---

## MEDIUM 问题（建议改进）

### MEDIUM-1: CfgDriftScore 表设计为单行全局配置，不支持多车型差异化

**章节**: 3.3.6

**问题**: CfgDriftScore 表只有 id=1 一行，所有车型共用相同的漂移参数。但不同车型（轿车 vs SUV vs 跑车）的漂移特性差异很大。

**建议**: 将 CfgDriftScore 的 id 关联到车辆配置表的 vehicle_type，支持不同车型不同漂移参数。或在 CfgVehicle 表中增加 drift_score_cfg_id 字段关联。

### MEDIUM-2: 碎片粒子使用 Timer.Register 回收，OnDestroy/场景切换时可能泄漏

**章节**: 3.2.1

**问题**: `SpawnDebrisParticles` 使用 `Timer.Register(2f, ...)` 延迟回收碎片，如果车辆在 2s 内被销毁或场景切换，回调中的 debris 引用可能已失效，且对象池未正确回收。

**建议**:
1. 碎片生命周期绑定到车辆实体，车辆销毁时立即回收所有碎片
2. 或使用 ParticleSystem（非刚体碎片），粒子自动销毁无需手动管理
3. 手机端 3-5 个刚体碎片的 CPU 开销需评估，建议低端机禁用

### MEDIUM-3: 漂移计分 UI 未设计

**章节**: 3.3.1 / AC-08

**问题**: DriftDetectorComp 通过 `EventManager.Dispatch(EventId.EVehicleDriftScoreUpdate, ...)` 发送事件，但设计文档未描述 UI 面板如何显示漂移计分。AC-08 要求"UI 显示漂移得分"，但无对应的 UI Panel 设计。

**建议**: 补充漂移计分 UI 设计（Panel 位置、显示内容、动画效果、消失时机）。可以是简单的屏幕中下方浮动文字。

### MEDIUM-4: 两轮行驶特技检测连续上报

**章节**: 3.3.5

**问题**: `CheckTwoWheelStunt` 在 `_twoWheelTimer > 1f` 后每帧都会调用 `UploadStuntEvent`，直到状态结束。应该只在首次达标时上报一次。

**建议**: 增加 `_twoWheelReported` 标记，首次达标后置 true，状态结束时重置。或改为结束时上报总持续时间。

### MEDIUM-5: 360 旋转检测在地面漂移时也会触发

**章节**: 3.3.5

**问题**: `CheckSpinStunt` 条件包含 `IsDrifting`，这意味着漂移中的连续转向（如停车场绕圈）也会累积到 360 度触发旋转特技，这不是真正的"特技"。

**建议**: 360 旋转特技应限定为空中旋转或极短时间内完成（如 <2s 内完成 360 度），与普通漂移转向区分。

---

## 确认无问题的部分

1. **架构层次划分清晰**: 输入层→物理层→碰撞损伤层→同步层→特技层，职责单一，依赖方向正确
2. **"激活+调优+补缺"策略正确**: 充分利用现有 VehicleDamage/VehicleStuntComp/SkidMarks 等组件，避免重写
3. **协议最小化原则**: 仅新增 VehicleDamageNtf 和 VehicleFlipReq，复用 DriveVehicleReq.handbrake
4. **侧向阻尼动态化设计合理**: 低速稳定/高速可甩尾的速度-阻尼插值方案比固定值好
5. **抓地力曲线 AnimationCurve 方案**: 可视化调参，运行时热调，适合需要多轮迭代的参数
6. **爆炸回收原子性设计**: 同帧内完成标记+驱逐+广播+定时器，回收前再次检查乘客，时序正确
7. **损伤同步仅推送阶段变化**: 带宽友好，手机端合理
8. **配置表驱动**: CfgDamageStage 和 CfgDriftScore 参数外置，支持运行时调优
9. **验收测试覆盖完整**: TC-001~TC-010 与 AC-01~AC-10 一一对应，MCP 验证方式可行
10. **REQ-001~010 全覆盖**: 每个需求都有对应的设计章节和验收用例

---

## 需求覆盖度矩阵

| REQ | 设计章节 | 协议 | 配置表 | TC | 状态 |
|-----|---------|------|--------|-----|------|
| REQ-001 | 3.1.1, 3.1.2, 3.1.5 | - | - | TC-002 | OK |
| REQ-002 | 3.1.3, 3.1.5 | - | - | TC-003 | OK |
| REQ-003 | 3.1.4 | - | - | (无独立TC) | MEDIUM: 建议补TC |
| REQ-004 | 3.2.1, 3.2.3 | - | - | TC-004 | OK |
| REQ-005 | 3.2.2, 3.2.5 | - | CfgDamageStage | TC-005 | OK |
| REQ-006 | 3.2.4 | VehicleDamageNtf | - | TC-006,010 | CRITICAL: 上报链路缺失 |
| REQ-007 | 3.3.1 | - | CfgDriftScore | TC-007,008 | OK |
| REQ-008 | 3.3.2, 3.3.3 | - | - | TC-007 | OK |
| REQ-009 | 3.3.4 | VehicleFlipReq/Ntf | - | TC-009 | HIGH: 协议拆分 |
| REQ-010 | 3.3.5 | - | - | (无独立TC) | MEDIUM: 建议补TC |

**注**: REQ-003 和 REQ-010 缺少独立验收测试用例，建议补充 TC-003b（低速转弯半径测试）和 TC-010b（特技检测测试）。
