# 路人 AI 与情绪反应 — 服务器需求文档

> **状态**: 待实现
> **日期**: 2026-03-13
> **参考**: GTA5/docs/design/路人AI与情绪反应需求.md
> **涉及工程**: P1GoServer
> **相关文档**: npc-gta5-behavior-implementation.md, npc-v2-decision-execution-redesign-tech-design.md

## 1. 模块职责边界

服务器负责所有逻辑计算，客户端只做视觉表现。

| 职责 | 服务器 | 客户端 |
|------|--------|--------|
| 感知计算（视觉/听觉） | ✅ | ❌ |
| 情绪状态机 + 衰减计算 | ✅ | ❌ |
| 社交情绪传播 | ✅ | ❌ |
| 应激任务调度（逃跑/围观/打电话） | ✅ | ❌ |
| 通缉值更新 | ✅ | ❌ |
| 动画参数下行（情绪状态+速度参数） | 推送 | 播放 |
| 特效/声音 | ❌ | ✅ |

---

## 2. 感知系统

基于 V2 OrthogonalPipeline Perception 能力扩展。

| 感知通道 | 参数 | 更新策略 |
|---------|------|---------|
| 视觉（圆锥） | 视角 120°，距离 30m，遮挡打折 | LOD0 每帧，LOD1 每 3 帧 |
| 听觉（球形，步行） | 半径 20m，穿墙衰减系数 0.6 | 同上 |
| 听觉（球形，载具内） | 半径 15m，穿墙衰减系数 0.4 | 同上 |

感知结果写入 `NpcState.threats[]`、`NpcState.heardEvent`（见 §7 协议扩展）。

**LOD 分级：**

| LOD | 距离 | 情绪计算完整度 |
|-----|------|-------------|
| 0 | 0–30m | 完整感知 + 完整情绪状态机 |
| 1 | 30–100m | 简化感知；执行 Flee/Gather；Angry 降级为快步离开 |
| 2 | 100m+ | 不执行决策；情绪状态丢弃，重置 Calm |

**LOD 切换时情绪状态处理：**
- LOD0 → LOD1：moodLevel 保留，持续时长继续倒计时（冻结）
- LOD1 → LOD0：恢复完整情绪计算，若已耗尽则重置 Calm
- 进入 LOD2：情绪状态丢弃，重置 Calm
- LOD2 → LOD0/1：以 Calm 初始状态进入，不恢复历史情绪

---

## 3. 情绪状态机

### 3.1 情绪状态定义

| 情绪状态 | moodLevel 初始值 | 衰减因子 k | 映射 NpcState |
|---------|----------------|------------|--------------|
| Calm | 0.0 | — | Idle（已有） |
| Curious | 0.3 | 0.95 | Watch=10（已有） |
| Nervous | 0.6 | 0.95 | Watch=10（动画参数区分） |
| Scared | 1.2 | 0.95 | Flee=9（已有） |
| Panicked | 2.5 | 0.95 | Flee=9（+is_panicked 标志位） |
| Angry | 1.0 | 0.95 | Combat=8（已有） |
| Brave | — | — | Combat=8（仅帮派/警察） |

个性系数：Coward k=0.92，Calm_personality k=0.98，Normal k=0.95（默认）。
`moodLevel` 范围 [0.0, 3.0]，每秒乘以衰减因子；衰减至 < 0.1 视为 Calm。

**典型衰减时长（k=0.95，供 QA 验证）：**

| 初始情绪 | moodLevel 初始值 | 衰减至 Calm（<0.1）所需秒数 |
|---------|----------------|--------------------------|
| Curious | 0.3 | ~23s |
| Nervous | 0.6 | ~37s |
| Angry | 1.0 | ~54s |
| Scared | 1.2 | ~60s |
| Panicked | 2.5 | ~83s（衰减至 Scared 阈值约 16s，再至 Calm 约 67s） |

Coward（k=0.92）约缩短 25%，Calm_personality（k=0.98）约延长 50%。

### 3.2 状态转换规则

