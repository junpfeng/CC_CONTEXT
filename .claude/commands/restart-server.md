---
description: 重启/停止游戏服务器集群
argument-hint: "[stop]"
---

## 参数解析

用户传入的参数：action=`$ARGUMENTS`

- `stop`（不区分大小写）：仅停止所有服务器进程
- 空或其他值：重启服务器（停止 → 编译 → 启动）

---

## 执行流程

### 第一步：停止所有服务器进程

通过 PowerShell 调用 bat 脚本（绕过 MSYS 对 Windows 命令的拦截）：

```bash
powershell.exe -Command "cmd.exe /C 'E:\gta\Projects\Server\scripts\stop_all.bat'"
```

timeout **30000**ms。

**如果 action 为 `stop`，到此结束，向用户输出"所有服务器已停止"。**

---

### 第二步：重新编译

Bash timeout 设置 **300000**ms（5 分钟，全量编译较慢）：

```bash
cd E:/gta/Projects/Server && make build
```

- Makefile 已配置 `EXE_EXT`，Windows 上自动输出 `.exe` 后缀
- 编译失败 → **立即停止**，输出错误给用户，不继续启动
- 编译成功 → 继续下一步

---

### 第三步：启动服务器集群

⚠️ **关键经验**：
- MSYS bash 的 `cmd.exe //C start_local.bat` 不可用（`start`/`timeout` 被 MSYS 拦截）
- bash 后台进程（`&`）随 bash 退出被终止，不能用
- 必须用 **CMD `start` 命令**启动独立窗口进程（每个服务器一个 CMD 窗口，日志可直接查看）
- 使用 `scripts/start_local.bat`，它用 CMD `start` 为每个进程创建独立窗口

通过 PowerShell 调用 bat 脚本（绕过 MSYS 对 `start`/`timeout` 的拦截）：

```bash
powershell.exe -Command "cmd.exe /C 'E:\gta\Projects\Server\scripts\start_local.bat'"
```

timeout **60000**ms。

---

### 第四步：验证进程

通过 PowerShell 调用验证脚本：

```bash
sleep 5 && powershell.exe -Command "cmd.exe /C 'E:\gta\Projects\Server\scripts\check_servers.bat'"
```

timeout **30000**ms。

脚本输出格式：
- `[Server Check] 15/15 processes running.` + `[OK] All servers running.` — 全部正常
- `[Server Check] N/15 processes running.` + `[MISSING] xxx yyy` — 有缺失，报告给用户

---

### 第五步：输出结果

简洁报告：
1. 停止了多少个旧进程
2. 编译结果（成功/失败）
3. 启动结果：运行中的服务器数量（期望 15 个）

---

## 脚本清单

| 脚本 | 路径 | 用途 |
|------|------|------|
| stop_all.bat | `P1GoServer/scripts/stop_all.bat` | 停止所有服务器进程 |
| start_local.bat | `P1GoServer/scripts/start_local.bat` | 启动所有服务器（每个独立 CMD 窗口） |
| check_servers.bat | `P1GoServer/scripts/check_servers.bat` | 检查 15 个服务器进程是否全部运行 |

⚠️ 所有 bat 脚本必须通过 `powershell.exe -Command "cmd.exe /C '...'"` 调用，直接在 MSYS bash 中运行会因 `find`/`start`/`timeout` 命令被拦截而失败。
