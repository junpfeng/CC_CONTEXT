# 数据库系统指南

本文档描述 P1GoServer 项目的数据库架构、存取流程和调试方法。所有代码路径均相对于 `P1GoServer/` 目录。

---

## 文档概述

| 内容 | 使用时机 |
|------|----------|
| 数据库架构（Section 1-5） | Phase 2 数据库设计 |
| 调试工具（Section 6-7） | Phase 4 实现、问题排查 |
| 存盘限制（Section 9） | Phase 6 审查、容量检查 |

### 相关文档

| 文档 | 用途 |
|------|------|
| `PROTO.md` | 协议工程规范、序列化格式 |
| `TEST.md` | Migration 测试、数据一致性测试 |
| `REVIEW.md` | DB 容量限制审查清单 |
| `SKILL.md` | Phase 7 经验沉淀（数据库相关经验沉淀到本文档） |

---

## 1. 架构概述

### 1.1 三层缓存模型

```
┌─────────────────────────────────────────────────────────────────────┐
│                         scene_server                                 │
│              (ECS 组件内存，如 TownNpcMgr)                            │
└──────────────────────────────┬──────────────────────────────────────┘
                               ↓ db_entry.SaveXxx() / GetXxx()
┌──────────────────────────────┴──────────────────────────────────────┐
│                          db_server                                   │
│                    (内存缓存 + dirtyFlag)                            │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  DataHandler → Table → RowMgr → Row                         │    │
│  │       │                           │                         │    │
│  │       │                           ├─ dirtyFlag (脏标记)     │    │
│  │       │                           ├─ lastRead (读取时间)    │    │
│  │       │                           └─ lastWrite (写入时间)   │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                          ↓ loop() 每秒检查                           │
└──────────────────────────────┬──────────────────────────────────────┘
                               ↓
        ┌──────────────────────┴──────────────────────┐
        ↓                                              ↓
┌───────────────────┐                       ┌─────────────────────┐
│      Redis        │                       │      MongoDB        │
│   (缓存层)        │  ←── 读取时回写 ──→   │    (持久化层)       │
│                   │                       │                     │
│  TTL: 7天         │                       │  永久存储           │
│  格式: BSON 二进制 │                       │  格式: BSON 文档    │
└───────────────────┘                       └─────────────────────┘
```

### 1.2 数据流向

| 操作 | 流程 |
|------|------|
| **读取** | db_server 内存 → Redis → MongoDB (读取时回写) |
| **写入** | 更新内存 + 设置 dirtyFlag → 删除 Redis → loop() 异步写入 MongoDB |

### 1.3 读取时回写

"读取时回写"是指：从 MongoDB 读取到数据后，自动写入 Redis 缓存，以便下次读取时直接从 Redis 获取。

```
读取请求
    ↓
1. 查 Redis ─────→ 命中 → 返回
    ↓ 未命中
2. 查 MongoDB ───→ 找到数据
    ↓
3. 回写 Redis ←── 把数据写入 Redis（读取时回写）
    ↓
4. 返回数据
```

**代码位置**: `servers/db_server/internal/data/row_mgr.go:189-222`

```go
func (r *RowMgr) getRowFromDB(rowKey *RowKey) (*Row, error) {
    // 1. 先查 Redis
    row, err := r.getRowFromRedis(rowKey)
    if err == nil && row != nil {
        return row, nil  // Redis 命中，直接返回
    }

    // 2. Redis 未命中，查 MongoDB
    row, err = r.getRowFromMgo(rowKey)
    if row == nil {
        return nil, errorx.ErrDbSvrRowDataIsNil
    }

    // 3. 读取时回写：把 MongoDB 的数据写入 Redis
    err = r.setRowToRedis(row)
    if err != nil {
        log.Errorf("setRowToRedis failed...")  // 回写失败不影响返回
    }

    return row, nil
}
```