| 源状态 | 目标状态 | 条件 |
|--------|---------|------|
| Calm | Curious | 感知到 Level 1 事件 |
| Calm | Nervous | 感知到 Level 2 事件 |
| Calm | Scared/Panicked | 感知到 Level 3 事件（可跨级跳变） |
| Calm | Angry | 被推挤/轻微碰撞 |
| Curious | Nervous | 感知到 Level 2+ 事件 |
| Nervous | Scared | 感知到 Level 3 事件 |
| Scared | Panicked | 感知到近距离（≤10m）Level 3 事件 |
| Panicked | Scared | 离开事件区域且无新触发（约 60s 衰减） |
| Brave | Scared | 自身受伤（立即触发，覆盖 Brave） |
| 任意 | Calm | moodLevel < 0.1 |

**多事件同帧叠加规则：**
- 取最高冲击等级事件为主事件，其余丢弃（不累加）
- Level 3 事件允许从任意状态直接跳入 Panicked
- 同等级多事件：moodLevel +0.2，上限 3.0
- 200ms 内同一事件源重复触发视为同一事件（时间窗口固定，独立于帧率）
- Angry 与恐惧系情绪互斥，恐惧优先级更高

**冲击等级映射：**

| 等级 | 事件示例 | 典型情绪响应 |
|------|---------|------------|
| Level 1 | 轻微车祸、街头打架 | Curious → Nervous |
| Level 2 | 枪声（远距离）、人员受伤 | Nervous → Scared |
| Level 3 | 近距离枪击、爆炸、玩家持枪冲刺 | Scared → Panicked |

### 3.3 个性类型（PersonalityType）

| 类型 | 逃跑距离 | 愤怒概率 | 围观安全距离 | 触发阈值 |
|------|---------|---------|------------|---------|
| Coward | 最远 | 极低 | 10m | 最低（Level 1 即响应） |
| Normal | 中等 | 中等 | 8m | 默认 |
| Confident | 较近 | 较高 | 6m | 较高 |
| Fearless | 不逃跑 | 高 | 4m | 高，可进入 Brave |
| Calm_personality | 适中 | 低 | 8m | 最高（仅 Level 3 响应） |

---

## 4. 应激任务（Handler 层实现）

基于 V2 OrthogonalPipeline Expression 维度。ThreatReact/SocialReact Handler 框架已存在，需补全 OnTick 逻辑（见 npc-gta5-behavior-implementation.md §1.3 第 13/14 项）。

### 4.1 ThreatReactHandler（Expression 维度）

**实现位置**：`servers/scene_server/internal/common/ai/execution/handler/threat_react_handler.go`

```
触发：NpcState.moodLevel 达到 Nervous 阈值（0.6）以上
OnTick：
  - Nervous  → 下行 react_type=Nervous；设置 moveSpeedParam=1.2 → Locomotion 维度读取
  - Scared   → 下行 react_type=Scared；设置 moveSpeedParam=2.0；Navigation 维度设置逃跑目标
  - Panicked → 下行 react_type=Panicked；设置 moveSpeedParam=3.5；强制 is_panicked=true
OnExit：清除 react_type，moveSpeedParam 恢复默认
```

### 4.2 SocialReactHandler（Expression 维度）

**实现位置**：`servers/scene_server/internal/common/ai/execution/handler/social_react_handler.go`

```
触发：NpcState.moodLevel 在 Curious 区间 [0.3, 0.6)
OnTick：
  - 设置 react_type=Curious；Navigation 维度设置目标点（事件位置）
  - 到达安全距离后停止（按个性类型 4–10m）
  - 围观超时 30s → OnExit，返回 Scenario
  - 事件升级 Level 2+ → 切换 ThreatReactHandler（由状态机跃迁触发）
```

### 4.3 DuckCoverHandler（Expression 维度）

**触发条件**：Scared 状态 + Navigation 维度无有效逃跑目标（被障碍物包围或服务器判定无路可逃）

```
OnTick：
  - 设置 react_type=DuckCover；寻找最近掩体（墙角/车辆/树木，搜索半径 15m）
  - 导航至掩体位置 → 到达后进入蹲伏姿势
  - 持续 LookAt 威胁方向（target_id），每帧更新朝向
  - 解除条件：威胁消失超过 10s（moodLevel 衰减至 Nervous 以下）→ OnExit 返回 Scenario
  - 高优先级打断：moodLevel 升至 Panicked → ForceExit，切换 ThreatReactHandler（逃跑）
```

### 4.4 AngryReactHandler（Expression 维度）

