# 樱花校园接入时间系统设计方案

## 1. 方案概述

将小镇(Town)的时间系统扩展到樱花校园(Sakura)场景，使樱花校园支持游戏内时间流逝、跨天、星期循环等功能。方案采用复用现有 `TimeMgr` 的方式，通过配置化控制不同场景的时间行为差异。

**核心思路**：
- 复用现有的 `TimeMgr` 时间管理器，不新建独立的时间系统
- 通过场景配置区分小镇/樱花校园的时间行为差异
- 樱花校园**不启用睡眠功能**，时间自动循环跨天
- 樱花校园时间**独立运行**：玩家进入时继续，离开时暂停
- 时间比率与小镇相同，保持一致的时间流速

**需求确认**：
| 功能点 | 小镇 | 樱花校园 |
|--------|------|---------|
| 时间流逝 | ✅ | ✅ |
| 跨天/星期循环 | ✅ | ✅ |
| 睡眠功能 | ✅ | ❌ 不启用，时间自动循环 |
| 时间独立性 | 独立 | 独立，离开时暂停 |
| NPC行为联动 | 决策系统 | 决策系统 |
| 时间比率 | 全局配置 | 与小镇相同 |

---

## 2. 工程总览

| 工程 | 路径 | 本次角色 | 涉及的改动 |
|------|------|---------|-----------|
| 业务工程 | `./ (P1GoServer)` | 主工程 | 修改场景初始化、新增协议处理、扩展配置 |
| 协议工程 | `../proto/old_proto/` | 协议定义 | 新增樱花校园时间相关协议（可选） |
| 配置工程 | `../config/RawTables/` | 配置管理 | 新增场景时间配置（可选） |

---

## 3. 现有小镇时间系统分析

### 3.1 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                        TimeMgr (Resource)                        │
├─────────────────────────────────────────────────────────────────┤
│ - timeRatio: int64        // 游戏时间与现实时间比率              │
│ - offset: int64           // 时间偏移量                         │
│ - townTime: *TownTimeInfo // 小镇时间信息（周几、总天数、跨天）   │
├─────────────────────────────────────────────────────────────────┤
│ + GetNowTimestampInScene() // 获取当前场景时间戳                 │
│ + GetNowTimeInScene()      // 获取当天时间（秒）                 │
│ + IsTimeFlowing()          // 判断时间是否在流失                 │
│ + PrepareSleep()           // 玩家准备睡觉                       │
│ + CanTownSleep()           // 是否可以睡觉                       │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 时间计算公式

```
townTimestamp = realTimestamp * timeRatio + offset
dayTime = townTimestamp % 86400  (当天秒数)
weekTime = townTimestamp % 604800 (周内秒数)
```

### 3.3 时间流逝控制

| 状态 | 条件 | 时间是否流逝 |
|------|------|-------------|
| 正常 | `!isCrossDay` | 是 |
| 跨天（0-4点） | `isCrossDay && dayTime < 4:00` | 是 |
| 跨天（4点后） | `isCrossDay && dayTime >= 4:00` | 否（暂停在4点） |

### 3.4 睡眠系统

- **可睡觉时间**：18:00-23:59（跳到次日07:00）或 00:00-04:00（跳到当日07:00）
- **触发条件**：单人场景直接睡觉 / 多人场景所有玩家都准备好
- **睡眠后处理**：植物水分流失、销售数据归档、垃圾刷新、任务时间调整

---

## 4. 模块设计

### 4.1 方案选择

**方案A（推荐）**：复用 TimeMgr，配置化控制行为
- 优点：代码复用率高，维护成本低
- 缺点：需要对 TimeMgr 做少量扩展

**方案B**：为樱花校园创建独立的 SakuraTimeMgr
- 优点：完全隔离，灵活性高
- 缺点：代码重复，维护两套逻辑

**选择方案A**，理由：
1. 小镇和樱花校园的时间逻辑本质相同
2. 后续可能有更多场景需要时间系统
3. 统一的时间系统便于跨场景时间同步

