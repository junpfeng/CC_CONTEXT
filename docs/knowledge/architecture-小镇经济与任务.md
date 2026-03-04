# 小镇经济与任务架构

> 小镇等级经验、交易订单流程、任务事件驱动、订单投放、产品管理、垃圾刷新、供货商负债、公共容器。

## 核心 Resource 全景

```
TownScene Resources
├─ TownMgr              小镇全局状态（经验、等级、ATM）
├─ TownNpcMgr           NPC 管理（会面、订单状态、持久化）
├─ TownAssetManager     房产资产（摆件、门权限）
├─ TradeManager          交易订单（生成、状态机、完成）
├─ TownProductManager   产品管理（激活、定价、上架）
├─ TaskManager           任务系统（事件驱动、观察者）
├─ OrderDropManager     订单投放（定时投放到容器）
├─ TownGarbageManager   垃圾系统（区域刷新、拾取）
├─ VendorManager         供货商（负债、还债）
└─ TownPublicContainerManager  公共容器（藏匿点）
```

## TownMgr — 小镇全局状态

```go
TownMgr {
    atmDeposit     int64    // ATM 存款（中央金库）
    townLevel      int32    // 当前等级
    townExp        int64    // 累计经验
    nextLevelExp   int64    // 下一级所需经验
    townNowDayLevel int32   // 当日新增等级
    townNowDayExp  int64    // 当日新增经验
    PlayerMap      map      // 在线玩家及进入时间
}
```

### 等级计算

- 配置表 `CfgTownLevel` 定义每级 `UpNeedExp`
- `getTownLevelByExp()` 二分查找当前等级和下一级阈值
- 任务完成 / 交易完成时调用 `AddTownExp()` 更新经验并自动升级

## 交易系统（TradeManager）

### 订单生命周期

```
checkAndGenerateOrders()
├─ 检查 NPC 联系人是否解锁
├─ 检查 NPC CD（现实世界时间，不随游戏时间推进）
├─ 验证偏好时间窗口 & 偏好日期
└─ 产品选择 → 订单计算 → 创建订单

订单状态机：
NONE → WAITING_RESPONSE → WAITING_TRADE → COMPLETED
                                       └→ EXPIRED
```

### 订单数据结构

```go
Order {
    state         TownTradeOrderState  // 订单状态
    startTime     int64     // 现实世界时间戳（秒）
    endTime       int64
    itemId        int32     // 道具 ID
    entryKey      uint64    // 词条 Key（压缩编码）
    productNum    int32     // 产品数量
    amount        int32     // 订单金额
    tradeLocation int32     // 交易地点 ID
    tradeDay      int32     // 交易应发生的小镇天数（超时判断）
    isDealerTrade bool      // 是否经销商代理交易
}
```

### 产品选择与订单计算

**产品选择器**：基于 NPC 吸引力加权随机，`NormalizedEnjoy + PriceAdjustment`，只从 `IsSelling == true` 的产品中选择。

**订单计算器三阶段**：
1. 基础预算 = `BaseQuantity × RankMultiplier × (1 + 好感度调整)`
2. 数量 = `预算 / 产品价格`（向下取整）
3. 金额 = `数量 × 实际价格`

### 顾客信息

```go
CustomerInfo {
    favorability   int32   // NPC 好感度
    budgetThisWeek int32   // 本周已用预算
    budgetLimit    int32   // 周预算上限
    cdEndTime      int64   // CD 结束时间戳（秒，现实世界时间）
    weekNumber     int32   // 预算周期编号（用于重置）
}
```

- 预算每周自动重置（`checkAndResetBudget()` 检查周数）
- CD 使用现实世界时间，不受游戏时间暂停影响
- 顾客最多一个订单

### 经销商订单处理

- `getCustomerDealer()` 查询 NPC 是否被经销商代理
- `CheckDealerInventory()` 验证经销商库存
- 库存不足 → NPC 进入 CD；库存充足 → 经销商代付订单

## 产品系统（TownProductManager）

```
二层嵌套结构：
activeProducts[itemID][entryKey] → ProductInfo {
    ItemID, EntryKey, IsSelling, Price, SuggestedPrice
}
```

| 操作 | 说明 |
|------|------|
| `AddProduct(itemID, entryKey)` | 验证道具类型 + 计算建议价格 |
| `SetProductInfo(itemID, entryKey, isSelling, price)` | 上架/改价，触发任务事件 |
| `GetSellingProductList()` | 交易系统获取可售产品 |

## 任务系统（TaskManager）

### 事件驱动架构

```
TaskManager.observers[EventType] → Task[]

TriggerEvent(EventType, tType, tValue)
├─ 查找所有监听该事件的 Task
├─ Task.OnNotify(EventData)
├─ 若有变化：
│  ├─ onTaskFinish() → 更新状态
│  ├─ 若完成：AddTownExp() + ContactManager.OnTaskCompleted()
│  └─ SetSync()
└─ CheckAllIncompleteTasks()（存量检测）
```

### 任务阶段结构

```
Task (进行中的任务实例)
├── Id           运行时唯一 ID
├── CfgTaskId    配置表任务 ID
├── CfgStageId   当前阶段 ID
├── Condition    条件集合
│   └── ConditionGroup[]
│       ├── EventType / TargetId / Progress
│       ├── CountdownTime（倒计时结束时间戳）
│       └── IsCompleted / HasEnded
└── State        InProgress / Completed / HasEnded
```

### 事件注册

```
registerAllTask():
遍历 CfgTownTask → 每个阶段的 targets[]
→ observers[EventType] = []{CfgStageId, CfgTaskId}
```

### 任务生成流程

