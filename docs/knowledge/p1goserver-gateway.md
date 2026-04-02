# P1GoServer Gateway 网关服务

> 网关服务的架构设计、消息路由、连接管理、事件系统等核心逻辑。

## 一、整体架构

Gateway 是客户端与后端服务集群之间的代理层，**不处理任何游戏业务逻辑**，只负责连接管理和消息转发。

```
客户端 ──TCP──> Gateway ──RPC──> Proxy ──RPC──> Logic/Scene/Mail/Match/...
                   │
                   ├── RegisterServer（服务注册与发现）
                   └── Redis（Token 验证、账号绑定、状态上报）
```

**关键特点**：
- 所有后端通信经由 Proxy 中转，不直接连接后端服务
- 每个 Gateway 实例由注册中心分配唯一标识（`selfUnique`）
- 单事件循环 + 事件通道实现无锁并发

## 二、代码结构

```
servers/gateway_server/
├── cmd/
│   ├── main.go             # 启动入口
│   ├── config.go           # TOML 配置加载
│   └── initialize.go       # Handler 和服务器创建
├── internal/
│   ├── domain/             # 核心业务逻辑（无锁串行化）
│   │   ├── gateway.go       # GatewayServer 主体（事件循环）
│   │   ├── builder.go       # GatewayBuilder（Runnable 接口）
│   │   ├── user_mgr.go      # 用户管理（在线/离线/重连）
│   │   ├── logic_mgr.go     # Logic 服务器管理（用户分配）
│   │   ├── event.go         # 所有事件定义（IGatewayEvent 实现）
│   │   ├── types.go         # UserInfo/UserSceneInfo/ClientCallInfo
│   │   └── errors.go        # 错误定义
│   ├── service/            # RPC Handler 层
│   │   ├── gateway_handler.go        # 认证/心跳/进入游戏
│   │   ├── forward_handler.go        # 转发 Handler 基类
│   │   ├── scene_handler.go          # Scene 转发
│   │   ├── logic_handler.go          # Logic 转发（拦截 EnterScene）
│   │   ├── mail_handler.go           # Mail 转发
│   │   ├── match_handler.go          # Match 转发
│   │   ├── generic_handler.go        # 通用转发（Bbs/Relation/Voxel）
│   │   ├── backend_push_handler.go   # 后端推送处理
│   │   └── proxy_conn_handler.go     # Proxy 握手
│   └── repository/         # Redis 操作
│       ├── account_repo.go  # Token/Logic/Gateway 绑定
│       ├── state_repo.go    # 在线人数上报
│       └── redis_key.go     # Redis Key 常量
└── docs/                   # 服务内部文档
```

## 三、核心模块

### 3.1 GatewayServer（事件循环主体）

文件：`internal/domain/gateway.go`

```go
type GatewayServer struct {
    selfUnique    uint32                       // 本网关唯一标识
    eventChan     chan IGatewayEvent            // 事件通道（串行化）
    registerEntry *register.RegisterClient     // 注册中心连接
    proxyEntry    *proxy_entry.ProxyEntry      // Proxy 连接管理
    userMgr       *UserMgr                     // 用户管理器
    logicMgr      *LogicMgr                    // Logic 服务器管理
    stateRepo     *repository.StateRepository  // 状态上报
    accountRepo   *repository.AccountRepository // 账号查询
    ticker        *time.Ticker                 // 定时器
}
```

主循环通过 `select` 消费事件通道和定时器：

```go
for {
    select {
    case event := <-g.eventChan:
        event.Process(g)              // 串行执行，无锁竞争
    case <-g.ticker.C:
        g.onTick()                    // 超时检查 + 状态上报
    }
}
```

核心操作：`addUser()`、`relogin()`、`userOffline()`、`removeExpiredUser()`、`getServerInfoBySession()`、`pushToClient()`、`onLogicServerClose()`、`onSceneServerClose()`。

### 3.2 UserMgr（用户管理器）

文件：`internal/domain/user_mgr.go`

```go
type UserMgr struct {
    usersByAccount  map[uint64]*UserInfo  // AccountId -> UserInfo
    usersBySession  map[uint64]*UserInfo  // SessionId -> UserInfo
    pendingSessions map[uint64]int64      // 未认证的会话
    reConnectTime   int64                 // 重连宽限期（秒）
}

type UserInfo struct {
    Session      *rpc.Session     // 客户端连接
    AccountId    uint64
    Token        string
    OfflineStamp int64            // 离线时间戳（0=在线）
    SceneInfo    *UserSceneInfo   // 绑定的场景
    LogicUnique  uint32           // 绑定的 Logic 服务器
}

type UserSceneInfo struct {
    SceneUnique       uint64     // 场景唯一标识
    SceneServerUnique uint32     // 场景服务器标识
}
```

关键方法：`AddUser()`（返回被顶号的旧用户）、`Relogin()`、`Offline()`（标记离线保留数据）、`RemoveUser()`、`Tick()`（返回过期用户列表）。

### 3.3 LogicMgr（Logic 服务器管理）

