# P1GoServer 登录服务知识图谱

> login_server 负责玩家身份认证、Token 管理、网关分配，是客户端进入游戏的第一个接触点。

## 目录结构

```
servers/login_server/
├── cmd/
│   ├── main.go            # 程序入口
│   ├── config.go          # TOML 配置结构和加载
│   └── initialize.go      # 依赖组装（三层架构初始化）
├── internal/
│   ├── domain/            # 领域层（业务逻辑）
│   │   ├── login_handler.go   # 核心登录处理器（5 种登录方式）
│   │   └── types.go           # LoginResponse 响应结构
│   ├── repository/        # 数据访问层
│   │   ├── account_repository.go   # 账户 CRUD、ID 生成、缓存
│   │   ├── token_repository.go     # Token 生成/验证/存储
│   │   ├── platform_repository.go  # 平台配置、版本、通知
│   │   ├── types.go                # AccountInfo、ManageConfig 等
│   │   └── redis_key.go            # Redis Key 定义
│   └── services/          # 服务层
│       ├── http_server.go      # HTTP 路由和请求处理
│       ├── platform_manager.go # 平台配置定时拉取、踢人广播
│       └── types.go            # 请求/响应结构体、错误类型
├── test/                  # 测试
│   ├── login_test.go          # Firebase JWT 验证测试
│   └── login_extra_test.go    # Token 格式和错误码测试
└── docs/                  # 服务内文档
```

## 架构概览

```
客户端
  │
  ▼ HTTP
┌─────────────────────────────────────────────────┐
│  HTTPServer (services/http_server.go)            │
│  路由: /re_login, /taptap_login, /guest_login,   │
│        /google_login, /google_guest_login,       │
│        /notice, /ping                            │
└─────────────┬───────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────┐
│  LoginHandler (domain/login_handler.go)          │
│  身份验证 → 账户查找/创建 → Token 生成 → 网关选择  │
└──┬──────────────┬───────────────┬────────────────┘
   │              │               │
   ▼              ▼               ▼
AccountRepo   TokenRepo     PlatformRepo
 (MongoDB      (Redis)       (Redis +
  + Redis                    远程 API)
  缓存)
              │
              ▼
       ┌─────────────┐     ┌──────────────┐
       │ RegisterClient│───▶│ Gateway 列表  │
       └─────────────┘     └──────────────┘
              │
              ▼
       ┌─────────────┐     ┌──────────────┐
       │ ProxyEntry   │───▶│ Logic Server │
       └─────────────┘     │ (踢人广播)    │
                            └──────────────┘
```

## 启动流程

1. `main()` 解析命令行参数、加载 TOML 配置、初始化日志
2. `initialize()` 组装依赖：
   - 连接 MongoDB（URI 自动补全）
   - 连接 Redis
   - 创建三层 Repository: AccountRepository、TokenRepository、PlatformRepository
   - 创建 RegisterClient（服务注册/发现）和 ProxyEntry（RPC 代理）
   - 创建 LoginHandler（领域逻辑）
   - 创建 HTTPServer（HTTP 路由）
   - 创建 PlatformManager（定时拉取平台配置）
3. `app.Run()` 启动所有 Runnable 组件

## 登录方式

| 登录方式 | HTTP 路由 | 验证方式 | 平台 Key 格式 |
|---------|-----------|---------|-------------|
| 重新登录 | `/re_login` | AccessToken 验证 | 无（按 AccountID 查找） |
| TapTap | `/taptap_login` | TapTap OAuth API | `taptap{unionid}` |
| 游客 | `/guest_login` | 无验证 | `guest_{user}` 或 Rust 兼容格式 |
| Google | `/google_login` | Firebase JWT (RS256) | `google:{firebase_uid}` |
| Google 游客 | `/google_guest_login` | 无验证 | 同游客 |

## 登录流程

### 首次登录（TapTap/Google/Guest）