### 4.2 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                     Scene (场景)                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │  TownSceneInfo  │    │ SakuraSceneInfo │                     │
│  └────────┬────────┘    └────────┬────────┘                     │
│           │                      │                               │
│           ▼                      ▼                               │
│  ┌─────────────────────────────────────────┐                    │
│  │            TimeMgr (共用)               │                    │
│  │  - 时间计算逻辑完全一致                  │                    │
│  │  - 通过 SceneTimeConfig 控制行为差异    │                    │
│  │  - enableSleep 控制是否启用睡眠暂停     │                    │
│  └─────────────────────────────────────────┘                    │
│                         │                                        │
│           ┌─────────────┴─────────────┐                         │
│           ▼                           ▼                          │
│    ┌──────────────────┐    ┌──────────────────┐                 │
│    │   Town 专属功能   │    │  Sakura 专属功能  │                │
│    │  - 睡眠系统       │    │  - 自动循环跨天   │                │
│    │  - 商店营业       │    │  - 离开时暂停     │                │
│    │  - 植物水分       │    │                   │                │
│    └──────────────────┘    └──────────────────┘                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 时间行为差异

| 行为 | 小镇 (Town) | 樱花校园 (Sakura) |
|------|-------------|-------------------|
| 跨天触发 | 自然时间到达24点 | 自然时间到达24点 |
| 跨天后行为 | 暂停在4点，等待睡眠 | **自动继续**，不暂停 |
| 时间恢复 | 睡眠后跳到7点 | 无需恢复，持续流逝 |
| 场景销毁时 | 保存当前时间戳 | 保存当前时间戳 |
| 场景加载时 | 从保存点继续 | 从保存点继续 |

### 4.4 关键设计：自动循环跨天

小镇的跨天逻辑会在4点后暂停时间，等待睡眠。樱花校园需要修改这个行为：

```go
// TimeMgr 新增字段
type TimeMgr struct {
    // ... 现有字段 ...
    enableSleep bool       // 是否启用睡眠暂停机制
    sceneType   SceneType  // 场景类型（用于区分输出哪个时间字段）
}

// 场景类型枚举
type SceneType int
const (
    SceneType_Town   SceneType = 0
    SceneType_Sakura SceneType = 1
)

// 修改 clampTownTimestamp 逻辑
func (t *TimeMgr) clampTownTimestamp(townTimestamp int64) int64 {
    // ... 计算 elapsedDays, dayTime ...

    // 小镇：跨天后暂停在4点
    // 樱花校园：跨天后自动继续（不暂停）
    if t.townTime.isCrossDay {
        if t.enableSleep {
            // 小镇逻辑：暂停在4点
            if elapsedDays != expectedDays || dayTime >= hour4Seconds {
                return BaseTownTimestamp + expectedDays*daySeconds + hour4Seconds
            }
        } else {
            // 樱花校园逻辑：自动跨天继续
            t.autoAdvanceDay()
        }
    }
    // ...
}

// ToProto 根据场景类型填充对应字段
func (t *TimeMgr) ToProto() *proto.TimeInfo {
    info := &proto.TimeInfo{
        TimeRatio:  int32(t.timeRatio),
        NowDayTime: int32(t.GetNowTimeInScene()),
        Timestamp:  t.GetNowTimestampInScene(),
    }

    if t.isUpdate && t.townTime != nil {
        switch t.sceneType {
        case SceneType_Town:
            info.TownTimeInfo = t.townTime.ToTownProto()
        case SceneType_Sakura:
            info.SakuraTimeInfo = t.townTime.ToSakuraProto()
        }
        t.isUpdate = false
    }

    return info
}
```

### 4.5 关键设计：离开时暂停

樱花校园时间独立，玩家离开时暂停，进入时继续。实现方式：

```
玩家离开/场景销毁时:
  1. 获取当前场景时间戳 GetNowTimestampInScene()
  2. 保存到 DBSaveSakuraInfo.TimeData.LastStopTime
  3. 下次加载时从 LastStopTime 继续

玩家进入/场景创建时:
  1. 读取 LastStopTime
  2. 计算新的 offset = LastStopTime - nowRealTime * timeRatio
  3. 时间从 LastStopTime 继续流逝
```