```
触发：Angry 状态（被推挤/碰撞）+ Confident/Fearless 个性
OnTick：
  - 设置 react_type=Angry；Navigation 设置朝向肇事者
  - Angry 衰减完毕（moodLevel < 0.1）→ OnExit
  - 对方攻击 → ForceExit 本 Handler，移交 CombatBtHandler
```

### 4.4 PhoneReportTask（Expression 维度）

```
触发：(Angry + 通缉值 < 2星) 或 (Scared + 目击犯罪)
冷却：同一 NPC reportCooldown=120s
流程：
  - Phase 1（2s）：动画=掏手机
  - Phase 2（随机 5–10s）：服务器随机决定时长，通过 Ntf.phone_duration 下行
  - 完成：WantedSystem.AddWanted(+1)；推送 NpcEmotionChangeNtf 含 react_type=Phone
打断：受攻击或 moodLevel 升至 Panicked → 立即 OnExit，不触发通缉加成
```

> 通话时长由服务器决定后写入 phone_duration 字段下行，客户端严格按该时长播放，不自行随机。

### 4.5 载具内 NPC 行为（VehicleEmotionHandler）

**车内感知参数**：听觉半径 15m，穿墙衰减 0.4；情绪响应：

| 情绪 | 角色 | 服务器行为 |
|------|------|---------|
| Curious/Nervous | 驾驶员 | 速度 ×0.6，Navigation 缓行 |
| Scared | 驾驶员 | 速度 ×1.5，随机变道；下行 react_type=VehicleEscape |
| Scared | 乘客 | react_type=VehicleCrouch，不下车 |
| Panicked | 驾驶员 | 停车 → 下车逃跑（切换步行 Flee 逻辑） |
| Panicked | 乘客 | 同时下车，切换步行 Flee |
| Angry 轻微碰撞 | 驾驶员 | react_type=VehicleShout |
| Angry 严重碰撞 | Confident/Fearless | 下车对抗 → AngryReactHandler；react_type=VehicleConfront |
| Angry 严重碰撞 | Coward | 弃车逃离 → Flee；react_type=VehicleEscape |

**碰撞等级判定**（服务器侧）：
- 轻微碰撞：碰撞冲量 < 阈值 `VehicleCollisionThreshold`（配置表，默认 500N·s）→ VehicleShout
- 严重碰撞：冲量 ≥ 阈值 → 按个性分流（VehicleConfront 或 VehicleEscape）
- 碰撞等级在 NpcEmotionChangeNtf.collision_severity 字段中下行（0=轻微, 1=严重）

**载具隔离**：车内 NPC 不参与社交传播（发送与接收均屏蔽）。

---

## 5. 社交情绪传播

| 参数 | 值 |
|------|---|
| 视觉传播半径 | 5m（需视线畅通，墙体/车辆完全遮挡失效） |
| 听觉传播半径 | 10m（穿墙衰减 50%） |
| 传播衰减 | 接收方情绪阈值 × 0.7（比直接触发弱） |
| 单 NPC 传播上限 | 向最近 3 个相邻 NPC 传播 |
| 全局每帧广播上限 | 40 次（超出本帧丢弃，次帧优先补算） |
| 反向传播 | 周围 NPC 均 Calm 时，Scared NPC 衰减因子提升至 k=0.98 |
| 载具隔离 | 车内 NPC 不参与（发送与接收均屏蔽） |

**Panicked 连锁触发**：半径 15m 内 ≥3 个 NPC 同时处于 Scared/Panicked 且彼此 15m 内 → 触发群体 Panicked。

**反向传播范围**：以 Scared NPC 为中心，视觉传播半径（5m）+ 听觉传播半径（10m）= 10m 内周围 NPC 均处于 Calm 时触发反向传播，衰减因子提升至 k=0.98。

**次帧补算队列排序**：超出 40 次/帧时，丢弃队列按 ① 距玩家距离（近优先）② 源 NPC 的 moodLevel（高优先）排序，最大积压不超过 3 帧；超过 3 帧仍未补算的丢弃。

---

## 6. 系统接口

| 依赖系统 | 接口说明 |
|---------|---------|
| CombatDirector | Angry NPC 进入肉搏后，控制权交给 CombatDirector；情绪系统暂停该 NPC 决策直到战斗结束 |
| RelationshipGroup | 帮派/警察情绪基线不同（不惧怕玩家，Brave 状态入口） |
| NpcState | 情绪状态写入 NpcState.moodLevel、NpcState.emotionState |
| ScenarioManager | 情绪 ≥ Scared 中断所有场景任务；Calm 后可重新进入 |
| WantedSystem | PhoneReportTask 完成后 +1 通缉星；通话未完成不触发 |
| 脚本系统 | SET_PED_FLEE_ATTRIBUTES 可强制覆盖情绪（flee_attr_flags 位掩码），见下方优先级规则 |