**目的**:
- **提高性能**: 下次读取直接从 Redis 获取，避免查询 MongoDB
- **减少 DB 压力**: 热点数据缓存在 Redis，减少 MongoDB 查询次数

### 1.4 DB Entry 与 DB Handler

这是数据库访问的两层抽象：

```
┌─────────────────────────────────────────────────────────┐
│  scene_server / logic_server (业务服务器)                │
│                                                         │
│   db_entry.SaveTownInfo()   ← DB Entry (调用入口)       │
│   db_entry.GetTownInfo()                                │
└────────────────────┬────────────────────────────────────┘
                     │ RPC 调用
                     ↓
┌────────────────────┴────────────────────────────────────┐
│  db_server (数据库服务器)                                │
│                                                         │
│   DataHandler → Table → RowMgr  ← DB Handler (处理层)   │
│        │                                                │
│        ├── 内存缓存管理                                  │
│        ├── 脏数据标记                                    │
│        └── Redis/MongoDB 读写                           │
└─────────────────────────────────────────────────────────┘
```

| 概念 | 位置 | 职责 |
|------|------|------|
| **DB Entry** | `common/db_entry/` | 业务层调用入口，封装 RPC 调用，提供 `SaveXxx()`/`GetXxx()` 接口 |
| **DB Handler** | `servers/db_server/internal/data/` | db_server 内部处理层，管理缓存、脏标记、实际读写 |

**简单理解**：
- **DB Entry** = 业务代码"怎么调"（API 接口）
- **DB Handler** = db_server"怎么存"（实现细节）

**代码示例**：

```go
// 1. 业务代码调用 DB Entry
db_entry.SaveTownInfo(roleId, townInfo)

// 2. DB Entry 内部通过 RPC 调用 db_server
dbSvrHandler.Save(tableName, rowKey, data)

// 3. db_server 的 DataHandler 处理请求
handler.Set(rowKey, data)  // 更新内存 + 设置 dirtyFlag
```

**代码位置**：
- DB Entry: `common/db_entry/town.go` - `SaveTownInfo()`, `GetTownIfno()`
- DB Handler: `common/db/db_handler.go` - `Save()`, `Load()`
- DataHandler: `servers/db_server/internal/data/data_handler.go`

### 1.5 db_server 数据处理层

db_server 数据处理层的核心作用是**集中管理数据的缓存和持久化**，避免业务服务器直接操作数据库。

```
业务服务器 (scene_server, logic_server...)
    │
    │  不直接访问 Redis/MongoDB
    ↓
db_server 数据处理层
    │
    ├── 1. 内存缓存    ← 最快，热点数据
    ├── 2. 脏数据合并  ← 多次修改只写一次
    ├── 3. 异步批量写入 ← 减少 IO 压力
    └── 4. 读取优化    ← 三级缓存穿透
    │
    ↓
Redis / MongoDB
```

**主要职责**：

| 职责 | 说明 | 收益 |
|------|------|------|
| **内存缓存** | 热点数据保存在内存 | 读取延迟 < 1ms |
| **写入合并** | 1秒内多次修改只产生一次 MongoDB 写入 | 减少 90%+ 写入量 |
| **异步持久化** | loop() 每秒检查脏数据批量写入 | 业务不阻塞 |
| **缓存一致性** | 写入时删除 Redis，防止脏读 | 数据正确 |
| **统一入口** | 所有服务器通过 RPC 访问 | 便于监控、限流 |

**为什么需要 db_server**（而非业务服务器直连数据库）：

| 直连数据库 | 通过 db_server |
|------------|----------------|
| 每次修改都直接写 MongoDB | 写入合并，批量持久化 |
| 多个服务器同时读写，缓存不一致 | 统一缓存管理，数据一致 |
| 无法做写入合并，IO 压力大 | 脏标记 + 异步写入，IO 可控 |
| 难以统一监控和限流 | 集中管理，便于运维 |

**核心组件**：