这与小镇的保存/加载逻辑一致，无需额外修改，`TimeMgr.LoadData()` 已支持。

---

## 5. 协议设计

### 5.1 现有协议结构

```protobuf
// 已存在于 scene.proto
message TimeInfo {
    int32 nowDayTime = 1;           // 当前游戏时间（秒）
    int32 timeRatio = 2;            // 时间比率
    TownTimeInfo townTimeInfo = 3;  // 小镇时间（周几、总天数）
    int64 timestamp = 4;            // 时间戳
}

message TownTimeInfo {
    int32 weekDay = 1;     // 周几 (1-7)
    int32 totalDays = 2;   // 总天数
}
```

### 5.2 新增协议

为避免语义歧义，新增独立的 `SakuraTimeInfo` 结构：

```protobuf
// 新增到 scene/scene.proto 或 scene/sakura.proto

// 樱花校园时间信息（结构与 TownTimeInfo 相同，但语义独立）
message SakuraTimeInfo {
    int32 weekDay = 1;     // 周几 (1-7)
    int32 totalDays = 2;   // 总天数
}

// 扩展 TimeInfo，新增樱花校园时间字段
message TimeInfo {
    int32 nowDayTime = 1;               // 当前游戏时间（秒）
    int32 timeRatio = 2;                // 时间比率
    TownTimeInfo townTimeInfo = 3;      // 小镇时间
    int64 timestamp = 4;                // 时间戳
    SakuraTimeInfo sakuraTimeInfo = 5;  // 新增：樱花校园时间
}
```

### 5.3 字段使用规则

| 场景类型 | 填充字段 | 说明 |
|---------|---------|------|
| Town | `townTimeInfo` | 小镇场景填充此字段 |
| Sakura | `sakuraTimeInfo` | 樱花校园填充此字段 |
| 通用字段 | `nowDayTime`, `timeRatio`, `timestamp` | 所有场景都填充 |

客户端根据场景类型读取对应字段，避免歧义。

### 5.4 DB 存储协议

```protobuf
// 新增樱花校园时间存储结构
message DBSaveSakuraTimeData {
    int32 weekDay = 1;
    int32 totalDays = 2;
    bool isCrossDay = 3;  // 内部状态，不同步给客户端
}

// 扩展 DBSaveSakuraInfo
message DBSaveSakuraInfo {
    // ... 现有字段 ...
    int64 lastStopTime = 10;              // 上次停止时的场景时间戳
    DBSaveSakuraTimeData timeData = 11;   // 樱花校园时间数据
}
```

---

## 6. 接口设计

### 6.1 场景初始化接口

```go
// 修改 scene_impl.go 中的 sakuraResourceInit
func (s *scene) sakuraResourceInit(saveInfo *proto.DBSaveSakuraInfo) error {
    // ... 现有初始化 ...

    // 新增：初始化时间管理器
    timeMgr := time_mgr.NewTimeMgr(s)
    if timeMgr != nil {
        s.AddResource(timeMgr)
        // 加载保存的时间数据
        timeMgr.LoadData(saveInfo.TimeData)
    }

    return nil
}
```

### 6.2 时间查询接口

复用现有接口，按场景类型路由：

```go
// net_func/sakura/time.go (新增)
func GetSakuraTime(scene common.Scene, player common.Player,
    req *proto.GetTownTimeReq) (*proto.GetTownTimeRsp, error) {

    timeMgr, ok := common.GetResourceAs[*time_mgr.TimeMgr](
        scene, common.ResourceType_TimeMgr)
    if !ok {
        return nil, errors.New("time manager not found")
    }

    return &proto.GetTownTimeRsp{
        TimeInfo: timeMgr.ToAllProto(),
    }, nil
}
```

---

## 7. DB 存取设计

### 7.1 数据结构扩展

在 `DBSaveSakuraInfo` 中新增时间数据字段：

