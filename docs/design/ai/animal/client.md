# 动物系统 — 客户端需求文档

> **状态：设计阶段** — 4 种动物（Dog/Bird/Crocodile/Chicken），资源驱动排期。
>
> 关联协议：[protocol.md](protocol.md)
> 关联服务器：[server.md](server.md)

## 1. 概述

客户端负责动物系统的**纯表现层**：接收服务器推送的状态数据，驱动 FSM 切换、动画播放、音效触发、视觉效果。不参与任何行为决策。

**客户端职责边界**：
- 接收 `AnimalData` / `AnimalStateChangeNtf` 等协议数据，驱动本地表现
- FSM 状态机管理动画/音效/特效的生命周期
- 动画系统：四足/鸟类动画播放（Animancer 单层）
- 视觉系统：LOD 切换、渲染剔除
- 音效系统：环境音、脚步音
- 交互 UI：喂食提示与动画（仅狗）

### 1.1 现有基础设施盘点

| 现有资源 | 路径/位置 | 复用方式 |
|---------|----------|---------|
| **MonsterController 架构** | `BigWorld/Entity/Monster/MonsterController.cs` | 参考组件注册模式，AnimalController 继承同一 `Controller` 基类 |
| **GuardedFsm 状态机** | `Libs/Fsm/GuardedFsm.cs` | 直接复用，Animal FSM 状态继承 `FsmState<AnimalController>` |
| **AnimationComp 基类** | `BigWorld/Entity/Common/Comp/Animation/AnimationComp.cs` | AnimalAnimationComp 继承此基类，复用 Animancer 层管理 |
| **TransformComp** | `BigWorld/Entity/Common/Comp/Transform/TransformComp.cs` | 直接复用，位置/朝向插值（lerp 0.4f） |
| **AudioComp + AudioEmitter3D** | `BigWorld/Entity/Common/Comp/AudioComp.cs` | 继承基类，对接 AudioStudio（Wwise） |
| **EventComp** | 通用事件总线 | 直接复用 |
| **RenderCullComp** | `BigWorld/Entity/Common/Comp/RenderCullComp.cs` | 直接复用，POI 剔除 + EnableCull/DisableCull |
| **HiZCullingGroupManager** | MonsterController 已集成 | 直接复用，OnEnable 注册 / OnDisable 注销 |
| **CfgAudioAnimal 配置表** | `RawTables/audio/AudioAnimal.xlsx` → `CfgAudioAnimal.cs` | 已有字段：soundBank, footstepSound, idleVo, warningVo, fleeVo, attackVo, hitVo, deathVo, atkSound1/2 |
| **AudioManager 动物方法** | `AudioManager.Interaction.cs` | 已定义 6 个方法（Idle/Alert/Flee/Attack/Hit/Death），当前未调用，可直接接入 |
| **Dog 角色模型** | `ArtResources/Character/Nonhuman/Animal/Dog_001_BorderCollie/` + `Dog_002_Labrador/` | 2 个品种变体，可直接用于 Prefab 制作 |
| **Bird 角色模型** | `ArtResources/Character/Nonhuman/Animal/Bird/Bird_001` | 已有角色目录 |
| **Crocodile 模型** | `ArtResources/Character/Nonhuman/Animal/Crocodile_001/002/003_Green` | 3 个外观变体 |
| **Chicken 模型** | `ArtResources/Character/Nonhuman/Animal/Chicken_001_Red` | 静态装饰用 |
| **MonsterType 枚举** | `CfgEnum.cs:1326` | 已有 Bird=47、Dog=48，Crocodile/Chicken 追加枚举值即可 |
| **CfgMonsterPrefab / CfgMonsterAnimation / CfgInitMonster** | 配置表 | 已有模型路径、动画层配置、基础属性（速度/视距等），动物可扩展复用 |
| **AnimationEventSoundMonster** | 动画事件音效触发 | 直接复用，脚步音通过 AnimationEvent 回调 |
| **Legs Animator 插件** | `3rd/FImpossible Creations/Plugins - Animating/Legs Animator/` | 四足 IK，Prefab 上预配置 |
| **InteractComp + 交互 UI** | `PlayerInteractWithNpcComp` + `EventId.EShowNpcInteractUI` | 复用距离检测 + UI 提示框架 |

## 2. 架构设计

### 2.1 模块位置

