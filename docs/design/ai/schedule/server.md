# NPC 日程与巡逻系统——服务器需求文档

> 版本：v1.0 | 日期：2026-03-13 | 状态：草稿
> 参考：GTA5 `req-ped-schedule-patrol.md`

## 目录

1. [背景与目标](#1-背景与目标)
2. [系统全景](#2-系统全景)
3. [人口调度（PopSchedule）](#3-人口调度popschedule)
4. [日程系统（DaySchedule）](#4-日程系统dayschedule)
5. [巡逻系统（Patrol）](#5-巡逻系统patrol)
6. [场景点系统（ScenarioPoint）](#6-场景点系统scenariopoint)
7. [与正交管线集成](#7-与正交管线集成)
8. [配置驱动](#8-配置驱动)
9. [关键约束与边界](#9-关键约束与边界)
10. [术语表](#10-术语表)

---

## 1 背景与目标

### 1.1 背景

《五星好市民》城镇场景中，路人 NPC 需要根据游戏内时间、地点、天气等条件做出真实可信的日常行为，营造"活着的城市"氛围。当前 V2 正交管线已支持 4 维度决策执行（Engagement / Expression / Locomotion / Navigation），但缺少**宏观调度**和**结构化日程**能力：

| 缺口 | 说明 |
|------|------|
| 人口调度 | 无法按时段动态调整 NPC 数量和类型分布 |
| 日程驱动 | NPC 缺少"几点去哪做什么"的时间表行为 |
| 巡逻路线 | 警卫/保安等角色无法沿预设路线巡逻 |
| 场景点 | 城市缺少"长椅/摊位/电话亭"等活动节点 |

### 1.2 目标

参考 GTA5 三层架构（PopCycle → 巡逻/场景 → 智能决策），在 V2 管线基础上实现：

1. **人口调度**：按时段控制 NPC 类型和数量（先实现基础版，预留扩展）
2. **日程系统**：NPC 按配置时间表执行日常行为序列
3. **巡逻系统**：支持预设路线的循环巡逻
4. **场景点系统**：城市活动节点，NPC 自主占用执行动画

### 1.3 设计原则

- **V2 独立**：完全基于 V2 正交管线，不依赖 V1 日程行为树（V1 仅供参考）
- **先基础后扩展**：优先实现常用核心功能，架构预留扩展点
- **数据驱动**：所有行为参数通过配置文件/配置表定义，不硬编码
- **服务端权威**：所有调度和决策在服务端完成，客户端只做表现

## 2 系统全景

### 2.1 三层架构

```
┌─────────────────────────────────────────────────────────┐
│                    人口调度层（PopSchedule）                │
│   按时段/区域控制 NPC 数量上限和类型分布                      │
│   时间表配置 → 实时配额 → Spawn/Despawn 门控                │
└───────────────────────┬─────────────────────────────────┘
                        │ 生成 NPC 实例 + 分配初始行为
          ┌─────────────┼──────────────┐
          ▼             ▼              ▼
    DaySchedule     Patrol        ScenarioPoint
    (日程时间表)    (路线巡逻)     (场景点行为)
          └─────────────┼──────────────┘
                        │ 写入 NpcState，驱动管线
             ┌──────────▼──────────┐
             │   V2 正交管线        │
             │   Engagement        │
             │   Expression        │  ← 情绪系统响应事件
             │   Locomotion        │  ← 日程/巡逻驱动移动
             │   Navigation        │  ← 场景点导航
             └─────────────────────┘
```

### 2.2 NPC 生命周期（日程视角）

```
[PopSchedule 配额有空位 & 玩家进入激活半径]
         │
         ▼
    Spawn（按时段选择 NPC 类型和模型）
         │
         ▼
    分配初始行为（DaySchedule / Patrol / ScenarioPoint）
         │
         ▼
    执行循环（V2 管线每帧 Tick）
      ┌───┴────┐
      │        │
  正常日程   事件中断（情绪/战斗/逃跑）
      │        │
      └───┬────┘
         │
         ▼
    [超出配额 or 玩家远离 or 日程结束]
         │
         ▼
    Despawn（释放场景点占用、清理状态）
```

### 2.3 寻路依赖

日程/巡逻/场景点的移动均依赖已有的三层寻路系统：

| 层 | 系统 | 用途 |
|----|------|------|
| 路网 | RoadNetwork A*（`footwalk`/`driveway` 有向图） | 长距离路径规划，返回路点 ID 序列 |
| 体素 | Voxel Pathfinding（三级体素树 A*） | 建筑表面移动 |
| NavMesh | C/C++ NavMesh 桥接 | 精细碰撞避障 |

- 日程 MoveTo / 巡逻节点间 / 场景点移动 → 写入 MoveTarget → Navigation 维度的 NavigateBtHandler → 调用路网 A* 寻路 → 逐路点移动 → 到达检测（平方距离 < 4.0，超时 15s 保护）
- 路网配置：`freelifeclient/RawTables/Json/Server/road_traffic_fl.json`（节点 + 边 + 权重）

### 2.4 与现有系统关系

| 现有系统 | 关系 | 说明 |
|---------|------|------|
| V2 正交管线 | **宿主** | 日程/巡逻作为 Navigation/Locomotion 维度的 Handler |
| V2Brain 决策 | **并行** | Brain 负责反应性决策，日程负责计划性行为 |
| 情绪系统 | **中断源** | 高情绪值可中断日程，日程恢复后续行 |
| MoveTarget 仲裁 | **复用** | 日程通过 MoveSourceSchedule 写入移动目标 |
| NpcState | **存储** | 日程/巡逻状态存入 NpcState.ScheduleState |

## 3 人口调度（PopSchedule）

### 3.1 业务目标

根据游戏内时间节律，动态调整城镇各区域的 NPC 数量和类型分布，使城市呈现早高峰热闹、深夜冷清的生活感。

### 3.2 时间分割

| 参数 | 基础版 | 扩展预留 |
|------|--------|---------|
| 每天时段数 | **6 段**（每段约 4 小时游戏时间） | 可扩展至 12 段 |
| 周期区分 | 不区分工作日/周末 | 预留周期维度 |
| 时段划分 | 凌晨/早晨/上午/下午/傍晚/夜晚 | 可配置 |

**基础版 6 段划分**：

| 段号 | 游戏时间 | 标签 | 典型人口特征 |
|------|---------|------|-------------|
| 0 | 00:00-04:00 | 凌晨 | 极少 NPC，夜间巡逻警卫 |
| 1 | 04:00-08:00 | 早晨 | 逐渐增加，晨练/上班族 |
| 2 | 08:00-12:00 | 上午 | 正常密度，店铺/办公 |
| 3 | 12:00-16:00 | 下午 | 高密度，午休/商业 |
| 4 | 16:00-20:00 | 傍晚 | 高密度，下班/休闲 |
| 5 | 20:00-24:00 | 夜晚 | 减少，夜生活/巡逻 |

### 3.3 人口配额（PopAllocation）

每个时段×区域对应一份配额配置：

| 字段 | 类型 | 说明 |
|------|------|------|
| MaxAmbientNpc | int | 环境漫游 NPC 上限 |
| MaxScheduleNpc | int | 日程 NPC 上限 |
| MaxPatrolNpc | int | 巡逻 NPC 上限 |
| MaxScenarioNpc | int | 场景点 NPC 上限 |
| NpcGroupWeights | map[string]int | 各 NPC 类型组的权重比例 |

### 3.4 NPC 类型组

| 类型 | 说明 | 典型行为 |
|------|------|---------|
| Ambient | 环境漫游 | 自由行走，无固定目标 |
| Schedule | 日程驱动 | 按时间表在地点间移动 |
| Patrol | 巡逻 | 沿路线循环巡逻 |
| Scenario | 场景绑定 | 在场景点执行特定动画 |
| Guard | 守卫 | 固定位置站岗 |

### 3.5 区域定义

人口配额按区域差异化。区域为场景的逻辑划分：

| 字段 | 类型 | 说明 |
|------|------|------|
| RegionId | int32 | 区域 ID |
| RegionName | string | 区域名称（调试用） |
| Center | Vec3 | 中心坐标 |
| Radius | float | 激活半径（玩家在此范围内才激活该区域 NPC） |

> 基础版使用圆形区域。扩展预留多边形/AABB 区域类型。
> 区域配置通过配置表定义，与场景地图编辑器关联。

### 3.6 Spawn/Despawn 规则

- **Spawn 条件**：配额有空位 AND 玩家在激活半径内 AND 当前时段允许该类型
- **Despawn 条件**：超出配额 OR 玩家远离 OR NPC 日程结束且无后续
- **渐变过渡**：时段切换时 NPC 数量平滑过渡，不跳变（每 Tick 最多增减 1-2 个）

### 3.7 关键需求

| 编号 | 需求描述 | 优先级 |
|------|---------|--------|
| FR-POP-01 | 每个游戏时间 Tick 评估当前时段，更新配额 | P0 |
| FR-POP-02 | 时段切换时 NPC 数量渐变过渡 | P0 |
| FR-POP-03 | 配额配置通过配置表定义，支持按区域差异化 | P0 |
| FR-POP-04 | 脚本可临时覆盖某区域配额（如剧情清街），结束后自动恢复 | P1 |
| FR-POP-05 | NPC 类型组权重影响 Spawn 时的类型选择概率 | P0 |

## 4 日程系统（DaySchedule）

### 4.1 业务目标

NPC 按配置的每日时间表执行行为序列：几点去哪里、做什么、待多久。使 NPC 呈现"早上去店铺上班、中午吃饭、下午继续工作、傍晚回家"等生活模式。

### 4.2 日程条目（ScheduleEntry）

每个 NPC 类型关联一份日程模板，由多个时段条目组成：

| 字段 | 类型 | 说明 |
|------|------|------|
| StartTime | int | 开始时间（游戏内小时，0-23） |
| EndTime | int | 结束时间（游戏内小时，0-23） |
| LocationId | int | 目标地点 ID（关联场景点或坐标） |
| BehaviorType | enum | 行为类型（见下表） |
| Priority | int | 优先级（高优先级条目覆盖低优先级） |
| Probability | float | 执行概率（0.0-1.0，支持随机化） |

### 4.3 日程行为类型

| 枚举 | 说明 | 典型表现 |
|------|------|---------|
| Idle | 原地停留 | 站立/坐下/闲聊 |
| MoveTo | 移动到目标点 | 步行至目标位置 |
| Work | 在工作点工作 | 绑定场景点动画 |
| Rest | 休息 | 坐/靠/打盹 |
| Patrol | 执行巡逻路线 | 切换到巡逻系统 |
| UseScenario | 使用场景点 | 占用并执行场景点行为 |
| EnterBuilding | 进入建筑 | 走向门口 → Despawn（模拟进入） |
| ExitBuilding | 离开建筑 | 在门口 Spawn → 走出 |

### 4.4 日程执行流程

```
[每帧 Tick]
     │
     ▼
检查当前游戏时间 → 匹配日程条目
     │
     ├─ 无匹配 → 保持当前行为（Idle fallback）
     │
     └─ 有匹配 → 与当前行为比较
              │
              ├─ 相同 → 继续执行
              │
              └─ 不同 → 切换行为
                       │
                       ├─ 计算目标位置
                       ├─ 写入 NpcState.ScheduleState
                       └─ 通过 MoveSourceSchedule 驱动移动
```

### 4.5 跨日时间段处理

当 `StartTime > EndTime`（如 `20:00 → 08:00`），表示跨越午夜：
- 匹配规则：`currentHour >= StartTime OR currentHour < EndTime`
- 示例：StartTime=20, EndTime=8 → 20:00~23:59 和 00:00~07:59 均匹配
- 日程条目按 StartTime 升序排列，跨日条目排在最后

### 4.6 日程中断与恢复

| 中断源 | 中断行为 | 恢复策略 |
|--------|---------|---------|
| 战斗（Engagement） | 立即中断，进入战斗 | 战斗结束后恢复当前日程条目 |
| 情绪（Expression） | 高情绪时中断 | 情绪衰减后恢复 |
| 脚本覆盖 | 脚本强制行为 | 脚本释放后恢复 |
| 玩家交互 | 暂停日程 | 交互结束后恢复 |

恢复时：若当前日程条目已过期，跳转到下一个有效条目。

### 4.7 关键需求

| 编号 | 需求描述 | 优先级 |
|------|---------|--------|
| FR-SCH-01 | NPC 按配置时间表自动切换行为，无需脚本逐帧驱动 | P0 |
| FR-SCH-02 | 日程条目支持概率触发，同一类型 NPC 行为有差异化 | P1 |
| FR-SCH-03 | 日程被高优先级事件中断后，事件结束可恢复执行 | P0 |
| FR-SCH-04 | 支持 EnterBuilding/ExitBuilding 模拟进出建筑 | P1 |
| FR-SCH-05 | 日程模板通过配置表定义，同类型 NPC 共享模板 | P0 |
| FR-SCH-06 | 日程切换时平滑过渡（先移动到新位置再切换行为） | P0 |

## 5 巡逻系统（Patrol）

### 5.1 业务目标

警卫、保安、帮派哨兵等 NPC 沿预设路线反复巡逻，在节点停留、播放动画，呈现"值班感"。支持脚本动态创建临时路线。

### 5.2 路线数据结构

#### PatrolRoute — 巡逻路线

| 字段 | 类型 | 说明 |
|------|------|------|
| RouteId | int32 | 路线唯一 ID |
| RouteName | string | 路线名称（调试用） |
| RouteType | enum | 路线类型：Permanent（永久）/ Scripted（临时） |
| Nodes | []PatrolNode | 节点列表（有序） |
| DesiredNpcCount | int32 | 期望 NPC 数量 |
| CurrentNpcCount | int32 | 当前占用 NPC 数（运行时） |

#### PatrolNode — 巡逻节点

| 字段 | 类型 | 说明 |
|------|------|------|
| NodeId | int32 | 节点 ID（路线内唯一） |
| Position | Vec3 | 世界坐标 |
| Heading | float | 朝向角度 |
| Duration | int32 | 停留时长（毫秒，0=不停留） |
| BehaviorType | string | 停留行为类型（动画哈希） |
| Links | []int32 | 可达后继节点 ID 列表（支持分叉） |

#### 路线拓扑

- **闭环路线**：最后节点链回第一节点，NPC 循环巡逻
- **开放路线**：到端点后反向遍历
- **分叉路线**：节点有多个 Link 时随机选择（或按权重）

### 5.3 巡逻状态机

| 状态 | 说明 |
|------|------|
| Start | 初始化，查找最近起始节点 |
| MoveToNode | 移动至目标节点 |
| StandAtNode | 到达节点，执行停留行为 |
| PlayBehavior | 播放节点配置的动画/行为 |
| SelectNext | 选择下一节点（方向偏好 + 分叉权重） |

**状态转移**：
```
Start → MoveToNode → StandAtNode → [PlayBehavior →] SelectNext → MoveToNode
                                                                      ↑
                                                    (循环) ───────────┘
```

**节点间移动**：节点坐标不是直线移动目标，而是通过**路网 A* 寻路**（`RoadNetworkManager`）计算节点间路径，沿路点序列逐点移动。NavigateBtHandler 负责驱动寻路和到达检测。

### 5.4 警惕等级

| 等级 | 名称 | 行为差异 |
|------|------|---------|
| 0 | Casual | 正常步速，正常停留时长 |
| 1 | Alert | 加速移动，启用 LookAt，缩短停留 |

警惕等级由情绪系统或脚本触发变更。

### 5.5 关键需求

| 编号 | 需求描述 | 优先级 |
|------|---------|--------|
| FR-PAT-01 | 支持闭环和开放两种路线拓扑 | P0 |
| FR-PAT-02 | 节点 Duration > 0 时触发停留行为动画 | P0 |
| FR-PAT-03 | 同路线多 NPC 互斥占用节点，禁止堆叠 | P0 |
| FR-PAT-04 | Alert 状态下 NPC 持续追踪警报目标的 LookAt | P1 |
| FR-PAT-05 | 脚本可动态创建/销毁临时路线 | P1 |
| FR-PAT-06 | Scripted 路线销毁时立即释放所有资源 | P1 |
| FR-PAT-07 | 巡逻路线配置通过配置表或 JSON 文件定义 | P0 |

## 6 场景点系统（ScenarioPoint）

### 6.1 业务目标

城镇中遍布活动节点（长椅、摊位、电话亭、健身器材等），NPC 自主寻找合适节点执行对应动画行为，形成城市生活细节。

### 6.2 场景点数据（ScenarioPoint）

| 字段 | 类型 | 说明 |
|------|------|------|
| PointId | int32 | 场景点唯一 ID |
| ScenarioType | int32 | 场景类型索引（关联动画和行为） |
| Position | Vec3 | 世界坐标 |
| Direction | float | 朝向角度 |
| MaxUsers | int32 | 最大同时占用 NPC 数（1-4） |
| CurrentUsers | int32 | 当前占用数（运行时） |
| TimeStart | int32 | 有效起始时间（游戏时间小时，0=不限） |
| TimeEnd | int32 | 有效结束时间（游戏时间小时，0=不限） |
| Duration | int32 | NPC 停留时长（秒，0=使用类型默认值） |
| Probability | int32 | 触发概率（百分比，0=类型默认值） |
| Radius | float | 占用半径 |
| Flags | uint32 | 功能标志位 |

### 6.3 场景点类型（基础版）

| 类型 | 说明 | 典型动画 |
|------|------|---------|
| Bench | 长椅 | 坐下/看报/玩手机 |
| Stall | 摊位 | 购买/交谈 |
| LeanWall | 靠墙 | 靠墙站立/抽烟 |
| Phone | 打电话 | 打电话动画 |
| Exercise | 健身 | 伸展/跑步 |
| Watch | 观看 | 围观/拍照 |
| Guard | 站岗 | 站岗警戒 |

> 扩展预留：场景类型通过配置表定义，无上限硬编码

### 6.4 场景点功能标志（基础版，16 位）

| 位 | 标志名 | 说明 |
|----|--------|------|
| 0 | NoSpawn | 禁止在此点生成 NPC |
| 1 | HighPriority | 高优先级，NPC 优先选择 |
| 2 | IndoorOnly | 仅室内有效 |
| 3 | OutdoorOnly | 仅室外有效 |
| 4 | WeatherSensitive | 受天气影响（下雨时停用露天点） |
| 5 | TimeRestricted | 启用 TimeStart/TimeEnd 时间限制 |
| 6 | ExtendedRange | 扩大 NPC 搜索范围 |
| 7 | StationaryReaction | 固定位置响应事件（不逃跑） |

> 扩展预留：标志位可扩展至 32 位

### 6.5 场景点分配流程

```
[NPC 需要场景点行为（日程/巡逻节点/空闲）]
         │
         ▼
    搜索附近可用场景点（距离² < 搜索半径²）
         │
         ▼
    过滤：时间段 + 概率 + 标志位 + 占用数
         │
         ▼
    排序：距离 + 优先级 + 类型匹配
         │
         ▼
    占用场景点（CurrentUsers++）
         │
         ▼
    移动到场景点位置 → 执行动画
         │
         ▼
    停留时长到期 → 释放（CurrentUsers--）
```

### 6.6 关键需求

| 编号 | 需求描述 | 优先级 |
|------|---------|--------|
| FR-SCN-01 | 场景点同时占用数受 MaxUsers 限制 | P0 |
| FR-SCN-02 | 分配前校验时间段和概率 | P0 |
| FR-SCN-03 | NPC 搜索场景点使用平方距离比较 | P0 |
| FR-SCN-04 | NoSpawn 标志可快速锁定场景点 | P0 |
| FR-SCN-05 | 场景点配置通过配置表定义 | P0 |
| FR-SCN-06 | 天气变化时重新评估 WeatherSensitive 场景点 | P1 |
| FR-SCN-07 | 场景链：NPC 完成一个场景后可自动衔接下一个 | P2 |

## 7 与正交管线集成

### 7.1 维度归属

| 系统 | 写入维度 | 说明 |
|------|---------|------|
| 日程 | **Locomotion** | 日程驱动移动行为（MoveTo/Work/Rest） |
| 巡逻 | **Locomotion** | 巡逻沿路线移动 |
| 场景点 | **Locomotion** | 场景点移动+交互（需写入 MoveTarget，不可放 Navigation 读取方） |
| 人口调度 | **管线外** | Spawn/Despawn 在管线外层执行 |

### 7.2 新增 Handler

| Handler | 维度 | 说明 |
|---------|------|------|
| ScheduleHandler | Locomotion | **调度路由器**：读取日程条目的 BehaviorType，分发到对应子 Handler |
| PatrolHandler | Locomotion | 巡逻状态机，沿路线移动和停留 |
| ScenarioHandler | Locomotion | 场景点搜索、占用、移动到位、执行、释放 |
| GuardHandler | Locomotion | 固定位置站岗（特殊巡逻） |

**Handler 路由机制**：Locomotion 维度同一时刻只有一个活跃 Handler。ScheduleHandler 作为**调度路由器**，根据日程条目的 BehaviorType 切换 PlanExecutor 的当前 Handler：

| BehaviorType | 路由到 |
|-------------|--------|
| Idle / MoveTo / Work / Rest | ScheduleHandler 自身处理 |
| Patrol | PatrolHandler |
| UseScenario | ScenarioHandler |
| Guard（配置表标记） | GuardHandler |
| EnterBuilding / ExitBuilding | ScheduleHandler 自身处理（特殊过渡） |

当 NPC 不在日程系统中时（如 Ambient 类型），直接由 V2Brain 决策选择 Handler。

### 7.3 MoveTarget 优先级

复用已有的 MoveSource 仲裁机制：

```
NONE < SCRIPT < EXPRESSION < SCHEDULE < ENGAGEMENT < OVERRIDE
```

- 日程/巡逻通过 `MoveSourceSchedule` 写入 MoveTarget
- 高优先级的战斗（Engagement）可覆盖日程移动目标
- 日程恢复时重新写入 MoveTarget

### 7.4 NpcState 扩展

在现有 `ScheduleState` 基础上扩展。已有字段标注复用关系：

**已有字段（复用）**：

| 已有字段 | 类型 | 复用方式 |
|---------|------|---------|
| CurrentNode | int32 | 复用：日程模式存日程条目索引，巡逻模式存巡逻节点 ID |
| NextNodeTime | int64 | 复用：下一日程条目/巡逻节点的切换时间戳 |
| TargetPos | Vec3 | 复用：当前行为的目标位置（日程/巡逻/场景点） |
| HasTarget | bool | 复用：是否有有效目标 |
| IsInterrupted | bool | 复用：日程被中断标记 |
| InterruptTime | int64 | 复用：中断时间戳 |
| PauseAccum | int64 | 复用：累计暂停时长 |
| CurrentPlan | string | 复用：当前活跃的 Handler 名称 |

**新增字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| ScheduleTemplateId | int32 | 日程模板 ID（0=无日程） |
| PatrolRouteId | int32 | 当前巡逻路线 ID（0=无巡逻） |
| PatrolDirection | int32 | 巡逻方向（0=forward, 1=backward） |
| ScenarioPointId | int32 | 当前占用的场景点 ID（0=无） |
| AlertLevel | int32 | 警惕等级（0=casual, 1=alert，int32 预留多级扩展） |

> 所有新增字段必须同步 Snapshot + FieldAccessor

### 7.5 帧执行流程

```
GlobalGuard（死亡/眩晕检查）
    │
    ▼
LockTimeout（交互锁超时检查）
    │
    ▼
ResetWritableFields
    │
    ▼
scheduleWriteBack（日程目标位置回写）
    │
    ▼
Engagement 维度（Brain → Executor）
    │
    ▼
Expression 维度（Brain → Executor）
    │
    ▼
Locomotion 维度（ScheduleHandler → PatrolHandler / ScenarioHandler / GuardHandler）
    │       ↑ 日程/巡逻/场景点在此维度写入 MoveTarget
    ▼
Navigation 维度（Interact / Investigate 等现有 Handler）
            ↑ 读取 MoveTarget 执行寻路
```

## 8 配置驱动

### 8.1 配置文件体系

| 配置 | 存储方式 | 说明 |
|------|---------|------|
| 人口配额 | 配置表（Excel） | 时段×区域的 NPC 配额 |
| 日程模板 | JSON 配置 | NPC 类型 → 每日行为时间表 |
| 巡逻路线 | JSON 配置 | 路线拓扑、节点坐标 |
| 场景点定义 | 配置表（Excel） | 场景点位置、类型、标志 |
| 场景类型 | 配置表（Excel） | 类型 → 动画映射 |
| NPC 类型组 | 配置表（Excel） | 类型组 → 模型、行为分类 |

### 8.2 JSON 配置示例

#### 日程模板（`bin/config/ai_schedule/`）

```json
{
  "templateId": 1001,
  "name": "shopkeeper",
  "entries": [
    {"startTime": 8,  "endTime": 12, "behavior": "Work",    "locationId": 5001},
    {"startTime": 12, "endTime": 13, "behavior": "Rest",    "locationId": 5002},
    {"startTime": 13, "endTime": 18, "behavior": "Work",    "locationId": 5001},
    {"startTime": 18, "endTime": 20, "behavior": "MoveTo",  "locationId": 5003},
    {"startTime": 20, "endTime": 8,  "behavior": "EnterBuilding", "locationId": 5004}
  ]
}
```

#### 巡逻路线（`bin/config/ai_patrol/`）

```json
{
  "routeId": 2001,
  "name": "town_guard_route_1",
  "type": "Permanent",
  "desiredNpcCount": 2,
  "nodes": [
    {"nodeId": 1, "position": [100, 0, 200], "heading": 90, "duration": 5000, "behavior": "Guard", "links": [2]},
    {"nodeId": 2, "position": [120, 0, 200], "heading": 0,  "duration": 0,    "behavior": "",      "links": [3]},
    {"nodeId": 3, "position": [120, 0, 220], "heading": 270,"duration": 3000, "behavior": "Guard", "links": [1]}
  ]
}
```

### 8.3 配置加载

- 服务器启动时加载所有配置到内存
- 配置变更通过热更新机制重新加载（不重启服务）
- 配置校验：启动时检查引用完整性（locationId 有效、routeId 存在等）

## 9 关键约束与边界

### 9.1 容量上限

| 约束项 | 基础版值 | 扩展预留 |
|--------|---------|---------|
| 每区域最大巡逻路线数 | 16 | 可调整 |
| 每路线最大节点数 | 32 | 可调整 |
| 每节点最大出边数 | 4 | 固定 |
| 场景点类型数 | 不硬编码 | 配置表驱动 |
| 单点最大占用 NPC 数 | 4 | 配置表驱动 |
| 每天时段分割数 | 6 | 可扩展至 12 |
| 日程模板条目数 | 不限 | 按配置 |

### 9.2 架构约束

| 约束 | 说明 |
|------|------|
| V2 独立 | 不依赖 V1 日程行为树代码，完全独立实现 |
| 服务端权威 | 所有调度/决策在服务端，客户端只同步状态 |
| Handler 无状态 | Handler 是场景级共享单例，状态存 NpcState |
| 平方距离 | 距离判断用 dx²+dz² vs radius²，禁用曼哈顿距离 |
| 业务时间 | 用 `mtime.NowTimeWithOffset()`，非 `time.Now()` |
| Snapshot 同步 | NpcState 新增字段必须同步 Snapshot + FieldAccessor |

### 9.3 性能约束

| 约束 | 说明 |
|------|------|
| 场景点搜索 | 空间分区（Grid 或四叉树），每帧搜索开销 O(1) |
| 人口调度 | 每 Tick 只增减 1-2 个 NPC，避免帧峰值 |
| 巡逻节点 | 内存池管理，避免频繁 GC |

## 10 术语表

| 术语 | 说明 |
|------|------|
| PopSchedule | 人口调度系统，按时段控制 NPC 数量和类型 |
| PopAllocation | 某时段×区域的人口配额配置 |
| DaySchedule | 日程系统，NPC 每日行为时间表 |
| ScheduleEntry | 日程条目，描述某时段的行为和目标 |
| ScheduleTemplate | 日程模板，同类型 NPC 共享 |
| PatrolRoute | 巡逻路线，由有序节点组成 |
| PatrolNode | 巡逻节点，含坐标/朝向/停留时长 |
| ScenarioPoint | 场景活动节点，NPC 可占用执行动画 |
| ScenarioType | 场景类型，关联动画和行为 |
| Handler | V2 管线中的行为处理器（共享单例，无状态） |
| MoveSourceSchedule | 移动目标优先级档位，日程驱动移动 |
| AlertLevel | 巡逻警惕等级（Casual / Alert） |