```
DataHandler (入口)
    ↓
Table (表管理)
    ↓
RowMgr (行管理)
    │
    ├── Row 内存缓存
    │     ├── data (实际数据)
    │     ├── dirtyFlag (是否需要写入)
    │     ├── lastRead (上次读取时间)
    │     └── lastWrite (上次写入时间)
    │
    ├── getRowFromRedis() / setRowToRedis()
    └── getRowFromMgo() / saveRowToMgo()
```

**代码位置**：`servers/db_server/internal/data/`
- `data_handler.go` - DataHandler 入口
- `table.go` - 表管理
- `row_mgr.go` - 行管理，核心缓存逻辑
- `row.go` - 单行数据结构

---

## 2. 配置位置

### 2.1 数据库名称

**定义文件**: `orm/mongo/const.go`

```go
const (
    DBName = "fl_test_tmp_"  // 数据库名前缀
)
```

**生成函数**: `orm/mongo/helper.go`

```go
func GetDatabaseName(clusterUnique uint32) string {
    return fmt.Sprintf("%s%d", DBName, clusterUnique)
    // 例如: fl_test_tmp_6 (当 clusterUnique=6)
}
```

### 2.2 表版本号

**定义文件**: `orm/mongo/const.go`

```go
const (
    TableVersion = "20250521"  // 表名后缀版本
    DBVersion    = "20250521"
)
```

**另一处定义**: `common/db_entry/account.go`

```go
const VERSION = "20250521"
```

### 2.3 表名定义

| 表名 | 定义位置 | 生成函数 |
|------|----------|----------|
| `account_table_20250521` | `common/db_entry/account.go:12` | `GetAccountCollection()` |
| `role_table_20250521` | `common/db_entry/role.go:38` | `getRoleCollection()` |
| `town_table_20250521` | `common/db_entry/town.go:13` | `GetTownCollection()` |
| `sakura_table_20250521` | `common/db_entry/sakura.go:13` | `GetSakuraCollection()` |
| `nick_name_table_20250521` | `common/db_entry/nick_name.go:13` | `getNickNameCollection()` |

### 2.4 Redis Key 格式

```
db_server:<表名>:<主键值>
```

示例:
```
db_server:town_table_20250521:10000001
db_server:role_table_20250521:10000001
```

---

## 3. 核心数据结构

### 3.1 ID 关系

```
account_id (账号ID)
    │
    └── role_list: [role_id_1, role_id_2, ...]
           │
           └── role_id (角色ID)
                  │
                  ├── role_table (角色数据)
                  ├── town_table (小镇数据)
                  └── sakura_table (樱花校园数据)
```

### 3.2 主要数据表

| 表名 | 主键 | 数据结构 | 说明 |
|------|------|----------|------|
| `account_table` | `account_id` | `DBSaveAccountInfo` | 账号信息 |
| `role_table` | `role_id` | `DBSaveRoleInfo` | 角色信息 |
| `town_table` | `role_id` | `DBSaveTownInfo` | 小镇数据 |
| `sakura_table` | `role_id` | `DBSaveSakuraInfo` | 樱花校园 |

### 3.3 DBSaveTownInfo 结构

**定义位置**: `common/proto/db_pb.go`

```go
type DBSaveTownInfo struct {
    RoleId              uint64
    Message             *DBSaveTownMessage
    TaskInfo            *DBSaveTownTaskInfo
    PublicContainerData *DBSaveAllTownPublicContainerData
    TimeData            *DBSaveTimeData
    AtmDeposit          int32
    AssetList           []*DBSaveTownAssetData
    // ... 其他字段 ...

    // 小镇 NPC 相关数据
    TradeProxyInfo      []*TradeProxyInfo      // 交易代理信息
    ScheduleInfo        []*ScheduleInfo        // 日程信息
    TownNpcData         []*TownNpcSaveData     // NPC 基础数据
}
```

