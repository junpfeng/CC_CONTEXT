# server.ps1 — P1GoServer 服务管理

脚本路径：`scripts/server.ps1`，PowerShell 5.1+，工作目录任意。

## 用法

```powershell
.\scripts\server.ps1 start                              # 启动所有服务
.\scripts\server.ps1 stop                               # 停止所有服务（逆序）
.\scripts\server.ps1 restart                            # 重启所有服务
.\scripts\server.ps1 status                             # 查看所有服务运行状态
.\scripts\server.ps1 start db_server                    # 只启动指定服务
.\scripts\server.ps1 restart login_server proxy_server  # 重启指定服务
```

## 服务列表（按启动优先级，停服逆序）

| 优先级 | 服务名 | 说明 |
|--------|--------|------|
| 1 | `register_server` | 服务注册中心（最先启动） |
| 2 | `db_server` | 数据库层 |
| 3 | `dbproxy_server` | 数据库代理 |
| 4 | `manager_server` | 场景调度 |
| 5 | `logic_server` / `scene_server` | 核心游戏逻辑 / 游戏世界实例 |
| 6 | `relation_server` / `team_server` / `chat_server` | 社交辅助 |
| 7 | `login_server` / `match_server` / `workshop_server` / `mail_server` / `gm_server` | 业务服务 |
| 8 | `proxy_server` | 服务代理 |
| 9 | `gateway_server` | 客户端网关（最后启动） |

## 关键路径

| 用途 | 路径 |
|------|------|
| 二进制 | `P1GoServer/bin/<服务名>.exe` |
| 配置 | `P1GoServer/bin/config.toml` |
| 标准输出日志 | `P1GoServer/log/out/<服务名>.log` |
| 错误日志 | `P1GoServer/log/err/<服务名>.log` |
| PID 文件 | `run/<服务名>.pid` |
