# P1GoServer 协议解析与处理

> 服务器自定义二进制协议的完整技术文档，涵盖帧格式、序列化、路由分发、代码生成全流程。

## 概述

P1GoServer **没有使用标准 gRPC**，而是实现了一套基于 TCP 的自定义二进制协议。核心特点：

- 自定义 varint 编码（类似 Protobuf 的 LEB128）
- 模块 ID 数组直接索引的 O(1) 路由分发
- 异步 Call/Ack + Push 消息模型
- 代码生成驱动的服务接口

## 帧格式

每条消息的二进制帧结构：

```
Byte 0-2:   消息总长度 (3 字节, big-endian)
            size = buf[0]<<16 | buf[1]<<8 | buf[2]

Byte 3:     标志位 (Flags)
            0x02  MsgFlag_Extra  — 携带路由元数据
            0x08  MsgFlag_Err    — 错误响应
            0x10  MsgFlag_Push   — 推送消息（无需响应）
            0x20  MsgFlag_Ack    — 确认/响应消息

Byte 4:     模块 ID (Module, 0-255)

Byte 5-6:   命令 ID (Command, 2 字节 big-endian)
            cmd = buf[5]<<8 | buf[6]

Byte 7-10:  序列号 (Sequence, 4 字节 big-endian, 仅 Call/Ack)

Byte 11+:   消息体 (protobuf 风格的 varint 编码)

末尾 1 字节 (如有 Extra): 路由类型标签
```

## 三种消息类型

| 类型 | 标志位 | 含义 | 是否有序列号 |
|------|--------|------|-------------|
| **Call** | 无特殊标志 | 请求，期望 Ack 响应 | 是 |
| **Ack** | `MsgFlag_Ack` | 对 Call 的响应 | 是（与请求相同） |
| **Push** | `MsgFlag_Push` | 单向推送，无需响应 | 否 |

## 路由元数据 (Extra Tags)

当 `MsgFlag_Extra` 置位时，消息末尾附加路由上下文，用于多跳消息转发：

| Tag | 常量 | 方向 | 附加字段 |
|-----|------|------|---------|
| 1 | `TAG_FLAG_CTOS` | 客户端→服务端 | AccountId, ServerUnique, SourceGateway |
| 2 | `TAG_FLAG_STOS` | 服务端→服务端 | AccountId, ServerUnique |
| 3 | `TAG_FLAG_STOC` | 服务端→客户端 | AccountId, GatewayUnique |
| 4 | `TAG_FLAG_STOMC` | 服务端→场景内所有客户端 | — |
| 5 | `TAG_FLAG_STOAC` | 服务端→所有在线客户端 | — |
| 6 | `TAG_FLAG_STOAS` | 服务端→所有服务器 | — |
| 7 | `TAG_FLAG_TOS` | 发往场景 | SceneUnique, ServerUnique |

> 源码位置: `common/rpc/extra.go`

## 模块 ID (ModuleCmd)

每个业务模块分配一个唯一的 Module ID（0-255），用于路由分发：

| ModuleCmd | ID | 说明 |
|-----------|-----|------|
| Login | 1 | 登录模块 |
| Scene | 2 | 场景/世界管理 |
| Logic | 3 | 核心游戏逻辑 |
| Gateway | 5 | 客户端网关 |
| Match | 7 | 匹配系统 |
| Mail | 8 | 邮件系统 |
| Bbs | 9 | 公告板 |
| CacheInternal | 246 | 缓存服务（内部） |
| Proxy | 247 | 代理协调 |
| Register | 249 | 服务注册 |

> 源码位置: `common/proto/module_pb.go`

## 序列化/反序列化

### 编解码器

位于 `common/proto_code/`：

- **Encoder** (`encode.go`): `WriteVarInt()`, `WriteString()`, `WriteBytes()` 等
- **Decoder** (`decoder.go`): `ReadUint8()`, `ReadUint32()`, `ReadUint64()`, `ReadString()` 等