```protobuf
// 修改 db/db.proto 或 scene/db_save.proto
message DBSaveSakuraInfo {
    uint64 roleId = 1;
    int64 lastSaveTime = 2;
    DBSavePlacementInfo placementInfo = 3;
    // ... 其他字段 ...

    // 新增时间数据
    DBSaveTimeData timeData = 10;  // 复用小镇的时间数据结构
}

// 已存在的时间数据结构
message DBSaveTimeData {
    int64 lastStopTime = 1;           // 上次停止时的小镇时间戳
    DBSaveTownTimeData townTimeData = 2;  // 小镇时间数据
}

message DBSaveTownTimeData {
    int32 weekDay = 1;
    int32 totalDays = 2;
    bool isCrossDay = 3;
}
```

### 7.2 数据迁移

对于已存在的樱花校园存档，`TimeData` 为空时使用默认值初始化：
- `WeekDay = 0` (周一)
- `TotalDays = 1` (第一天)
- `isCrossDay = false`
- `lastStopTime` 根据当前时间和配置的初始时间计算

---

## 8. 事务设计

### 8.1 事务边界识别

本次改动涉及的事务场景：

| 操作 | 事务类型 | 说明 |
|------|---------|------|
| 时间数据读取 | 无需事务 | 只读操作 |
| 时间数据保存 | 单服务单数据源 | 随场景存档一起保存 |
| 睡眠操作（如启用） | 单服务多步骤 | 需要原子性保证 |

### 8.2 睡眠事务设计（如果启用）

```
睡眠操作事务流程:
1. 验证是否可以睡觉 (CanSleep)
2. 记录睡眠前状态快照
3. 更新时间数据 (offset, weekDay, totalDays)
4. 触发睡眠后处理 (可选)
5. 标记数据变更 (isUpdate = true)

失败回滚:
- 步骤3失败 → 恢复时间数据快照
- 步骤4失败 → 可选择回滚或继续（睡眠后处理非关键）
```

### 8.3 并发控制

- 时间数据的读写在单个 goroutine（场景主循环）中执行，无并发问题
- 多玩家准备睡觉使用 map 存储，由场景主循环串行处理

---

## 9. 关键流程

### 9.1 场景初始化流程

```
┌─────────────────────────────────────────────────────────────────┐
│                    樱花校园场景初始化                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ 从DB加载存档数据 │
                    │ GetSakuraInfo() │
                    └────────┬────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ sakuraResource  │
                    │    Init()       │
                    └────────┬────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  SakuraMgr   │    │ Placement    │    │  TimeMgr     │ (新增)
│              │    │   Manager    │    │              │
└──────────────┘    └──────────────┘    └──────┬───────┘
                                               │
                                               ▼
                                    ┌──────────────────┐
                                    │ LoadData()       │
                                    │ 从 timeData 恢复 │
                                    │ 或使用默认值     │
                                    └──────────────────┘
```

### 9.2 时间同步流程

```
┌─────────────────────────────────────────────────────────────────┐
│                      客户端时间同步                              │
└─────────────────────────────────────────────────────────────────┘

玩家进入场景
      │
      ▼
┌─────────────────┐
│ 场景初始化完成   │
│ 发送 SceneInfo  │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  SnapshotMgr.Cache 包含 TimeInfo                                │
│  - nowDayTime: 当前秒数                                         │
│  - timeRatio: 时间比率                                          │
│  - timestamp: 场景时间戳                                        │
│  - townTimeInfo: { weekDay, totalDays }                        │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
客户端根据 timeRatio 和 timestamp 本地计算时间
定期通过 GetTime 接口校准
```

### 9.3 跨天流程对比

