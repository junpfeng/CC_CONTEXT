# NPC 系统指南

本文档描述 P1GoServer 项目中 NPC 系统的架构、DB 存取流程和测试要点。

---

## 文档概述

| 内容 | 使用时机 |
|------|----------|
| NPC 系统架构（Section 1-3） | NPC 功能开发、问题排查 |
| AI 决策系统（Section 4） | Plan 开发、状态转换调试 |
| DB 存取流程（Section 5-6） | 数据持久化开发、测试 |
| 小镇/樱花校园差异（Section 7） | 场景特定功能开发 |
| 测试要点（Section 8） | Phase 4 实现后测试、Phase 6 审查 |

### 相关文档

| 文档 | 用途 |
|------|------|
| `DB.md` | 数据库架构、db_server 缓存机制 |
| `TEST.md` | 测试规范、压测机器人 |
| `SKILL.md` | Phase 7 经验沉淀 |

### 相关 Rules

| 规范文件 | 用途 |
|----------|------|
| `P1GoServer/.claude/rules/ai-decision.md` | AI 决策系统开发规范 |
| `P1GoServer/.claude/rules/behavior-tree.md` | 行为树节点实现规范 |
| `P1GoServer/.claude/rules/npc-component.md` | NPC 组件开发规范 |
| `P1GoServer/.claude/rules/ecs-architecture.md` | ECS 架构规范 |

---

## 1. NPC 系统架构概述

### 1.1 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    AI 决策层                                 │
│   GSS Brain → Plan 生成 → 状态转换 → 行为树执行              │
└─────────────────────────────┬───────────────────────────────┘
                              ↓
┌─────────────────────────────┴───────────────────────────────┐
│                    ECS 组件层                                │
│   NpcComp / TownNpcComp / SakuraNpcComp / TradeProxyComp    │
└─────────────────────────────┬───────────────────────────────┘
                              ↓
┌─────────────────────────────┴───────────────────────────────┐
│                    资源管理层                                │
│   TownNpcMgr / SakuraNpcMgr (数据加载/保存)                 │
└─────────────────────────────┬───────────────────────────────┘
                              ↓
┌─────────────────────────────┴───────────────────────────────┐
│                    持久化层                                  │
│   db_entry → db_server → Redis/MongoDB                      │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 核心目录结构

```
servers/scene_server/internal/
├── common/ai/                    # AI 决策系统
│   ├── decision/                 # 决策框架
│   │   ├── types.go              # Plan、Task、Agent 等类型定义
│   │   ├── agent/                # AI 代理实现
│   │   │   ├── gss.go            # GSS Brain 实现
│   │   │   └── factory.go        # Agent 工厂
│   │   ├── fsm/                  # 状态机
│   │   ├── gss_brain/            # GSS 大脑核心
│   │   │   ├── config/           # Plan 配置、转换配置
│   │   │   ├── transition/       # 计划转换逻辑
│   │   │   ├── feature/          # 特征值管理
│   │   │   └── condition/        # 条件判断
│   │   ├── goap/                 # GOAP 规划器
│   │   └── value/                # 特征值系统
│   └── bt/                       # 行为树系统
│       ├── tree/                 # 树和节点实现
│       └── config/               # 行为树配置
│
├── ecs/
│   ├── com/cnpc/                 # NPC 组件
│   │   ├── npc_comp.go           # 基础 NPC 组件
│   │   ├── town_npc.go           # 小镇 NPC 组件
│   │   ├── sakura_npc.go         # 樱花校园 NPC 组件
│   │   ├── npc_move.go           # NPC 移动组件
│   │   ├── schedule_comp.go      # 日程组件
│   │   └── trade_proxy_comp.go   # 交易代理组件
│   │
│   ├── res/                      # 资源管理
│   │   ├── town/town_npc.go      # TownNpcMgr
│   │   └── sakura/sakura_npc.go  # SakuraNpcMgr
│   │
│   ├── system/                   # ECS 系统
│   │   ├── decision/             # 决策系统
│   │   └── npc/                  # NPC 更新系统
│   │
│   └── scene/                    # 场景管理
│       ├── scene_impl.go         # 场景初始化（数据加载）
│       └── save.go               # 场景保存
│
└── net_func/npc/                 # 网络接口
    ├── common.go                 # 通用 NPC 创建函数
    ├── town_npc.go               # 小镇 NPC 创建
    └── sakura_npc.go             # 樱花校园 NPC 创建
```

