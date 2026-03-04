---
paths:
  - "servers/**/*.go"
  - "common/**/*.go"
  - "pkg/**/*.go"
---

# Go 代码规范

## 命名

文件名小写下划线，函数/变量驼峰，导出大驼峰，常量大写下划线（如 `MAX_PLAYER_COUNT`）。

## 时间包

**禁止直接用 `time` 包获取当前时间**（游戏服务做了 UTC+8 偏移），必须用 `common/mtime`：

| 禁止 | 正确 |
|------|------|
| `time.Now()` | `mtime.NowTimeWithOffset()` |
| `time.Since(t)` | `mtime.Since(t)` |
| `time.Now().Unix()` | `mtime.NowSecondTickWithOffset()` |
| `time.Now().UnixMilli()` | `mtime.NowMilliTickWithOffset()` |

`time.Duration`/`time.Sleep`/`time.NewTicker` 等可直接用 `mtime` 重导出别名。

## 自动生成代码（勿手动编辑）

ORM 目录和 `cfg_*.go` 见 `constitution.md`。另外：`*_pb.go`、`common/proto/scene_service.go`、`common/proto/scene_client.go`、`servers/scene_server/internal/common/message_cache.go`、`servers/scene_server/internal/net_func/server_func.go`、`servers/scene_server/internal/service/scene_service.go`。
