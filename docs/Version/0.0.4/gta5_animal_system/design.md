# GTA5 动物系统复刻 - 技术设计

## 1. 需求回顾

| ID | 标题 | 优先级 | 端 |
|----|------|--------|-----|
| REQ-001 | 动物数量提升(20只)+Chicken解锁Wander | P0 | server |
| REQ-002 | 感知系统(视觉+听觉) | P0 | server |
| REQ-003 | 逃跑行为(Dog/Bird/Chicken) | P0 | both |
| REQ-004 | 鳄鱼攻击(演示级,不扣血) | P0 | both |
| REQ-005 | 群体行为(成群生成+群体逃跑) | P1 | server |
| REQ-006 | 投喂交互(3D气泡,无需食物) | P0 | both |
| REQ-007 | 召唤狗(轮盘/快捷按钮) | P1 | client |
| REQ-008 | 协议扩展(group_id/threat_source_id/Flee/Attack) | P0 | both |

## 2. 架构设计

### 2.1 系统边界

| 功能 | 服务端(P1GoServer) | 客户端(freelifeclient) | 协议(old_proto) |
|------|-------|---------|--------|
| 感知检测 | AnimalPerceptionHandler(新增) | - | - |
| 逃跑决策 | AnimalFleeHandler(新增) | AnimalFleeState(新增) | AnimalState.Flee=6 |
| 攻击决策 | AnimalAttackHandler(新增) | AnimalAttackState(新增) | AnimalState.Attack=7 |
| 群体广播 | AnimalGroupComp+Spawner改造 | - | AnimalData.group_id |
| 投喂 | AnimalFeed(移除item_id校验) | AnimalInteractComp(移除背包检查) | AnimalFeedReq不变 |
| 召唤狗 | SummonDog(复用) | PoseWheelPanel(新增slot) | SummonDogReq不变 |
| 数量调整 | SpawnAreaConfig/Spawner | - | - |

### 2.2 状态流转

现有状态机扩展两个状态(Flee=6, Attack=7), 完整状态图:

```
                  +--> Walk(2) --+
                  |              |
  Idle(1) <------+---> Run(3)   +----> Idle(1)
    |             |              |
    +---> Flee(6)-+   Flight(4)--+
    |             |
    +---> Attack(7) --> Idle(1)  (鳄鱼专用)
    |
    +---> Follow(5) --> Idle(1)  (Dog喂食后)
```

**转换触发条件:**
- Idle/Walk/Flight → Flee: 感知到威胁(被动动物)
- Idle/Walk → Attack: 感知到玩家(鳄鱼, distSq < 15m^2)
- Attack → Idle: 攻击冷却结束(5s)
- Flee → Idle: 逃离安全距离(2x感知范围) 或 超时(10s)
- 任意 → Follow: 服务端设置 FollowTargetID(喂食触发)

### 2.3 感知系统架构

```
[BtTickSystem] pipeline tick
  └─ engagement 维度
       └─ AnimalPerceptionHandler.OnTick()
            ├─ 获取最近玩家 XZ 平方距离
            ├─ 视觉检测: distSq < visionRange^2 && LOD != Off
            ├─ 听觉检测: 枪声事件 → distSq < (visionRange*2)^2
            └─ 触发:
                 ├─ 被动动物 → ctx.RequestPlanSwitch("flee")
                 └─ 鳄鱼 → ctx.RequestPlanSwitch("attack")
```

感知Handler替代现有 AnimalIdleHandler 的 engagement 角色, AnimalIdleHandler 降级为 perception 未触发时的默认行为(idle plan 内部逻辑不变).

### 2.4 群体行为架构

```
[Spawner.SpawnAnimals]
  ├─ 按群组生成(2-4只, 5-10m间距)
  └─ 分配 groupId → SpawnResult.GroupID

[AnimalGroupComp] (新增, 挂载到 SceneNpcComp.State.Animal)
  ├─ GroupID uint32
  └─ 由 AnimalPerceptionHandler 触发群组广播

[群组逃跑广播]
  AnimalPerceptionHandler 检测到威胁:
  1. 自身切换 flee plan
  2. scene.ForEachEntityWithComponent(SceneNpcComp):
     - 同 groupId → 0.3-0.5s 延迟后写入 ThreatSourceID, 切换 flee
```

