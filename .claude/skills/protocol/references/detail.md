# 协议设计规范 - 详细参考

## 目录结构

```
old_proto/
├── module.proto          # 模块定义（ModuleCmd 枚举）
├── client/               # 客户端协议（与客户端交互）
│   ├── account.proto     # 账号服务协议
│   ├── base.proto        # 基础数据类型
│   ├── codes.proto       # 错误码定义
│   ├── lobby.proto       # 大厅服务协议
│   ├── room.proto        # 房间服务协议
│   └── room_define.proto # 房间相关定义
└── inner/                # 内部协议（进程间交互）
    ├── db_user.proto     # 数据库用户协议
    ├── gate_inner.proto  # 网关内部协议
    ├── lobby_inner.proto # 大厅内部协议
    ├── match_inner.proto # 匹配内部协议
    ├── push_inner.proto  # 推送内部协议
    ├── room_inner.proto  # 房间内部协议
    └── team_inner.proto  # 组队内部协议
```

## 协议分类

### 客户端协议 (client/)

用于客户端与服务器之间的通信：
- **account.proto** - 账号登录、注册等（HTTP 协议）
- **lobby.proto** - 大厅服务（登录、心跳、创建房间、匹配等）
- **room.proto** - 房间服务（加入游戏、帧同步、事件处理等）

### 内部协议 (inner/)

用于服务器进程之间的通信：
- **db_user.proto** - 数据库用户服务
- **gate_inner.proto** - 网关内部服务
- **lobby_inner.proto** - 大厅内部服务
- **match_inner.proto** - 匹配内部服务
- **push_inner.proto** - 推送内部服务
- **room_inner.proto** - 房间内部服务（创建地图、停止地图、踢出用户）
- **team_inner.proto** - 组队内部服务

## 模块定义 (module.proto)

```protobuf
enum ModuleCmd {
  None        = 0;    // 无模块
  // 外部协议号（客户端可访问）
  Account     = 1;    // 账号服务（HTTP）
  Lobby       = 2;    // 大厅服务
  Room        = 3;    // 房间服务
  Push        = 4;    // 推送服务

  // 内部协议号（仅服务器内部使用）
  TeamInner   = 250;  // 组队服务（内部）
  GateInner   = 251;  // 网关服务（内部）
  RouteInner  = 252;  // 路由服务（内部）
  MatchInner  = 253;  // 匹配服务（内部）
  RoomInner   = 254;  // 房间服务（内部）
  LobbyInner  = 255;  // 大厅服务（内部）
}
```

## 协议命名规范

### 消息命名

| 类型 | 前缀 | 示例 |
|------|------|------|
| 请求消息 | `Req` | `ReqLobbyLogin`, `ReqCreateMap` |
| 响应消息 | `Rsp` | `RspLobbyLogin`, `RspCreateMap` |
| 通知消息 | `Notify` | `NotifyMatchRet` |
| 数据结构 | 无前缀 | `LobbyUserInfo`, `MapUserInfo` |

### 服务定义 (trait)

使用 `trait` 关键字定义服务接口：

```protobuf
trait SessionService {
    // cs = client-server 双向调用
    cs Login(ReqLobbyLogin) returns (RspLobbyLogin) = 1;
    cs HeartBeat(ReqLobbyHeartBeat) returns (RspLobbyHeartBeat) = 2;

    // cc = client callback (服务器推送到客户端)
    cc MatchResult(NotifyMatchRet) = 1024;
}
```

- `cs` - Client-Server 双向调用（请求-响应模式）
- `cc` - Client Callback（服务器主动推送）
- 数字为消息命令号（cmd）

## 支持的关键字和语法

### 基本关键字

| 关键字 | 说明 | 示例 |
|--------|------|------|
| `package` | 定义包名 | `package lobby;` |
| `import` | 导入其他proto文件 | `import "module.proto";` |
| `message` | 定义消息结构 | `message ReqLogin { ... }` |
| `enum` | 定义枚举类型 | `enum LoginChannel { ... }` |
| `trait` | 定义服务接口 | `trait Service { ... }` |
| `repeated` | 定义数组字段 | `repeated uint64 ids = 1;` |

