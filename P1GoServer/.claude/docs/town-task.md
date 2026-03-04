# 小镇任务系统 (Town Task System)

## 概述

小镇任务系统是一个基于事件驱动的任务管理框架，用于跟踪玩家在小镇场景中的任务进度。系统采用观察者模式，通过事件触发来更新任务条件的完成状态。

## 核心文件

| 文件 | 路径 | 职责 |
|------|------|------|
| `town_task.go` | `servers/scene_server/internal/ecs/res/town/town_task.go` | TaskManager 任务管理器，Resource 实现 |
| `task.go` | `servers/scene_server/internal/common/town_task/task.go` | Task 任务结构体定义 |
| `task_condition.go` | `servers/scene_server/internal/common/town_task/task_condition.go` | 条件系统实现 |
| `task_event.go` | `servers/scene_server/internal/common/town_task/task_event.go` | 事件类型定义 |
| `types.go` | `servers/scene_server/internal/common/town_task/types.go` | 通用类型定义 |

## 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                       TaskManager (Resource)                     │
│  ┌─────────────────────┐    ┌─────────────────────────────────┐ │
│  │ observers           │    │ tasks                           │ │
│  │ map[EventType][]Obs │    │ map[stageId][]*Task             │ │
│  └─────────────────────┘    └─────────────────────────────────┘ │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    TriggerEvent(eventType, tType, tValue)
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                           Task                                   │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────────────────┐  │
│  │ Id       │  │ State    │  │ Condition (ConditionGroup)    │  │
│  │ StageId  │  │ IsUpdate │  │ ┌─────────────────────────┐   │  │
│  │ TaskId   │  │          │  │ │ []Condition             │   │  │
│  └──────────┘  └──────────┘  │ └─────────────────────────┘   │  │
│                              └───────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 任务状态 (TaskState)

```go
const (
    TaskState_None       TaskState = iota
    TaskState_InProgress           // 进行中
    TaskState_Completed            // 已完成（全部条件满足）
    TaskState_HasEnded             // 已结束（有条件未完成但已过期）
)
```

## 事件分类 (EventCategory)

| 分类 | 值 | 说明 | 条件类型 |
|------|---|------|----------|
| State | 1 | 状态类，只需触发一次即完成 | `StateCondition` |
| Progress | 2 | 进度类，需要累积达到目标值 | `ProgressCondition` |
| AutoTime | 3 | 倒计时类，需要等待时间到达 | `AutoTimeCondition` |

## 条件组类型 (ConditionGroupType)

```go
const (
    ConditionGroup_All ConditionGroupType = iota // 所有条件都满足
    ConditionGroup_Any                           // 任意一个条件满足
)
```

## 核心 API

### TaskManager

```go
// 创建任务管理器
func NewTaskManager(scene common.Scene) *TaskManager

// 添加任务
func (tm *TaskManager) AddTask(cfgStageId, cfgTaskId uint32) *Task

// 触发事件（更新任务进度）
func (tm *TaskManager) TriggerEvent(eventType EventType, tType, tValue, autoCompTm int32)

// 触发自动完成事件（倒计时任务检查）
func (tm *TaskManager) TriggerAutoTaskEvent(param, param2 int64)

// 创建下一个任务
func (tm *TaskManager) CreateNextTasks(curTaskId uint32, nextStageIds []int32, nextTaskIds []int32)

// 设置倒计时结束时间
func (tm *TaskManager) SetCountdownTime(eventType EventType, valueTm int64, param int32)

// 更新倒计时（睡眠加速）
func (tm *TaskManager) UpdateSpeedTime(second int64)

// 设置条件参数
func (tm *TaskManager) SetConditionParam(eventType EventType, param map[string]string)

// 持久化
func (tm *TaskManager) LoadFromData(saveData *proto.DBSaveTownTaskInfo)
func (tm *TaskManager) ToSaveData() *proto.DBSaveTownTaskInfo

// 同步
func (tm *TaskManager) ToProto() *proto.TownTaskData
func (tm *TaskManager) ToAllProto() *proto.TownTaskData
```

