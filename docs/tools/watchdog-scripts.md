# 监控与自动化脚本

## 脚本总览

| 脚本 | 用途 | 入口 |
|------|------|------|
| `scripts/claude-start.ps1` | 一键启动（watchdog + claude 交互会话） | 日常使用 |
| `scripts/claude-headless.ps1` | 非交互式执行任务，实时看过程（PowerShell） | 无人值守 |
| `scripts/claude-headless.sh` | 同上（Bash/Git Bash 版，依赖 jq） | 无人值守 |
| `scripts/claude-watchdog.ps1` | 后台监控（Claude 卡住 / Unity 崩溃 / MCP 断连） | 被前两个自动拉起 |
| `scripts/unity-restart.ps1` | 手动重启 Unity / MCP | 手动操作 |

## 日常使用

```powershell
# 交互式（推荐）
.\scripts\claude-start.ps1

# 无人值守跑任务
.\scripts\claude-headless.ps1 "任务描述"
.\scripts\claude-headless.ps1 "任务描述" -ExtraArgs "--max-turns","10"
.\scripts\claude-headless.ps1 "任务描述" -Safe   # 不跳过权限

# 管理 watchdog
.\scripts\claude-watchdog.ps1 -Stop              # 停止
cat logs\watchdog.log                             # 看日志

# 手动重启 Unity/MCP
.\scripts\unity-restart.ps1 status
.\scripts\unity-restart.ps1 mcp
.\scripts\unity-restart.ps1 unity
.\scripts\unity-restart.ps1 all -Force
```

## claude-headless.sh（Bash 版）

PowerShell 版的 Bash 移植，适用于 Git Bash / MSYS2 / WSL。

```bash
# 基本用法
sh scripts/claude-headless.sh "任务描述"
sh scripts/claude-headless.sh "任务描述" --max-turns 5
sh scripts/claude-headless.sh "任务描述" --safe   # 不跳过权限
```

### 依赖

- **jq**：`winget install jqlang.jq`。脚本自动补全 winget 安装路径到 PATH

### 实现要点

- 输出解析用**单个 `jq --unbuffered -r`** 流式处理整个 stream-json，不能用 `while read | jq`（Git Bash 下每行 fork jq 进程极慢，看起来像卡住）
- `tee` 同时写日志 + 送 jq 解析
- `|| true` 吞掉 jq 非零退出码，避免 `pipefail` 误报
- stderr 重定向到 `.err` 文件，结束后有内容才显示

### Unity MCP 崩溃恢复测试结论

| 场景 | 行为 |
|------|------|
| Unity 被杀（MCP 断连） | Claude 检测到 MCP 不可用，自动降级尝试 `mcp_call.py` 直连，最终正常退出 |
| Unity 重启后再次运行 | MCP 约 30-40 秒恢复，脚本完整执行所有 MCP 调用 |

> **注意**：bash 版不含 watchdog，Unity 崩溃不会自动重启。需要自动恢复时用 PowerShell 版。

## Watchdog 监控机制

### Claude 卡住检测

- **判定标准**：session `.jsonl` 文件连续 15 分钟无更新 + Claude 进程存在
- **原理**：Claude Code 在对话中实时逐条写入 session 文件（每次工具调用、回复都是一行），文件长时间不变说明无输出
- **排除误判**：进程不在时（正常退出）不触发；刚启动未发消息时无 session 文件也不触发

### 处理流程

```
session 文件 15 分钟无更新 + 进程在
    ↓
阶段 1：Windows 弹窗通知 + 蜂鸣声（给用户 2 分钟手动 Ctrl+C）
    ↓ 用户处理了 → session 恢复活跃 → 重置，结束
    ↓ 2 分钟没反应
    ↓
阶段 2：kill 进程 → claude --continue -p "你卡住了，继续任务"
    ↓ 恢复结果存到 logs/claude-recovery-*.txt
    ↓ 同一会话最多重试 3 次
```

### Unity / MCP 自动恢复

| 故障 | 自动动作 |
|------|---------|
| Unity 进程消失 | 重启 Unity → 等 MCP 跟起来 |
| MCP 进程消失 + Unity 在 | 只拉起 MCP Server |
| MCP 进程在但端口不通（连续 3 次） | 重启 MCP Server |
| Unity + MCP 都没了 | 重启 Unity（带起 MCP） |

### 已知限制

- **无法给运行中的 Claude 发消息**：Windows ConPTY 限制，外部进程无法注入键盘输入到 Claude 终端
- **Unity 重启后 Claude 需重连 MCP**：watchdog 恢复了 Unity/MCP，但当前 Claude 会话的 MCP 客户端不会自动重连，需要退出后 `claude -c` 重新进入
- **Unity 恢复期间 Claude 监控暂停**：`Restart-UnityEditor` 是同步阻塞的（最长 ~4 分钟）

## 技术要点

### PS 5.1 兼容

- 不用 `$x = if () {} else {}`，改为 `$x = default; if () { $x = ... }`
- 不用 `$x = try {} catch {}`，改为 `$x = $null; try { $x = ... } catch {}`
- 所有 `.ps1` 文件必须带 UTF-8 BOM（中文 Windows 默认 GBK）
- `claude` 是 `.ps1` 脚本不是 `.exe`，不能用 `System.Diagnostics.Process`，用 `& claude` 管道

### 日志位置

| 文件 | 内容 |
|------|------|
| `logs/watchdog.log` | watchdog 后台运行日志 |
| `logs/watchdog.pid` | watchdog 进程 PID |
| `logs/claude-headless-*.json` | headless 执行的 stream-json 原始输出 |
| `logs/claude-recovery-*.txt` | 卡住恢复后的 claude 回复 |