文件：`internal/domain/logic_mgr.go`

```go
type LogicMgr struct {
    logicServerMap map[uint32]map[uint64]struct{}  // LogicUnique -> AccountIds
    logicByUser    map[uint64]uint32               // AccountId -> LogicUnique
}
```

**负载均衡策略**：选择当前用户数最少的 Logic 服务器分配新用户。

## 四、消息处理流程

### 4.1 双 RPC 服务器

Gateway 启动两个 RPC 服务器：

| 服务器 | 监听地址 | 注册的 Handler | 职责 |
|--------|---------|---------------|------|
| **clientServer** | `listen_addr` | ForwardHandler 子类 + GatewayHandler | 接收客户端消息和后端推送响应 |
| **internalServer** | `inner_addr` | BackendPushHandler | 接收 Proxy 推送的后端消息 |

### 4.2 上行：客户端 → 后端

```
客户端发送消息
    ↓
clientServer 按 Module 分发到对应 Handler
    ↓
ForwardHandler.HandleNetMsg()
    ↓
eventChan <- EventGetServerInfoBySession（查询目标服务器）
    ↓
GatewayServer 根据模块选择路由目标
    ↓
proxySession.Call/Push（MsgTypeClientToServer）
    ↓
Proxy 路由到后端服务
```

**模块路由表**（`getServerInfoForUser` 逻辑）：

| 模块 | 路由策略 | ServerUnique |
|------|---------|--------------|
| Scene / SceneInternal / Voxel | 用户绑定的场景服务器 | `user.SceneInfo.SceneServerUnique` |
| Logic / LogicInternal / Bbs / SocialInternal | 用户绑定的 Logic 服务器 | `user.LogicUnique` |
| Match / Mail / OnewayRelation | 任意可用服务器 | `0`（由 Proxy 分配） |

### 4.3 下行：后端 → 客户端

```
后端服务通过 Proxy 发送推送
    ↓
internalServer 接收（BackendPushHandler）
    ↓
根据 MsgType TAG 分发：
    ├── TAG_FLAG_STOC  → EventPushToClient（推送给单个客户端）
    ├── TAG_FLAG_STOS  → EventForwardToBackend（后端间转发）
    └── TAG_FLAG_STOMC/STOAC → EventPushToAllClients（广播）
    ↓
eventChan → GatewayServer 主循环处理
    ↓
user.Session.Push() 转发给客户端
```

**特殊处理**：Logic 模块的 `SwitchSceneNtf`（cmd=101）推送时会同步更新用户场景信息。

### 4.4 LogicHandler 拦截

`LogicHandler` 继承 `ForwardHandler`，额外拦截 `EnterScene` 响应（cmd=201/202），从响应中提取场景信息并更新用户的 `SceneInfo`。

## 五、事件系统

### 5.1 设计原理

所有状态修改通过事件串行化处理，RPC Handler 在独立 goroutine 中运行，通过事件通道与主循环通信：

```
RPC Handler (goroutine)
    ↓
eventChan <- Event（包含 ResChan）
    ↓
主循环 event.Process(g)
    ↓
ResChan <- result
    ↓
Handler 收到结果继续处理
```

慢事件监控：处理超过 10ms 的事件会输出警告日志。

### 5.2 事件列表

**用户管理事件**：

| 事件 | 触发场景 | 行为 |
|------|---------|------|
| `EventAddUser` | 认证成功 | 添加用户，处理顶号 |
| `EventRelogin` | 重连请求 | Token/超时验证，替换 Session |
| `EventUserOffline` | Session 关闭回调 | 标记离线，通知 Logic |
| `EventRemovePendingSession` | 认证成功后 | 清理 pending 状态 |

**查询事件**：

| 事件 | 返回值 | 用途 |
|------|--------|------|
| `EventCheckToken` | bool | 缓存中检查 Token |
| `EventCheckTokenFromDB` | bool | Redis 中检查 Token |
| `EventGetSession` | *rpc.Session | 获取用户连接 |
| `EventGetAccountIdBySession` | uint64 | Session 反查 AccountId |
| `EventGetServerInfoBySession` | *ClientCallInfo | 查询消息转发目标 |
| `EventGetEnterGameInfo` | *EnterGameInfo | 获取进入游戏信息 |

**绑定事件**：`EventAddUserToScene`、`EventAddUserToLogic`

**推送事件**：`EventPushToClient`（单播）、`EventPushToAllClients`（广播）、`EventForwardToBackend`（后端间）、`EventPushToAll`（系统消息）

**服务器事件**：`EventOnLogicServerClose`、`EventOnSceneServerClose`、`EventStop`

### 5.3 Tick 机制

每 `tickInterval`（默认 1000ms）执行一次：

1. `userMgr.Tick()` — 检查离线用户是否超过重连宽限期（默认 60s）
2. `removeExpiredUser()` — 从 UserMgr/LogicMgr 移除、删除 Redis 绑定、通知 Logic 移除玩家
3. 如果用户数变化，上报注册中心和 Redis

## 六、连接管理

### 6.1 用户生命周期