## 3. 协议设计(old_proto)

### 3.1 AnimalData 字段扩展

文件: `old_proto/scene/npc.proto`, message AnimalData

```protobuf
message AnimalData {
    // 现有字段 1-8 不变
    uint32 group_id          = 9;  // 群组ID(0=不属于任何群组)
    uint64 threat_source_id  = 10; // 威胁源实体ID(逃跑/攻击时有效, 0=无威胁)
}
```

### 3.2 AnimalState enum 扩展

```protobuf
enum AnimalState {
    // 现有 0-5 不变
    AnimalState_Flee   = 6; // 逃跑(被动动物感知威胁后)
    AnimalState_Attack = 7; // 攻击(鳄鱼专用)
}
```

### 3.3 AnimalFeedReq 变更

协议消息体不变, 服务端 `animal_feed.go` 移除:
- item_id 非空校验(改为允许空字符串)
- BackpackComp 物品数量校验(跳过扣减)
- `backpackComp.RemoveItem()` 调用

客户端 AnimalInteractComp 移除 `HasFoodInBackpack()` 校验, 改为距离内直接显示气泡.

## 4. 服务端详细设计(P1GoServer)

### 4.1 感知Handler

**文件**: `servers/scene_server/internal/common/ai/execution/handlers/animal_perception.go`(新增)

```go
// AnimalPerceptionHandler engagement 维度, 替代纯 idle 逻辑
// OnTick: 检测最近玩家距离 → 触发 flee/attack plan 切换
type AnimalPerceptionHandler struct{}

func (h *AnimalPerceptionHandler) OnTick(ctx *execution.PlanContext) {
    lod := ctx.NpcState.Animal.Base.CurrentLOD
    if lod == animal.LODOff { return } // LODOff 跳过感知

    playerDistSq := getClosestPlayerDistSq(ctx)
    meta := animal.AnimalMetadata[ctx.NpcState.Animal.Base.AnimalType]
    visionSq := meta.VisionRange * meta.VisionRange

    // 听觉扩展: 检查枪声事件(EventSensor)
    if hasGunshotEvent(ctx) { visionSq *= 4 } // 2倍范围 → 4倍平方

    if playerDistSq > visionSq { return }

    // 写入威胁源
    ctx.NpcState.Animal.Perception.ThreatSourceID = closestPlayerEntityID
    ctx.NpcState.Animal.Base.ThreatSourceID = closestPlayerEntityID

    if meta.AnimalType == 3 { // Crocodile → attack
        ctx.RequestPlanSwitch("attack")
    } else {
        ctx.RequestPlanSwitch("flee")
    }
}
```

**LOD交互**: LODOff(>300m) 完全跳过感知; LODMedium/Low 降频已由 BtTickSystem 的 `ShouldTick` 控制.

### 4.2 逃跑Handler

**文件**: `servers/scene_server/internal/common/ai/execution/handlers/animal_flee.go`(新增)

```go
// AnimalFleeHandler engagement 维度 flee plan
// OnEnter: 计算逃跑方向(威胁源反方向 ±15deg), 设 BehaviorState=Flee
// OnTick: 检测是否到达安全距离(2x感知范围) 或 超时(10s)
// OnExit: 恢复 BehaviorState=Idle, 清除 ThreatSourceID
type AnimalFleeHandler struct{}

func (h *AnimalFleeHandler) OnEnter(ctx *execution.PlanContext) {
    threatPos := getThreatPosition(ctx)
    selfPos := getSelfPosition(ctx)
    fleeDir := normalize(selfPos - threatPos)
    // ±15deg 随机偏移
    offsetRad := (rand.Float64()*30 - 15) * math.Pi / 180
    fleeDir = rotateY(fleeDir, offsetRad)
    // 逃跑距离 = 2x 感知范围
    target := selfPos + fleeDir * meta.AwarenessRadius * 2
    ctx.NpcState.SetMoveTarget(target, state.MoveSourceScript)
    ctx.NpcState.Movement.IsMoving = true
    ctx.NpcState.Animal.Base.BehaviorState = 6 // Flee
    ctx.NpcState.Animal.Base.MoveSpeed = meta.MoveSpeed[2] // 奔跑速度
    ctx.NpcState.Animal.Base.FleeStartMs = now
}
```

