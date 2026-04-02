# NPC 日程与巡逻系统——客户端需求文档

> 版本：v1.0 | 日期：2026-03-13 | 状态：草稿
> 参考：GTA5 `req-ped-schedule-patrol.md`

## 目录

1. [背景与目标](#1-背景与目标)
2. [系统全景](#2-系统全景)
3. [日程状态表现](#3-日程状态表现)
4. [巡逻表现](#4-巡逻表现)
5. [场景点交互](#5-场景点交互)
6. [动画与条件动画](#6-动画与条件动画)
7. [与现有组件集成](#7-与现有组件集成)
8. [关键约束](#8-关键约束)
9. [术语表](#9-术语表)

---

## 1 背景与目标

### 1.1 背景

NPC 日程与巡逻系统由服务端驱动，客户端负责**纯表现层**：接收服务端状态同步，驱动 FSM 切换、动画播放、移动插值等视觉表现。客户端不做任何决策计算。

### 1.2 目标

1. **日程状态表现**：NPC 按服务端日程指令平滑切换行为动画
2. **巡逻表现**：沿路线移动、节点停留动画、警惕状态视觉差异
3. **场景点交互**：NPC 在场景点执行交互动画（坐下、打电话等）
4. **条件动画**：同一场景点在不同天气/时间下呈现不同动画

### 1.3 设计原则

- **纯表现层**：客户端不做 AI 决策，只同步和展示
- **复用现有架构**：基于 TownNpcFsmComp + AnimationComp 扩展
- **平滑过渡**：状态切换使用过渡动画，不硬切

## 2 系统全景

### 2.1 客户端职责边界

```
┌─ 服务端 ──────────────────────────────┐
│ PopSchedule → DaySchedule/Patrol      │
│ → V2 管线 → NpcState → Proto 同步     │
└───────────────────┬───────────────────┘
                    │ NpcState 枚举 + TownNpcData 字段
                    ▼
┌─ 客户端 ──────────────────────────────┐
│ Proto 接收 → StateData 更新           │
│ → FsmComp 状态切换 → 动画/移动表现    │
└───────────────────────────────────────┘
```

### 2.2 数据流

```
MoveStateProto.State（NpcState 枚举值）
    │
    ▼
TownNpcStateData.Notify(StateIdUpdate, StateId - 1)
    │
    ▼
TownNpcFsmComp.ChangeStateById(index)
    │
    ▼
对应 FSM State 的 OnEnter → 播放动画 + 设置移动参数
```

## 3 日程状态表现

### 3.1 新增 FSM 状态

基于现有 13 个 TownNpcState，日程系统需扩展：

| 新增状态 | NpcState 枚举 | 说明 |
|---------|--------------|------|
| TownNpcPatrolState | Patrol(17) | 巡逻移动 |
| TownNpcGuardState | Guard(18) | 站岗警戒 |
| TownNpcScenarioState | Scenario(19) | 场景点行为 |
| TownNpcScheduleIdleState | ScheduleIdle(20) | 日程空闲（等待下一日程） |

> 枚举值与 `protocol.md` 3.1 节一致。

**进出建筑处理**：EnterBuilding / ExitBuilding 为瞬时过渡动作，不新增 FSM 状态。通过 `NpcScheduleChangeNtf` 的 `new_behavior` 字段传递，客户端在当前状态中播放渐隐/渐显过渡动画：
- **进入**：收到 Ntf → 当前状态播放走向门口动画 → 渐隐（材质透明度或 Dissolve） → Despawn
- **离开**：Spawn → 渐显 → 收到 Ntf → 过渡到正常日程状态

### 3.2 日程切换表现

| 切换场景 | 客户端表现 |
|---------|-----------|
| Idle → MoveTo | 从站立过渡到行走动画 |
| MoveTo → Work | 到达位置后切换工作动画 |
| Work → Rest | 过渡到休息动画 |
| Ntf: EnterBuilding | 走向门口 → 播放开门动画 → 渐隐 → Despawn |
| Ntf: ExitBuilding | Spawn → 渐显 → 播放关门动画 → 过渡到下一行为 |
| 日程中断 → 战斗/逃跑 | 立即切换到对应情绪/战斗状态 |
| 事件结束 → 日程恢复 | 平滑过渡回日程行为 |

### 3.3 关键需求

| 编号 | 需求描述 | 优先级 |
|------|---------|--------|
| FR-CLI-SCH-01 | 日程状态切换使用过渡动画，不硬切 | P0 |
| FR-CLI-SCH-02 | 进出建筑使用渐隐/渐显效果（材质透明度或 Dissolve），时长通过配置表定义 | P1 |
| FR-CLI-SCH-03 | 日程中断时优先播放中断反应动画再切换 | P1 |

## 4 巡逻表现

### 4.1 巡逻移动表现

| 状态 | 动画/表现 |
|------|----------|
| 巡逻行走（Casual） | 正常步速行走动画，自然摆臂 |
| 巡逻行走（Alert） | 加速行走，手持武器/警棍姿态 |
| 节点停留 | 停下 → 环顾四周 → 执行节点行为动画 |
| 方向转换 | 到达路线端点时平滑转身 |

### 4.2 警惕等级视觉差异

| 等级 | 移动速度 | 头部动作 | 姿态 |
|------|---------|---------|------|
| Casual | 正常步速 | 自然环顾 | 放松 |
| Alert | 快步 | LookAt 追踪目标 | 警戒姿态 |

### 4.3 关键需求

| 编号 | 需求描述 | 优先级 |
|------|---------|--------|
| FR-CLI-PAT-01 | 巡逻移动使用路径插值，不瞬移 | P0 |
| FR-CLI-PAT-02 | 节点停留时播放配置的动画 | P0 |
| FR-CLI-PAT-03 | Alert 状态下启用 LookAt 组件追踪目标 | P1 |
| FR-CLI-PAT-04 | 路线端点转身使用平滑旋转 | P0 |

## 5 场景点交互

### 5.1 场景点动画流程

```
[服务端同步 NpcState = Scenario + ScenarioPointId]
         │
         ▼
    FsmComp → TownNpcScenarioState.OnEnter()
         │
         ▼
    查询场景点类型 → 获取对应动画配置
         │
         ▼
    移动到场景点位置（插值）+ 调整朝向
         │
         ▼
    播放交互动画（坐下/打电话/站岗...）
         │
         ▼
    [服务端通知离开] → 播放离开动画 → 切换状态
```

### 5.2 场景类型与动画映射

| 场景类型 | 进入动画 | 循环动画 | 离开动画 |
|---------|---------|---------|---------|
| Bench | 坐下 | 坐着/看报/玩手机 | 站起 |
| LeanWall | 靠上去 | 靠墙站/抽烟 | 离开墙壁 |
| Phone | 掏手机 | 打电话 | 收起手机 |
| Exercise | 准备动作 | 运动循环 | 结束动作 |
| Guard | 立正 | 站岗警戒 | 稍息 |

> 动画映射通过配置表定义，不硬编码

### 5.3 关键需求

| 编号 | 需求描述 | 优先级 |
|------|---------|--------|
| FR-CLI-SCN-01 | 场景点交互有进入/循环/离开三段动画 | P0 |
| FR-CLI-SCN-02 | NPC 到达场景点后精确对齐位置和朝向 | P0 |
| FR-CLI-SCN-03 | 动画映射通过配置表驱动 | P0 |

## 6 动画与条件动画

### 6.1 条件动画系统

同一场景类型在不同条件下播放不同动画变体：

| 条件维度 | 示例效果 |
|---------|---------|
| 天气 | 下雨时 Bench 动画 → 撑伞坐 |
| 时间 | 夜晚时 LeanWall → 裹外套 |
| NPC 类型 | 老人用慢速版动画 |

### 6.2 条件评估时机

- **进入场景点时**评估一次，确定动画变体
- **天气/时间切换事件**触发重新评估（播放过渡动画后切换）
- 不在每帧重新评估（性能）

### 6.3 关键需求

| 编号 | 需求描述 | 优先级 |
|------|---------|--------|
| FR-CLI-ANI-01 | 条件动画在进入场景点时评估确定 | P1 |
| FR-CLI-ANI-02 | 天气/时间变化触发动画切换，使用过渡而非硬切 | P2 |
| FR-CLI-ANI-03 | 条件→动画映射通过配置表定义 | P1 |

## 7 与现有组件集成

### 7.1 组件关系

| 现有组件 | 集成方式 |
|---------|---------|
| TownNpcFsmComp | 注册新增 FSM 状态（Patrol/Guard/Scenario 等） |
| AnimationComp | 调用 `Play(TransitionKey)` + `SetSpeed/SetParameter` |
| TownNpcMoveComp | 复用移动插值逻辑 |
| TownNpcStateData | 接收新增 NpcState 枚举的 Notify |

### 7.2 新增组件

| 组件 | 说明 | 异步操作 |
|------|------|---------|
| TownNpcScenarioComp | 管理场景点交互状态（当前场景点 ID、动画阶段） | 涉及移动插值+动画等待序列，需 CancellationToken，OnClear 中 Cancel |
| TownNpcPatrolVisualComp | 管理巡逻视觉效果（警惕姿态、LookAt 目标） | 无异步操作 |

> 新 Comp 必须在 Controller.OnInit 中 AddComp

### 7.3 旧巡逻兼容性

NpcWeakStateCommand 中的 `patrol_*` 字段已标记为 deprecated。新 Patrol 状态下客户端忽略 WeakStateCommand 的巡逻字段，仅从 TownNpcData.patrol_data（NpcPatrolData 子消息）读取巡逻信息。

### 7.3 日志规范

- 使用 `MLog.Info?.Log(LogModule.TownNpc + ...)` 格式
- 禁用 `Debug.Log`

## 8 关键约束

| 约束 | 说明 |
|------|------|
| 纯表现层 | 客户端不做 AI 决策，只同步和展示 |
| FSM 索引 | 服务端 NpcState 枚举值 - 1 = _stateTypes 数组索引 |
| 异步安全 | async UniTaskVoid 方法必须带 CancellationToken，OnClear 中 Cancel |
| 动画控制 | 通过 AnimationComp.Play(ConfigEnum.TransitionKey.xxx) |
| 帧率无关 | 移动插值使用 deltaTime，不依赖固定帧率 |

## 9 术语表

| 术语 | 说明 |
|------|------|
| FsmComp | 有限状态机组件，管理 NPC 行为状态切换 |
| AnimationComp | 动画组件，控制动画播放和过渡 |
| ScenarioPoint | 场景活动节点（长椅/摊位等） |
| TransitionKey | 动画过渡键，配置表中定义的动画 ID |
| LookAt | 头部注视追踪组件 |
| StateData | NPC 状态数据容器，接收 Proto 同步 |