varint 采用 7 位分段编码，MSB 为续传标志，与 Protobuf 编码兼容。

### 消息接口

所有消息实现 `IProto` 接口：

```go
type IProto interface {
    Marshal([]byte) []byte      // 序列化到字节切片
    Unmarshal(*Decoder) error   // 从解码器反序列化
    Size() int32                // 计算序列化后大小
}
```

### 字段编码

每个字段使用 tag 标识: `tag = (field_number << 3) | wire_type`，与 Protobuf 的 wire format 类似。

## 网络层

### TCP 连接管理

位于 `common/rpc/server.go`：

```go
type RpcServer struct {
    ln        net.Listener      // TCP 监听器
    handle    *RpcHandleMgr     // 消息处理器注册表
    pool      *worker.Pool      // 协程池 (512 workers, 8192 队列)
}
```

连接参数配置：
- TCP KeepAlive: 1 秒间隔
- NoDelay: 开启（禁用 Nagle 算法，降低延迟）
- 读写缓冲区: 各 128KB

### Session 模型

每个连接对应一个 `Session`，包含：
- `readMsg()` 协程 — 持续读取并解析消息帧
- `tick()` 协程 — 处理消息队列、检测超时
- `reqHash` — 追踪待响应的 Call 请求（`sync.Map`）
- `ctxChan` — 消息上下文队列（缓冲区 1000）

> 源码位置: `common/rpc/session.go`

## 消息路由与分发

### Handler 注册表

```go
type RpcHandleMgr struct {
    handlers [256]IHandler   // 按 Module ID 直接索引
}
```

O(1) 查找，无需 map 哈希计算。

### Handler 接口

```go
type IHandler interface {
    HandleNetMsg(data []byte, context *RpcContext)
    Module() uint8
}
```

### 分发流程

1. `readMsg()` 解析帧头，提取 module、cmd、flags
2. 根据 flags 判断消息类型（Call/Push/Ack）
3. Call → `HandleCallMsg()` → `handlers[module].HandleNetMsg()`
4. Push → `HandlePushMsg()` → `handlers[module].HandleNetMsg()`
5. Ack → 匹配 `reqHash` 中的序列号，通知等待协程

### 协程池处理

消息处理提交到 `worker.Pool`（512 并发 workers），避免无限制 goroutine 爆炸：

```go
c.submit(func() {
    c.handle.HandleCallMsg(c, module, cmd, sequence, msgBytes, extra)
})
```

## 代码生成

### 输入与输出

| 输入 | 输出 | 工具 |
|------|------|------|
| `resources/orm/` (XML 定义) | `common/proto/*_pb.go` — 消息结构体 | `tools/orm_tool` |
| | `common/proto/*_service.go` — 服务端 Wrapper | |
| | `common/proto/*_client.go` — 客户端调用库 | |

### 生成的服务端 Wrapper

每个模块自动生成 `*ServerWrapper`，实现 `IHandler` 接口：

```go
type CacheInternalServerWrapper struct {
    ServerInner ICacheInternalServerHandler
}

func (h *CacheInternalServerWrapper) Module() uint8 {
    return uint8(ModuleCmd_CacheInternal)  // 246
}

func (h CacheInternalServerWrapper) HandleNetMsg(reqBytes []byte, ctx *rpc.RpcContext) {
    switch ctx.Cmd {
    case 1:  // AccountOnline
        msg := &AccountOnlineReq{}
        msg.Unmarshal(proto_code.NewDecoder(reqBytes))
        rsp, err := h.ServerInner.AccountOnline(msg, ctx)
        // 设置响应或错误
    case 2:  // AccountOffline
        // ... 同模式
    }
}
```

### 业务方只需实现接口

```go
type ICacheInternalServerHandler interface {
    AccountOnline(*AccountOnlineReq, *rpc.RpcContext) (*AccountOnlineRsp, *proto_code.RpcError)
    AccountOffline(*AccountOfflineReq, *rpc.RpcContext) (*AccountOfflineRsp, *proto_code.RpcError)
}
```