```
验证身份（第三方 API / 无验证）
    ↓
构建 platform_key
    ↓
按 platform_key 查找账户
    ├─ 找到 → 跳到封禁检查
    └─ 未找到 → 创建新账户
         ├─ 申请自增 ID（批量从 MongoDB 获取 100 个，内存缓存）
         ├─ 处理昵称冲突（追加 #{accountID} 后缀）
         ├─ 插入 MongoDB + 缓存 Redis
         └─ 增加注册计数
    ↓
检查封禁（UnblockTime > now → 返回 3001）
    ↓
生成 Token 对（短期 10s + 长期 7d）
    ↓
更新 last_login_time（同时清除 Redis 账户缓存）
    ↓
选择网关（优先旧网关，否则随机）
    ↓
获取版本号
    ↓
增加登录计数
    ↓
检查维护模式（最后执行，可被白名单绕过）
    ↓
返回 LoginResponse
```

### 重新登录（/re_login）

```
验证 AccessToken（Redis 精确比对）
    ↓
查询账户（Redis 缓存优先，TTL 2h±10%）
    ↓
检查封禁 → 刷新 Token 对 → 更新登录时间 → 选择网关 → 返回
```

### 网关选择策略

```
从注册中心获取 Gateway 列表
    ↓
查 Redis 上次使用的 Gateway
    ├─ 存在且可用 → 复用
    └─ 不存在或下线 → 随机选择
    ↓
保存映射到 Redis
```

## Token 机制

### 双 Token 设计

| Token 类型 | TTL | 用途 | 验证方 |
|-----------|-----|------|-------|
| 短期 Token | 10 秒 | 登录后立即连接 Gateway | Gateway |
| 长期 AccessToken | 7 天 | 离线重连 | Login Server |

### 生成算法（与 Rust 端一致）

```
短期 Token   = SHA1("login_token_{accountID}_{rand}_{timestamp}")
长期 Token   = SHA1("login_access_token_{accountID}_{rand}_{timestamp}")_{timestamp}
```

重登时自动刷新：删除旧 Token → 生成新 Token 对。

## 安全机制

### 账户封禁

- 字段：`UnblockTime`（int64 时间戳），`BlockReason`（string）
- 判定：`UnblockTime > 当前时间` 即为封禁中
- 错误码 3001，返回解封时间（格式 `2006-01-02 15:04:05`）
- 检查时机：所有登录方式在生成 Token 前检查

### 维护模式

- 由 PlatformManager 从远程 API 定时拉取配置
- `game_close=true` 时进入维护模式
- 白名单（可绕过维护限制）：
  - GM 列表（从本地文件加载）
  - 平台配置中的 user_ids
  - 设备白名单（本地文件 + 平台配置的 device_list）
- 维护中返回错误码 2001 + 维护消息
- 启用踢人模式时，通过 ProxyEntry 向 Logic Server 广播 `PushSystemMessageType_ServerMaintenance`

## 数据存储

### MongoDB

**数据库名：** 通过 `orm/mongo.GetDatabaseName(clusterUnique)` 动态获取

| 集合 | 索引 | 说明 |
|------|------|------|
| `account_table` | `account_id`(唯一), `platform_key`(唯一), `account` | 账户信息 |
| `unique_id_table` | `name` | 账户 ID 原子自增（FindOneAndUpdate + $inc） |

**AccountInfo 核心字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| AccountID | uint64 | 自增唯一 ID |
| Account | string | 账户名（昵称或 `昵称#ID`） |
| Nickname | string | 原始昵称 |
| PlatformKey | string | 平台标识（唯一索引） |
| UnblockTime | int64 | 解封时间戳（>now 表示封禁中） |
| BlockReason | string | 封禁原因 |
| LastLoginTime | uint64 | 最后登录时间 |
| Gender | uint64 | 性别（默认 1） |
| DisplayPicture | uint32 | 头像 ID（默认 1001） |

### Redis Key 映射