1. **首次进入**：`initOpenTasks()` 自动创建 `taskOpen==1` 的任务
2. **任务链**：完成时 `CreateNextTasks()` 检查 `nextTaskStages[]` + `activeTask[]`
3. **短信触发**：`CreateTaskByMessage()` 通过容器 ID 创建任务

### 条件完成判定

- 全部条件：逻辑 AND（所有条件都需完成）
- 倒计时：`CountdownTime <= NowTime`
- 完成类型：`AllCompleted` / `InProgress` / `NotAllCompleted`

## 订单投放系统（OrderDropSystem）

### 投放任务

```go
OrderDropTask {
    TaskID    uint64           // 内存 ID（递增）
    GoodsList []*OrderGoodsInfo // 商品列表
    OwnerPos  *Vector3         // 小镇所有者位置
    DropTime  int64            // 投放时间戳（秒）
    DropMsgId int32            // 完成后短信 ID
}
```

### 系统 Tick

```
OrderDropSystem.Update()
├─ 检查玩家在线（无玩家 → 暂停）
├─ 玩家回线 → AdjustTasksTime(timeDiff)
├─ 遍历投放任务
│  ├─ now >= DropTime → executeDrop(task)
│  └─ 成功 → 移除 + 发送短信
```

### 容器选择算法

```
calculateDropContainer(containerMgr, ownerPos):
1. 获取所有可投放空容器，计算距离
2. 空容器 <= 1 → 不投放
3. 按距离排序
4. 去掉最近 1 个
5. 去掉最远 ⌊剩余/2⌋ 个
6. 中间范围随机选择
```

目的：中等距离范围内随机，防止固定地点被猜破。

## 垃圾系统（TownGarbageManager）

```go
TownGarbageManager {
    areaGarbageMap map[int32]*areaGarbageInfo  // 区域 → 垃圾列表
    entityAreaMap  map[uint64]int32            // entityID → areaID
}
```

### 刷新算法

```
refreshAreaGarbage(cfg):
├─ 最大刷新数 = ⌊maxCount × 20%⌋
├─ 可刷新数 = min(maxCount - 当前数, 最大刷新数)
├─ 按权重随机选择垃圾 objID
├─ 随机位置（极坐标均匀分布）
└─ 创建场景实体
```

刷新时机：首次进入场景、睡觉后。

## 供货商系统（VendorManager）

```go
Vendor {
    Cfg     *CfgTownOrder
    DebtNum uint32  // 当前负债值
}
```

### 还债流程

```
HandleVendorRepayDebt(container)
├─ 检查容器内 CashItemID 数量
├─ 扣现金 = min(现金数量, 负债)
├─ 负债清零 → 移出 DebtVendorIds
└─ 触发还债短信 + 更新好感度
```

## 公共容器（TownPublicContainerManager）

```go
PublicContainer {
    cfg       *CfgDeadDrop
    openerId  uint64                    // 打开者 ID
    isOpen    bool
    container *TownInventoryComp        // 内部道具栏
}
```

- OrderDropSystem 通过 `AddItemByQuantity()` 投放商品
- 容器满时投放失败（下次 Tick 重试）
- `canOrderDrop` 标志控制可用性

## Resource 协作关系

```
交易订单生成：
TradeManager.checkAndGenerateOrders()
├─ TownProductManager.GetSellingProductList()
├─ ProductSelector.SelectProduct()
├─ OrderCalculator.Calculate()
├─ TownNpcMgr.SetNpcOrderMeeting()
└─ OrderDropManager.AddOrderDropTask()

交易完成：
TradeManager.CompleteOrder()
├─ TownMgr.AddTownExp()
├─ ContactManager.OnTradeCompleted()
└─ TaskManager.TriggerEvent(EventType_TradeCompleted)

任务完成链：
TaskManager.TriggerEvent() → onTaskFinish()
├─ TownMgr.AddTownExp()
├─ ContactManager.OnTaskCompleted()
└─ CreateNextTasks()
```

## 时间管理

| 类型 | 用途 |
|------|------|
| **现实世界时间** | NPC CD、订单有效期、投放时间 |
| **游戏内时间** | NPC 日程、交易时间、睡眠刷新 |

OrderDropSystem 在无玩家时暂停，回线时补偿倒计时。

## 关键设计原则

1. **事件驱动 + 观察者**：任务系统与业务系统解耦，新增任务只需配置表
2. **配置驱动**：NPC、产品、任务等从配置表加载
3. **两层索引**：`NpcMap + PoliceNpcMap`、`areaGarbageMap + entityAreaMap`、`activeProducts[itemId][entryKey]`
4. **脏标记同步**：`SetSync()` 增量更新客户端，`SetSave()` 持久化 DB

## 关键文件路径

| 文件/目录 | 内容 |
|----------|------|
| `ecs/res/town/town.go` | TownMgr（等级、经验、ATM） |
| `ecs/res/town/town_npc.go` | TownNpcMgr（NPC 管理） |
| `ecs/res/town/town_asset.go` | TownAssetManager（房产摆件） |
| `ecs/res/town/town_task.go` | TaskManager（任务事件驱动） |
| `ecs/res/town/town_vendor.go` | VendorManager（供货商负债） |
| `ecs/res/town/town_container.go` | TownPublicContainerManager |
| `ecs/res/town/order_drop.go` | OrderDropManager |
| `ecs/res/trade/trade_mgr.go` | TradeManager（订单核心） |
| `ecs/res/trade/trade_order.go` | Order 数据结构 |
| `ecs/res/trade/trade_info.go` | CustomerInfo |
| `ecs/res/trade/product_selector.go` | 产品选择器 |
| `ecs/res/trade/order_calculator.go` | 订单计算器 |
| `ecs/res/town_product/` | TownProductManager |
| `ecs/res/town_garbage/` | TownGarbageManager |
| `ecs/system/order_drop/` | OrderDropSystem |