## Call 请求-响应流程

```
客户端发送 Call
  ↓
Session.readMsg() 解析帧 → module=2, cmd=1001, seq=12345
  ↓
submit → HandleCallMsg(module=2, cmd=1001, seq=12345, data)
  ↓
handlers[2].HandleNetMsg(data, RpcContext{Cmd:1001, Seq:12345})
  ↓ (生成的 Wrapper 按 cmd switch)
ServerInner.SomeMethod(req, ctx) → (rsp, err)
  ↓
ctx.ResponseMsg = rsp  或  ctx.ErrData = err
  ↓
Session.Ack(seq=12345, rsp)  或  Session.AckError(seq=12345, err)
  ↓
写回 TCP: [size][MsgFlag_Ack][seq=12345][response_data]
```

### 超时机制

`Session.Call()` 发起请求后，通过 `tick()` 每 100ms 检查一次挂起的请求，超过 30 次（3 秒）视为超时，返回 `RpcError("timeout")`。

## Push 推送流程

```
后端服务发起 Push
  ↓
构建帧: [size][MsgFlag_Push|MsgFlag_Extra][module][cmd][data][TAG_FLAG_STOC]
  ↓
Gateway 收到 → HandlePushMsg()
  ↓
解析 Extra → MsgTypeServerToClient{AccountId, GatewayUnique}
  ↓
查找 AccountId 对应的客户端 Session
  ↓
直接转发 Push 帧给客户端（无需 Ack）
```

## 错误处理

### RpcError

```go
type RpcError struct {
    ty   uint32  // 7 = 错误码, 14 = 错误消息
    code uint64  // 错误码 (ty=7 时)
    msg  string  // 错误消息 (ty=14 时)
}
```

错误响应通过 `MsgFlag_Ack | MsgFlag_Err` 标志返回，客户端解析后可区分正常响应和错误。

> 源码位置: `common/proto_code/rpc_error.go`

## 架构总览

```
┌──────────────┐
│  Game Client │
└──────┬───────┘
       │ TCP (自定义二进制协议)
       ▼
┌──────────────────────────────────────────────┐
│  Gateway Server                              │
│  ┌─────────┐  ┌──────────────────────────┐  │
│  │ Session  │→ │ RpcHandleMgr             │  │
│  │ readMsg()│  │ handlers[5]  → Gateway   │  │
│  │ tick()   │  │ handlers[2]  → Scene转发 │  │
│  └─────────┘  │ handlers[3]  → Logic转发 │  │
│               └──────────┬───────────────┘  │
└──────────────────────────┼───────────────────┘
                           │ TCP (内部 RPC)
                    ┌──────┴──────┐
                    ▼             ▼
              ┌──────────┐  ┌──────────┐
              │ Proxy    │  │ Backend  │
              │ Server   │  │ Services │
              │ (中继)    │  │ (业务)   │
              └──────────┘  └──────────┘
```

## 关键源码索引

| 文件 | 职责 |
|------|------|
| `common/rpc/server.go` | TCP 监听、连接接受、RpcServer |
| `common/rpc/session.go` | 连接会话、帧解析、消息读写 |
| `common/rpc/handle.go` | Handler 注册表、消息分发 |
| `common/rpc/extra.go` | 路由元数据（Extra Tags）定义 |
| `common/proto_code/encode.go` | varint 编码器 |
| `common/proto_code/decoder.go` | varint 解码器 |
| `common/proto_code/rpc_error.go` | 错误类型定义 |
| `common/proto/module_pb.go` | 模块 ID 常量 |
| `common/proto/*_pb.go` | 生成的消息结构体 |
| `common/proto/*_service.go` | 生成的服务端 Wrapper |
| `common/proto/*_client.go` | 生成的客户端调用库 |
| `resources/orm/` | XML 协议定义源文件 |
| `tools/orm_tool` | 代码生成工具 |