**终止条件**: distToThreat > AwarenessRadius*2 || elapsed > 10s → RequestPlanSwitch("idle")

### 4.3 攻击Handler(鳄鱼专用)

**文件**: `servers/scene_server/internal/common/ai/execution/handlers/animal_attack.go`(新增)

内部子状态机: Chase → Attack → Cooldown → Idle

```go
type AnimalAttackHandler struct{}

// 子状态常量
const (
    attackSubChase    = 0 // 追击: 向玩家移动
    attackSubAttack   = 1 // 攻击: 到达5m, 播放攻击
    attackSubCooldown = 2 // 冷却: 5s后回归
)

func (h *AnimalAttackHandler) OnTick(ctx *execution.PlanContext) {
    switch ctx.NpcState.Animal.Base.AttackSubState {
    case attackSubChase:
        // 向玩家移动, distSq < 25(5m) → 切 Attack
        playerPos := getPlayerPosition(ctx)
        ctx.NpcState.SetMoveTarget(playerPos, state.MoveSourceScript)
        if distSq < 25 { enterAttackSub(ctx) }
        // 玩家逃出15m → 放弃回归idle
        if distSq > 225 { ctx.RequestPlanSwitch("idle") }
    case attackSubAttack:
        // 攻击动画1.5s, 设 BehaviorState=Attack
        if elapsed > 1500ms { enterCooldown(ctx) }
    case attackSubCooldown:
        // 冷却5s → 回归idle
        if elapsed > 5000ms { ctx.RequestPlanSwitch("idle") }
    }
}
```

### 4.4 群体系统

**AnimalState扩展**(npc_state.go):
```go
type AnimalBaseState struct {
    // 现有字段...
    GroupID         uint32  // 群组ID(新增)
    ThreatSourceID  uint64  // 威胁源实体ID(新增)
    FleeStartMs     int64   // 逃跑开始时间戳(新增, Handler内部用)
    AttackSubState  uint32  // 攻击子状态(新增, 鳄鱼专用)
    AttackTimerMs   int64   // 攻击/冷却计时器(新增)
}

type AnimalPerceptionState struct {
    AwarenessRadius float32
    FollowTargetID  uint64
    ThreatSourceID  uint64 // 新增, 与 Base.ThreatSourceID 同步写入
}
```

**Spawner群组改造**(animal_spawner.go):
```go
type SpawnResult struct {
    // 现有字段...
    GroupID uint32 // 新增, 同批次生成的动物共享此ID
}

// SpawnAnimals 改造: 按2-4只一组生成, 组内间距5-10m
func (s *Spawner) SpawnAnimals(cfg *SpawnAreaConfig) []*SpawnResult {
    groupSize := 2 + rand.Intn(3) // 2-4
    groupID := nextGroupID()
    for i := 0; i < cfg.Count; i++ {
        if i % groupSize == 0 { groupID = nextGroupID() }
        result.GroupID = groupID
        // 组内第2+只在第1只位置 5-10m 内偏移
    }
}
```

**群组逃跑广播**: 在 AnimalPerceptionHandler 检测到威胁后, 遍历场景内同 GroupID 的动物实体, 写入 ThreatSourceID 并标记延迟切换(0.3-0.5s).

### 4.5 Spawner配置调整

`defaultTestConfigs` 更新:
```go
{AreaID: "bigworld_dogs",     Count: 4, AnimalType: 1} // Dog 2→4
{AreaID: "bigworld_birds",    Count: 6, AnimalType: 2} // Bird 15→6(按需求)
{AreaID: "bigworld_crocs",    Count: 4, AnimalType: 3} // Croc 3→4
{AreaID: "bigworld_chickens", Count: 6, AnimalType: 4} // Chicken 5→6
```