**NPC 死亡/复活时的情绪处理：**
- 死亡：GlobalGuard 触发 → moodLevel 清零 → emotionState 重置 Calm → 推送 NpcEmotionChangeNtf(Calm) 给客户端；所有情绪计时器（decayTimer/reportCooldown/spreadCooldown）同步清零
- 复活/重新生成：以 Calm 初始状态进入，不恢复历史情绪

**脚本强制覆盖 vs 自然衰减优先级：**
- 脚本通过 `FLEE_FORCED_MOOD` 设置的情绪状态，moodLevel 被强制钉定（pinned），**不参与自然衰减**
- 脚本调用 `ClearForcedMood()` 或 NPC 死亡时解除钉定，恢复自然衰减
- 钉定期间自然事件仍可触发更高等级跳变（如脚本钉定 Nervous，玩家枪击仍可升至 Scared/Panicked）
- 优先级：死亡 GlobalGuard > 事件触发跳变 > 脚本钉定 > 自然衰减

**SET_PED_FLEE_ATTRIBUTES 位掩码定义：**

| 位 | 字段名 | 说明 |
|----|--------|------|
| 0 | FLEE_ON_FOOT_ALWAYS | 强制步行逃跑，禁止使用载具 |
| 1 | FLEE_PREFER_PAVEMENT | 优先走人行道 |
| 2 | FLEE_TURN_180_BEFORE_FLEE | 逃跑前先做 180° 转身动画 |
| 3 | FLEE_CAN_SCREAM | 逃跑时允许触发尖叫动画 |
| 4–31 | 保留 | — |

---

## 7. 协议扩展（old_proto）

**编辑入口**：`old_proto/`，运行 `_tool_new/1.generate.py` 生成代码。

### 7.1 NpcState 枚举扩展

**决策**：`Flee=9` 保留用于通用逃跑（向后兼容），情绪系统使用新枚举值精确表达，避免客户端 FSM 双入口冲突。

现有枚举已有 Combat=8/Flee=9/Watch=10/Investigate=11，新增：

| 枚举值 | 名称 | 说明 |
|--------|------|------|
| 12 | NpcState_Scared | 恐惧（慢跑逃跑） |
| 13 | NpcState_Panicked | 恐慌（全力奔跑） |
| 14 | NpcState_Curious | 好奇（围观走近） |
| 15 | NpcState_Nervous | 紧张（快走回头） |
| 16 | NpcState_Angry | 愤怒（辱骂追打） |

`0 = NpcState_Idle`（proto int32 默认值 = Calm 基线状态），确保旧客户端兼容。

### 7.2 TownNpcData 新增字段

```proto
message TownNpcData {
  // ...现有字段（保留，不修改）...
  float mood_level        = 30; // 情绪强度 [0.0, 3.0]
  int32 emotion_state     = 31; // EmotionState 枚举（与 NpcState 枚举对应）
  int32 personality_type  = 32; // PersonalityType（0=Normal/1=Coward/2=Confident/3=Fearless/4=Calm）
  float move_speed        = 33; // 移动速度参数（由情绪决定，供动画使用）
  int32 flee_attr_flags   = 34; // SET_PED_FLEE_ATTRIBUTES 位掩码
}
```

### 7.3 新增消息