---

## 4. 存取流程

### 4.1 读取流程

```
scene_server 调用 db_entry.GetTownIfno(roleId)
    ↓
dbSvrHandler.Load() 发送 RPC 到 db_server
    ↓
db_server.DataHandler.Load()
    ↓
Table.load() → RowMgr.getRow()
    ↓
┌─ 1. getRowFromMemory() ─────────────────────┐
│      内存命中 → 返回                         │
└─────────────────────────────────────────────┘
    ↓ 未命中
┌─ 2. getRowFromRedis() ──────────────────────┐
│      Redis 命中 → 返回                       │
└─────────────────────────────────────────────┘
    ↓ 未命中
┌─ 3. getRowFromMgo() ────────────────────────┐
│      MongoDB 查询 → 回写 Redis → 返回        │
└─────────────────────────────────────────────┘
```

**关键代码路径**:
- `common/db_entry/town.go:16` - `GetTownIfno()`
- `common/db/db_handler_logic.go:66` - `doLoad()`
- `servers/db_server/internal/data/row_mgr.go:343` - `getRow()`

### 4.2 写入流程

```
scene_server 调用 db_entry.SaveTownInfo(townInfo)
    ↓
dbSvrHandler.Save() 发送 RPC 到 db_server
    ↓
db_server.DataHandler.Save()
    ↓
Table.save() → RowMgr.updateRow()
    ↓
┌─ 1. 更新内存缓存 ───────────────────────────┐
│      row.updateData(data)                    │
│      row.dirtyFlag = true                    │
└─────────────────────────────────────────────┘
    ↓
┌─ 2. 删除 Redis 缓存 ────────────────────────┐
│      deleteRowFromRedis() (防止脏读)         │
└─────────────────────────────────────────────┘
    ↓
┌─ 3. loop() 每秒检查 ────────────────────────┐
│      flush() → 批量写入 MongoDB              │
│      collection.ReplaceOne() with upsert     │
│      清除 dirtyFlag                          │
└─────────────────────────────────────────────┘
```

**关键代码路径**:
- `common/db_entry/town.go:46` - `SaveTownInfo()`
- `common/db/db_handler_logic.go:22` - `doSave()`
- `servers/db_server/internal/data/row_mgr.go:92` - `flush()`

---

## 5. 小镇 NPC 数据详解

这三个字段存储在 `DBSaveTownInfo` 中，都是数组结构，以 `npc_cfg_id` / `cfg_id` 作为逻辑主键。

### 5.1 TradeProxyInfo (交易代理信息)

**定义位置**: `common/proto/npc_pb.go:4938`

```go
type TradeProxyInfo struct {
    NpcCfgId         int32     // NPC配置ID (主键)
    EmployerEntityId int32     // 雇主实体ID
    TradeStatus      int32     // 交易状态
    TradeNpcList     []uint64  // 交易NPC列表
    TradedCount      int32     // 已交易次数
    CoolDownEndTime  int64     // 冷却结束时间(毫秒)
    Balance          int32     // 余额
}
```

**场景代码路径**:
- 组件: `servers/scene_server/internal/ecs/com/cnpc/trade_proxy_comp.go`
- 序列化: `ToSaveProto()` (line 171)
- 反序列化: `LoadFromProto()` (line 183)
- 资源管理: `servers/scene_server/internal/ecs/res/town/town_npc.go`

### 5.2 ScheduleInfo (日程信息)

**定义位置**: `common/proto/scene_pb.go:51970`

```go
type ScheduleInfo struct {
    OrderedMeeting int32  // 预约会面ID
    MeetingState   int32  // 会面状态
    MeetingPointId int32  // 会面点ID
    NpcCfgId       int32  // NPC配置ID (主键)
}
```

**场景代码路径**:
- 组件: `servers/scene_server/internal/ecs/com/cnpc/schedule_comp.go`
- 序列化: `ToSaveProto()` (line 154)
- 反序列化: `LoadFromProto()` (line 164)

