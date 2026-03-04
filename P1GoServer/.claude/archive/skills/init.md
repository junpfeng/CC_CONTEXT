---
name: init
description: 初始化分析项目结构和技术栈
---

# 项目初始化分析

当用户调用此 skill 时，全面分析项目结构并生成项目概览。

## 分析内容

### 1. 项目基本信息

- 项目名称
- 项目类型（Web 服务、CLI 工具、库等）
- 主要编程语言
- 框架和主要依赖

### 2. 目录结构分析

```
project/
├── cmd/           # 主程序入口
├── internal/      # 私有代码
├── pkg/           # 公共库
├── api/           # API 定义
├── configs/       # 配置文件
├── scripts/       # 脚本
├── test/          # 测试
└── docs/          # 文档
```

### 3. 技术栈识别

- **Web 框架**: gin, echo, fiber, chi 等
- **数据库**: MySQL, PostgreSQL, MongoDB, Redis 等
- **ORM**: gorm, ent, sqlx 等
- **消息队列**: Kafka, RabbitMQ, NSQ 等
- **配置管理**: viper, envconfig 等
- **日志**: zap, logrus, zerolog 等

### 4. 关键文件识别

- 入口文件 (main.go)
- 配置文件
- 路由定义
- 数据模型
- 业务逻辑

### 5. 开发规范

- 代码风格
- 目录命名约定
- 错误处理模式
- 测试规范

## 输出格式

```markdown
# 项目分析报告

## 基本信息
- **项目名称**: xxx
- **类型**: Web 服务
- **Go 版本**: 1.21
- **模块名**: github.com/xxx/xxx

## 技术栈
| 类别 | 技术 | 版本 |
|------|------|------|
| Web 框架 | Gin | v1.9.0 |
| 数据库 | MySQL | - |
| ORM | GORM | v1.25.0 |

## 目录结构
[树形结构]

## 核心模块
1. **模块A**: 描述
2. **模块B**: 描述

## 入口点
- 主入口: cmd/server/main.go
- API 路由: internal/router/router.go

## 配置
- 配置文件: configs/config.yaml
- 环境变量: .env

## 开发命令
- 运行: `go run cmd/server/main.go`
- 测试: `go test ./...`
- 构建: `go build -o bin/server cmd/server/main.go`

## 建议
[基于分析给出的改进建议]
```

## 使用方式

- `/init` - 分析当前项目
- `/init path/to/project` - 分析指定项目
- `/init --deep` - 深度分析（包括代码质量）
