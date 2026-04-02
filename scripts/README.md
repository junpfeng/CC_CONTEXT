# scripts - 工具脚本

## 脚本列表

| 脚本 | 说明 |
|------|------|
| `server.ps1` | 服务管理脚本（起服 / 停服 / 状态查看） |
| `claude-git.sh` | Claude 上下文文件版本控制辅助脚本 |

---

## server.ps1 - 服务管理

管理 P1 全部游戏服务进程，包括 P1GoServer（Go）和 server_old（Rust 场景服务）。

### 前置条件

1. 已编译服务二进制到对应的 `bin/` 目录：
   - Go 服务：`cd P1GoServer && make build`
   - Rust 场景服务：`cd server_old && make scene`，将编译产物拷贝到 `bin/scene_server.exe`
2. 配置文件已就绪（从 `.example` 复制并按环境修改）：
   - `P1GoServer/bin/config.toml`
   - `server_old/bin/config.toml`

### 用法

```powershell
.\scripts\server.ps1 <命令> [服务名...]
```

### 命令

| 命令 | 说明 |
|------|------|
| `start` | 启动服务（按优先级顺序，间隔 1 秒） |
| `stop` | 停止服务（按逆优先级顺序，优雅关闭 → 超时强杀） |
| `status` | 查看服务运行状态、PID、内存占用 |
| `restart` | 先停后启 |

不指定服务名时操作全部服务，指定时只操作指定的服务。

### 示例

```powershell
# 全量操作
.\scripts\server.ps1 start           # 启动所有服务
.\scripts\server.ps1 stop            # 停止所有服务
.\scripts\server.ps1 status          # 查看状态

# 指定服务
.\scripts\server.ps1 start db_server login_server
.\scripts\server.ps1 restart old_scene_server
.\scripts\server.ps1 status gateway_server
```

### 管理的服务

按启动优先级排序：

| 优先级 | 服务名 | 类型 | 说明 |
|--------|--------|------|------|
| 1 | register_server | Go | 服务注册中心（所有服务依赖） |
| 2 | db_server | Go | 数据库层 |
| 3 | dbproxy_server | Go | 数据库代理（依赖 db_server） |
| 4 | manager_server | Go | 场景调度 |
| 5 | logic_server | Go | 核心游戏逻辑 |
| 5 | scene_server | Go | 游戏世界实例 |
| 6 | relation_server | Go | 玩家关系 |
| 6 | team_server | Go | 队伍/公会 |
| 6 | chat_server | Go | 聊天 |
| 7 | login_server | Go | 登录认证 |
| 7 | match_server | Go | 匹配 |
| 7 | workshop_server | Go | 制作系统 |
| 7 | mail_server | Go | 邮件 |
| 7 | gm_server | Go | GM 工具 |
| 8 | proxy_server | Go | 服务代理 |
| 8 | old_scene_server | Rust | 场景服务（server_old） |
| 9 | gateway_server | Go | 客户端网关（依赖 proxy） |

### 目录结构

脚本运行后会自动创建以下目录：

```
P1/
├── run/                          # PID 文件（*.pid）
├── P1GoServer/
│   └── log/
│       ├── out/                  # Go 服务 stdout 日志
│       └── err/                  # Go 服务 stderr 日志
└── server_old/
    └── log/
        ├── out/                  # Rust 服务 stdout 日志
        └── err/                  # Rust 服务 stderr 日志
```

### 配置修改

如需调整服务列表或参数，编辑 `server.ps1` 顶部配置区：

- `$Services` - 服务列表及优先级
- `$StartDelay` - 启动间隔（默认 1 秒）
- `$StopTimeout` - 停服超时（默认 10 秒）
