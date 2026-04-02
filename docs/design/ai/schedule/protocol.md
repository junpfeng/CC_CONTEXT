# NPC 日程与巡逻系统——协议需求文档

> 版本：v1.0 | 日期：2026-03-13 | 状态：草稿
> 参考：GTA5 `req-ped-schedule-patrol.md`

## 目录

1. [背景与目标](#1-背景与目标)
2. [现有协议基线](#2-现有协议基线)
3. [日程相关消息](#3-日程相关消息)
4. [巡逻相关消息](#4-巡逻相关消息)
5. [场景点相关消息](#5-场景点相关消息)
6. [枚举与常量扩展](#6-枚举与常量扩展)
7. [兼容性与版本策略](#7-兼容性与版本策略)
8. [术语表](#8-术语表)

---

## 1 背景与目标

NPC 日程与巡逻系统需要在服务端和客户端之间同步以下信息：
- NPC 当前行为状态（日程/巡逻/场景点）
- 巡逻和场景点的视觉表现参数
- 日程切换和中断事件通知

本文档定义所需的协议扩展，基于现有 `npc.proto` 扩展。

## 2 现有协议基线

### 2.1 NpcState 枚举（现有 17 值）

**文件**：`old_proto/scene/npc.proto`

```
None(0) / Stand(1) / Ground(2) / Drive(3) / Interact(4) / Death(5) /
Shelter(6) / Shiver(7) / Combat(8) / Flee(9) / Watch(10) / Investigate(11) /
Scared(12) / Panicked(13) / Curious(14) / Nervous(15) / Angry(16)
```

### 2.2 TownNpcData（现有 16 字段）

配置、交易、战斗、反应、情绪相关字段。

### 2.3 NpcWeakStateCommand（现有巡逻字段）

已有弱状态巡逻信息：`patrol_lane_id` / `patrol_start_pos` / `patrol_enter_point_id` / `patrol_clockwise` / `patrol_speed` / `patrol_start_time` / `patrol_current_time`

> **废弃策略**：NpcWeakStateCommand 中的 `patrol_*` 字段标记为 **deprecated**。新日程/巡逻系统完全通过 TownNpcData 扩展字段 + Ntf 消息同步。过渡期间（旧客户端兼容期），服务端同时写入两套字段；新客户端忽略 WeakStateCommand 中的巡逻字段，仅读取 TownNpcData。过渡期结束后停止写入旧字段。

## 3 日程相关消息

### 3.1 NpcState 枚举扩展

| 新增值 | 名称 | 说明 |
|--------|------|------|
| 17 | Patrol | 巡逻移动 |
| 18 | Guard | 站岗警戒 |
| 19 | Scenario | 场景点行为 |
| 20 | ScheduleIdle | 日程空闲 |

> EnterBuilding / ExitBuilding 为瞬时过渡动作，不作为持久 NpcState 枚举。通过 NpcScheduleChangeNtf 的 `new_behavior` 字段（ScheduleBehaviorType.EnterBuilding=6 / ExitBuilding=7）传递，客户端收到后播放过渡动画。

### 3.2 TownNpcData 扩展（子消息方式）

为避免字段膨胀，日程/巡逻/场景点分别定义子消息：

| 字段号 | 名称 | 类型 | 说明 |
|--------|------|------|------|
| 17 | schedule_data | NpcScheduleData | 日程数据（无日程时不携带） |
| 18 | patrol_data | NpcPatrolData | 巡逻数据（无巡逻时不携带） |
| 19 | scenario_data | NpcScenarioData | 场景点数据（无场景交互时不携带） |

#### NpcScheduleData 子消息

| 字段 | 类型 | 说明 |
|------|------|------|
| template_id | int32 | 日程模板 ID |
| entry_index | int32 | 当前日程条目索引 |
| behavior | int32 | 当前行为类型（ScheduleBehaviorType） |

### 3.3 NpcScheduleChangeNtf — 日程切换通知

当 NPC 日程条目切换时，服务端推送：

| 字段 | 类型 | 说明 |
|------|------|------|
| npc_id | int64 | NPC 实例 ID |
| prev_behavior | int32 | 前一个行为类型（ScheduleBehaviorType） |
| new_behavior | int32 | 新行为类型（ScheduleBehaviorType） |
| target_pos | Vec3 | 新目标位置 |
| change_reason | int32 | 切换原因（ScheduleChangeReason 枚举） |

**ScheduleChangeReason 枚举**：

| 值 | 名称 | 说明 |
|----|------|------|
| 0 | Normal | 正常日程切换（时间触发） |
| 1 | Interrupted | 被高优先级事件中断 |
| 2 | Resumed | 中断结束，恢复日程 |
| 3 | ScriptOverride | 脚本覆盖 |

> 用途：客户端根据前后行为类型 + 切换原因选择过渡动画（恢复时可用柔和过渡）

## 4 巡逻相关消息

### 4.1 NpcPatrolData 子消息

| 字段 | 类型 | 说明 |
|------|------|------|
| route_id | int32 | 当前巡逻路线 ID |
| node_id | int32 | 当前目标节点 ID |
| alert_level | int32 | 警惕等级（PatrolAlertLevel） |
| look_at_pos | Vec3 | Alert 时的注视目标位置 |

### 4.2 NpcPatrolNodeArriveNtf — 到达巡逻节点通知

| 字段 | 类型 | 说明 |
|------|------|------|
| npc_id | int64 | NPC 实例 ID |
| node_id | int32 | 到达的节点 ID |
| behavior_type | int32 | 节点停留行为类型（配置表动画枚举 ID） |
| duration_ms | int32 | 停留时长（毫秒） |

> 用途：客户端在 NPC 到达节点时播放对应停留动画

### 4.3 NpcPatrolAlertChangeNtf — 警惕等级变更通知

| 字段 | 类型 | 说明 |
|------|------|------|
| npc_id | int64 | NPC 实例 ID |
| alert_level | int32 | 新警惕等级 |
| look_at_pos | Vec3 | 注视目标位置（alert 时有效） |

## 5 场景点相关消息

### 5.1 NpcScenarioData 子消息

| 字段 | 类型 | 说明 |
|------|------|------|
| point_id | int32 | 当前占用的场景点 ID |
| scenario_type | int32 | 场景类型 |
| phase | int32 | 动画阶段（ScenarioPhase） |
| direction | float | 朝向（弧度） |
| duration | int32 | 停留时长（秒，客户端用于表现计时） |

### 5.2 NpcScenarioEnterNtf — 进入场景点通知

| 字段 | 类型 | 说明 |
|------|------|------|
| npc_id | int64 | NPC 实例 ID |
| point_id | int32 | 场景点 ID |
| scenario_type | int32 | 场景类型 |
| position | Vec3 | 场景点位置 |
| direction | float | 场景点朝向 |

### 5.3 NpcScenarioLeaveNtf — 离开场景点通知

| 字段 | 类型 | 说明 |
|------|------|------|
| npc_id | int64 | NPC 实例 ID |
| point_id | int32 | 场景点 ID |

## 6 枚举与常量扩展

### 6.1 ScheduleBehaviorType 枚举（新增）

| 值 | 名称 | 说明 |
|----|------|------|
| 0 | Idle | 原地停留 |
| 1 | MoveTo | 移动到目标 |
| 2 | Work | 工作 |
| 3 | Rest | 休息 |
| 4 | Patrol | 巡逻 |
| 5 | UseScenario | 使用场景点 |
| 6 | EnterBuilding | 进入建筑 |
| 7 | ExitBuilding | 离开建筑 |

### 6.2 ScenarioPhase 枚举（新增）

| 值 | 名称 | 说明 |
|----|------|------|
| 0 | Enter | 进入动画 |
| 1 | Loop | 循环动画 |
| 2 | Leave | 离开动画 |

### 6.3 ScheduleChangeReason 枚举（新增）

| 值 | 名称 | 说明 |
|----|------|------|
| 0 | Normal | 正常日程切换 |
| 1 | Interrupted | 被高优先级事件中断 |
| 2 | Resumed | 中断结束，恢复日程 |
| 3 | ScriptOverride | 脚本覆盖 |

### 6.4 PatrolAlertLevel 枚举（新增）

| 值 | 名称 | 说明 |
|----|------|------|
| 0 | Casual | 正常状态 |
| 1 | Alert | 警戒状态 |

### 5.4 进出建筑的可见性处理

NPC 进入建筑后从场景消失，采用 **Despawn** 方式（非新增可见性字段）：
- **进入**：客户端收到 `NpcScheduleChangeNtf(new_behavior=EnterBuilding)` → 播放走向门口 + 渐隐动画 → 服务端 Despawn NPC
- **离开**：服务端在门口 Spawn NPC → 客户端收到 `NpcScheduleChangeNtf(new_behavior=ExitBuilding)` → 渐显 + 走出动画

> 复用现有 Spawn/Despawn 机制，无需新增可见性协议字段。

## 7 兼容性与版本策略

### 7.1 向后兼容

- NpcState 枚举新增值（17-22）不影响旧客户端（未知值 fallback 到 Idle）
- TownNpcData 新增字段（17-26）使用高字段号，旧客户端自动忽略
- 新增 Ntf 消息旧客户端不处理，不影响核心功能

### 7.2 版本要求

- 日程/巡逻完整功能需要客户端和服务端同时更新
- 最低兼容：旧客户端看到日程 NPC 表现为普通移动（fallback 到 Move 状态）

### 7.3 协议编辑流程

1. 编辑 `old_proto/scene/npc.proto`
2. 运行 `old_proto/_tool_new/1.generate.py`
3. 代码自动写入服务端和客户端目录

## 8 术语表

| 术语 | 说明 |
|------|------|
| NpcState | NPC 行为状态枚举，服务端→客户端同步 |
| TownNpcData | NPC 附加数据消息，携带行为参数 |
| Ntf | 通知消息（Notification），服务端→客户端单向推送 |
| NpcWeakStateCommand | 弱状态命令（现有巡逻机制） |
| Vec3 | 三维向量消息（x, y, z） |
| ScenarioPhase | 场景点动画阶段（进入/循环/离开） |