```
连接建立 → 认证 → 进入游戏 → 在线 → 断线 → 重连宽限期 → 超时清理
                                    ↓           ↓
                                    └─── 重连 ──┘
```

### 6.2 认证流程（AuthenticateUser）

1. 客户端发送 `AuthenticateUserReq`（UserId + Token）
2. 先从缓存检查 Token（`EventCheckToken`）
3. 缓存未命中则从 Redis 查询（`EventCheckTokenFromDB`）
4. Token 验证通过后 `addUser` 添加用户
5. 返回 `GatewayLoginRes`（含客户端 IP）

### 6.3 顶号处理

`addUser()` 检测到同一 AccountId 已存在时：
1. 通知 Logic 服务器旧用户离线
2. 向旧客户端推送"您的账号在其他设备登录"
3. 延迟 100ms 后关闭旧连接

### 6.4 重连机制（Relogin）

1. 客户端发送 `ReloginReq`（UserId + Token）
2. 检查用户是否存在、Token 是否匹配
3. 检查断线时间是否在重连宽限期内（`reConnectTime`，默认 60 秒）
4. 验证通过后替换 Session，清除 OfflineStamp
5. 如果旧 Session 仍存在，踢掉旧连接

### 6.5 断线处理

Session 关闭触发 `EventUserOffline`：
1. 标记用户 `OfflineStamp` 为当前时间
2. 从 `usersBySession` 移除映射
3. 通知 Logic 服务器用户离线
4. **不立即移除用户**，保留等待重连

超时清理由 Tick 触发，超过 `reConnectTime` 未重连则永久移除。

### 6.6 进入游戏（EnterGame / ReturnGame）

1. 查询用户之前绑定的 LogicUnique（内存 → Redis）
2. 通过 Proxy 调用 Logic 的 `EnterGameInternal`
3. 如果指定 Logic 失败，重试一次（`logicUnique=0`，由 Proxy 分配新的）
4. 成功后更新用户的 LogicUnique 绑定

### 6.7 后端服务器关闭处理

**Logic 关闭**：获取该 Logic 上所有用户 → 关闭客户端连接 → 通知 Scene 离开场景 → 移除用户

**Scene 关闭**：筛选该场景服务器上所有用户 → 关闭客户端连接 → 通知 Logic 移除玩家 → 移除用户

## 七、GatewayHandler RPC 方法

| 方法 | CMD | 功能 |
|------|-----|------|
| `AuthenticateUser` | 1 | 首次登录认证 |
| `PingToGateway` | 2 | 心跳 |
| `Relogin` | 3 | 重连 |
| `EnterGame` | 4 | 进入游戏 |
| `ReturnGame` | 5 | 返回游戏（重连后恢复） |

## 八、与其他服务的交互

| 服务 | 交互方式 | 说明 |
|------|---------|------|
| **RegisterServer** | 启动时注册，定期上报指标 | 服务发现、获取 selfUnique |
| **Proxy** | RPC 双向通信 | 上行用 `MsgTypeClientToServer`，RPC Call 用 `MsgTypeServerToServer` |
| **Logic** | 经 Proxy 间接调用 | `EnterGameInternal`、`OfflineLogic`、`RemovePlayer` |
| **Scene** | 经 Proxy 间接调用 | `LeaveScene` |
| **Redis** | 直接连接 | Token 验证、账号绑定、在线人数上报 |

## 九、配置说明

### 全局配置 [global]

| 字段 | 说明 |
|------|------|
| `register_addr` | 注册中心地址（必填） |
| `redis_addr` | Redis 地址（可选） |
| `log_dir` | 日志输出目录 |
| `log_level` | 日志级别 |
| `cluster_unique` | 集群唯一标识（Redis Key 前缀） |

### 网关配置 [gateway]

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `listen_addr` | — | 客户端连接监听地址（必填） |
| `register_addr` | — | 注册到注册中心的地址（必填） |
| `inner_addr` | — | 内部 RPC 监听地址（必填） |
| `reconnect_time` | 60 | 重连宽限期（秒） |
| `tick_interval` | 1000 | Tick 间隔（毫秒） |
| `event_chan_size` | 3000 | 事件通道缓冲区大小 |

### Redis Key

| Key 模式 | 类型 | 说明 |
|----------|------|------|
| `test_account_token_key{ver}_{cluster}_{accountId}` | String | 账号 Token |
| `test_account_logic_key{ver}_{cluster}_{accountId}` | String | 账号绑定的 Logic |
| `test_account_gateway_key{ver}_{cluster}_{accountId}` | String | 账号绑定的 Gateway |
| `gw_online_user_num` | Hash | 各 Gateway 在线人数 |

## 十、性能设计

- **无锁并发**：所有状态修改通过事件串行化，避免互斥锁
- **原始字节转发**：使用 `RawBytes` 避免不必要的反序列化
- **TCP 连接复用**：单一 Proxy 连接用于所有转发
- **批量推送**：支持 STOMC/STOAC 批量推送给多个客户端
- **慢事件监控**：事件处理超过 10ms 输出警告日志
