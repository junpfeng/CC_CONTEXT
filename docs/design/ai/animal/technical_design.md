# 动物系统技术设计文档

> **状态：设计阶段** | **日期：2026-03-23**
>
> 需求文档：[client.md](client.md) | [server.md](server.md) | [protocol.md](protocol.md)

## 1. 需求回顾

### 1.1 功能概述

为大世界场景添加动物系统，支持 4 种动物（Dog/Bird/Crocodile/Chicken）。服务器负责全部 AI 行为决策，客户端纯表现。核心玩法为 Dog 喂食→跟随交互。

### 1.2 验收标准

1. 4 种动物在大世界中正确生成、AI 行为正确（待机/游荡/跟随/飞行）
2. 客户端正确接收协议，驱动 FSM/动画/音效/LOD
3. Dog 喂食交互完整闭环（FeedReq→FeedResp→Follow→回归 Idle）
4. Bird 空中 fly↔idle 循环正常
5. 同屏限制和 AI LOD 策略生效
6. 性能预算达标（< 30 DrawCall、< 2ms GPU、< 2ms AI CPU）

### 1.3 涉及工程

| 工程 | 职责 | 修改范围 |
|------|------|---------|
| `old_proto/` | 协议定义 | npc.proto 追加消息/枚举，codes.proto 追加错误码 |
| `P1GoServer/` | AI 行为、实体管理、交互校验、状态同步 | scene_server AI 模块 |
| `freelifeclient/` | Controller、FSM、动画、音效、交互 UI | BigWorld/Entity/Animal 模块 |

## 2. 架构设计

### 2.1 系统边界

```
┌─────────────────────────────────────────────────────────────┐
│                      服务器 (scene_server)                   │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌───────────┐  │
│  │ Spawner  │→│ AI Brain │→│  Handler   │→│ Sync/Proto│  │
│  │(生成管理) │  │(正交管线) │  │(行为执行)  │  │(状态同步)  │  │
│  └──────────┘  └──────────┘  └───────────┘  └───────────┘  │
└─────────────────────────┬───────────────────────────────────┘
                          │ NpcDataUpdate(animal_info) / AnimalStateChangeNtf
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    客户端 (freelifeclient)                    │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌───────────┐  │
│  │Controller│→│ FsmComp  │→│ AnimComp  │→│ AudioComp │  │
│  │(实体管理) │  │(状态切换) │  │(动画播放)  │  │(音效触发)  │  │
│  └──────────┘  └──────────┘  └───────────┘  └───────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 数据流

1. **生成**：AnimalSpawner 按区域配置生成动物 → NpcDataUpdate(SceneNpcExtType=4, animal_info) → 客户端创建 AnimalController
2. **AI 决策**：OrthogonalPipeline Tick → Handler 修改 NpcState.Animal → 同步层填充 AnimalData
3. **状态切换**：Handler 切状态 → AnimalStateChangeNtf 即时推送 → 客户端 FSM 切换
4. **交互**：AnimalFeedReq → 服务器校验 → AnimalFeedResp → 客户端播放动画 → Follow 状态

## 3. 协议设计

详见 [protocol.md](protocol.md)。关键决策摘要：

| 决策 | 方案 | 理由 |
|------|------|------|
| NpcDataUpdate.animal_info 字段号 | **38** | 当前最大 37 |
| 动物错误码段 | **14001-14004** | 当前最大 10005，10006-14000 段确认未被占用 |
| 同步策略 | 全量快照 + 事件通知互补 | 快照保一致性，Ntf 保实时性 |
| 独立 AnimalState 枚举 | 不混用 NpcState | 语义隔离，避免枚举膨胀 |

## 4. 服务器设计

详见 [server.md](server.md)。关键决策摘要：

### 4.1 ECS 集成

- `SceneNpcExtType_Animal = 4`（cnpc/scene_ext.go）
- **BtTickSystem 管线路由**：将单一 `orthogonalPipeline` 字段改为 `pipelines map[int]*OrthogonalPipeline` 查表分发。Update 循环内根据 NPC 的 `ExtType` 查表获取对应管线：`ExtType_Animal` → animalPipeline，其他 → 原有管线。`syncNpcMovement`/`syncNpcStateToAnimComp`/`emotion.Tick` 等后续同步逻辑也需按 ExtType 分叉：Animal 跳过 emotion.Tick 和人形同步，仅执行 `syncAnimalStateToProto`
- v2_pipeline_defaults.go 新增 `animalDimensionConfigs()`，在 `setupOrthogonalPipeline` 中注册到 pipelines map

### 4.2 NpcState 扩展

NpcState 新增 `Animal AnimalState` 字段组（AnimalBaseState + AnimalPerceptionState），同步扩展 Snapshot + FieldAccessor。

**字段可见性澄清**：`AnimalPerceptionState.FollowTargetID` 虽在感知结构中，但**需下发客户端**（客户端需知道跟随目标以驱动 Follow 表现），故在 FieldAccessor 中注册。仅 `AwarenessRadius` 为纯内部字段，不注册。

### 4.3 Handler 设计

| Handler | 维度 | 适用动物 |
|---------|------|---------|
| AnimalIdleHandler | Engagement | 全部（Chicken 跳过感知，锁定 Rest） |
| AnimalFollowHandler | Locomotion | Dog |
| AnimalNavigateBtHandler | Navigation | Dog/Crocodile |
| AnimalBirdFlightHandler | Navigation | Bird |

### 4.4 喂食流程

AnimalFeedReq → 校验(类型+距离+物品+存活) → 消耗物品 → FollowTargetID=playerID → AnimalFeedResp(follow_dur=30) → 30s 后清除 FollowTargetID

## 5. 客户端设计

详见 [client.md](client.md)。关键决策摘要：

### 5.1 模块位置

`Assets/Scripts/Gameplay/Modules/BigWorld/Entity/Animal/`（统一放 BigWorld，不放 S1Town——动物属于大世界系统，且 client.md 中写的 S1Town 路径已废弃）

### 5.2 组件架构

```
AnimalController : Controller
  ├── EventComp（直接复用）
  ├── TransformComp（直接复用）
  ├── RenderCullComp（直接复用）
  ├── AnimalAnimationComp（继承 AnimationComp）
  ├── AnimalAudioComp（继承 AudioComp）
  ├── AnimalFsmComp（新建，GuardedFsm<AnimalController>）
  └── AnimalInteractComp（新建，仅 Dog）