### Task

```go
// 创建任务
func NewTask(id int32, cfgStageId, cfgTaskId uint32) *Task

// 初始化条件
func (t *Task) InitTaskCondition(stageId int32)

// 事件通知
func (t *Task) OnNotify(event *EventData) bool

// 状态检查
func (t *Task) IsCompleted() bool
```

## 事件类型 (EventType)

### 状态类事件
```go
EventType_OpenPhoneSMS                  = 10101  // 打开手机App看短信
EventType_PhoneBooth                    = 10102  // 和公共电话亭交互
EventType_BookMotelRoom                 = 10105  // 租下一间汽车旅馆房间
EventType_BuyItemZhangPeng              = 20201  // 买一个帐篷
EventType_PlacementAssetItemPackStation = 140201 // 放置包装站
EventType_PutZhangpeng                  = 150401 // 放置帐篷
EventType_PhoneBooth4                   = 150601 // 和公共电话亭交互4
EventType_CellWithNpcCompleted          = 160101 // 与NPC完成交易
EventType_ChatWithMrMing                = 170201 // 和指定NPC对话（param2=npc_cfg_id）
EventType_BuyUpRoom                     = 170301 // 购买指定资产（param2=assetId）
// ... 更多见 task_event.go
```

### 进度类事件
```go
EventType_AddInventoryItem        = 10103  // 获得指定藏匿物
EventType_CellAnythingCompleted   = 150301 // 完成一笔交易
EventType_DoThreeTransaction      = 150501 // 累计完成了三笔交易（存量检测）
EventType_UnlockCustomersNRC      = 150801 // 解锁指定数量的顾客
EventType_OwnItem                 = 170101 // 拥有指定数量的某种物品（存量检测）
EventType_UnlockCustomersRC       = 170102 // 已解锁指定数量的顾客（存量检测）
// ... 更多见 task_event.go
```

### 倒计时类事件
```go
EventType_WaitContainer = 20701 // 等待藏匿点布置任务完成
```

## 条件参数常量

```go
const (
    TaskConditionParam_Cell_NPCId    = "cell_npc_id"    // 交易npcId
    TaskConditionParam_Cell_ItemId   = "cell_item_id"   // 交易道具Id
    TaskConditionParam_Cell_ItemKey  = "cell_item_key"  // 交易道具key
    TaskConditionParam_Cell_ItemNum  = "cell_item_num"  // 交易道具数量
    TaskConditionParam_Cell_Location = "cell_location"  // 交易位置
    TaskConditionParam_Cell_TimeSpan = "cell_time_span" // 交易持续时间(秒)
)
```

## 使用示例

### 1. 获取任务管理器
```go
taskMgr, ok := common.GetResourceAs[*town.TaskManager](scene, common.ResourceType_TaskManager)
if !ok {
    return
}
```

### 2. 触发任务事件
```go
// 触发状态类事件
taskMgr.TriggerEvent(town_task.EventType_BookMotelRoom, 0, 1, 0)

// 触发进度类事件（购买道具）
taskMgr.TriggerEvent(town_task.EventType_AddInventoryItem, itemId, quantity, 0)
```

### 3. 设置倒计时
```go
// 设置藏匿点任务倒计时结束时间
taskMgr.SetCountdownTime(town_task.EventType_WaitContainer, endTimestamp, 0)
```

### 4. 设置条件参数（交易任务）
```go
params := map[string]string{
    town_task.TaskConditionParam_Cell_NPCId:    "123",
    town_task.TaskConditionParam_Cell_ItemId:   "456",
    town_task.TaskConditionParam_Cell_TimeSpan: "3600",
}
taskMgr.SetConditionParam(town_task.EventType_CellWithNpcCompleted, params)
```

## 配置表依赖

| 配置表 | 获取函数 | 说明 |
|--------|----------|------|
| CfgTownTask | `config.GetCfgTownTaskById(id)` | 任务配置 |
| CfgTownTaskStage | `config.GetCfgTownTaskStageById(id)` | 任务阶段配置 |
| CfgTownTaskTarget | `config.GetCfgTownTaskTargetById(id)` | 任务目标/条件配置 |

