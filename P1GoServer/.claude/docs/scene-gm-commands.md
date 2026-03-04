# Go 场景服务 GM 命令文档

## 概览

- **命令总数**: 40 条
- **命令格式**: `/ke* gm <command> <params...>`
- **代码位置**: `servers/scene_server/internal/net_func/gm/`
- **开关配置**: `Global.AllowGm = true` 时启用
- **RPC命令码**: 110 (`GMOperateReq`)

## 参数格式

支持两种参数格式：
1. **空格分隔**: `/ke* gm add_town_item 10000 5 8`
2. **键值对**: `/ke* gm add_town_item itemId=1001|quantity=5|cellIndex=2`

---

## 按功能分类索引

| 分类 | 命令数 | 关键词 |
|------|--------|--------|
| [时间管理](#时间管理) | 2 | set_time, do_town_sleep |
| [物品管理](#物品管理) | 2 | add_town_item, add_town_product |
| [任务系统](#任务系统) | 4 | clear/init_town_task, trigger_task, jump_to_task |
| [NPC生成与位置](#npc生成与位置) | 3 | add_town_npc, add_simple_npc, set_npc_pos |
| [NPC交互与对话](#npc交互与对话) | 2 | dialog_to_town_npc, end_dialog_with_town_npc |
| [NPC联系人与好感度](#npc联系人与好感度) | 2 | unlock_npc_contact, add_npc_favorability |
| [NPC行为控制](#npc行为控制) | 2 | npc_pursuit, npc_vision |
| [警察系统](#警察系统) | 7 | make/remove_police, set_wanted, suspicion相关 |
| [交易系统](#交易系统) | 5 | add_trade_order, dealer_trade, npc_order_meeting等 |
| [资产与家具](#资产与家具) | 3 | buy_town_asset, add/remove_town_furniture |
| [商店与银行](#商店与银行) | 2 | buy_town_shop, add_atm_deposit |
| [藏匿点（公共容器）](#藏匿点) | 2 | add/get_town_public_container |
| [消息系统](#消息系统) | 1 | add_town_msg |
| [门系统](#门系统) | 2 | door_permission, door_state |
| [测试](#测试) | 1 | test_panic |

---

## 时间管理

### set_time
设置当天游戏时间。
```
/ke* gm set_time <秒数>
```
- `秒数`: 0-86400，例如 25200 = 07:00
- 函数: `handleSetTimeGM` @ `time.go`

### do_town_sleep
执行小镇睡眠逻辑（跳到下一天）。
```
/ke* gm do_town_sleep
```
- 函数: `handleDoTownSleepGM` @ `town.go`

---

## 物品管理

### add_town_item
添加普通物品到玩家库存。
```
/ke* gm add_town_item <itemId> [quantity=1] <cellIndex>
/ke* gm add_town_item itemId=1001|quantity=5|cellIndex=2
```
- `itemId`: 物品配置ID
- `quantity`: 数量，默认1，上限10000
- `cellIndex`: 格子索引（必填，>=0）
- 函数: `handleAddTownItemGM` @ `town.go`

### add_town_product
添加产品类道具（支持自定义词条）。
```
/ke* gm add_town_product <itemId> <quantity> <cellIndex> [entries]
/ke* gm add_town_product itemId=1001|quantity=5|cellIndex=0|entries=1,2,3
```
- `entries`: 逗号分隔词条ID，不指定则用配置默认词条
- 仅限 `ProductionTownItemType` 类型道具
- 函数: `handleAddTownProductGM` @ `town.go`

---

## 任务系统

### clear_town_task
清空所有小镇任务。
```
/ke* gm clear_town_task
```
- 函数: `handleClearTownTaskGM` @ `town.go`

### init_town_task
重新初始化小镇任务。
```
/ke* gm init_town_task
```
- 函数: `handleInitTownTaskGM` @ `town.go`

### handler_trigger_task
触发小镇任务事件。
```
/ke* gm handler_trigger_task <eventType> [param1] [param2] [param3]
```
- `eventType`: 任务事件类型ID（如 10102）
- 函数: `handleTriggerTaskGM` @ `town.go`

### jump_to_task
直接跳转到指定任务。
```
/ke* gm jump_to_task <taskId>
```
- 函数: `handleJumpToTaskGM` @ `town.go`

---

## NPC生成与位置

### add_town_npc
在玩家位置创建小镇NPC（带AI决策组件、对话组件）。
```
/ke* gm add_town_npc <townNpcCfgId>
```
- 使用 `CfgTownNpc` 配置
- 自动创建 GSS 决策模板 `npc_dialog`
- 函数: `handleAddTownNpcItem` @ `town.go`

### add_simple_npc
在玩家位置创建简单NPC（无AI）。
```
/ke* gm add_simple_npc
```
- 函数: `handleAddSimpleNpcGM` @ `town.go`

### set_npc_pos
设置NPC位置和旋转。
```
/ke* gm set_npc_pos <cfgId> <x> <y> <z> [rx] [ry] [rz]
```
- `cfgId`: NPC配置ID
- `x y z`: 世界坐标
- `rx ry rz`: 旋转角度（可选，默认0）
- 函数: `handleSetNpcPosGM` @ `town.go`

---

## NPC交互与对话

### dialog_to_town_npc
主动向NPC发起对话（通过AI决策 feature_dialog_req）。
```
/ke* gm dialog_to_town_npc <npcCfgId> [dialogId]
```
- 函数: `handleDialogToTownNpcGM` @ `town.go`

### end_dialog_with_town_npc
结束与NPC的对话（通过AI决策 feature_dialog_finish_req）。
```
/ke* gm end_dialog_with_town_npc <npcCfgId>
```
- 函数: `handleEndDialogWithTownNpcGM` @ `town.go`

---

## NPC联系人与好感度

### unlock_npc_contact
解锁NPC为联系人。
```
/ke* gm unlock_npc_contact <npcId>
```
- 仅小镇场景可用
- 函数: `handleUnlockNpcContactGM` @ `town.go`

### add_npc_favorability
增加/减少NPC好感度。
```
/ke* gm add_npc_favorability <npcId> <delta>
```
- `delta`: 正数增加，负数减少
- 仅小镇场景可用
- 函数: `handleAddNpcFavorabilityGM` @ `town.go`

---

## NPC行为控制

### npc_pursuit
让NPC追击目标。
```
/ke* gm npc_pursuit <npcCfgId> [targetId]
```
- 不指定 `targetId` 则追击玩家自己
- `targetId=0` 取消追击
- 通过 `feature_pursuit_entity_id` 和 `feature_state_pursuit` 控制AI
- 函数: `handleNpcPursuitGM` @ `town.go`

### npc_vision
标记NPC视野内有当前玩家。
```
/ke* gm npc_vision <cfgId>
```
- `cfgId=0` 表示没有NPC看到玩家
- 调用 `VisionSystem.UpdateVisionByProto`
- 函数: `handleNpcVisionGM` @ `town.go`

---

## 警察系统

### make_police
将NPC设置为警察。
```
/ke* gm make_police <npcCfgId>
```
- 已有警察组件则更新，否则新建
- 函数: `handleMakePoliceGM` @ `town.go`

### remove_police
移除NPC的警察身份。
```
/ke* gm remove_police <npcCfgId>
```
- 函数: `handleRemovePoliceGM` @ `town.go`

### set_wanted
设置玩家通缉等级。
```
/ke* gm set_wanted <playerId> <wantedLevel>
```
- 通过 `NpcPoliceSystem.SetWantedLevel` 设置
- 函数: `handleSetWantedGM` @ `town.go`

### get_police_info
获取警察NPC信息（日志输出）。
```
/ke* gm get_police_info <npcCfgId>
```
- 输出: is_police, arresting_player, suspicion_count, suspicion_threshold
- 函数: `handleGetPoliceInfoGM` @ `town.go`

### set_suspicion_threshold
设置NPC警察的警戒阈值。
```
/ke* gm set_suspicion_threshold <npcCfgId> <threshold>
```
- 函数: `handleSetSuspicionThresholdGM` @ `town.go`

### get_suspicion_info
获取NPC警察的警戒信息（日志输出）。
```
/ke* gm get_suspicion_info <npcCfgId>
```
- 输出: suspicion_count, threshold, suspicion_players
- 函数: `handleGetSuspicionInfoGM` @ `town.go`

### clear_suspicion
清空NPC警察的警戒列表。
```
/ke* gm clear_suspicion <npcCfgId>
```
- 函数: `handleClearSuspicionGM` @ `town.go`

---

## 交易系统

### add_trade_order
强制创建交易订单。
```
/ke* gm add_trade_order <npcId> <productId> <productNum> <amount> <entryIds> [isDealerOrder]
```
- `entryIds`: 逗号分隔词条ID（如 `1,2,3`）
- `isDealerOrder`: `1`/`true` 创建经销商订单（可选）
- 函数: `handleAddTradeOrderGM` @ `town.go`

### npc_order_meeting
触发NPC订单会议。
```
/ke* gm npc_order_meeting <npcCfgId> <meetingId> <pointId>
```
- 设置NPC日程组件的预约会议
- 函数: `handleNpcOrderMeetingGM` @ `town.go`

### get_trade_location_occupied
获取所有交易地点占用情况（日志输出）。
```
/ke* gm get_trade_location_occupied
```
- 函数: `handleGetTradeLocationOccupiedGM` @ `town.go`

### get_all_trade_orders
获取所有交易订单信息（日志输出）。
```
/ke* gm get_all_trade_orders
```
- 函数: `handleGetAllTradeOrdersGM` @ `town.go`

### dealer_trade
模拟经销商与客户的交易。
```
/ke* gm dealer_trade <dealerNpcId> <customerNpcId>
```
- 函数: `handleDealerTradeGM` @ `town.go`

---

## 资产与家具

### buy_town_asset
购买小镇资产（房屋等）。
```
/ke* gm buy_town_asset <assetId>
```
- 函数: `handleBuyTownAssetGM` @ `town.go`

### add_town_furniture
在玩家前方1米处添加家具。
```
/ke* gm add_town_furniture <assetId> <cfgId>
```
- 函数: `handleAddTownFurnitureGM` @ `town.go`

### remove_town_furniture
移除指定ID的家具。
```
/ke* gm remove_town_furniture <entityId>
```
- 函数: `handleRemoveTownFurnitureGM` @ `town.go`

---

## 商店与银行

### buy_town_shop
从商店购买商品。
```
/ke* gm buy_town_shop <goodsId1> <num1> [goodsId2] [num2] ...
/ke* gm buy_town_shop goodsId=1001|num=5|goodsId=1002|num=3
```
- 参数成对出现（goodsId + num）
- 函数: `handleBuyTownShopGM` @ `town.go`

### add_atm_deposit
增加银行账户存款。
```
/ke* gm add_atm_deposit <amount>
```
- `amount` 必须大于0
- 函数: `handleAddATMDepositGM` @ `town.go`

---

## 藏匿点

### add_town_public_container
从道具栏放入道具到公共藏匿点。
```
/ke* gm add_town_public_container <containerId> <fromCellIndex> <itemId> <quantity> <toCellIndex>
```
- 函数: `handleAddTownPublicContainerGM` @ `town.go`

### get_town_public_container
从公共藏匿点取出道具到道具栏。
```
/ke* gm get_town_public_container <containerId> <fromCellIndex> <itemId> <quantity> <toCellIndex>
```
- 函数: `handleGetTownPublicContainerGM` @ `town.go`

---

## 消息系统

### add_town_msg
添加小镇短信。
```
/ke* gm add_town_msg <msgId> [contentVars]
```
- `contentVars`: `|` 分隔的 key=value 对，如 `taskId=3001|npcId=4001|content=Hello`
- 函数: `handleAddTownMsgGM` @ `town.go`

---

## 门系统

### door_permission
设置/清除门权限。
```
/ke* gm door_permission <entityId> <permission> <isClear>
```
- `permission`: `inside`/`in` 或 `outside`/`out`
- `isClear`: `true`/`false`/`1`/`0`/`yes`/`no`
- 函数: `handleDoorPermissionGM` @ `town.go`

### door_state
改变门状态。
```
/ke* gm door_state <entityId> <state>
```
- `state`: `open_in`/`in`/`inside` | `open_out`/`out`/`outside` | `close`/`closed`
- 函数: `handleDoorStateGM` @ `town.go`

---

## 测试

### test_panic
触发 panic，用于测试崩溃恢复。
```
/ke* gm test_panic
```
- 位置: `gm.go` → `GmOperate` switch-case 中直接 `panic("test panic")`