| Key 模式 | TTL | 说明 |
|----------|-----|------|
| `test_account_token_key20250521_{cluster}_{id}` | 10s | 短期 Token |
| `test_access_token_key20250521_{cluster}_{id}` | 7d | 长期 AccessToken |
| `account_cache_20250521_{cluster}_{id}` | 2h±10% | 账户缓存（防雪崩） |
| `test_account_gateway_key20250521_{cluster}_{id}` | 无 | 网关映射 |
| `platform_config_{cluster}` | 无 | 平台配置 |
| `test_version_key20250521_{cluster}` | 无 | 版本号 |
| `test_notice_key20250521_{cluster}` | 无 | 系统通知 |
| `login_count_20250521_{cluster}` | 无 | 登录计数（INCR） |
| `register_count_20250521_{cluster}` | 无 | 注册计数（INCR） |
| `gw_online_user_num` | 无 | 网关在线人数（Hash） |

## HTTP API

### 请求/响应

**请求体：**

```go
// POST /re_login
type ReLoginRequest struct {
    UserID      uint64
    AccessToken string
}

// POST /taptap_login
type TapTapLoginRequest struct {
    Kid, MacKey, UnionID string
}

// POST /guest_login | /google_guest_login
type GuestLoginRequest struct {
    User string
}

// POST /google_login
type GoogleLoginRequest struct {
    IDToken string
}
```

**统一响应：**

```go
type LoginResponse struct {
    Code        int32   // 0=成功, 1001=错误, 2001=维护, 3001=封禁
    UserID      uint64
    Name        string  // 账户名
    Nickname    string
    AccessToken string  // 长期 Token（7d）
    Token       string  // 短期 Token（10s）
    Msg         string  // 错误/维护消息
    Addr        string  // Gateway 地址
    Sex         uint64
    Version     uint64
}
```

### 错误码

| 码 | 含义 | 触发场景 |
|---|------|---------|
| 0 | 成功 | - |
| 1001 | 通用错误 | Token 验证失败、JSON 解析失败、账户创建失败、数据库错误 |
| 2001 | 服务器维护中 | game_close=true 且不在白名单 |
| 3001 | 账户被封禁 | UnblockTime > now |

## 关键依赖

### common/ 包

| 包 | 功能 |
|------|------|
| `common/cmd` | 应用框架（Runnable 接口、生命周期管理） |
| `common/log` | 日志 |
| `common/proto` | gRPC 协议定义（ServerType、RPC 方法） |
| `common/register` | 服务注册/发现（获取 Gateway 列表） |
| `common/proxy_entry` | RPC 代理入口（向 Logic Server 广播） |
| `common/taptap` | TapTap OAuth 验证 |
| `common/google` | Google Firebase JWT 验证 |
| `common/mtime` | 时间工具 |
| `common/safego` | 安全 goroutine |
| `common/rpc` | RPC 消息类型 |

### 其他

| 包 | 功能 |
|------|------|
| `pkg/gredis` | Redis 客户端封装 |
| `orm/mongo` | MongoDB 集合/库名定义 |
| `base/ghttp` | HTTP 服务器框架 |

## Rust 兼容性

login_server 从 Rust 迁移而来，以下格式与旧版保持一致：

- Redis Key 前缀包含版本号 `20250521`
- Token 生成算法（SHA1 哈希格式）
- 平台 Key 格式（`taptap{unionid}`、`google:{uid}`）
- 游客账户的 account 字段格式：`test_guest_account_key_{VERSION}_{user}`
- MongoDB 集合名和字段名（通过 orm/mongo 动态获取）
- 网关选择策略（优先旧网关，否则随机）

## 与其他服务的关系

```
                    ┌──────────────┐
                    │ 注册中心      │
                    │ (etcd/consul) │
                    └──────┬───────┘
                           │ 注册/发现
┌──────────┐  HTTP   ┌─────┴──────┐  gRPC   ┌──────────────┐
│  客户端   │────────▶│ Login      │────────▶│ Logic Server │
│          │◀────────│ Server     │         │ (踢人广播)    │
└──────────┘ 响应    └─────┬──────┘         └──────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────────┐
        │ MongoDB  │ │ Redis    │ │ Gateway 列表  │
        │ (账户)   │ │ (Token   │ │ (分配给客户端) │
        │          │ │  缓存)   │ │              │
        └──────────┘ └──────────┘ └──────────────┘
```

客户端登录成功后拿到 Gateway 地址和短期 Token，随后用短期 Token 连接 Gateway 进入游戏。
