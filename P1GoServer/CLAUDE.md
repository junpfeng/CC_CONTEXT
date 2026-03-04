# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此仓库中工作时提供指导。

## 项目概述

P1GoServer 是一个使用 Go 1.25 编写的分布式微服务游戏服务器。这是一个生活模拟类游戏，包含多个相互连接的服务器组件，处理不同的游戏玩法（古董、鉴定、烹饪、建造等）。

**技术栈**: Go 1.25, MongoDB (v2), Redis, 自定义 gRPC RPC, Protocol Buffers 3, TOML 配置

## 构建命令

```bash
# 前置条件: Go 1.25, make (Windows 使用 MinGW)
git submodule init && git submodule update
go env -w GOPROXY=https://goproxy.cn,direct

# 构建所有服务器
make build

# 构建指定服务器
make manager_server
make db_server
make scene_server  # 特殊: 保留调试信息，禁用优化

# 覆盖构建目标
make build APPS='db_server logic_server'

# ORM 代码生成 (修改 /resources/orm 后需要执行)
make orm_tool      # 重建生成器 (仅 Linux)
make orm           # 从 XML 生成 Go/Redis/MongoDB/Protobuf 代码

# 测试
make test                  # 运行所有测试
make test-coverage         # 生成覆盖率报告 (build/coverage.html)
go test -v ./common/db/... # 运行指定包测试

# 代码质量
make lint   # golangci-lint
make fmt    # go fmt

# 测试机器人
make robot_game
make run-robot
```

## 模块结构

使用 Go module replacements（非 workspaces）:
- `mp` (主模块) - 聚合所有模块
- `base` - 基础工具库 (git submodule，来自 git2.miao.one)
- `pkg` - 共享包 (FSM, Redis, gRPC, 物理引擎, 导航网格)
- `common` - 核心游戏和基础设施 (40+ 包)
- `orm` - 生成的 ORM 实体 (自动生成，不要直接编辑)
- `tools` - 构建工具，包括 ORM 代码生成器

## 目录结构

```
/servers/           # 微服务 (每个包含 cmd/ 和 internal/)
  manager_server/   # 场景/世界管理 (调度器)
  db_server/        # 中心化数据库层
  logic_server/     # 核心游戏逻辑
  scene_server/     # 游戏世界实例 (ECS 模式)
  login_server/     # 认证
  chat_server/      # 聊天和语音频道
  relation_server/  # 玩家关系
  team_server/      # 队伍/公会管理
  match_server/     # 玩家匹配
  gm_server/        # 管理工具
  workshop_server/  # 制作系统

/common/            # 共享库
  cmd/              # 应用框架 (Runnable 接口, 生命周期)
  config/           # 自动生成的游戏配置 (100+ cfg_*.go 文件)
  rpc/              # RPC 会话管理
  db/, db_entry/    # 数据库抽象和缓存

/resources/
  proto/            # Protocol Buffer 定义 (git submodule)
  orm/              # ORM XML 定义 (代码生成的源文件)

/test/robot_game/   # 压测机器人
```

## 架构模式

### 服务器生命周期
所有服务器遵循以下初始化模式:
1. 加载 TOML 配置
2. 首先初始化日志 (`log.InitLogfile`)
3. 加载游戏配置 (`config.NewConfigLoader().LoadAll`)
4. 创建服务 (RPC, HTTP, 数据库连接)
5. 使用 `cmd.NewApp()` 和 `cmd.WithServers()` 创建应用
6. 使用 `app.Run()` 运行 (处理优雅关闭)

### ORM 代码生成
`/tools/orm/conv` 生成器从 `/resources/orm` 中的 XML 定义创建 Go/Redis/MongoDB/Protobuf 绑定。修改 XML 定义后，运行 `make orm` 重新生成。不要直接编辑 `/orm/golang`、`/orm/redis`、`/orm/mongo`。

### 服务通信
- 内部 RPC: `common/rpc` 中的自定义 gRPC 包装器
- 服务注册/发现: 通过 `common/register`
- Proto 定义在 `/resources/proto/`

## 代码风格

- 文件名: 小写加下划线
- 函数/变量: 驼峰命名
- 公开导出: 大驼峰命名
- 公共代码放在 `/common` 包中
- 代码检查: golangci-lint，Go 1.25 (见 `.golangci.yml`)
- Depguard 规则: 使用 `go.uber.org/atomic` 替代 `sync/atomic`，使用 `github.com/google/uuid` 替代 `pborman/uuid`

## 重要说明

- `scene_server` 构建时保留调试信息并禁用优化，便于性能分析
- Git submodules: `base` (gobase 库) 和 `resources/proto` (协议定义)
- `/common/config/cfg_*.go` 中的游戏配置是自动生成的 - 数据源是游戏数据系统
