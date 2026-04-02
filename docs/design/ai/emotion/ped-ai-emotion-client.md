# 路人 AI 与情绪反应 — 客户端需求文档

> **状态**: 待实现
> **日期**: 2026-03-13
> **参考**: GTA5/docs/design/路人AI与情绪反应需求.md
> **涉及工程**: freelifeclient
> **相关文档**: ped-ai-emotion-server.md（协议定义在服务器需求文档 §7）

## 1. 模块职责边界

客户端纯表现层，所有逻辑由服务器计算后通过协议下行。

| 职责 | 服务器 | 客户端 |
|------|--------|--------|
| 情绪状态计算 | ✅ | ❌ |
| 动画参数接收与播放 | ❌（下发） | ✅ |
| 逃跑路径选择 | ✅ | ❌ |
| 逃跑动画播放 | ❌ | ✅ |
| 蹲伏/躲避动画 | ❌ | ✅ |
| 围观行走动画 | ❌ | ✅ |
| 打电话动画 | ❌ | ✅ |
| 辱骂/推搡动画 | ❌ | ✅ |
| 载具弃车动画 | ❌ | ✅ |
| 情绪传染特效（人群恐慌视觉） | ❌ | ✅ |

---

## 2. 协议接收与 FSM 映射

### 2.1 接收消息

- **TownNpcData**（全量同步）：首次进入视野时同步 emotion_state、mood_level、personality_type、move_speed_param
- **NpcEmotionChangeNtf**（增量推送）：情绪状态跃迁时推送，含 react_type、target_id

### 2.2 FSM 状态映射

**枚举值决策**：`Flee=9` 保留用于通用逃跑（向后兼容），情绪系统使用新枚举值，无双入口冲突。
FSM 规则：`服务端 NpcState 枚举值 - 1 = _stateTypes 数组索引`。

| NpcState 枚举值 | 情绪含义 | FSM 状态名 | 说明 |
|---------------|---------|-----------|------|
| Idle=0 | Calm | TownNpcIdleState | 现有，proto 默认值，旧客户端兼容 |
| Combat=8 | Angry / Brave | TownNpcCombatState | 现有 |
| Flee=9 | 通用逃跑（旧） | TownNpcFleeState | 保留向后兼容，不新增动画 |
| Watch=10 | （旧 Watch）| TownNpcWatchState | 保留现有逻辑 |
| Investigate=11 | 调查 | TownNpcInvestigateState | 现有 |
| **Scared=12** | 恐惧（慢跑） | TownNpcScaredState | **新增** |
| **Panicked=13** | 恐慌（全力奔跑） | TownNpcPanickedState | **新增** |
| **Curious=14** | 好奇（围观） | TownNpcCuriousState | **新增** |
| **Nervous=15** | 紧张（快走） | TownNpcNervousState | **新增** |
| **Angry=16** | 愤怒（辱骂） | TownNpcAngryState | **新增** |

> `int32 emotion_state` 默认值 0（Idle/Calm），旧版 TownNpcData 无该字段时客户端保持 Idle，无崩溃。

### 2.3 TownNpcData 新字段读取

```csharp
// 在 TownNpcStateData 中新增
public float MoodLevel { get; private set; }         // 情绪强度 [0, 3]
public EmotionState EmotionState { get; private set; }  // 当前情绪
public PersonalityType PersonalityType { get; private set; }
public float MoveSpeed { get; private set; }         // 动画移动速度参数
public int FleeAttrFlags { get; private set; }       // 逃跑属性标志位

public void OnNpcEmotionChange(NpcEmotionChangeNtf ntf) {
    EmotionState = (EmotionState)ntf.EmotionState;
    MoodLevel = ntf.MoodLevel;
    Notify(StateIdUpdate, (int)EmotionState - 1); // 触发 FSM 切换
}
```

---

## 3. 各情绪状态动画表现

### 3.1 Calm（平静）
- 正常日常动画（Idle、Walk、Scenario），无特殊处理

### 3.2 Curious（好奇）
- 动画：转身朝向目标 + 好奇走路循环
- 速度：正常步速（moveSpeed=1.0）
- ReactComp：激活 GawkBehavior，小步向目标移近
- 安全距离由 PersonalityType 决定（4–10m）

### 3.3 Nervous（紧张）
- 动画：快步走 + 偶发回头张望（每 2–3s 一次）
- 速度：moveSpeedParam=1.2，AnimationComp.SetSpeed(1.2)
- 附加：偶发打电话动画（10% 概率，不影响移动）