### 5.3 TownNpcSaveData (NPC基础数据)

**定义位置**: `common/proto/npc_pb.go:4589`

```go
type TownNpcSaveData struct {
    CfgId           int32  // NPC配置ID (主键，注意字段名是 cfg_id)
    OutDurationTime int64  // 外出持续时间
    TradeOrderState int32  // 交易订单状态
    IsDealerTrade   bool   // 是否商人交易
}
```

**场景代码路径**:
- 组件: `servers/scene_server/internal/ecs/com/cnpc/town_npc.go`
- 序列化: `ToSaveProto()` (line 64)

### 5.4 数据加载/保存流程

**加载** (`scene_impl.go`):
```go
case *common.TownSceneInfo:
    saveInfo := s.dbEntry.GetTownIfno(sceneType.OwnerRole)
    // ...
    townNpcMgr.LoadTradeProxyData(saveInfo.TradeProxyInfo)
    townNpcMgr.LoadScheduleData(saveInfo.ScheduleInfo)
    townNpcMgr.LoadTownNpcData(saveInfo.TownNpcData)
```

**保存** (`save.go`):
```go
townInfo.TradeProxyInfo = townNpcMgr.ToSaveTradeProxyList()
townInfo.ScheduleInfo = townNpcMgr.ToSaveScheduleList()
townInfo.TownNpcData = townNpcMgr.ToSaveTownNpcDataList()
```

---

## 6. 调试工具

### 6.1 db_modifier 工具

**位置**: `tools/db_modifier/`

**安装**:
```bash
cd P1GoServer/tools/db_modifier
python3 -m venv venv
./venv/bin/pip install pymongo redis
```

**常用命令**:

```bash
# 查找角色ID
./venv/bin/python db_modifier.py -action find-by-account -account 100002
./venv/bin/python db_modifier.py -action find-by-name -name "玩家昵称"

# 查看数据
./venv/bin/python db_modifier.py -role 10000001 -action show
./venv/bin/python db_modifier.py -role 10000001 -action npc-list

# 查看指定 NPC
./venv/bin/python db_modifier.py -role 10000001 -action npc-show \
  -field trade_proxy_info -npc 1001

# 更新 NPC 数据
./venv/bin/python db_modifier.py -role 10000001 -action npc-update \
  -field trade_proxy_info -npc 1001 -updates '{"trade_status":2}'

# 删除 NPC 数据
./venv/bin/python db_modifier.py -role 10000001 -action npc-delete \
  -field trade_proxy_info -npc 1001

# 清除所有 NPC 数据
./venv/bin/python db_modifier.py -role 10000001 -action clear-all

# 带 Redis 清除
./venv/bin/python db_modifier.py -role 10000001 -action clear-all \
  -redis "localhost:6379"
```

### 6.2 MongoDB 直接查询

```bash
# 连接 MongoDB
mongosh mongodb://localhost:27017

# 切换数据库
use fl_test_tmp_6

# 查看所有集合
show collections

# 查询小镇数据
db.town_table_20250521.findOne({role_id: 10000001})

# 查询指定字段
db.town_table_20250521.findOne(
  {role_id: 10000001},
  {trade_proxy_info: 1, schedule_info: 1, town_npc_data: 1}
)

# 更新 NPC 数据
db.town_table_20250521.updateOne(
  {role_id: 10000001},
  {$set: {"trade_proxy_info.0.trade_status": 2}}
)

# 删除指定 NPC
db.town_table_20250521.updateOne(
  {role_id: 10000001},
  {$pull: {trade_proxy_info: {npc_cfg_id: 1001}}}
)
```

### 6.3 Redis 缓存操作