```
┌─────────────────────────────────────────────────────────────────┐
│                    小镇跨天流程（需睡眠）                         │
└─────────────────────────────────────────────────────────────────┘

时间流逝中 → elapsedDays > expectedDays? → Yes → onCrossDay()
                                                    │
                                                    ▼
                                          ┌─────────────────┐
                                          │ isCrossDay=true │
                                          │ TotalDays++     │
                                          │ WeekDay循环     │
                                          └────────┬────────┘
                                                   │
                                                   ▼
                                          时间暂停在4点
                                          等待玩家睡觉
                                                   │
                                                   ▼
                                          睡眠后跳到7点
                                          isCrossDay=false


┌─────────────────────────────────────────────────────────────────┐
│                 樱花校园跨天流程（自动循环）                       │
└─────────────────────────────────────────────────────────────────┘

时间流逝中 → elapsedDays > expectedDays? → Yes → onCrossDay()
                                                    │
                                                    ▼
                                          ┌─────────────────┐
                                          │ isCrossDay=true │
                                          │ TotalDays++     │
                                          │ WeekDay循环     │
                                          └────────┬────────┘
                                                   │
                                          enableSleep=false
                                                   │
                                                   ▼
                                          ┌─────────────────┐
                                          │ autoAdvanceDay()│
                                          │ isCrossDay=false│
                                          └────────┬────────┘
                                                   │
                                                   ▼
                                          时间继续从0点流逝
                                          （自动进入新的一天）
```

### 9.4 樱花校园时间生命周期

```
┌─────────────────────────────────────────────────────────────────┐
│                   樱花校园时间完整生命周期                        │
└─────────────────────────────────────────────────────────────────┘

[首次创建场景]
      │
      ▼
┌─────────────────┐
│ TimeMgr 初始化   │
│ TimeData = nil  │
│ 使用默认值:      │
│  - WeekDay = 0  │
│  - TotalDays = 1│
│  - 时间从配置的  │
│    初始时间开始  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 时间正常流逝     │◄────────────────────────┐
│ 跨天自动循环     │                          │
└────────┬────────┘                          │
         │                                    │
    [玩家离开场景]                             │
         │                                    │
         ▼                                    │
┌─────────────────┐                          │
│ SaveData()      │                          │
│ 保存:           │                          │
│  - LastStopTime │                          │
│  - WeekDay      │                          │
│  - TotalDays    │                          │
└────────┬────────┘                          │
         │                                    │
    [场景销毁]                                │
         │                                    │
    [玩家再次进入]                             │
         │                                    │
         ▼                                    │
┌─────────────────┐                          │
│ LoadData()      │                          │
│ 恢复:           │                          │
│  - 从LastStopTime│                         │
│    继续计时      │                          │
│  - WeekDay      │                          │
│  - TotalDays    │                          │
└────────┬────────┘                          │
         │                                    │
         └────────────────────────────────────┘
```

---

## 10. 依赖分析

### 10.1 代码依赖

```
time_mgr/time_mgr.go
    ├── common/config        (读取 TimeRatio 配置)
    ├── common/mtime         (获取现实时间)
    ├── common/proto         (协议结构)
    └── scene_server/internal/common (Resource 接口)

scene_impl.go
    ├── time_mgr             (新增依赖)
    ├── proto                (DBSaveSakuraInfo 扩展)
    └── sakura/              (现有依赖)
```

### 10.2 配置依赖

| 配置项 | 来源 | 说明 |
|--------|------|------|
| TimeRatio | CfgServerSetting | 全局时间比率 |
| GameDayTimeStart | CfgSceneInfo | 场景初始时间 |

---

## 11. 风险点和注意事项

### 11.1 兼容性风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 旧存档无 TimeData | 场景加载失败 | TimeData 为空时使用默认值初始化 |
| 协议变更 | 客户端不兼容 | 复用现有协议结构，无需客户端改动 |

### 11.2 性能考虑

- 时间计算为纯数学运算，性能开销可忽略
- 时间数据随场景存档周期性保存，无额外 IO

### 11.3 注意事项

1. **睡眠功能是否启用**：需要与策划确认樱花校园是否需要睡眠机制
2. **跨场景时间同步**：如果玩家在小镇和樱花校园之间切换，时间如何处理？
3. **NPC 日程联动**：樱花校园 NPC 是否需要根据时间改变行为？

---

## 12. 任务拆解

### 任务总览