```
Assets/Scripts/Gameplay/Modules/S1Town/Entity/Animal/
├── AnimalController.cs              # 动物主控制器（继承 Controller）
├── Comp/                            # 动物专用组件（通用 Comp 直接复用不在此目录）
│   ├── AnimalFsmComp.cs             # 动物 FSM 状态机（GuardedFsm<AnimalController>）
│   ├── AnimalAnimationComp.cs       # 动画组件（继承 AnimationComp，仅 Base 层）
│   ├── AnimalAudioComp.cs           # 音效组件（继承 AudioComp，对接 CfgAudioAnimal）
│   └── AnimalInteractComp.cs        # 交互组件（仅喂食，仅狗）
├── State/                           # FSM 状态实现
│   ├── AnimalIdleState.cs           # 全部动物
│   ├── AnimalWalkState.cs           # Dog / Crocodile
│   ├── AnimalRunState.cs            # Dog only
│   ├── AnimalFlightState.cs         # Bird only（fly 循环）
│   └── AnimalFollowState.cs         # Dog only（喂食后跟随）
└── Data/
    ├── AnimalStateData.cs           # 状态数据（协议映射）
    └── AnimalClientData.cs          # 客户端数据聚合

# 直接复用（不在 Animal/ 目录，已有实现）：
# - TransformComp             → BigWorld/Entity/Common/Comp/Transform/TransformComp.cs
# - RenderCullComp            → BigWorld/Entity/Common/Comp/RenderCullComp.cs
# - EventComp                 → 通用事件总线
# - HiZCullingGroupManager    → 已有遮挡剔除管理
# - AnimationEventSoundMonster → 动画事件音效触发
```

### 2.2 组件架构

沿用 MonsterController / TownNpc 的 Controller + Comp 模式，组件分"直接复用"和"动物专用"两类：

```
AnimalController : Controller
  ├── EventComp（直接复用）           // 通用事件总线
  ├── TransformComp（直接复用）       // 位置/朝向插值（已有 lerp 0.4f）
  ├── RenderCullComp（直接复用）      // POI 剔除 + 渲染开关
  ├── AnimalAnimationComp（继承）     // 继承 AnimationComp，简化为单层 Animancer
  ├── AnimalAudioComp（继承）         // 继承 AudioComp，对接 CfgAudioAnimal + AudioManager 已有方法
  ├── AnimalFsmComp（新建）           // GuardedFsm<AnimalController>，动物专用状态集
  └── AnimalInteractComp（新建，可选）// 交互提示（Dog 喂食，复用 EventId.EShowNpcInteractUI 框架）
```

> **对比 MonsterController**：MonsterController 注册 20+ Comp（含武器、载具、人形动画分层等），动物仅需 6-7 个，大幅精简。不继承 MonsterController 是因为其深度绑定人形体系（HumanBaseData、BodyPartsMap、WeaponComp），分叉成本远高于新建。

**Update 流程**：

`AnimalController.OnUpdate` 每帧调用以下 Comp 的 Tick：
- `TransformComp.Tick(dt)` — 位置/朝向插值（直接复用，无需重写）
- `AudioComp.Tick(dt)` — 环境音随机触发计时
- `InteractComp.Tick(dt)` — 交互提示距离检测（可降频为 5Hz，仅 Dog 注册）

**组件注册规则**（遵循 feedback_client_comp_registration）：
- 所有 Comp 在 `AnimalController.OnInit()` 中通过 `AddComp<T>()` 注册
- 条件注册：InteractComp 仅 Dog 注册
- 生命周期：`OnAdd(ICompOwner)` / `OnClear()`，OnClear 中取消所有异步操作

### 2.3 与现有系统的复用关系

| 类别 | 直接复用 | 继承扩展 | 不复用 |
|------|---------|---------|--------|
| 基类 | Controller、Comp、NetEntity | — | MonsterController（人形绑定过深） |
| FSM | GuardedFsm<T> 框架 | AnimalFsmComp | MonsterFsmComp 状态集（Stand/Ground/Driving 等人形状态） |
| 动画 | AnimationComp 基类、Animancer 引擎 | AnimalAnimationComp（仅 Base 层） | MonsterAnimationComp 多层分层（UpperBody/Arms/Face）、MonsterAnimStateMap |
| 音效 | AudioComp 基类、AudioEmitter3D、AnimationEventSoundMonster | AnimalAudioComp（对接 CfgAudioAnimal） | Monster 人形音效逻辑 |
| 渲染 | RenderCullComp、HiZCullingGroupManager | — | — |
| 数据 | NpcData 基础结构、TransformSnapShotData | AnimalStateData / AnimalClientData | HumanBaseData、MonsterData、PersonInteractionData |
| 交互 | InteractComp 基类、EventId.EShowNpcInteractUI | AnimalInteractComp | — |
| 配置表 | CfgAudioAnimal（已有）、CfgMonsterPrefab（模型路径） | CfgInitMonster 扩展动物属性 | — |
| 其他 | EventComp | — | TownNpcEmotionComp、PhoneComp、BodyPartsMap、BoneModification |

