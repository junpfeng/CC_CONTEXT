---
name: build-server
description: 构建 Go 游戏服务器。当用户说"构建服务器"、"编译"、"make build"、"make all"时使用
allowed-tools: Bash, Read, Glob
argument-hint: "[服务器名称，如 scene_server]"
---

# 构建 Go 服务器

在 `P1GoServer/` 目录下执行构建命令。

## 使用方式

- `/build-server` - 构建所有服务器
- `/build-server scene_server` - 构建指定服务器
- `/build-server db_server logic_server` - 构建多个服务器

## 执行步骤

1. 切换到当前项目跟目录
2. 如果指定了 `$ARGUMENTS`，执行 `make $ARGUMENTS`
3. 如果没有参数，执行 `make build`
4. 报告构建结果