---

## 2. NPC 组件系统

### 2.1 组件列表

| 组件 | 文件 | 说明 | 持久化 |
|------|------|------|--------|
| `NpcComp` | `npc_comp.go` | 基础 NPC 属性（配置ID、名称、性别） | ❌ |
| `TownNpcComp` | `town_npc.go` | 小镇专用（交易订单状态、外出时长） | ✅ |
| `SakuraNpcComp` | `sakura_npc.go` | 樱校专用（外出时长） | ❌ |
| `NpcMoveComp` | `npc_move.go` | 移动（速度、导航） | ❌ |
| `NpcScheduleComp` | `schedule_comp.go` | 日程（会议预约、状态） | ✅ |
| `TradeProxyComp` | `trade_proxy_comp.go` | 交易代理（余额、交易状态、冷却） | ✅ |
| `DecisionComp` | `caidecision/decision.go` | AI 决策组件 | ❌ |

### 2.2 组件脏标记机制

所有 NPC 组件继承 `ComponentBase`，支持两种脏标记：

```go
// 标记需要同步给客户端
comp.SetSync()

// 标记需要保存到 DB
comp.SetSave()
```

**示例：TradeProxyComp.SetBalance()**
```go
func (c *TradeProxyComp) SetBalance(amount int) {
    c.balance = amount
    c.SetSync()      // 同步给客户端
    c.SetSave()      // 标记需要保存
}
```

### 2.3 组件序列化方法

| 组件 | 序列化 | 反序列化 | 保存条件 |
|------|--------|----------|----------|
| TradeProxyComp | `ToSaveProto(npcCfgId)` | `LoadFromProto(data)` | 有余额/交易状态/冷却 |
| NpcScheduleComp | `ToSaveProto(npcCfgId)` | `LoadFromProto(data)` | 有会议预约 |
| TownNpcComp | `ToSaveProto()` | `LoadFromProto(data)` | 有订单状态 |

---

## 3. NPC 资源管理

### 3.1 TownNpcMgr

**文件**: `servers/scene_server/internal/ecs/res/town/town_npc.go`

```go
type TownNpcMgr struct {
    NpcMap       map[int32]uint32  // npcCfgId → entityId
    PoliceNpcMap map[int32]uint32  // 警察 NPC 优化映射

    // 待加载的保存数据（场景初始化时设置）
    savedPositions    map[int32]*DBSaveTownNpcPosition
    savedTradeProxy   map[int32]*TradeProxyInfo
    savedSchedule     map[int32]*ScheduleInfo
    savedTownNpcData  map[int32]*TownNpcSaveData
}
```

**核心方法**：

| 方法 | 说明 |
|------|------|
| `LoadPositions(data)` | 加载 NPC 位置数据到缓存 |
| `LoadTradeProxyData(data)` | 加载交易代理数据到缓存 |
| `LoadScheduleData(data)` | 加载日程数据到缓存 |
| `LoadTownNpcData(data)` | 加载 NPC 基础数据到缓存 |
| `ToSavePositions()` | 收集所有 NPC 位置数据 |
| `ToSaveTradeProxyList()` | 收集所有交易代理数据 |
| `ToSaveScheduleList()` | 收集所有日程数据 |
| `ToSaveTownNpcDataList()` | 收集所有 NPC 基础数据 |
| `ClearAllSaveFlags()` | 清除所有组件的脏标记 |

### 3.2 SakuraNpcMgr

**文件**: `servers/scene_server/internal/ecs/res/sakura/sakura_npc.go`

```go
type SakuraNpcMgr struct {
    NpcMap map[int32]uint32  // npcCfgId → entityId
}
```

**特点**：
- 简洁设计，无特殊映射
- **不保存 NPC 状态数据**（设计如此）

---

## 4. AI 决策系统

### 4.1 Plan 数据结构

**文件**: `common/ai/decision/types.go`

```go
type Plan struct {
    Name         string       // 计划名称
    DecisionType DecisionType // 决策类型（GSS/NDU）
    Tasks        []*Task      // 任务列表
    Transition   string       // 转换目标
    FromPlan     string       // 来源计划
}

type Task struct {
    Name     string   // 任务名称
    Type     TaskType // 任务类型（Entry/Exit/Main/Normal）
    ExecArgs []any    // 执行参数
}
```

