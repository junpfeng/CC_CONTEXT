# 动物系统协议设计

> **状态：设计阶段 — 4 种动物（Dog/Bird/Crocodile/Chicken），资源驱动排期**
>
> 本文档定义动物系统的客户端-服务器通信契约，是服务器需求和客户端需求的共同依赖。
> 关联服务器：[server.md](server.md) | 关联客户端：[client.md](client.md)

## 1. 设计原则

1. **复用 NPC 通道**：动物作为特殊 NPC 类型（`SceneNpcExtType_Animal = 4`），复用 `NpcDataUpdate` 同步通道，不新建独立实体通道
2. **服务端权威**：所有行为决策（状态切换）由服务器完成，客户端纯表现
3. **最小协议面**：只传输客户端表现必需的信息，AI 内部状态（感知数据、行为树节点）不下发
4. **LOD 感知同步**：根据玩家与动物距离分级控制同步频率，远距离降低带宽
5. **向后兼容**：新增字段使用 proto 追加语义（新 field number），不修改已有字段含义
6. **资源驱动排期**：仅实现有模型 + 有动画的 4 种动物（Dog/Bird/Crocodile/Chicken）

### 1.1 可用资源

| 动物 | 模型变体 | 动画 Clip |
|------|---------|----------|
| Dog（狗） | 2（BorderCollie / Labrador） | idle, walk, run, specialidle（4 个）|
| Bird（鸟） | 1（Bird_001） | fly, idle（2 个）|
| Crocodile（鳄鱼） | 3（001 / 002 / 003_Green） | idle, walk（2 个）|
| Chicken（鸡） | 1（Chicken_001_Red） | squatidle（1 个）|

### 1.2 现有协议基础

| 现有资源 | 位置 | 说明 |
|---------|------|------|
| `NpcDataUpdate` 消息 | `old_proto/scene/npc.proto` | 字段 1-39 已用，**实现前需查询最新最大字段号** |
| `SceneNpcExtType` | `cnpc/scene_ext.go` | 已有 Default/Town/Sakura/TownGta，需新增 `Animal = 4` |
| `Codes` 错误码枚举 | `old_proto/base/codes.proto` | 动物错误码追加至 14001-14004 段 |
| `Vector3` / `Codes` 等基础类型 | `old_proto/base/base.proto` | 已有，直接引用 |

### 1.3 Proto 文件规划

所有动物系统消息定义在 `old_proto/scene/npc.proto` 中追加（与现有 NPC 消息同文件），不新建独立 .proto 文件。

```protobuf
// 需要的 import（已在 npc.proto 中存在）
import "base/base.proto";   // Vector3, Codes
```

## 2. 枚举定义

### 2.1 AnimalType — 动物类型

> **AnimalType vs MonsterType 映射说明**：协议层使用 `AnimalType` 枚举（Dog=1），客户端配置表使用 `MonsterType` 枚举（Dog=48）。两者是**独立枚举**，通过配置表关联映射（`CfgInitMonster` 中 AnimalType 字段 → MonsterType ID）。服务器以 `AnimalType` 为准，客户端收到后通过配置表查到对应 `MonsterType` 加载 Prefab/动画。

```protobuf
// 动物种类，对应配置表 cfg_id 的大类
enum AnimalType {
    AnimalType_None        = 0;
    AnimalType_Dog         = 1;   // 狗（BorderCollie / Labrador）
    AnimalType_Bird        = 2;   // 鸟（Bird_001）
    AnimalType_Crocodile   = 3;   // 鳄鱼（001 / 002 / 003_Green）
    AnimalType_Chicken     = 4;   // 鸡（Chicken_001_Red）
}
```

### 2.2 AnimalState — 动物行为状态

```protobuf
// 动物行为状态，服务器决策后下发，客户端驱动 FSM 切换
// 仅保留有对应动画 Clip 的状态
enum AnimalState {
    AnimalState_None    = 0;
    AnimalState_Idle    = 1;   // 待机（Dog:idle / Bird:idle / Croc:idle / Chicken:squatidle）
    AnimalState_Walk    = 2;   // 漫步（Dog:walk / Croc:walk）
    AnimalState_Run     = 3;   // 奔跑（Dog:run）
    AnimalState_Flight  = 4;   // 飞行（Bird:fly）
    AnimalState_Follow  = 5;   // 跟随（Dog 喂食后跟随玩家）
}
```