## 3. 实体管理

### 3.1 AnimalController

```csharp
public class AnimalController : Controller
{
    public override EntityType EntityType => EntityType.Animal; // 需新增枚举值

    // 直接复用的通用组件
    public TransformComp TransformComp;      // 直接复用，无需子类化
    public RenderCullComp RenderCullComp;    // 直接复用

    // 继承扩展的动物组件
    public AnimalFsmComp FsmComp;
    public AnimalAnimationComp AnimationComp;
    public AnimalAudioComp AudioComp;

    // 可选组件（仅 Dog 注册）
    public AnimalInteractComp InteractComp;
}
```

**EntityType 决策**：选择**新增 `EntityType.Animal` 枚举值**。

当前 `EntityType` 枚举中所有怪物/NPC 均使用 `EntityType.Npc`，但动物与人形 NPC 差异过大（无 Avatar、无 BodyPartsMap、不同 FSM 状态集、不同组件集合），若复用 `EntityType.Npc` 则需在 `DataManager.Npc_UpdateNetFrame()` 的创建路径中持续分叉判断，维护成本高。新增独立枚举值使创建路径清晰，EntityManager 根据 EntityType 直接路由到 AnimalController 工厂。

### 3.2 数据层

**AnimalStateData**（协议数据映射）：
- 接收 `AnimalData` 和各种 Ntf 消息，存储最新状态
- 状态信号链：`AnimalData.animal_state` → `AnimalStateData.Notify(StateIdUpdate, stateId)` → `AnimalFsmComp.ChangeStateById`
- 与 TownNpcStateData 同模式：服务端枚举值直接对应 FSM 状态索引

**AnimalClientData**（客户端数据聚合）：
- 聚合 AnimalStateData + 配置表数据（动画配置、音效配置、LOD 配置）
- 提供便捷访问接口（`AnimalType`、`Category`、`IsFlying` 等）
- **AnimalType → MonsterType 映射**：协议下发 `AnimalType`（Dog=2），客户端通过配置表映射到 `MonsterType`（Dog=48）加载对应 Prefab/动画

### 3.3 生成与销毁

**生成**（沿用现有 Monster 创建管线，增加分支）：
1. `DataManager.Npc_UpdateNetFrame()` 收到 `NpcDataUpdate`
2. 判断 `SceneNpcExtType`：`= 4` 时走 Animal 创建路径（原路径 `= 1` 为人形 Monster）
3. 根据 `MonsterType`（已有 Bird=47, Dog=48）查询 `CfgMonsterPrefab` 加载对应 Prefab
4. 创建 `AnimalController`（非 MonsterController），调用 `OnInit(npcData)`
5. `OnInit` 内注册组件 → 设置初始状态

> **复用说明**：Prefab 路径、动画配置、基础属性仍通过现有 `CfgMonsterPrefab` / `CfgMonsterAnimation` / `CfgInitMonster` 配置表获取，无需新建配置表。音效通过 `CfgAudioAnimal`（已有）独立配置。

**销毁**：
- 收到移除通知时执行 OnClear 清理链
- 所有异步操作（UniTask）在 OnClear 中 Cancel（遵循 feedback_unitask_cancellation）

## 4. FSM 状态机

### 4.1 状态列表

| 索引 | 状态 | 对应 AnimalState 枚举 | 适用动物 |
|------|------|---------------------|---------|
| 0 | AnimalIdleState | Idle (1) | 全部（Dog/Bird/Crocodile/Chicken） |
| 1 | AnimalWalkState | Walk (2) | Dog、Crocodile |
| 2 | AnimalRunState | Run (3) | Dog only |
| 3 | AnimalFlightState | Flight (4) | Bird only（fly 循环） |
| 4 | AnimalFollowState | Follow (5) | Dog only（喂食后跟随） |