### 4.2 Plan 配置格式

**文件**: `common/ai/decision/gss_brain/config/plan.go`

```go
type Plan struct {
    Name      string `json:"name"`       // 计划名称（如 daily_schedule, meeting, dialog, pursuit）
    MainTask  string `json:"main_task"`  // 主任务（do_main）
}
```

### 4.3 决策执行流程

```
DecisionSystem.Update()
    ↓
EntityList 筛选 NPC
    ↓
DecisionComp.Update()
    ↓
Agent.Tick()
    ↓
GSS Brain.Tick()
    ↓ (基于特征值生成 Plan)
GetNextPlan()
    ↓
Executor.OnPlanCreated()  [执行 Plan 任务]
    ↓
更新 currentPlan
```

### 4.4 特征值与计划选择

NPC 的 AI 决策基于**特征值**（Feature）选择计划：

1. 从 DB 加载的组件状态（交易代理、日程、订单等）
2. 组件状态更新到特征值系统
3. GSS Brain 根据特征值和转换条件选择新计划
4. 执行器执行计划中的任务

**关键点**：
- NPC 每次从初始状态开始
- 基于 DB 加载的组件数据，AI 会选择正确的计划
- AI 计划本身不持久化

---

## 5. DB 存取流程

### 5.1 存储位置

| 场景 | 数据库表 | 主键 |
|------|----------|------|
| 小镇 | `town_table_{VERSION}` | `role_id` |
| 樱花校园 | `sakura_table_{VERSION}` | `role_id` |

### 5.2 NPC 持久化字段

#### 小镇 NPC 持久化数据

**DBSaveTownInfo 中的 NPC 相关字段**：

| 字段 | Proto 类型 | 说明 |
|------|-----------|------|
| `NpcPositions` | `[]*DBSaveTownNpcPosition` | NPC 位置和旋转 |
| `TradeProxyInfo` | `[]*TradeProxyInfo` | 交易代理状态 |
| `ScheduleInfo` | `[]*ScheduleInfo` | 日程/会议信息 |
| `TownNpcData` | `[]*TownNpcSaveData` | NPC 基础数据 |

**DBSaveTownNpcPosition**：
```protobuf
message DBSaveTownNpcPosition {
    int32 npc_cfg_id = 1;  // NPC 配置 ID
    Vector3 position = 2;   // 位置
    Vector3 rotation = 3;   // 旋转
}
```

**TradeProxyInfo**：
```protobuf
message TradeProxyInfo {
    int32 npc_cfg_id = 1;          // NPC 配置 ID
    int32 employer_entity_id = 2;   // 雇主实体 ID
    int32 trade_status = 3;         // 交易状态
    repeated uint64 trade_npc_list = 4;  // 待交易 NPC 队列
    int32 traded_count = 5;         // 已交易数量
    int64 cool_down_end_time = 6;   // 冷却结束时间
    int32 balance = 7;              // 余额
}
```

**ScheduleInfo**：
```protobuf
message ScheduleInfo {
    int32 ordered_meeting = 1;   // 预约的会议 ID
    int32 meeting_state = 2;     // 会议状态
    int32 meeting_point_id = 3;  // 会议地点 ID
    int32 npc_cfg_id = 4;        // NPC 配置 ID
}
```

**TownNpcSaveData**：
```protobuf
message TownNpcSaveData {
    int32 cfg_id = 1;              // NPC 配置 ID
    int64 out_duration_time = 2;   // 外出持续时间
    TownTradeOrderState trade_order_state = 3;  // 交易订单状态
    bool is_dealer_trade = 4;      // 是否经销商交易
}
```

#### 樱花校园 NPC 持久化数据

**DBSaveSakuraInfo 不包含 NPC 状态数据**：
```protobuf
message DBSaveSakuraInfo {
    uint64 role_id = 1;
    DBSaveSakuraPlacementInfo placement_info = 2;  // 放置物件
    int64 last_stop_time = 3;                       // 最后停止时间
    DBSaveSakuraTimeData time_data = 4;            // 时间数据
}
```

### 5.3 数据加载流程（玩家进入场景）

**文件**: `servers/scene_server/internal/ecs/scene/scene_impl.go`