```proto
// 情绪状态变更通知（增量推送，避免每帧全量同步）
message NpcEmotionChangeNtf {
  int64 npc_id           = 1;
  int32 emotion_state    = 2; // NpcState 枚举值（与 TownNpcData.emotion_state 同枚举）
  float mood_level       = 3;
  int32 react_type       = 4; // ReactType 枚举（见下）
  int64 target_id        = 5; // 触发事件源（玩家 ID 或事件位置 NPC ID）
  float move_speed       = 6; // 移动速度参数（动画用）
  int32 flee_attr_flags  = 7; // SET_PED_FLEE_ATTRIBUTES 位掩码（客户端动画控制）
  float phone_duration   = 8; // 打电话通话时长（秒，仅 ReactType_Phone 有效）
  bool  is_trip_fall     = 9; // 是否触发跌倒动画（仅 Panicked 时有效，服务器决定）
  int32 collision_severity = 10; // 碰撞等级（0=轻微, 1=严重，仅载具碰撞时有效）
}

// ReactType 枚举
enum ReactType {
  ReactType_None           = 0;
  ReactType_Nervous        = 1; // 快走回头
  ReactType_Scared         = 2; // 慢跑逃跑
  ReactType_Panicked       = 3; // 全力奔跑
  ReactType_DuckCover      = 4; // 蹲伏躲避
  ReactType_Curious        = 5; // 围观走近
  ReactType_Angry          = 6; // 辱骂追打
  ReactType_Phone          = 7; // 打电话报警
  ReactType_VehicleEscape  = 8; // 载具加速逃离
  ReactType_VehicleCrouch  = 9; // 载具内蹲伏
  ReactType_VehicleShout   = 10; // 载具内辱骂
  ReactType_VehicleConfront = 11; // 下车对抗
}
```

**同步策略**：
- 情绪状态跃迁时立即推送 NpcEmotionChangeNtf
- mood_level 仅在跨等级（阈值边界）变化时推送，不每帧同步

---

## 8. 性能预算

| 指标 | 预算值 | 说明 |
|------|--------|------|
| 单 NPC 情绪计算（LOD 0） | ≤ 0.05ms/帧 | 含状态机评估 + 衰减计算 |
| 单 NPC 情绪计算（LOD 1） | ≤ 0.01ms/帧 | 仅衰减计时，无状态评估 |
| 同帧最大完整情绪 NPC 数 | 60 个 | LOD 0 范围内上限 |
| Panicked 并发上限 | 20 个 | 超出排队：① 距玩家最近 ② 触发时间最早 ③ LOD0 > LOD1 |
| 社交传播每帧广播上限 | 40 次 | 超出本帧丢弃，次帧补算，不遗漏 |
| 情绪计算内存（per NPC） | ≤ 64 bytes | moodLevel(4B)+state(1B)+personality(1B)+decayTimer(4B)+reportCooldown(4B)+spreadCooldown(4B)+dedupeTimer(4B)+padding ≈ 24B 留余量 |

---

## 9. 验收标准（服务器侧）

### 9.1 功能验收

| 用例 | 操作 | 预期结果 |
|------|------|---------|
| 基础逃跑 | 5m 内对空鸣枪 | 附近 NPC 3s 内 NpcState 变为 Scared/Panicked，推送 NpcEmotionChangeNtf |
| 跨级跳变 | 人群中心引爆炸弹 | 范围内 NPC 直接进入 Panicked，服务器日志确认跳过中间状态 |
| 情绪传播 | NPC 间距 3-5m，对最近 NPC 开枪 | 10s 内情绪扩散至半径 15m 内 ≥60% 的 NPC |
| 个性差异 | 对 Coward 与 Fearless 同时亮武器 | Coward 逃跑距离 ≥ Fearless × 2（Fearless 不逃跑） |
| 打电话冷却 | 同一 NPC 连续 3 次目击犯罪 | 第 2、3 次报警间隔 ≥ 120s |
| 反向传播 | Scared NPC 移至无事件区域 | 周围均 Calm 时，60s 内情绪恢复 Calm |
| LOD 边界 | Scared NPC 离开 100m | 重新进入 30m 后以 Calm 初始状态运行 |
| 载具行为 | 玩家车辆在道路上开枪 | 附近驾驶员 react_type=VehicleEscape（加速）或 Panicked（弃车），取决于个性 |
| 蹲伏躲避 | Scared NPC 被障碍物包围 | 服务器下发 react_type=DuckCover，NPC 找掩体蹲伏，不逃跑 |
| 死亡重置 | NPC 死亡时处于 Panicked 状态 | 立即推送 NpcEmotionChangeNtf(Calm)，客户端切换 Idle 动画 |

### 9.2 性能验收

| 场景 | 测试方法 | 通过条件 |
|------|---------|---------|
| 大规模 Panic | 50+ NPC 人群中触发爆炸 | 服务器帧率下降 ≤ 5% |
| Panicked 排队 | 同帧触发 30 个 Panicked | 3 帧内全部完成状态切换 |
| 传播满载 | 40 次/帧广播上限 | 溢出广播次帧补算，不遗漏 |