### 配置表字段

**CfgTownTask**:
- `Id`: 任务ID
- `TaskStages`: 任务阶段列表
- `NextTask`: 下一个任务列表
- `TaskOpen`: 是否自动开启 (1=自动开启)

**CfgTownTaskStage**:
- `Id`: 阶段ID
- `TaskId`: 所属任务ID
- `Targets`: 目标条件列表
- `NextTaskStages`: 下一阶段列表
- `ActiveTask`: 完成后激活的任务
- `TaskStageOpen`: 是否自动开启 (1=自动开启)
- `Exp`: 完成奖励经验
- `EventType`: 阶段事件类型
- `EventParam`: 阶段事件参数

**CfgTownTaskTarget**:
- `Id`: 目标ID (同时作为 EventType)
- `Param1`: 目标值
- `Param2`: 触发类型（如道具ID）

## 与其他系统的集成

### 联系人系统
```go
// 任务完成时通知联系人系统
contactMgr.OnTaskCompleted(task.CfgStageId)
```

### 小镇管理器
```go
// 任务完成时给玩家加经验
townMgr.AddTownExp(exp)
```

### 短信系统
```go
// 通过短信创建任务
taskMgr.CreateTaskByMessage(params)
```

### 道具栏系统
```go
// 检查玩家道具是否满足任务条件
townInventoryComp.Inner().GetItemQuantity(itemId)
```

## 任务生命周期

```
1. 注册阶段 (registerAllTask)
   - 从配置表读取所有任务
   - 注册到 observers 观察者列表

2. 初始化阶段 (initOpenTasks)
   - 检查 taskOpen=1 的任务
   - 自动创建开启任务

3. 运行阶段
   - TriggerEvent 触发事件
   - onNotify 更新条件进度
   - onTaskFinish 处理任务完成
   - CreateNextTasks 创建后续任务

4. 持久化阶段
   - LoadFromData 从数据库加载
   - ToSaveData 保存到数据库
```

## 进度类事件：增量检测 vs 存量检测

进度类事件分为两种检测模式：

| 模式 | 说明 | 进度更新方式 | 典型场景 |
|------|------|-------------|----------|
| 增量检测 | 只计算接取任务后的增量 | `c.Current += event.TriggerValue` | 完成N笔交易（从接任务开始计） |
| 存量检测 | 计算历史累计总量 | `c.Current = event.TriggerValue` | 拥有N个道具、累计完成N笔交易 |

### 存量检测事件列表

```go
// task_condition.go:473-476
case EventType_OwnItem, EventType_UnlockCustomersRC, EventType_UnlockCustomersNRC, EventType_DoThreeTransaction:
    // 存量检测：覆盖当前进度
    c.Current = uint32(event.TriggerValue)
```

| 事件类型 | 事件ID | 说明 |
|---------|--------|------|
| `EventType_OwnItem` | 170101 | 拥有指定数量的某种物品 |
| `EventType_UnlockCustomersRC` | 170102 | 好感度解锁了指定数量顾客 |
| `EventType_UnlockCustomersNRC` | 150801 | 好感度解锁了指定数量顾客（另一个版本） |
| `EventType_DoThreeTransaction` | 150501 | 累计完成了指定次数交易 |

### 实现存量检测任务的完整步骤

**核心要点：存量检测 = 任务创建时检查 + 后续事件更新**

#### 步骤 1：定义事件类型
```go
// task_event.go
EventType_DoThreeTransaction EventType = 150501 // 累计完成了三笔交易
```

#### 步骤 2：注册为进度类条件
```go
// task_condition.go - AddCondition 方法
case EventType_DoThreeTransaction:
    condition := NewProgressCondition(event, uint32(event), triggerType, target)
    cg.Conditions = append(cg.Conditions, condition)
```

#### 步骤 3：添加到存量检测 case
```go
// task_condition.go - OnEvent 方法
case EventType_OwnItem, EventType_UnlockCustomersRC, EventType_DoThreeTransaction:
    c.Current = uint32(event.TriggerValue) // 覆盖而非累加
```