```
玩家进入场景
    ↓
scene.init()
    ↓
┌─ 小镇场景 ─────────────────────────────────────────┐
│ 1. dbEntry.GetTownInfo(roleId)                     │
│    - 从 MongoDB 加载 DBSaveTownInfo                │
│                                                     │
│ 2. townResourceInit(saveInfo)                      │
│    - NewTownNpcMgr()                               │
│    - LoadPositions(saveInfo.NpcPositions)          │
│    - LoadTradeProxyData(saveInfo.TradeProxyInfo)   │
│    - LoadScheduleData(saveInfo.ScheduleInfo)       │
│    - LoadTownNpcData(saveInfo.TownNpcData)         │
│                                                     │
│ 3. npc.InitTownNpcs(scene)                         │
│    - CreateTownNpc() 创建每个 NPC                  │
│    - 从 TownNpcMgr 缓存恢复保存的数据              │
│      * 恢复位置 (Transform)                         │
│      * 恢复交易代理 (TradeProxyComp)               │
│      * 恢复日程 (NpcScheduleComp)                  │
│      * 恢复基础数据 (TownNpcComp)                  │
│    - InitNpcAIComponents() 初始化 AI               │
│    - AI 基于组件状态选择初始计划                   │
└────────────────────────────────────────────────────┘

┌─ 樱花校园场景 ─────────────────────────────────────┐
│ 1. dbEntry.GetSakuraInfo(roleId)                   │
│    - 从 MongoDB 加载 DBSaveSakuraInfo              │
│                                                     │
│ 2. sakuraResourceInit(saveInfo)                    │
│    - 加载放置物件、时间数据                         │
│    - 不加载 NPC 状态                               │
│                                                     │
│ 3. npc.InitSakuraNPCs(scene)                       │
│    - CreateSakuraNpc() 创建每个 NPC                │
│    - NPC 从默认状态开始                            │
└────────────────────────────────────────────────────┘
```

### 5.4 数据保存流程（玩家离开场景）

**文件**: `servers/scene_server/internal/ecs/scene/save.go`

```
scene.Save()
    ↓
┌─ 小镇场景 ─────────────────────────────────────────┐
│ 1. saveTownInfo()                                  │
│                                                     │
│ 2. 收集各类数据                                     │
│    - TownMgr.ToSaveData()                          │
│    - 其他 Manager 数据...                          │
│                                                     │
│ 3. 收集 NPC 数据                                   │
│    townNpcMgr := GetResourceAs[*TownNpcMgr](scene) │
│    townInfo.NpcPositions = townNpcMgr.ToSavePositions()     │
│    townInfo.TradeProxyInfo = townNpcMgr.ToSaveTradeProxyList() │
│    townInfo.ScheduleInfo = townNpcMgr.ToSaveScheduleList()    │
│    townInfo.TownNpcData = townNpcMgr.ToSaveTownNpcDataList()  │
│                                                     │
│ 4. 写入 DB                                         │
│    dbEntry.SaveTownInfo(townInfo)                  │
│                                                     │
│ 5. 清除脏标记                                       │
│    townNpcMgr.ClearAllSaveFlags()                  │
└────────────────────────────────────────────────────┘

┌─ 樱花校园场景 ─────────────────────────────────────┐
│ 1. saveSakuraInfo()                                │
│                                                     │
│ 2. 收集放置数据和时间数据                           │
│    - 不收集 NPC 状态                               │
│                                                     │
│ 3. 写入 DB                                         │
│    dbEntry.SaveSakuraInfo(sakuraInfo)              │
└────────────────────────────────────────────────────┘
```

---

## 6. DB 存取代码位置索引