> **状态与动画对应约束**：Bird 无 walk/run，不进入 Walk/Run 状态；Crocodile 无 run，不进入 Run/Flight 状态；Chicken 仅有 squatidle，始终保持 Idle 状态。

### 2.3 AnimalIdleSubState — 待机子状态

```protobuf
// Idle 下的子状态，用于客户端播放不同待机动画变体
enum AnimalIdleSubState {
    AnimalIdleSubState_Rest    = 0;  // 休息（默认）
    AnimalIdleSubState_Wander  = 1;  // 缓慢游荡
}
```

### 2.4 AnimalCategory — 动物大类

```protobuf
// 运动类型大类，决定客户端使用哪套运动/动画系统
enum AnimalCategory {
    AnimalCategory_Land  = 0;  // 陆地（Dog / Crocodile / Chicken）
    AnimalCategory_Bird  = 1;  // 鸟类（Bird）
}
```

## 3. 数据消息

### 3.1 AnimalData — 动物实体数据（随 NpcDataUpdate 下发）

```protobuf
// 动物实体数据，挂载在 NpcDataUpdate.animal_info 字段
// 每次全量同步或增量更新时携带完整快照
message AnimalData {
    uint32 animal_type      = 1;  // AnimalType 枚举
    uint32 animal_state     = 2;  // AnimalState 枚举
    uint32 idle_sub_state   = 3;  // AnimalIdleSubState，仅 state=Idle 时有效
    float  move_speed       = 4;  // 当前移动速度 m/s（客户端用于动画混合）
    float  heading          = 5;  // 朝向角度（弧度）
    uint64 follow_target_id = 6;  // 跟随目标实体 ID（Dog 专用，0=无跟随）
    uint32 variant_id       = 7;  // 外观变体 ID（同种动物不同皮肤/体型，0=默认）
    uint32 animal_category  = 8;  // AnimalCategory 枚举（陆地/鸟类）
}
```

**字段说明：**

| 字段 | 适用动物 | 说明 |
|------|---------|------|
| `animal_type` | 全部 | 决定客户端加载哪种动物 Prefab |
| `animal_state` | 全部 | 驱动客户端 FSM 切换动画 |
| `idle_sub_state` | 全部（Idle 时）| Rest=默认休息，Wander=游荡 |
| `move_speed` | Dog / Crocodile | 用于动画混合树速度参数 |
| `heading` | 全部 | 世界空间朝向角（弧度） |
| `follow_target_id` | Dog | 跟随目标玩家/NPC 实体 ID |
| `variant_id` | Dog(0-1) / Crocodile(0-2) | 外观变体索引，客户端对应不同 Prefab |
| `animal_category` | 全部 | 陆地=0 / 鸟类=1 |

### 3.2 生成与消失通知

动物复用 NPC 生成/消失通道：

- **生成**：通过 `NpcDataUpdate`（`SceneNpcExtType = 4`）推送，`animal_info` 携带完整 `AnimalData`
- **消失**：通过 NPC 移除通道（`NpcRemoveNtf` 或等效机制）移除

## 4. 行为通知

### 4.1 AnimalStateChangeNtf — 状态切换通知

```protobuf
// 动物状态切换通知（仅在状态发生变化时推送，不等下一帧 NpcDataUpdate）
message AnimalStateChangeNtf {
    uint64 animal_id      = 1;  // 动物实体 ID
    uint32 new_state      = 2;  // AnimalState
    uint32 idle_sub_state = 3;  // 仅 new_state=Idle 时有效，其余置 0
    float  move_speed     = 4;  // 切换后的移动速度
}
```

> **设计说明**：`AnimalStateChangeNtf` 是事件通知，仅在状态变化瞬间推送（立即响应，不等下一个 `NpcDataUpdate` 帧）。`NpcDataUpdate` 携带的 `AnimalData` 是全量快照，用于状态对齐。两者互补：Ntf 保证实时性，全量快照保证一致性。

## 5. 玩家交互

### 5.1 AnimalFeedReq / AnimalFeedResp — 喂食请求/响应

```protobuf
// 玩家喂食动物（Dog 专属核心玩法）
message AnimalFeedReq {
    uint64 animal_id = 1;  // 目标动物实体 ID
    string item_id   = 2;  // 使用的食物物品 ID
}

message AnimalFeedResp {
    uint32 code       = 1;  // 0=成功，非 0 见错误码
    uint64 animal_id  = 2;
    float  follow_dur = 3;  // 喂食后跟随时长（秒），0=不跟随
}
```