### 数据类型

| 类型 | 说明 |
|------|------|
| `uint32` | 无符号32位整数 |
| `uint64` | 无符号64位整数 |
| `int32` | 有符号32位整数 |
| `int64` | 有符号64位整数 |
| `float` | 32位浮点数 |
| `double` | 64位浮点数 |
| `bool` | 布尔值 |
| `string` | 字符串 |
| `bytes` | 字节数组 |

### 服务定义 (trait)

```protobuf
trait ServiceName {
    // cs: Client-Server 请求响应（客户端调用，服务端处理）
    cs MethodName(ReqMessage) returns (RspMessage) = cmd_number;

    // cc: Client Callback 服务器推送（服务端主动推送到客户端）
    cc NotifyName(NotifyMessage) = cmd_number;
}
```

- `cs` - 双向调用（请求-响应模式）
- `cc` - 服务器主动推送到客户端
- `cmd_number` - 消息命令号（唯一标识，用于路由）

### 不支持的语法

以下标准 protobuf 语法**不支持**：
- `syntax = "proto3";` - 可以写但会被忽略
- `option` - 选项配置
- `oneof` - 联合类型
- `map` - 映射类型
- `reserved` - 保留字段
- `extensions` - 扩展
- `service` / `rpc` - 使用 `trait` / `cs` / `cc` 代替

## 协议编写示例

### 客户端协议示例

```protobuf
// client/lobby.proto
package lobby;

import "module.proto";

// 请求消息
message ReqLobbyLogin {
    uint64 session_id = 1;  // 登录会话ID
    uint64 uid = 2;         // 用户唯一ID
    string token = 3;       // 鉴权Token
}

// 响应消息
message RspLobbyLogin {
    uint64 uid = 1;         // 账号ID
    string uname = 2;       // 账号名称
}

// 服务定义
trait SessionService {
    cs Login(ReqLobbyLogin) returns (RspLobbyLogin) = 1;
}
```

### 内部协议示例

```protobuf
// inner/room_inner.proto
package room_inner;

import "module.proto";

message MapUserInfo {
    uint64 uid = 1;
    string name = 2;
}

message ReqCreateMap {
    uint64 request_uid = 1;
    string map_type = 2;
    repeated MapUserInfo user_list = 3;
}

message RspCreateMap {
    uint64 map_id = 1;
}

trait Service {
    cs CreateMap(ReqCreateMap) returns (RspCreateMap) = 1;
}
```

## 代码生成

### 生成命令

修改 proto 文件后，在 Proto 目录下执行 build.cmd 即可生成代码：

```bash
cd ../Proto
./build.cmd
```

或者分步执行：

```bash
cd ../old_proto/bin
./proto_gen.exe
# 然后手动复制生成的文件到目标目录
cp ../old_proto/bin/go/*.go ../P1GoServer/gen/proto/
```

### 生成文件

协议文件编译后生成到 `P1GoServer/gen/proto/` 目录：

```
gen/proto/
├── account_pb.go           # 账号协议消息
├── account_service.go      # 账号服务接口
├── lobby_pb.go             # 大厅协议消息
├── lobby_service.go        # 大厅服务接口
├── room_pb.go              # 房间协议消息
├── room_service.go         # 房间服务接口
├── room_inner_pb.go        # 房间内部协议消息
├── room_inner_service.go   # 房间内部服务接口
├── gate_inner_pb.go        # 网关内部协议消息
├── gate_inner_service.go   # 网关内部服务接口
├── match_inner_pb.go       # 匹配内部协议消息
├── match_inner_service.go  # 匹配内部服务接口
├── push_inner_pb.go        # 推送内部协议消息
├── push_inner_service.go   # 推送内部服务接口
├── team_inner_pb.go        # 组队内部协议消息
├── team_inner_service.go   # 组队内部服务接口
└── module_pb.go            # 模块定义
```

### 服务接口

生成的 `*_service.go` 文件包含：
- `I*Handler` 接口 - 需要实现的服务方法
- `*ServerWrapper` - RPC 消息分发器
- `*Server` - 客户端调用接口（用于推送消息）