> Chicken 只有 `squatidle` 一个 Clip，FSM 仅注册 IdleState，永远停在 Idle。

### 4.2 状态切换驱动

与 TownNpc 相同模式：
1. 收到 `AnimalStateChangeNtf` 或 `AnimalData.animal_state` 变化
2. `AnimalStateData.Notify(StateIdUpdate, newStateId)`
3. `AnimalFsmComp` 监听通知，调用 `ChangeStateById(newStateId - 1)`（枚举值 - 1 = 数组索引）
4. FSM 执行状态切换：旧状态 `OnExit()` → 新状态 `OnEnter()`

### 4.3 各状态实现要点

**AnimalIdleState**：
- Dog：播放 `idle` 或 `specialidle` 动画（`idle_sub_state` 决定）
- Bird：播放 `idle` 动画循环；Flight 状态时播放 `fly` 循环
- Crocodile：播放 `idle` 动画循环
- Chicken：播放 `squatidle` 动画循环，永不切换

**AnimalWalkState**：
- 播放 `walk` 动画，`AnimationComp.SetSpeed` 匹配服务器下发的 `move_speed`
- TransformComp 插值追踪服务器位置

**AnimalRunState**（Dog only）：
- 播放 `run` 动画，速度参数匹配服务器 `move_speed`
- Walk/Run 通过 `move_speed` 阈值切换，无 BlendTree 需求

**AnimalFlightState**（Bird only）：
- 播放 `fly` 循环动画
- TransformComp 插值位置（X/Z 从服务器，Y = `flight_altitude`）
- 无 Takeoff/Landing/Perch 状态——直接 Idle（停栖）↔ Flight 切换，中间无过渡动画（资源不足）
- 飞行时禁用 Legs Animator IK

**AnimalFollowState**（Dog only）：
- 播放 `run` 动画跟随玩家，`follow_dur` 秒后服务器推送状态切换
- 速度与玩家保持同步（通过 `move_speed` 参数控制）

## 5. 动画系统

### 5.1 AnimalAnimationComp

继承 `AnimationComp`（`BigWorld/Entity/Common/Comp/Animation/AnimationComp.cs`），简化为单层 Animancer（仅 Base 层）：
- **对比 MonsterAnimationComp**：Monster 使用 AnimancerLayers 枚举管理 9 层（Base/UpperBody/Arms/.../Face），动物仅需 Base 层，去掉所有人形分层逻辑
- 动画通过 `ConfigEnum.TransitionKey` 索引，配置表驱动（复用现有 `CfgMonsterAnimation` 表结构，`baseLayer` + `baseType` 字段）
- 速度匹配：`SetSpeed(key, move_speed / max_speed)` 动态调整动画播放速度
- Dog Walk/Run 通过速度参数切换，无需 BlendTree（只有两速，无 trot/sprint）

### 5.2 动画资源清单

仅列实际有资源的 4 种动物：

| 动物 | 模型路径 | 可用 Clip | Clip 数 | 备注 |
|------|---------|---------|--------|------|
| **Dog** | `Character/Nonhuman/Animal/Dog_001_BorderCollie`<br>`Character/Nonhuman/Animal/Dog_002_Labrador` | idle, walk, run, specialidle | 4 | 2 个品种变体，资源就绪，可立即开发 |
| **Bird** | `Character/Nonhuman/Animal/Bird/Bird_001` | fly, idle | 2 | 资源就绪，fly 循环即为飞行状态 |
| **Crocodile** | `Character/Nonhuman/Animal/Crocodile_001`<br>`Character/Nonhuman/Animal/Crocodile_002`<br>`Character/Nonhuman/Animal/Crocodile_003_Green` | idle, walk | 2 | 3 个外观变体，仅 idle/walk |
| **Chicken** | `Character/Nonhuman/Animal/Chicken_001_Red` | squatidle | 1 | 纯静态装饰，永远 Idle |

### 5.3 四足 IK（Legs Animator）

项目已有 Legs Animator 插件（`Assets/Scripts/3rd/FImpossible Creations/Plugins - Animating/Legs Animator/`）：
- Dog / Crocodile 启用 Legs Animator，用于四足脚部 IK 适配地形
- Bird 站立（Idle）时启用双足 IK，飞行（Flight）时禁用
- Chicken 可启用双足 IK（装饰用，性能允许时开启）
- 配置在 Prefab 上预设，运行时根据状态启用/禁用