> **服务器校验**：动物类型为 Dog、距离 <= 3m、物品为有效食物、动物存活。
> 喂食成功后服务器设置 `AnimalData.follow_target_id = 玩家实体 ID`，并切换状态为 `AnimalState_Follow`，随下一帧 `NpcDataUpdate` 下发。

## 6. 与现有协议的集成点

### 6.1 NpcDataUpdate 扩展

> **字段号注意**：实现前必须查询 `old_proto/scene/npc.proto` 中 `NpcDataUpdate` 的当前最大字段号，在其后追加，避免冲突。

```protobuf
// 在现有 NpcDataUpdate 中追加字段（字段号 XX 需查最新 proto 确认，此处示意）
message NpcDataUpdate {
    // ... 现有字段 ...
    AnimalData animal_info = XX;  // 动物专属数据（SceneNpcExtType=4 时填充）
}
```

### 6.2 SceneNpcExtType 扩展

```go
// Go 侧枚举扩展（cnpc/scene_ext.go）
// 现有值：Default, Town, Sakura, TownGta
const SceneNpcExtType_Animal = 4  // 新增
```

> **不扩展 NpcState 枚举**：动物使用独立的 `AnimalState` 枚举，不与人形 NPC 的 `NpcState` 混用，避免枚举膨胀和语义混淆。

### 6.3 错误码

项目使用单一 `Codes` 枚举（定义在 `codes.proto`），不新建独立枚举。在现有 `Codes` 枚举中追加 14001-14004 段：

```protobuf
// 追加到 codes.proto 的 Codes 枚举中
// 动物系统错误码（14001-14004）
// Codes_AnimalNotFound      = 14001;  // 动物不存在
// Codes_AnimalTooFar        = 14002;  // 距离太远
// Codes_AnimalInvalidFood   = 14003;  // 无效食物物品
// Codes_AnimalNotFeedable   = 14004;  // 该动物不可喂食（非 Dog）
```

## 7. 同步策略

### 7.1 全量快照 vs 事件通知

**两套机制角色不同，互补而非增量关系：**

- **AnimalData（全量快照）**：随 `NpcDataUpdate` 下发，每次发送完整的 `AnimalData` 结构。客户端以此为权威状态，处理进入 AOI、重连、LOD 切回等场景的状态对齐。
- **AnimalStateChangeNtf（事件通知）**：仅在状态发生变化的瞬间推送，不等下一个 `NpcDataUpdate` 同步帧。用于客户端立即响应关键状态变化（如进入飞行、开始跟随）。

| 场景 | 机制 | 说明 |
|------|------|------|
| 动物进入 AOI | 全量快照 | `NpcDataUpdate` 含完整 `AnimalData` |
| 帧同步 | 全量快照 | 每次下发完整 `AnimalData`，频率按 LOD 分级 |
| 状态切换 | 事件通知 | `AnimalStateChangeNtf` 立即推送，不等帧同步 |

### 7.2 LOD 分级同步频率

| 距离 | 同步频率 | 同步内容 |
|------|---------|---------|
| < 50m（Full LOD） | 每帧（30Hz） | 位置 + 朝向 + 速度 + 状态 |
| 50-150m（Medium LOD） | 10Hz | 位置 + 朝向 + 状态 |
| 150-300m（Low LOD） | 2Hz | 位置 + 状态（无朝向插值） |
| > 300m | 不同步 | 服务器保留实体，不推送数据 |

### 7.3 AOI 管理

- 动物复用 NPC 的 AOI 管理（`WorldDataUpdate` 中的 npcs 列表）
- 进入 AOI：随 `SceneInfoNtf` 或增量 `NpcDataUpdate` 推送
- 离开 AOI：随 NPC 移除通道移除
- 性能保护：单个玩家 AOI 内动物超出上限时，服务器挂起最远动物的同步

### 7.4 LOD 决策归属

**服务器控制 AI LOD**（Tick 频率、行为简化、同步频率），**客户端独立控制渲染 LOD**（模型精度、骨架、Billboard 切换）。两者均以玩家-动物距离为基准，使用相同的阈值（50m/150m/300m），但各自独立计算，不通过协议下发 LOD 标记。服务器的同步频率降低自然驱动客户端表现降级。