### 4.6 creature_metadata 参数更新

```go
var animalDefaultMetadata = map[uint32]*CreatureMetadata{
    1: {VisionRange: 20, HearingRange: 40, ...},  // Dog: 20m视觉
    2: {VisionRange: 30, HearingRange: 60, ...},  // Bird: 30m视觉
    3: {VisionRange: 15, HearingRange: 30, ...},  // Croc: 15m视觉
    4: {VisionRange: 10, HearingRange: 20, ...},  // Chicken: 10m视觉
}
```

Chicken 解除 Rest 锁定: `animal_idle.go` 中移除 `animalAnimalTypeChicken` 的特殊分支.

### 4.7 animalDimensionConfigs 管线改造

```go
func animalDimensionConfigs() []DimensionConfig {
    return []DimensionConfig{
        {
            Name: "engagement",
            ConfigPath: cfgPath("engagement"),
            RegisterHandlers: func(exec *execution.PlanExecutor) {
                exec.RegisterHandler("idle", handlers.NewAnimalIdleHandler())
                exec.RegisterHandler("perception", handlers.NewAnimalPerceptionHandler()) // 新增
                exec.RegisterHandler("flee", handlers.NewAnimalFleeHandler())             // 新增
                exec.RegisterHandler("attack", handlers.NewAnimalAttackHandler())         // 新增
            },
        },
        // locomotion/navigation 维度不变
    }
}
```

对应 AI 决策配置 `animal_engagement.json` 新增条件分支:
- 检测到威胁 → flee plan(被动) / attack plan(鳄鱼)
- 无威胁 → idle plan(现有)

## 5. 客户端详细设计(freelifeclient)

### 5.1 AnimalFleeState(新增FSM状态)

**文件**: `Assets/Scripts/Gameplay/Modules/BigWorld/Entity/Animal/State/AnimalFleeState.cs`

```csharp
public class AnimalFleeState : FsmState<AnimalController>
{
    public override void OnEnter()
    {
        // 播放 run 动画(逃跑复用 run clip)
        Owner.AnimationComp?.PlayAnimation("run");
    }
    public override void OnUpdate(float deltaTime)
    {
        // 归一化移速, 使用奔跑参考速度
        var speed = Owner.StateData?.MoveSpeed ?? 7f;
        Owner.AnimationComp?.SetAnimSpeed(speed, 7f);
        Owner.AnimationComp?.TickLoopNonLoopingClip();
    }
    public override void OnExit()
    {
        Owner.AnimationComp?.StopBaseLayer();
    }
}
```

### 5.2 AnimalAttackState(新增FSM状态)

**文件**: `Assets/Scripts/Gameplay/Modules/BigWorld/Entity/Animal/State/AnimalAttackState.cs`

```csharp
public class AnimalAttackState : FsmState<AnimalController>
{
    private float _attackTimer;
    private bool _pushApplied;

    public override void OnEnter()
    {
        // 鳄鱼无专用攻击clip → 用walk加速模拟冲击
        Owner.AnimationComp?.PlayAnimation("walk");
        Owner.AnimationComp?.SetSpeed(3f); // 3x加速模拟冲击
        _attackTimer = 0f;
        _pushApplied = false;
    }
    public override void OnUpdate(float deltaTime)
    {
        _attackTimer += deltaTime;
        // 0.5s时触发推开+镜头震动(一次性)
        if (!_pushApplied && _attackTimer > 0.5f)
        {
            _pushApplied = true;
            ApplyPushEffect();
            ApplyCameraShake();
        }
        Owner.AnimationComp?.TickLoopNonLoopingClip();
    }
    // 推开效果: 玩家沿鳄鱼朝向反方向移动2m
    private void ApplyPushEffect()
    {
        var player = PlayerManager.Controller;
        if (player == null) return;
        var pushDir = (player.transform.position - Owner.transform.position).normalized;
        pushDir.y = 0;
        player.transform.position += pushDir * 2f;
    }
    // 镜头轻震: 复用CameraManager震动接口
    private void ApplyCameraShake()
    {
        CameraManager.Instance?.Shake(0.15f, 0.3f); // 幅度0.15, 时长0.3s
    }
    public override void OnExit()
    {
        Owner.AnimationComp?.StopBaseLayer();
    }
}
```