## 6. 视觉表现

### 6.1 LOD 与渲染剔除策略

**已有基础**：MonsterController 已集成 `RenderCullComp`（POI 剔除）和 `HiZCullingGroupManager`（遮挡剔除），AnimalController 直接复用：
- `RenderCullComp`：`EnableCull()` / `DisableCull()` 控制渲染开关，`EnableRender(bool)` 暂停/恢复 Animancer 动画图
- `HiZCullingGroupManager`：`OnEnable` 注册 / `OnDisable` 注销（与 Monster 同模式）

**动物 LOD 分级**（在现有剔除基础上叠加 LOD Group）：

| 距离 | 渲染方式 | 动画 |
|------|---------|------|
| < 50m（Full LOD） | 完整模型 + 骨架动画 | 完整骨架 |
| 50-150m（Medium LOD） | 简化模型 | 简化骨架 |
| > 150m | 不渲染（RenderCullComp 接管） | 无 |

Bird 飞行时 Full LOD 扩展至 100m。LOD 切换距离由配置表 `lodDistances` 配置。

**LOD 切换联动行为**：
- Full → Medium：音效降 50% 音量
- Medium → 剔除：停止骨架动画，音效静音
- 恢复时按距离还原对应层级的动画和音效

## 7. 音效系统

### 7.1 音效组定义

**已有基础**：`CfgAudioAnimal`（`RawTables/audio/AudioAnimal.xlsx` 生成）已定义以下字段，`AudioManager.Interaction.cs` 已实现 6 个播放方法（当前未调用）：

| CfgAudioAnimal 字段 | 对应音效 | AudioManager 已有方法 | 适用动物 |
|---------------------|---------|---------------------|---------|
| `idleVo` | 环境待机音 | `PlayAnimalIdleSound()` | 全部 |
| `footstepSound` | 脚步音（地表切换） | —（通过 AnimationEvent 触发） | Dog / Crocodile |
| `soundBank` / `soundBank_PerAnimal` | 音频 Bank 加载 | — | 全部 |

> warningVo / fleeVo / attackVo / hitVo / deathVo 字段已预留，当前 4 种动物无对应 Clip，暂不触发。

音效由 `AnimalAudioComp` 管理，FSM 状态切换时调用对应 `AudioManager.PlayAnimal*()` 方法。

**AnimalAudioComp 触发逻辑**（精简版）：

```csharp
// AnimalAudioComp.Tick(float dt)
void Tick(float dt)
{
    // idle_ambient：随机间隔播放（仅 Idle 状态）
    if (_currentState == AnimalState.Idle)
    {
        _ambientTimer -= dt;
        if (_ambientTimer <= 0)
        {
            AudioManager.Instance.PlayAnimalIdleSound(/* CfgAudioAnimal.idleVo */);
            _ambientTimer = Random.Range(8f, 20f); // 8-20s 随机间隔
        }
    }
    // 脚步音通过 AnimationEvent 触发，不在 Tick 中处理
}

// FSM 状态切换回调（仅保留有资源的状态）
void OnStateChanged(AnimalState oldState, AnimalState newState)
{
    // 当前 4 种动物无 startle/attack/death Clip，相关 case 暂空
}
```

### 7.2 地表脚步音

陆地动物（Dog / Crocodile）脚步音根据地表材质切换：
- 支持材质：泥地（mud）、草地（grass）、石地（stone）
- 通过动画事件（AnimationEvent）触发，**直接复用已有 `AnimationEventSoundMonster.cs` 模式**——动物 Prefab 挂载同类脚本，动画 Clip 中标注 FootstepEvent
- `CfgAudioAnimal.footstepSound` 字段已预留，配置对应 Wwise Event 名即可
- Full LOD 下播放完整脚步音，Medium LOD 下降低音量

## 8. 玩家交互 UI

### 8.1 交互提示（仅 Dog）

`AnimalInteractComp` 管理交互 UI 提示，仅在 Dog 上注册。**复用现有交互框架**：继承 `InteractComp` 基类，通过 `EventId.EShowNpcInteractUI` / `EventId.EHideNpcInteractUI` 控制 UI 显隐（与 Monster/NPC 交互同模式），距离检测复用 `PlayerInteractWithNpcComp` 的近距离检测逻辑。