### 3.4 Scared（恐惧）
- 动画：慢跑 + 惊恐表情
- 速度：moveSpeedParam=2.0，AnimationComp.SetSpeed(2.0)
- ReactComp：激活 FleeBehavior（方向由服务器下发目标点）
- 附加：偶发尖叫动画（flee_attr_flags 中 FLEE_CAN_SCREAM 位控制）

### 3.5 Panicked（恐慌）
- 动画：全力奔跑 + 随机跌倒（5% 概率触发绊倒动画）+ 互相推挤
- 速度：moveSpeedParam=3.5，AnimationComp.SetSpeed(3.5)
- ReactComp：高优先级 FleeBehavior，忽略障碍物（直接绕行）
- 附加：跌倒后爬起 → 继续奔跑（动画序列）

### 3.6 Angry（愤怒）
- 动画：快步走向肇事者 + 辱骂手势循环
- ReactComp：激活 ConfrontBehavior（面向 target_id）
- 升级：收到服务器 Combat 通知后切换 CombatComp（已有）

### 3.7 Brave（勇敢）
- 动画：正常站立 + 警惕姿势（不逃跑）
- 复用 TownNpcCombatState，配置不同动画参数

---

## 4. 应激行为视觉实现

### 4.1 逃跑行为（ScaredState / PanickedState）

**新增/扩展组件**：`TownNpcFleeComp`（或在现有 ReactComp 中新增 Flee 模式）

```csharp
// 接收 NpcEmotionChangeNtf 后
void OnEmotionChange(NpcEmotionChangeNtf ntf) {
    float speed = ntf.MoveSpeed; // 服务器下发：Scared=2.0, Panicked=3.5
    AnimationComp.SetSpeed(speed);
    if (ntf.IsTrip fall) {   // 跌倒由服务器决定并下行，客户端不自行随机
        PlayTripSequence();
    }
    // flee_attr_flags 从 Ntf 读取（增量），或从 TownNpcData 缓存读取（全量）
    if ((ntf.FleeAttrFlags & FLEE_CAN_SCREAM) != 0) {
        PlayScreamOneShot(); // 一次性尖叫音效+动画
    }
}
```

**动画参数**（AnimationComp.SetParameter）：

| 参数名 | 类型 | 值域 | 说明 |
|--------|------|------|------|
| EmotionState | int | 0–16 | 当前情绪枚举值 |
| MoveSpeed | float | 0–4 | 移动速度倍率 |
| IsPanicked | bool | — | 触发跌倒/推挤动画层 |
| CanScream | bool | — | 启用尖叫动画 |

### 4.2 蹲伏/躲避（DuckCoverState）

- 触发：服务器下发 Scared 状态 + 无逃跑目标时
- 动画：播放 DuckCover 循环（AnimationComp.Play(TransitionKey.DuckCover)）
- 朝向：持续 LookAt 威胁方向（由 target_id 定位）
- 解除：收到服务器更新为 Calm/Nervous 时切换动画

### 4.3 围观聚集（GawkState）

- 触发：NpcEmotionChangeNtf.ReactType == Curious
- 动画：好奇步行循环（Walk + HeadLook 朝向 target_id）
- 到达安全距离（PersonalityType 决定）后：切换 GawkIdle（原地张望）
- 离开：超时或收到 Scared+ 状态后，切换逃跑 FSM

### 4.4 打电话报警（PhoneState）

- 触发：ReactType == Phone
- 动画序列：掏手机（固定 2s）→ 通话循环（`ntf.PhoneDuration` 秒）→ 收手机
- 通话时长从 `NpcEmotionChangeNtf.phone_duration` 读取，**不自行随机**，确保与服务器状态同步
- 打断：收到高优先级 Scared/Panicked 时立即切换（中断动画）
- 音效：拨号音 + 通话音（客户端本地播放，时长跟随 phone_duration）

### 4.5 愤怒对抗（AngryConfrontState）

- 触发：ReactType == Angry
- 动画：快步走向 target_id + 辱骂手势循环
- 推搡：到达 1.5m 内后播放 Push 动画
- 升级：收到服务器 Combat=8 通知 → 切换 TownNpcCombatState

### 4.6 载具内行为（VehicleEmotionState）