| 编号 | 任务 | 工程 | 涉及文件 | 依赖 | 说明 |
|------|------|------|---------|------|------|
| T1 | 新增 SakuraTimeInfo 协议 | 协议工程 | `scene/scene.proto` | 无 | 新增 SakuraTimeInfo 消息，扩展 TimeInfo |
| T2 | 新增 DBSaveSakuraTimeData 协议 | 协议工程 | `scene/sakura.proto` 或 `db.proto` | 无 | 新增存储结构，扩展 DBSaveSakuraInfo |
| T3 | 运行协议生成脚本 | 协议工程 | `_tool_new/` | T1, T2 | 生成新的 pb.go 文件 |
| T4 | 扩展 TimeMgr 支持自动循环 | 业务工程 | `time_mgr.go`, `town_time.go` | T3 | 新增 enableSleep、sceneType 字段，修改跨天和输出逻辑 |
| T5 | 修改樱花校园场景初始化 | 业务工程 | `scene_impl.go` | T4 | 创建 TimeMgr 并加载数据 |
| T6 | 修改樱花校园数据保存 | 业务工程 | `scene_impl.go` | T5 | 保存时间数据到 DB |
| T7 | 添加时间同步到客户端 | 业务工程 | `snapshot_mgr.go` 或相关 | T5 | 场景信息中包含 TimeInfo.SakuraTimeInfo |
| T8 | 构建验证 | 业务工程 | - | T4-T7 | make build 通过 |
| T9 | 单元测试 | 业务工程 | `time_mgr_test.go` | T8 | 测试自动循环逻辑 |

### 详细任务描述

#### T1: 新增 SakuraTimeInfo 协议

**文件**: `../proto/old_proto/scene/scene.proto`

**改动内容**:
```protobuf
// 新增樱花校园时间信息
message SakuraTimeInfo {
    int32 weekDay = 1;     // 周几 (1-7)
    int32 totalDays = 2;   // 总天数
}

// 扩展 TimeInfo
message TimeInfo {
    int32 nowDayTime = 1;
    int32 timeRatio = 2;
    TownTimeInfo townTimeInfo = 3;
    int64 timestamp = 4;
    SakuraTimeInfo sakuraTimeInfo = 5;  // 新增
}
```

#### T2: 新增 DBSaveSakuraTimeData 协议

**文件**: `../proto/old_proto/scene/sakura.proto` 或 `db/db.proto`

**改动内容**:
```protobuf
// 新增樱花校园时间存储结构
message DBSaveSakuraTimeData {
    int32 weekDay = 1;
    int32 totalDays = 2;
    bool isCrossDay = 3;
}

// 扩展 DBSaveSakuraInfo
message DBSaveSakuraInfo {
    // ... 现有字段 ...
    int64 lastStopTime = 10;              // 新增：上次停止时的场景时间戳
    DBSaveSakuraTimeData timeData = 11;   // 新增：樱花校园时间数据
}
```

#### T4: 扩展 TimeMgr 支持自动循环

**文件**: `servers/scene_server/internal/ecs/res/time_mgr/time_mgr.go`, `town_time.go`

**改动内容**:
```go
// time_mgr.go - 新增字段
type TimeMgr struct {
    // ... 现有字段 ...
    enableSleep bool       // 是否启用睡眠暂停机制
    sceneType   SceneType  // 场景类型
}

// 新增构造函数
func NewTimeMgrForSakura(scene common.Scene) *TimeMgr

// town_time.go - 新增方法
func (t *TownTimeInfo) ToSakuraProto() *proto.SakuraTimeInfo
func (t *TimeMgr) autoAdvanceDay()  // 自动推进到新的一天

// 修改 clampTownTimestamp 支持自动循环
func (t *TimeMgr) clampTownTimestamp(townTimestamp int64) int64

// 新增樱花校园专用的加载/保存方法
func (t *TimeMgr) LoadSakuraData(lastStopTime int64, data *proto.DBSaveSakuraTimeData)
func (t *TimeMgr) SaveSakuraData() (int64, *proto.DBSaveSakuraTimeData)
```

#### T5: 修改樱花校园场景初始化

**文件**: `servers/scene_server/internal/ecs/scene/scene_impl.go`