| 功能 | 文件路径 | 关键行号 |
|------|----------|----------|
| **DB Entry** | | |
| 小镇数据加载 | `common/db_entry/town.go` | `GetTownInfo()` |
| 小镇数据保存 | `common/db_entry/town.go` | `SaveTownInfo()` |
| 樱校数据加载 | `common/db_entry/sakura.go` | `GetSakuraInfo()` |
| 樱校数据保存 | `common/db_entry/sakura.go` | `SaveSakuraInfo()` |
| **场景管理** | | |
| 场景初始化 | `ecs/scene/scene_impl.go` | `init()` |
| 小镇资源初始化 | `ecs/scene/scene_impl.go` | `townResourceInit()` |
| 场景保存 | `ecs/scene/save.go` | `Save()` |
| 小镇保存 | `ecs/scene/save.go` | `saveTownInfo()` |
| **NPC 管理器** | | |
| TownNpcMgr 定义 | `ecs/res/town/town_npc.go` | 结构体定义 |
| 数据加载方法 | `ecs/res/town/town_npc.go` | `Load*()` 方法 |
| 数据保存方法 | `ecs/res/town/town_npc.go` | `ToSave*()` 方法 |
| **NPC 创建** | | |
| 小镇 NPC 创建 | `net_func/npc/town_npc.go` | `CreateTownNpc()` |
| 樱校 NPC 创建 | `net_func/npc/sakura_npc.go` | `CreateSakuraNpc()` |
| **组件序列化** | | |
| TradeProxyComp | `ecs/com/cnpc/trade_proxy_comp.go` | `ToSaveProto()`, `LoadFromProto()` |
| NpcScheduleComp | `ecs/com/cnpc/schedule_comp.go` | `ToSaveProto()`, `LoadFromProto()` |
| TownNpcComp | `ecs/com/cnpc/town_npc.go` | `ToSaveProto()`, `LoadFromProto()` |
| **Proto 定义** | | |
| DBSaveTownInfo | `common/proto/db_pb.go` | 约 13232 行 |
| DBSaveSakuraInfo | `common/proto/db_pb.go` | 约 10929 行 |
| TradeProxyInfo | `common/proto/npc_pb.go` | 约 4938 行 |
| ScheduleInfo | `common/proto/scene_pb.go` | 约 52066 行 |
| TownNpcSaveData | `common/proto/npc_pb.go` | 约 4589 行 |

---

## 7. 小镇与樱花校园差异

### 7.1 功能差异对比

| 特性 | 小镇 | 樱花校园 |
|------|------|---------|
| **专用组件** | TownNpcComp (83行) | SakuraNpcComp (38行) |
| **交易系统** | ✅ 支持（订单状态） | ❌ 不支持 |
| **警察系统** | ✅ 支持（警察职业） | ❌ 不支持 |
| **经销商系统** | ✅ 支持（TradeProxyComp） | ❌ 不支持 |
| **玩家控制** | ❌ 不支持 | ✅ 支持（SakuraNpcControlComp） |
| **NPC 位置持久化** | ✅ 保存 | ❌ 不保存 |
| **NPC 状态持久化** | ✅ 保存 | ❌ 不保存（设计如此） |

### 7.2 数据持久化差异

| 数据类型 | 小镇 | 樱花校园 |
|----------|------|---------|
| NPC 位置 | ✅ `NpcPositions` | ❌ |
| 交易代理 | ✅ `TradeProxyInfo` | ❌ |
| 日程信息 | ✅ `ScheduleInfo` | ❌ |
| NPC 基础数据 | ✅ `TownNpcData` | ❌ |
| 时间数据 | ✅ `TimeData` | ✅ `TimeData` |
| AI 计划/决策 | ❌ 不保存 | ❌ 不保存 |

### 7.3 NPC 管理器差异

**TownNpcMgr**：
- 维护 NpcMap（所有 NPC）
- 维护 PoliceNpcMap（警察优化映射）
- 保存数据缓存（位置、交易代理、日程、NPC数据）
- 完整的 Load/Save 方法

**SakuraNpcMgr**：
- 仅维护 NpcMap（所有 NPC）
- 无保存数据缓存
- 简化的管理逻辑

---

## 8. 测试要点

### 8.1 现有测试文件

| 测试文件 | 覆盖内容 |
|----------|----------|
| `decision/agent/gss_test.go` | GSS 决策测试 |
| `gss_brain/config/config_test.go` | 配置加载测试 |
| `gss_brain/feature/feature_test.go` | 特征值测试 |
| `value/value_mgr_test.go` | 值管理器测试 |
| `system/npc/move_test.go` | NPC 移动测试 |

### 8.2 AI 决策测试要点

| 测试场景 | 验证内容 |
|----------|----------|
| Plan 生成 | GSS Brain 根据特征值正确生成 Plan |
| 状态转换 | 状态机正确转换（WaitConsume ↔ WaitCreate） |
| 任务执行 | Plan 中的 Task 正确执行（Entry/Main/Exit） |
| 特征值更新 | 组件状态变化正确更新到特征值系统 |
| 计划选择 | 基于不同特征值选择正确的计划 |