| ReactType | 视觉表现 | 备注 |
|-----------|---------|------|
| VehicleEscape | 加速动画（方向盘打满，身体前倾） | collision_severity 无关 |
| VehicleCrouch | 座椅蹲伏动画，头部低于车窗 | 乘客专用 |
| VehicleShout | 摇下车窗 + 挥手辱骂动画 | collision_severity=0（轻微） |
| VehicleConfront | 停车 → 下车 → 对抗姿势 | collision_severity=1（严重）+Confident/Fearless |
| Panicked（弃车） | 停车 → 推开车门动画 → 切换步行 PanickedState | ReactType_Panicked + 车内 |

> `collision_severity` 字段来自 `NpcEmotionChangeNtf.collision_severity`（0=轻微, 1=严重），客户端据此播放不同动画。

---

## 5. 组件注册与扩展

### 5.1 新增/扩展组件

| 组件 | 说明 | 注册位置 |
|------|------|---------|
| `TownNpcEmotionComp` | 接收 NpcEmotionChangeNtf，驱动 FSM 切换 | TownNpcController.OnInit |
| `TownNpcFleeComp` | 逃跑行为（Scared/Panicked），管理速度+动画 | TownNpcController.OnInit |
| `TownNpcGawkComp` | 围观行为（Curious），管理 LookAt+移动 | TownNpcController.OnInit |
| `TownNpcAngryComp` | 愤怒对抗行为，扩展现有 ReactComp | TownNpcController.OnInit |

> 现有 CombatComp / ReactComp 保留，新组件不重复已有逻辑。

### 5.3 配置表驱动（个性参数）

个性相关参数（逃跑距离、围观安全距离、衰减因子、触发阈值）应读自配置表，不硬编码：

| 参数 | Excel 表名（待策划确认） | 字段 |
|------|------------------------|------|
| 各个性类型逃跑距离 | NpcPersonalityConfig | flee_distance |
| 围观安全距离 | NpcPersonalityConfig | gawk_safe_distance |
| 情绪触发阈值 | NpcEmotionConfig | trigger_threshold |
| 衰减因子 | NpcEmotionConfig | decay_factor_k |

> 配置表由策划填写，客户端在启动时加载，热更新时重新读取。

### 5.2 FSM 状态注册

新增 FSM 状态需在 `_stateTypes` 数组中按 `枚举值 - 1` 位置注册：

```csharp
// TownNpcFsmComp 中补充
_stateTypes[11] = typeof(TownNpcScaredState);    // 枚举值 12
_stateTypes[12] = typeof(TownNpcPanickedState);  // 枚举值 13
_stateTypes[13] = typeof(TownNpcCuriousState);   // 枚举值 14
_stateTypes[14] = typeof(TownNpcNervousState);   // 枚举值 15
_stateTypes[15] = typeof(TownNpcAngryState);     // 枚举值 16
```

---

## 6. 验收标准（客户端侧）

| 用例 | 操作 | 预期结果 |
|------|------|---------|
| 逃跑动画 | 服务器推送 Scared | NPC 3s 内开始播放慢跑动画，速度参数 2.0 |
| 全力奔跑 | 服务器推送 Panicked | NPC 播放全力奔跑，5% 概率触发跌倒序列 |
| 围观走近 | 服务器推送 Curious | NPC 转向目标，缓步移近至安全距离后原地张望 |
| 打电话 | 服务器推送 Phone | 掏手机动画 → 通话循环 → 被打断时立即切换 |
| 个性差异 | Coward vs Fearless 同时亮武器 | Coward 逃跑距离视觉上明显远于 Fearless |
| 载具弃车 | 驾驶员 Panicked | 停车 → 推门 → 步行奔跑，动画连贯无穿帮 |
| FSM 切换 | 情绪从 Scared 衰减到 Calm | FSM 正确退回 Idle/Scenario 状态 |
| 协议兼容 | 旧版 NPC 无 emotion_state 字段（int32 默认 0） | FSM 保持 Idle/Calm，无崩溃 |
| 死亡重置 | NPC Panicked 状态中死亡 | 收到 Calm Ntf 后立即切换 Idle 动画，无跌倒残留 |
| 蹲伏躲避 | 服务器下发 ReactType_DuckCover | NPC 找掩体蹲伏，持续朝向 target_id，10s 后自动恢复 |
| 社交传播视觉 | 人群中触发爆炸，情绪向外扩散 | 外圈 NPC 依次触发对应情绪动画，视觉上呈现向外扩散效果 |