```bash
# 连接 Redis
redis-cli

# 查看缓存
GET "db_server:town_table_20250521:10000001"

# 删除缓存 (修改 MongoDB 后必须执行)
DEL "db_server:town_table_20250521:10000001"

# 批量删除
redis-cli KEYS "db_server:town_table_20250521:*" | xargs redis-cli DEL
```

---

## 7. 常见问题排查

### 7.1 修改数据不生效

**原因**: 修改 MongoDB 后未清除 Redis 缓存

**解决**:
```bash
# 清除 Redis 缓存
redis-cli DEL "db_server:town_table_20250521:<role_id>"
```

### 7.2 玩家在线时修改被覆盖

**原因**: scene_server 内存中有数据，定期保存会覆盖 MongoDB

**解决**: 确保玩家离线后再修改数据

### 7.3 数据库连接失败

**检查项**:
1. MongoDB 地址是否正确
2. 数据库名是否正确 (默认 `fl_test_tmp_6`)
3. clusterUnique 配置是否匹配

### 7.4 数据丢失

**可能原因**:
1. db_server 重启时内存中有未持久化的脏数据 (最多丢失 1 秒)
2. MongoDB 写入失败

**排查**:
```bash
# 查看 db_server 日志
tail -f bin/log/db_server.log | grep -i "flush\|save\|error"
```

---

## 8. 代码索引

| 功能 | 文件路径 |
|------|----------|
| DB 配置常量 | `orm/mongo/const.go` |
| DB 接口定义 | `common/db/types.go` |
| DB Handler 实现 | `common/db/db_handler.go`, `db_handler_logic.go` |
| DB Entry (业务层) | `common/db_entry/*.go` |
| db_server 数据处理 | `servers/db_server/internal/data/` |
| 小镇数据保存 | `servers/scene_server/internal/ecs/scene/save.go` |
| 小镇数据加载 | `servers/scene_server/internal/ecs/scene/scene_impl.go` |
| NPC 资源管理 | `servers/scene_server/internal/ecs/res/town/town_npc.go` |
| 交易代理组件 | `servers/scene_server/internal/ecs/com/cnpc/trade_proxy_comp.go` |
| 日程组件 | `servers/scene_server/internal/ecs/com/cnpc/schedule_comp.go` |
| NPC 组件 | `servers/scene_server/internal/ecs/com/cnpc/town_npc.go` |

---

## 9. 存盘限制

### 9.1 数据库层限制

#### MongoDB 限制

| 限制项 | 限制值 | 说明 |
|--------|--------|------|
| 单文档大小 | **16 MB** | BSON 文档最大限制，超过会写入失败 |
| 字段名长度 | 128 字节 | 字段名不能超过此长度 |
| 嵌套深度 | 100 层 | 文档嵌套层级限制 |
| 索引数量 | 64 个/集合 | 单个集合最多创建的索引数 |

#### Redis 限制

| 限制项 | 限制值 | 定义位置 |
|--------|--------|----------|
| 缓存 TTL | **7 天** | `servers/db_server/internal/data/row_mgr.go:20` |
| 单个 Key 大小 | 512 MB | Redis 内置限制 |

```go
const cacheTTL = 7 * 24 * 60 * 60  // 7天，单位：秒
```

#### db_server 限制

| 限制项 | 限制值 | 定义位置 |
|--------|--------|----------|
| 表数量上限 | 256 | `servers/db_server/internal/data/types.go:13` |
| 单次查询字段数 | 100 | `servers/db_server/internal/data/types.go:18` |
| 内存缓存写超时 | 1800 秒 | `servers/db_server/internal/data/types.go:15` |
| 内存缓存读超时 | 1800 秒 | `servers/db_server/internal/data/types.go:16` |
| 索引状态缓存 TTL | 24 小时 | `servers/db_server/internal/data/index_manager.go:20` |
| 索引创建锁超时 | 30 秒 | `servers/db_server/internal/data/index_manager.go:23` |