**改动内容**:
```go
func (s *scene) sakuraResourceInit(saveInfo *proto.DBSaveSakuraInfo) error {
    // ... 现有初始化 ...

    // 新增：初始化时间管理器（樱花校园模式）
    timeMgr := time_mgr.NewTimeMgrForSakura(s)
    if timeMgr != nil {
        s.AddResource(timeMgr)
        timeMgr.LoadSakuraData(saveInfo.LastStopTime, saveInfo.TimeData)
    }

    return nil
}
```

#### T6: 修改樱花校园数据保存

**文件**: `servers/scene_server/internal/ecs/scene/scene_impl.go`

**改动内容**:
```go
func (s *scene) saveSakuraData() *proto.DBSaveSakuraInfo {
    // ... 现有保存 ...

    // 新增：保存时间数据
    if timeMgr, ok := common.GetResourceAs[*time_mgr.TimeMgr](s, common.ResourceType_TimeMgr); ok {
        saveInfo.LastStopTime, saveInfo.TimeData = timeMgr.SaveSakuraData()
    }

    return saveInfo
}
```

### 任务依赖图

```
T1 (SakuraTimeInfo协议)     T2 (DBSave协议)
       │                        │
       └───────────┬────────────┘
                   │
                   ▼
             T3 (协议生成)
                   │
                   ▼
         T4 (TimeMgr扩展)
                   │
                   ▼
         T5 (场景初始化)
                   │
          ┌────────┴────────┐
          ▼                 ▼
    T6 (数据保存)     T7 (时间同步)
          │                 │
          └────────┬────────┘
                   ▼
            T8 (构建验证)
                   │
                   ▼
            T9 (单元测试)
```

### 并行执行分析

| 批次 | 可并行任务 | 说明 |
|------|-----------|------|
| Batch 1 | T1, T2 | 两个协议扩展任务无依赖，可并行 |
| Batch 2 | T3 | 协议生成依赖 T1, T2 |
| Batch 3 | T4 | TimeMgr 扩展依赖 T3 |
| Batch 4 | T5 | 场景初始化依赖 T4 |
| Batch 5 | T6, T7 | 数据保存和时间同步可并行，都依赖 T5 |
| Batch 6 | T8 | 构建验证 |
| Batch 7 | T9 | 单元测试 |

---

## 13. 测试策略

### 13.1 单元测试

```go
// time_mgr_test.go
func TestTimeMgr_SakuraScene(t *testing.T) {
    // 1. 测试新场景初始化（TimeData 为空）
    // 2. 测试已存在场景加载（TimeData 有值）
    // 3. 测试时间计算正确性
    // 4. 测试跨天逻辑（如果启用）
}

func TestTimeMgr_DataMigration(t *testing.T) {
    // 测试旧存档（无 TimeData）能正常加载
}
```

### 13.2 集成测试

| 测试场景 | 预期结果 |
|---------|---------|
| 玩家进入樱花校园 | 收到正确的 TimeInfo |
| 玩家离开后重进 | 时间数据正确恢复 |
| 场景重启后加载 | 时间从上次保存点继续 |

### 13.3 兼容性测试

- 旧版客户端连接新版服务器
- 旧存档加载测试

---

## 14. 已确认需求

| 需求点 | 确认结果 |
|--------|---------|
| 睡眠功能 | ❌ 不启用，时间自动循环 |
| 跨天机制 | ✅ 支持，自动跨天继续 |
| NPC 行为 | 由决策系统控制，无需额外联动 |
| 跨场景同步 | 独立，不与小镇同步 |
| 离开时行为 | 暂停时间，保存当前时间戳 |
| 时间比率 | 与小镇相同，使用全局配置 |

---

## 15. 版本历史

| 版本 | 日期 | 作者 | 说明 |
|------|------|------|------|
| v1.0 | 2026-02-10 | Claude | 初始设计方案 |
| v1.1 | 2026-02-10 | Claude | 根据用户确认更新：不启用睡眠、自动循环跨天、离开时暂停 |
| v1.2 | 2026-02-10 | Claude | 协议设计优化：新增独立的 SakuraTimeInfo 字段，避免与 townTimeInfo 语义歧义 |