**鳄鱼攻击动画方案**: 当前鳄鱼仅有 idle/walk clip, 无攻击动画. 采用 walk clip 3x加速模拟冲击表现. 后续美术提供攻击clip后替换 `PlayAnimation("attack")`.

### 5.3 AnimalFsmComp 状态路由扩展

`AnimalFsmComp.cs` 变更:

1. `CreateFsm()` 新增:
```csharp
_states.Add(FsmState<AnimalController>.Create<AnimalFleeState>());   // index=5
_states.Add(FsmState<AnimalController>.Create<AnimalAttackState>()); // index=6
```

2. `ChangeStateById()` switch 新增:
```csharp
case AnimalState.AnimalState_Flee:
    _fsm.ChangeState<AnimalFleeState>();
    break;
case AnimalState.AnimalState_Attack:
    _fsm.ChangeState<AnimalAttackState>();
    break;
```

3. 修复日志 `$""` 插值 → `+` 拼接(lesson-003).

### 5.4 投喂气泡UI优化

`AnimalInteractComp.cs` 变更:
- 移除 `HasFoodInBackpack()` 检查, `DetectPlayerProximity()` 改为仅判距离
- 移除 `GetFirstBackpackItemCfgId()`, `SendFeedRequest` 中 `itemId` 传空字符串
- 气泡视觉: 复用现有 `EventId.EShowNpcInteractUI`, 图标改为爪印图标(配置层)

### 5.5 召唤狗UI方案

**方案**: 在 PoseWheelPanel(姿势轮盘) 中新增"召唤狗"slot.

**理由**: PoseWheelPanel 已有固定功能按钮(自杀/拍照模式/姿势管理), 结构上支持追加. HandheldWheelPanel 是武器切换轮盘, 不适合放非武器功能.

**具体实现**:
1. `PoseWheelPanel.cs` → `OnOpen()` 中追加一个 SlotView, 绑定 SummonDog 图标和点击事件
2. 点击回调: 直接发送 `SummonDogReq`(复用 `SummonDogPanel.cs` 的网络逻辑)
3. `SummonDogPanel` 保留为兜底(Alt+P 不变), 不删除

**代码路径**:
- 修改: `freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/PoseWheelPanel.cs`
- 新增View元素: `PoseWheelView.cs` 中添加 summonDogButton VisualElement

### 5.6 AnimalStateData 字段扩展

```csharp
public class AnimalStateData
{
    // 新增字段
    public uint GroupId { get; private set; }
    public ulong ThreatSourceId { get; private set; }

    private void ApplyAnimalData(AnimalData data)
    {
        // 现有字段...
        GroupId = data.GroupId;               // proto field 9
        ThreatSourceId = data.ThreatSourceId; // proto field 10
    }
}
```

## 6. 配置变更

### 6.1 MonsterConfig 感知参数

`CfgInitMonster` 表中更新(通过 RawTables Excel):

| MonsterID | SightDistance | SightAngle | 说明 |
|-----------|-------------|------------|------|
| 47 (Bird) | 30 | 270 | 鸟类宽视野 |
| 48 (Dog) | 20 | 180 | 狗 |
| 49 (Croc) | 15 | 120 | 鳄鱼窄视野 |
| 50 (Chicken) | 10 | 180 | 鸡 |

### 6.2 SpawnAreaConfig 数量与群组

硬编码在 `animal_spawner.go` 的 `defaultTestConfigs` 中, 不走配置表.
后续迁移到配置表时再统一.

### 6.3 AI 决策配置