```

### 5.3 FSM 状态

| 索引 | 状态 | AnimalState 枚举 | 适用动物 |
|------|------|-----------------|---------|
| 0 | AnimalIdleState | Idle(1) | 全部 |
| 1 | AnimalWalkState | Walk(2) | Dog/Crocodile |
| 2 | AnimalRunState | Run(3) | Dog |
| 3 | AnimalFlightState | Flight(4) | Bird |
| 4 | AnimalFollowState | Follow(5) | Dog |

### 5.4 EntityType 决策

新增 `EntityType.Animal` 枚举值。动物与人形 NPC 差异过大，新增独立枚举使创建路径清晰。

## 6. 事务性设计

### 6.1 喂食交互事务

**事务范围**：单服务器内（scene_server），无跨服务事务。

**操作序列**：
1. 校验条件（动物类型=Dog、XZ 平方距离 ≤ 9m²、物品为有效食物、动物存活且 FollowTargetID==0）
2. 消耗食物物品（调用背包 `RemoveItem(item_id, 1)` 接口）
3. 设置 FollowTargetID = playerEntityID
4. 切换动物状态为 Follow
5. 返回 AnimalFeedResp

**有效食物定义**：通过配置表 `CfgItem` 的 `item_sub_type` 字段判断，`item_sub_type = AnimalFood` 为有效食物。具体 item_id 由策划在配置表中维护。

**回滚机制**：
- 步骤 2 失败（物品不足）→ 直接返回错误码，无需回滚
- 步骤 3-4 为内存操作，原子性由单线程保证
- 无持久化写入（动物状态为内存态），无需 DB 事务

**幂等性**：
- 同一动物同一时间只能被一个玩家喂食（通过 FollowTargetID != 0 判断）
- 重复请求返回 AnimalNotFeedable 错误码

**并发控制**：
- scene_server 单线程模型，无并发竞争
- 多玩家同时喂食同一只狗：先到先得，后者收到错误码

### 6.2 生成/销毁事务

- 生成为纯内存操作，AnimalSpawner 管理实体生命周期
- 销毁时 OnClear 链式清理所有组件，CancellationToken 取消异步操作
- 无持久化需求，场景卸载时全部清除

## 7. 接口契约

### 7.1 协议 ↔ 服务器

| 契约 | 说明 |
|------|------|
| SceneNpcExtType=4 时必须填充 animal_info | 服务器同步层在 NpcDataUpdate 序列化时判断 ExtType |
| AnimalState 枚举值由服务器 Handler 设置 | 客户端不校验合法性，直接映射 FSM |
| AnimalStateChangeNtf 在状态变化瞬间推送 | 不等 NpcDataUpdate 帧同步 |
| 错误码 14001-14004 覆盖所有喂食失败场景 | 客户端按错误码显示提示 |

### 7.2 协议 ↔ 客户端

| 契约 | 说明 |
|------|------|
| animal_type → MonsterType 映射 | 通过 CfgInitMonster 配置表关联 |
| animal_state → FSM 索引 | 枚举值 - 1 = 数组索引 |
| move_speed 单位 m/s | 客户端用于动画速度匹配 |
| variant_id 映射 Prefab | 通过配置表关联不同外观 |

### 7.3 配置 ↔ 业务

| 配置表 | 用途 | 修改方式 |
|--------|------|---------|
| CfgInitMonster | 动物基础属性（速度/视距等） | 扩展现有表，添加 4 条动物记录 |
| CfgMonsterPrefab | 动物模型路径 | 添加 4 条记录 |
| CfgMonsterAnimation | 动画配置 | 添加 4 条记录 |
| CfgAudioAnimal | 音效配置 | 已有表结构，填充数据 |
| MonsterType 枚举 | 已有 Bird=47/Dog=48 | 新增 Crocodile/Chicken 枚举值 |

## 8. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| NpcDataUpdate 字段号冲突 | 协议不兼容 | 已确认最大 37，用 38 |
| 动物 Prefab 缺失 | 客户端无法渲染 | 模型资源已确认存在 |
| 正交管线 Animal 分支影响现有 NPC | 人形 NPC 行为异常 | ExtType 互斥分发，互不影响 |
| Bird 飞行 Y 坐标与海洋冲突 | 鸟飞入水面 | flightMinAlt=5m，海洋 Y=50（参考 memory），生成区域避开海面 |

## 9. 验收测试方案

### TC-001: 动物生成验证

**前置条件**：服务器已启动，客户端已登录大世界场景
**操作步骤**：
1. [MCP: script-execute] 查询场景中 AnimalController 实例数量
2. [MCP: screenshot-game-view] 截取游戏画面，确认动物可见
3. [MCP: script-execute] 遍历 AnimalController 实例，验证 EntityType、AnimalType、FSM 状态
**预期结果**：场景中存在至少 1 只动物实体，EntityType=Animal，FSM 处于 Idle 状态

### TC-002: Dog 待机/行走/奔跑动画

**前置条件**：场景中有 Dog 实体
**操作步骤**：
1. [MCP: script-execute] 获取最近 Dog 实体的 FSM 当前状态和动画 Clip 名
2. [MCP: screenshot-game-view] 截图验证 Dog 动画播放
3. [MCP: script-execute] 等待状态切换（Idle→Walk），再次验证动画 Clip
**预期结果**：Idle 时播放 idle/specialidle，Walk 时播放 walk，Run 时播放 run

### TC-003: Bird 飞行循环

**前置条件**：场景中有 Bird 实体
**操作步骤**：
1. [MCP: script-execute] 获取 Bird 实体 FSM 状态和 Y 坐标
2. [MCP: screenshot-game-view] 截图验证 Bird 在空中飞行
3. [MCP: script-execute] 多帧采样验证 Bird 位置变化（fly 时移动，idle 时悬停）
**预期结果**：Bird Y 坐标在 flightMinAlt~flightCeiling 范围，fly↔idle 循环正常

### TC-004: Dog 喂食交互

**前置条件**：玩家背包有食物，场景中有 Dog
**操作步骤**：
1. [MCP: script-execute] 移动玩家到 Dog 附近（< 3m）
2. [MCP: screenshot-game-view] 验证交互提示 UI 显示
3. [MCP: script-execute] 触发喂食交互
4. [MCP: script-execute] 验证 Dog FSM 切换到 Follow 状态，follow_target_id = 玩家 ID
5. [MCP: script-execute] 等待 30s，验证 Dog 回归 Idle
**预期结果**：喂食后 Dog 跟随玩家 30s，到期自动回归

### TC-005: 同屏限制验证

**前置条件**：场景配置动物数量超过上限
**操作步骤**：
1. [MCP: script-execute] 统计当前场景中各类动物实体数量
2. [验证] 陆地动物 ≤ 12，鸟类 ≤ 20
**预期结果**：同屏数量不超过配置上限

### TC-006: LOD 切换验证

**前置条件**：场景中有可见动物
**操作步骤**：
1. [MCP: script-execute] 获取动物距离和当前 LOD 级别
2. [MCP: script-execute] 移动玩家远离动物，验证 LOD 切换
3. [MCP: screenshot-game-view] 截图验证远距离动物渲染降级
**预期结果**：< 50m Full LOD，50-150m Medium，> 150m 剔除

### TC-007: 异常场景

**场景 1**：重复喂食同一只 Dog
- 第二次喂食返回错误码 14004（AnimalNotFeedable）

**场景 2**：距离超过 3m 喂食
- 返回错误码 14002（AnimalTooFar）

**场景 3**：喂食非 Dog 动物
- 返回错误码 14004（AnimalNotFeedable）