| 条件 | 提示内容 | 按键 |
|------|---------|------|
| 动物为 Dog + 玩家手持食物 + 距离<=3m | "喂食" | 交互键 |

提示 UI 显示在动物头顶（World Space），超出距离或条件不满足时自动隐藏。

### 8.2 喂食表现

1. 玩家按交互键 → 发送 `AnimalFeedReq`
2. 收到 `AnimalFeedResp`（code=0）→ 播放玩家喂食动画
3. 狗进入 Idle 状态（播放 `specialidle` 嗅闻动画，约 2s）
4. 喂食完成 → 狗切换到 Follow 状态
5. `follow_dur` 秒后狗自动回归原行为（服务器推送状态切换）

**异步安全**：喂食全流程所有 async 操作传递 `CancellationToken`（来自 `AnimalInteractComp.OnClear` 中的 `CancellationTokenSource.Cancel`）。

## 9. 性能预算

| 类别 | 预算 |
|------|------|
| 每种动物骨架 + 动画 | < 8MB |
| 全部动物同屏（满配额） | < 30 DrawCall（Full LOD），< 2ms GPU |
| 音效同时播放 | < 8 通道（动物音效） |

LOD 切换是性能控制的核心手段，Medium LOD 大幅降低 DrawCall 和 CPU 动画开销。

## 10. 实现计划

> 标注 `✅已有` 表示可直接复用无需开发，`🔧扩展` 表示在现有基础上改造，`🆕新建` 表示从零实现。
> **原则：只做有资源的动物，4 种动物同期实现。**

```
一期（当前）— 基础框架 + 4 种动物
  ├─ 【协议层】🆕 old_proto 新增动物专用消息（AnimalData/StateChangeNtf/FeedReq 等）
  ├─ 【基础框架】
  │    ├─ 🆕 EntityType.Animal 枚举值 + EntityManager 创建路由
  │    ├─ 🆕 AnimalController（继承 Controller，精简版 6-7 Comp）
  │    ├─ 🆕 AnimalFsmComp（GuardedFsm<AnimalController>）+ 5 个状态
  │    │    Idle/Walk/Run/Flight/Follow
  │    ├─ 🔧 AnimalAnimationComp（继承 AnimationComp，单层 Animancer，复用 CfgMonsterAnimation）
  │    ├─ 🔧 AnimalAudioComp（继承 AudioComp，对接已有 CfgAudioAnimal + AudioManager 方法）
  │    ├─ ✅ TransformComp 直接复用（位置/朝向插值）
  │    ├─ ✅ RenderCullComp + HiZCulling 直接复用
  │    ├─ 🔧 AnimalInteractComp（继承 InteractComp，复用 EShowNpcInteractUI 框架，仅 Dog）
  │    ├─ 🆕 LOD 切换系统（LOD Group 分级，与 RenderCullComp 联动）
  │    └─ 🆕 AnimalStateData / AnimalClientData（协议映射 + 配置聚合）
  ├─ 【配置表】
  │    ├─ 🔧 CfgMonsterPrefab / CfgInitMonster 添加 4 种动物条目
  │    ├─ 🔧 CfgAudioAnimal 填充 4 种动物音效配置
  │    └─ 🔧 CfgMonsterAnimation 添加 4 种动物动画映射
  ├─ Dog（✅ 已有 4 Clip + FBX + 2 角色变体，MonsterType.Dog=48）
  │    ├─ 🔧 Prefab 制作（基于 Dog_001_BorderCollie / Dog_002_Labrador）
  │    ├─ ✅ 利用已有 Clip 实现 Idle/Walk/Run 基础表现
  │    └─ 🆕 FollowState + 喂食交互表现（AnimalInteractComp）
  ├─ Bird（✅ 已有 2 Clip + 角色目录，MonsterType.Bird=47）
  │    ├─ 🔧 Prefab 制作（基于 Bird_001）
  │    └─ 🆕 FlightState（fly 循环 + Idle 两状态切换）
  ├─ Crocodile（✅ 已有 2 Clip + 3 变体，需新增 MonsterType 枚举值）
  │    ├─ 🔧 Prefab 制作（3 个外观变体）
  │    └─ ✅ Idle/Walk 基础表现
  └─ Chicken（✅ 已有 1 Clip + 角色目录，需新增 MonsterType 枚举值）
       ├─ 🔧 Prefab 制作（基于 Chicken_001_Red）
       └─ ✅ Idle（squatidle）纯静态装饰
```