### 8.3 DB 存取测试要点

#### 小镇 NPC 测试

| 测试场景 | 验证内容 |
|----------|----------|
| **位置持久化** | |
| 保存位置 | NPC 位置和旋转正确保存到 DB |
| 加载位置 | 重新进入场景后 NPC 位置正确恢复 |
| 精度验证 | 位置/旋转的 float 精度正确 |
| **交易代理** | |
| 保存状态 | 余额、交易状态、冷却时间正确保存 |
| 加载状态 | 重新进入后交易代理状态正确恢复 |
| 计划恢复 | 基于交易代理状态，AI 选择正确计划 |
| **日程信息** | |
| 保存会议 | 会议预约、状态、地点正确保存 |
| 加载会议 | 重新进入后会议信息正确恢复 |
| 计划恢复 | 基于日程状态，AI 选择正确计划 |
| **NPC 基础数据** | |
| 保存订单 | 交易订单状态正确保存 |
| 加载订单 | 重新进入后订单状态正确恢复 |
| 计划恢复 | 基于订单状态，AI 选择正确计划 |

#### 樱花校园 NPC 测试

| 测试场景 | 验证内容 |
|----------|----------|
| 无状态保存 | 验证 DBSaveSakuraInfo 不包含 NPC 状态字段 |
| 默认初始化 | 每次进入场景，NPC 从默认状态开始 |
| AI 正常运行 | NPC AI 决策正常工作 |

### 8.4 边界条件测试

| 测试场景 | 验证内容 |
|----------|----------|
| 空数据处理 | NPC 列表为空时保存/加载正常 |
| 部分数据 | 只有部分组件有数据时正确处理 |
| 脏标记清除 | 保存后脏标记正确清除 |
| 保存失败 | DB 写入失败时脏标记保留 |
| 并发访问 | 多玩家同时操作场景时数据一致 |

### 8.5 集成测试流程

```
1. 创建小镇场景
2. 设置 NPC 状态（交易代理、日程、订单）
3. 验证 AI 选择正确计划
4. 保存场景
5. 销毁场景
6. 重新创建场景（模拟玩家重新进入）
7. 验证 NPC 状态从 DB 正确恢复
8. 验证 AI 基于恢复的状态选择正确计划
```

---

## 9. 常见问题排查

### 9.1 NPC 状态未恢复

**可能原因**：
1. 组件未调用 `SetSave()` 标记脏数据
2. `ToSaveProto()` 保存条件不满足（如余额为 0 不保存）
3. DB 写入失败
4. Redis 缓存未清除（参考 `DB.md` 缓存一致性）

**排查步骤**：
```bash
# 1. 检查 MongoDB 数据
mongosh
use fl_test_tmp_6
db.town_table_20250521.findOne({role_id: <role_id>}, {
    trade_proxy_info: 1,
    schedule_info: 1,
    town_npc_data: 1,
    npc_positions: 1
})

# 2. 检查 Redis 缓存
redis-cli GET "db_server:town_table_20250521:<role_id>"

# 3. 清除 Redis 缓存后重试
redis-cli DEL "db_server:town_table_20250521:<role_id>"
```

### 9.2 AI 计划选择错误

**可能原因**：
1. 组件状态未正确更新到特征值系统
2. 转换条件配置错误
3. 特征值初始化顺序问题

**排查步骤**：
1. 检查组件状态是否正确加载
2. 检查特征值是否正确更新
3. 检查转换条件是否满足

### 9.3 玩家在线时修改被覆盖

**原因**：scene_server 内存中有数据，定期保存会覆盖 MongoDB

**解决**：确保玩家离线后再修改数据（参考 `DB.md` Section 7.2）

---

## 10. 扩展阅读

- **AI 决策系统开发**：`P1GoServer/.claude/rules/ai-decision.md`
- **行为树节点实现**：`P1GoServer/.claude/rules/behavior-tree.md`
- **NPC 组件开发**：`P1GoServer/.claude/rules/npc-component.md`
- **数据库系统**：`.claude/skills/dev-workflow/DB.md`
- **测试规范**：`.claude/skills/dev-workflow/TEST.md`
