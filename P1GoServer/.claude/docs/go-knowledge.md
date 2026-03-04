# Go 服务端核心知识

> 合并自项目 learned/：ECS 框架、性能经验、项目规范、Bug 模式。

## 一、ECS 框架

### 核心接口

```go
// Entity = ID + 组件列表
entity.ID() uint64
entity.GetComponent(comType) Component

// Component = 纯数据 + 脏标记
comp.SetSync()   // 需同步到客户端
comp.SetSave()   // 需持久化到数据库

// System = 逻辑处理，33ms tick
sys.OnBeforeTick() → sys.Update() → sys.OnAfterTick()

// Resource = 场景级全局组件（管理器）
res.ResourceType() ResourceType
```

### Tick 流程（33ms 一帧）

```
scene.tick()
  ├─ frame++
  ├─ [所有系统] OnBeforeTick()
  ├─ [所有系统] Update()       # 按 SystemType 枚举顺序执行
  ├─ [所有系统] OnAfterTick()
  └─ doSaveData()
```

原则：数据系统先执行，NetUpdate（网络同步）**总是最后**。

### ComponentMap 存储

- O(1) 查找：`scene.GetComponent(comType, entityID)`
- 批量遍历：`scene.ComList(comType)` — 连续内存，缓存友好
- 交换删除保持数组连续性

### 组件数据同步模式

```go
// 1. 结构体添加字段
type TownNpcComp struct {
    common.ComponentBase
    tradeOrderState proto.TownTradeOrderState
}

// 2. Setter 调用 SetSync()（无变化不同步）
func (t *TownNpcComp) SetTradeOrderState(state proto.TownTradeOrderState) {
    if t.tradeOrderState == state { return }
    t.tradeOrderState = state
    t.SetSync()
}

// 3. ToProto / ToSaveProto / LoadFromProto 三件套同步更新
```

### 开发规则

- 新组件 → `ecs/com/c<name>/`，实现 Component 接口
- 新系统 → `ecs/system/<name>/`，实现 System 接口
- 新资源 → `ecs/res/<name>/`，实现 Resource 接口
- 新请求处理 → `net_func/<domain>/<handler>.go`

## 二、项目规范

### 配置系统

| 前缀 | 说明 | 打配置时 |
|------|------|----------|
| `cfg_*.go` | 自动生成 | 会被清理重建 |
| `config_*.go` | 手动维护 | 保留不变 |

配置扩展开发：创建 `config_build_xxx.go` → 在 `config_build.go` 的 `afterLoadConfig()` 中调用。

### Proto 字段添加流程

1. 修改 proto 文件（`resources/proto/scene/*.proto` 或 `base/*.proto`）
2. 执行 `/proto-gen go`
3. 修改 Go 代码：Component 添加字段 → ToProto/ToSaveProto/LoadFromProto 三件套

注意：字段号**不能复用只能递增**；Go 字段名自动转驼峰 `is_dealer_trade` → `IsDealerTrade`

### Redis 规范

| 类型 | TTL 策略 |
|------|---------|
| 缓存（有 MongoDB 回源） | 必须设 TTL（建议 2h） |
| 持久化（纯 Redis） | 不能设 TTL |

## 三、性能经验

### 已踩的坑

| 问题 | 根因 | 解法 |
|------|------|------|
| 22,287 goroutine 死锁 | RLock 内调 RLock（sceneMgr） | 公共方法不互调，拆无锁私有方法 |
| 数据修改后查询仍是旧值 | 网格缓存标志跨帧残留 | 修改时立即 `invalidateCache()` |
| 196GB/4h allocs | 全量遍历所有实体同步 | 实体级脏检查 `syncDirtyEntities` map |
| 全量遍历网格 | 未区分脏/干净网格 | `dirtyGridIds` 列表 |

### DB 优化数据

- BulkWrite：`SetOrdered(false)` + 500 条批量
- redisKey 拼接比 `fmt.Sprintf` 快 3-5 倍
- flush 快照：读锁 memcpy，写锁 flag 清理，`dirtyVersion` 防并发丢失

## 四、Bug 模式库（Go 端）

| 模式 | 症状 | 预防 |
|------|------|------|
| **SetSync/SetSave 遗漏** | 客户端未同步 / 重启后数据丢失 | 修改 Component 字段后立即检查 |
| **ToProto 三件套不同步** | 数据保存/加载/同步不完整 | 新增字段必须同步更新三个方法 |
| **网格缓存残留** | 修改后查询仍是旧值 | 修改处立即清缓存 |
| **RWMutex 重入死锁** | 服务卡死无响应 | 公共方法不互调，拆内部无锁函数 |
| **Proto 字段编号冲突** | 反序列化数据错乱 | 新字段总用最大编号 + 1 |
| **配置字段遗漏** | 新增配置项部分端读不到 | 修改 Excel 后 `/config-gen` 重新生成 |