新增/修改 `P1GoServer/bin/config/ai_decision_v2/animal_engagement.json`:
- 增加 perception/flee/attack plan 的触发条件
- 现有 idle plan 条件不变(无威胁时默认)

## 7. 接口契约

### 7.1 服务端→客户端同步

NpcDataUpdate.animal_info 字段映射(AnimalData):

| Proto字段 | 服务端写入源 | 客户端消费 |
|-----------|------------|-----------|
| animal_state(2) | AnimalBaseState.BehaviorState | AnimalFsmComp.ChangeStateById |
| move_speed(4) | AnimalBaseState.MoveSpeed | AnimationComp.SetAnimSpeed |
| group_id(9) | AnimalBaseState.GroupID | AnimalStateData.GroupId |
| threat_source_id(10) | AnimalPerceptionState.ThreatSourceID | AnimalStateData.ThreatSourceId |

同步时机: SceneNpcComp.SetSync() → 帧同步 NpcDataUpdate 广播

### 7.2 错误码

复用现有错误码, 不新增:
- 14001: 动物实体不存在
- 14002: 距离过远
- 14003: 食物相关(改为通用交互冷却)
- 14004: 动物类型不支持
- 14005: 附近无狗(召唤)
- 14006: 召唤异常

## 8. 验收测试方案(Unity MCP)

### TC-001 动物数量(REQ-001)
1. 启动服务器 + Unity Play → 登录大世界
2. `script-execute`: 遍历所有 AnimalController, 统计各类型数量
3. 预期: Dog=4, Bird=6, Croc=4, Chicken=6, 总计=20

### TC-002 Chicken行为(REQ-001)
1. 观察 Chicken 区域 30s
2. 截图确认 Chicken 在 Idle↔Walk 间切换(不再锁定 Rest)

### TC-003 鳄鱼攻击(REQ-004)
1. 操控玩家走向鳄鱼, 进入 5m 范围
2. 截图确认: 鳄鱼加速冲击动画 + 玩家被推开 + 镜头震动
3. 等 5s 确认鳄鱼冷却后回归巡逻

### TC-004 被动动物逃跑(REQ-003)
1. 走向 Dog/Bird/Chicken 至感知范围内
2. 截图确认: 动物转向远离玩家方向奔跑

### TC-005 群体逃跑(REQ-005)
1. 找到一群同类动物(2-4只)
2. 接近其中一只至感知范围
3. 观察其余动物 0.3-0.5s 内跟随逃跑, 方向基本一致

### TC-006 投喂(REQ-006)
1. 走近 Dog 至 3m 内
2. 截图确认: 头顶出现投喂气泡(无论背包有无物品)
3. 点击气泡 → 确认 Dog 进入 Follow 状态

### TC-007 召唤狗(REQ-007)
1. 打开 PoseWheelPanel(姿势轮盘)
2. 确认有"召唤狗"选项
3. 点击 → 确认最近的 Dog 跑向玩家

### TC-008 枪声感知(REQ-002)
1. 在动物附近发射武器(触发枪声事件)
2. 确认 2x 范围内动物触发逃跑

### TC-009 编译验证(REQ-008)
1. 服务端: `cd P1GoServer && make build` → 无错误
2. 客户端: Unity MCP `console-get-logs` → 无 CS 编译错误

## 9. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| 鳄鱼无攻击动画clip | 攻击表现不够自然 | walk 3x加速模拟冲击, 后续美术补充替换 |
| 推开效果直接修改玩家Transform | 可能穿墙/穿地 | 推开后raycast修正Y, 加碰撞检测 |
| 20只动物感知tick性能 | 手机端CPU超预算 | LODOff跳过感知; Medium/Low已降频; 感知仅XZ平方距离 |
| 枪声事件依赖EventSensor | 当前Animal管线仅注册State+Distance | 需追加 EventSensorPlugin 到 animalDimensionConfigs |
| 群组广播遍历全场景实体 | O(N)性能 | 20只上限, N极小; 后续可建GroupID索引 |
| PoseWheelPanel slot数量上限 | 可能布局溢出 | 当前仅3个固定按钮, 加1个不影响布局 |