```go
// servers/db_server/internal/data/types.go
const (
    TableSlotSize = 99 * 99
    TableNum = 256              // 最多支持256个表
    memoryWriteTimeout = 1800   // 内存缓存写超时时间（秒）
    memoryReadTimeout  = 1800   // 内存缓存读超时时间（秒）
    MaxFieldsNum = 100          // 单次查询字段数量上限
)
```

### 9.2 数据结构定义

#### 表与结构体映射

| 表名 | 数据结构 | 定义位置 |
|------|----------|----------|
| `account_table` | `DBSaveAccountInfo` | `common/proto/db_pb.go:980` |
| `role_table` | `DBSaveRoleInfo` | `common/proto/db_pb.go:10055` |
| `town_table` | `DBSaveTownInfo` | `common/proto/db_pb.go:13232` |
| `sakura_table` | `DBSaveSakuraInfo` | `common/proto/db_pb.go:10929` |

命名规则：`xxx_table` → `DBSaveXxxInfo`

#### 存储格式

| 位置 | 格式 | 说明 |
|------|------|------|
| 业务进程内存 | Go struct | 带 `bson`/`json` tag |
| RPC 传输 | Protobuf bytes | `proto.Marshal()` 序列化 |
| db_server 内存 | `[]byte` | Row.Data 字段 |
| Redis | `[]byte` | Protobuf 二进制 |
| MongoDB | BSON 文档 | 字段名由 `bson` tag 决定 |

### 9.3 游戏容器限制

游戏内各类容器的容量限制由配置表定义，位于 `common/config/` 目录。

#### 背包相关

| 配置项 | 配置文件 | 说明 |
|--------|----------|------|
| 背包容量 | `cfg_backpackinit.go` | `maxSize` 字段 |
| 背包类型 | `cfg_backpackinit.go` | 格子数量 / 承重 |
| 容器槽位 | `cfg_containerslots.go` | 槽位验证器配置 |
| 默认容量 | `cfg_container.go` | `defaultCapacity` 字段 |

#### NPC 相关

| 配置项 | 配置文件 | 说明 |
|--------|----------|------|
| NPC 最大控制数 | `config_kv.go` | `MaxNpcControlNum` |
| 交通 NPC 上限 | `config_kv.go` | `TransportationNpcMax` |
| NPC 创建规则 | `cfg_npccreaterule.go` | `GetNpcMaxCount()` |

#### 建筑相关

| 配置项 | 配置文件 | 说明 |
|--------|----------|------|
| 房屋容量 | `cfg_house.go` | `buildLimit` 字段 |
| 组件占用 | `cfg_buildingcomponents.go` | `buildValue` 字段 |
| 家具占用 | `cfg_residencefurniture.go` | `buildValue` 字段 |

### 9.4 存盘注意事项

#### 文档大小监控

MongoDB 单文档 16MB 限制是硬性限制，需要注意：

1. **数组字段增长**：如 `trade_proxy_info`、`schedule_info` 等数组字段持续增长可能导致文档超限
2. **嵌套结构膨胀**：复杂嵌套结构会增加序列化后的大小
3. **监控建议**：定期检查大文档，设置告警

```javascript
// MongoDB 查询大文档
db.town_table_20250521.find().forEach(function(doc) {
    var size = Object.bsonsize(doc);
    if (size > 10 * 1024 * 1024) {  // 10MB 预警
        print("Large doc: role_id=" + doc.role_id + ", size=" + size);
    }
});
```

#### 缓存一致性

1. **写入时删除 Redis**：防止读到旧数据
2. **Redis TTL 7 天**：超过 7 天未访问的数据会从 Redis 过期
3. **读取时回写**：从 MongoDB 读取后自动写入 Redis

#### 内存超时清理

db_server 会清理超时的内存缓存：
- 写超时：1800 秒（30 分钟）未写入
- 读超时：1800 秒（30 分钟）未读取

超时的数据会被从内存中移除，下次访问时从 Redis/MongoDB 重新加载。