#### 步骤 4：存储累计值并持久化
```go
// 在相关 Manager 中添加字段
completedTradeCount int32

// 在 SaveData/LoadData 中处理持久化
```

#### 步骤 5：触发事件时传递累计值
```go
// 错误 ❌ - 增量方式
taskMgr.TriggerEvent(town_task.EventType_DoThreeTransaction, 0, 1, 0)

// 正确 ✅ - 存量方式
t.AddCompletedTradeCount()
taskMgr.TriggerEvent(town_task.EventType_DoThreeTransaction, 0, t.GetCompletedTradeCount(), 0)
```

#### 步骤 6：任务创建时检查存量（关键！）
```go
// town_task.go - checkAnyPlayerCompleted 方法
case town_task.EventType_DoThreeTransaction:
    type tradeCountProvider interface {
        GetCompletedTradeCount() int32
    }
    if res, ok := tm.GetScene().GetResource(common.ResourceType_TradeManager); ok && res != nil {
        if provider, ok := res.(tradeCountProvider); ok {
            count := provider.GetCompletedTradeCount()
            if count >= targetCfg.GetParam1() {
                targetIds[uint32(targetId)] = town_task.NewEventData(...)
            }
        }
    }
```

### 常见错误

| 错误 | 后果 | 解决方案 |
|------|------|----------|
| 只实现事件触发，未实现任务创建时检查 | 接取任务前完成的不计入进度 | 在 `checkAnyPlayerCompleted` 中添加检查 |
| 触发时传递增量值而非累计值 | 进度被覆盖为1 | 传递 `GetCompletedTradeCount()` |
| 未添加到存量检测 case | 进度累加而非覆盖 | 在 `OnEvent` 的 switch 中添加 |
| 累计值未持久化 | 重启后丢失 | 在 SaveData/LoadData 中处理 |
| 遗漏功能相似的事件类型 | 部分任务无法正常完成 | 在 `task_event.go` 中搜索所有同类事件，逐一确认 |

### 新增存量检测事件的检查清单

**添加新的存量检测事件时，必须完成以下所有步骤：**

1. **搜索所有相关事件**
   - 在 `task_event.go` 中搜索功能相似的事件（如 `UnlockCustomers` 会有 `RC` 和 `NRC` 两个版本）
   - 不要只看已有代码中提到的事件，要主动搜索同类事件

2. **确认每个事件的实现状态**
   ```bash
   # 搜索事件在各文件中的使用情况
   grep -r "EventType_XXX" servers/scene_server/internal/
   ```

3. **逐一核对三处代码**
   - [ ] `task_condition.go` - `OnEvent` 方法的存量检测 switch case
   - [ ] `town_task.go` - `checkAnyPlayerCompleted` 方法的 switch case
   - [ ] `task_condition.go` - `AddCondition` 方法（注册为进度类条件）

4. **验证构建和测试**
   - 构建通过后，实际测试任务是否能在接取时立即完成

**教训：功能相似的事件容易遗漏，如 `EventType_UnlockCustomersRC` (170102) 和 `EventType_UnlockCustomersNRC` (150801) 都是"解锁顾客"，但事件ID不同，必须分别处理。**

## 注意事项

1. **事件触发顺序**: 先更新条件进度，再检查任务完成，最后创建下一任务

2. **倒计时任务**: 需要外部定时调用 `TriggerAutoTaskEvent` 来检查完成

3. **睡眠加速**: 调用 `UpdateSpeedTime(seconds)` 来加速倒计时任务

4. **条件参数**: 部分任务（如交易任务）需要先设置条件参数才能正确触发

5. **同步标记**: 修改任务状态后需要调用 `SetSync()` 以触发数据同步

6. **任务ID**: `Task.Id` 是自增的唯一标识，`CfgTaskId` 和 `CfgStageId` 是配置表ID

7. **存量检测任务**: 必须同时实现"任务创建时检查"和"事件触发时更新"两个触发点
