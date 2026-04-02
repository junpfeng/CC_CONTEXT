<#
.SYNOPSIS
    Claude Code + Unity/MCP 统一监控与自动恢复
.DESCRIPTION
    持续监控：
    1. Claude Code 进程 — 检测卡死/内存溢出，自动 kill 并用 --continue 恢复会话
    2. Unity Editor — 检测崩溃，自动重启
    3. MCP Server — 检测断连，自动恢复
.PARAMETER Interval
    检查间隔（秒），默认 30
.PARAMETER AutoKill
    自动 kill 卡死的 Claude 进程并恢复会话，默认 false
.PARAMETER NoAutoRecover
    禁用 Unity/MCP 自动恢复（默认开启自动恢复）
.PARAMETER MaxClaudeRetries
    同一会话最大自动恢复次数，默认 3
.PARAMETER Background
    后台运行（隐藏窗口，输出到日志文件）
.EXAMPLE
    # 完整自动监控（推荐，Unity/MCP 默认自动恢复）
    .\claude-watchdog.ps1 -AutoKill
    # 后台运行（推荐日常使用）
    .\claude-watchdog.ps1 -AutoKill -Background
    # 停止后台 watchdog
    .\claude-watchdog.ps1 -Stop
    # 仅监控不处理（Claude 不 kill，Unity/MCP 不恢复）
    .\claude-watchdog.ps1 -NoAutoRecover
    # 自定义间隔和重试次数
    .\claude-watchdog.ps1 -AutoKill -Interval 15 -MaxClaudeRetries 5
#>

param(
    [int]$Interval = 30,
    [switch]$AutoKill,
    [switch]$NoAutoRecover,
    [int]$MaxClaudeRetries = 3,
    [switch]$Background,
    [switch]$Stop
)

# ===== -Stop：停止后台 watchdog =====
$pidFile = "$PSScriptRoot\..\logs\watchdog.pid"
if ($Stop) {
    if (Test-Path $pidFile) {
        $pidContent = (Get-Content $pidFile -Raw -ErrorAction SilentlyContinue)
        if (-not $pidContent -or -not $pidContent.Trim()) {
            Remove-Item $pidFile -Force
            Write-Host "pid 文件为空，已清理" -ForegroundColor Yellow
            exit 0
        }
        $bgPid = [int]$pidContent.Trim()
        $bgProc = Get-Process -Id $bgPid -ErrorAction SilentlyContinue
        if ($bgProc) {
            Stop-Process -Id $bgPid -Force
            Write-Host "Watchdog (PID=$bgPid) 已停止" -ForegroundColor Green
        } else {
            Write-Host "Watchdog 进程 (PID=$bgPid) 已不存在" -ForegroundColor Yellow
        }
        Remove-Item $pidFile -Force
    } else {
        Write-Host "没有运行中的后台 watchdog" -ForegroundColor Yellow
    }
    exit 0
}

# ===== -Background：后台启动自身 =====
if ($Background) {
    $logDir = "$PSScriptRoot\..\logs"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    $logFile = "$logDir\watchdog.log"

    # 检查是否已有 watchdog 在运行
    if (Test-Path $pidFile) {
        $pidContent = (Get-Content $pidFile -Raw -ErrorAction SilentlyContinue)
        if ($pidContent -and $pidContent.Trim()) {
            $existingPid = [int]$pidContent.Trim()
        } else {
            $existingPid = 0
        }
        $existingProc = $null
        if ($existingPid -gt 0) { $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue }
        if ($existingProc) {
            Write-Host "Watchdog 已在后台运行 (PID=$existingPid)，跳过重复启动" -ForegroundColor Yellow
            Write-Host "  日志: $logFile"
            Write-Host "  停止: .\claude-watchdog.ps1 -Stop"
            exit 0
        }
    }

    # 构建参数（转发除 -Background 外的所有参数）
    $fwdArgs = @("-Interval", $Interval, "-MaxClaudeRetries", $MaxClaudeRetries)
    if ($AutoKill) { $fwdArgs += "-AutoKill" }
    if ($NoAutoRecover) { $fwdArgs += "-NoAutoRecover" }

    $scriptPath = $MyInvocation.MyCommand.Path
    $projectDir = (Resolve-Path "$PSScriptRoot\..").Path
    $allArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) + $fwdArgs
    $proc = Start-Process -FilePath "powershell" -ArgumentList $allArgs -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru -RedirectStandardOutput $logFile -RedirectStandardError "$logDir\watchdog.err"

    # 保存 PID
    $proc.Id | Out-File -FilePath $pidFile -Encoding ascii -NoNewline

    Write-Host "Watchdog 已后台启动" -ForegroundColor Green
    Write-Host "  PID:  $($proc.Id)"
    Write-Host "  日志: $logFile"
    Write-Host "  停止: .\claude-watchdog.ps1 -Stop"
    exit 0
}

$AutoRecover = -not $NoAutoRecover

$ErrorActionPreference = "Continue"

# ===== Unity/MCP 配置 =====
$UnityExe = "E:\workspace\Unity\Editor\Unity.exe"
$ProjectPath = "E:\workspace\PRJ\P1\freelifeclient"
$McpServerPath = "$ProjectPath\Library\mcp-server\win-x64\unity-mcp-server.exe"
$McpPort = 8080

# ===== Claude 会话配置 =====
$ClaudeSessionDir = "$env:USERPROFILE\.claude\projects\E--workspace-PRJ-P1"
$ClaudeStallMinutes = 15   # 硬性指标：session 文件 15 分钟无更新 = 卡住

# ===== 状态跟踪 =====
$mcpFailCount = 0          # MCP 连续失败次数
$unityRecovering = $false  # Unity 正在恢复中，跳过重复触发
$claudeRetryCount = @{}    # 每个会话的重试计数
$claudeAlreadyKilled = @{} # 已 kill 的会话，避免重复 kill
$claudeNotified = @{}      # 已通知的会话（通知后等 2 分钟再 kill）

# ===== 工具函数 =====
function Write-Status($icon, $msg, $color = "White") {
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $icon " -NoNewline -ForegroundColor DarkGray
    Write-Host $msg -ForegroundColor $color
}

function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return "{0:N1} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N0} KB" -f ($bytes / 1KB)
}

# ===== Claude Code 检测 =====
function Get-ClaudeProcesses {
    $nodeProcs = Get-Process -Name "node" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
                $cmd -match "claude" -or $cmd -match "@anthropic-ai"
            } catch { $false }
        }
    $claudeProcs = Get-Process -Name "claude*" -ErrorAction SilentlyContinue
    $all = @()
    if ($nodeProcs) { $all += $nodeProcs }
    if ($claudeProcs) { $all += $claudeProcs }
    return $all | Sort-Object Id -Unique
}

function Get-ActiveSessionFiles {
    # 获取最近有更新的 session 文件（可能有多个 claude 实例各自的会话）
    if (-not (Test-Path $ClaudeSessionDir)) { return @() }
    Get-ChildItem -Path $ClaudeSessionDir -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-2) } |  # 只看 2 小时内活跃的
        Sort-Object LastWriteTime -Descending
}

function Test-SessionStalled($sessionFile) {
    # 检查 session 文件是否超过 $ClaudeStallMinutes 分钟未更新
    $minutesSinceWrite = ((Get-Date) - $sessionFile.LastWriteTime).TotalMinutes
    return ($minutesSinceWrite -ge $ClaudeStallMinutes)
}

# ===== Unity 检测 =====
function Get-UnityProcesses {
    Get-Process -Name "Unity" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
                $cmd -match [regex]::Escape($ProjectPath)
            } catch { $false }
        }
}

function Get-McpServerProcess {
    Get-Process -Name "unity-mcp-server" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
                $cmd -match "port=$McpPort"
            } catch { $false }
        }
}

function Test-McpConnection {
    try {
        Invoke-WebRequest -Uri "http://localhost:$McpPort" -Method GET -TimeoutSec 3 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# ===== Claude 卡住通知 =====
function Send-StallNotification([int]$minutesAgo) {
    # 蜂鸣声提醒
    try {
        [System.Console]::Beep(800, 500)
        [System.Console]::Beep(800, 500)
    } catch {}

    # Windows 气泡通知（非阻塞）
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $script:_notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $script:_notifyIcon.Icon = [System.Drawing.SystemIcons]::Warning
        $script:_notifyIcon.BalloonTipIcon = "Warning"
        $script:_notifyIcon.BalloonTipTitle = "Claude Code 卡住了"
        $script:_notifyIcon.BalloonTipText = "会话已 ${minutesAgo} 分钟无输出。请手动 Ctrl+C，或等 2 分钟后自动 kill + 恢复。"
        $script:_notifyIcon.Visible = $true
        $script:_notifyIcon.ShowBalloonTip(10000)
        # 不阻塞等待，下次调用时清理上一个
    } catch {
        Write-Status "!!" "  [通知] Claude 卡住 ${minutesAgo}m，等待手动 Ctrl+C 或 2min 后自动 kill" "Yellow"
    }
}

function Dispose-StallNotification {
    if ($script:_notifyIcon) {
        try { $script:_notifyIcon.Dispose() } catch {}
        $script:_notifyIcon = $null
    }
}

# ===== Claude 卡住恢复 =====
function Invoke-ClaudeRecovery {
    # kill 后用 --continue 恢复会话，追问卡住原因并继续任务
    Dispose-StallNotification
    $logDir = "E:\workspace\PRJ\P1\logs"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = "$logDir\claude-recovery-${ts}.txt"

    $recoveryPrompt = "你刚才的响应卡住了（watchdog 检测到超时无输出被强制终止）。请：1) 简要说明卡在哪一步、可能原因 2) 继续完成之前未完成的任务。如果之前的任务已经完成，直接说明即可。"

    Write-Status ">>" "  恢复会话: claude --continue -p ..." "Cyan"

    $recoverArgs = @(
        "--continue"
        "-p"
        $recoveryPrompt
        "--output-format"
        "text"
        "--dangerously-skip-permissions"
        "--max-turns"
        "10"
    )

    try {
        $result = & claude @recoverArgs 2>&1
        $result | Out-File -FilePath $logFile -Encoding utf8

        Write-Status "OK" "  恢复完成，输出已保存: $logFile" "Green"

        # 在 watchdog 终端显示恢复摘要（前 5 行）
        $lines = $result -split "`n" | Select-Object -First 5
        foreach ($l in $lines) {
            Write-Host "    | $l" -ForegroundColor DarkCyan
        }
        if (($result -split "`n").Count -gt 5) {
            Write-Host "    | ... (完整内容见 $logFile)" -ForegroundColor DarkGray
        }
    } catch {
        Write-Status "!!" "  恢复失败: $_" "Red"
    }
}

# ===== 恢复动作 =====
function Restart-McpServer {
    Write-Status ">>" "正在重启 MCP Server..." "Magenta"

    # 关闭旧进程
    $proc = Get-McpServerProcess
    if ($proc) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # 启动新进程
    if (Test-Path $McpServerPath) {
        Start-Process -FilePath $McpServerPath `
            -ArgumentList "port=$McpPort", "plugin-timeout=10000", "client-transport=streamableHttp", "authorization=none" `
            -WindowStyle Hidden
        Start-Sleep -Seconds 3

        if (Test-McpConnection) {
            Write-Status "OK" "MCP Server 已恢复  端口=$McpPort" "Green"
            return $true
        } else {
            Write-Status "!!" "MCP Server 启动但连接失败" "Red"
            return $false
        }
    } else {
        Write-Status "!!" "MCP Server 不存在: $McpServerPath" "Red"
        return $false
    }
}

function Restart-UnityEditor {
    # 注意：此函数是同步阻塞的（最长 ~4 分钟），期间主循环暂停，Claude 监控也会暂停
    $script:unityRecovering = $true
    Write-Status ">>" "正在重启 Unity Editor（期间 Claude 监控暂停）..." "Magenta"

    # 关闭 MCP
    $mcpProc = Get-McpServerProcess
    if ($mcpProc) {
        Stop-Process -Id $mcpProc.Id -Force -ErrorAction SilentlyContinue
    }

    # 关闭 Unity
    $unityProcs = Get-UnityProcesses
    foreach ($p in $unityProcs) {
        Write-Status ">>" "关闭 Unity PID=$($p.Id)" "Yellow"
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 5

    # 启动 Unity
    Write-Status ">>" "启动 Unity（需要 1-3 分钟）..." "Yellow"
    Start-Process -FilePath $UnityExe -ArgumentList "-projectpath", $ProjectPath

    # 等待 Unity 启动
    $elapsed = 0
    while ($elapsed -lt 180) {
        Start-Sleep -Seconds 10
        $elapsed += 10
        $procs = Get-UnityProcesses
        if ($procs) {
            Write-Status "OK" "Unity Editor 已启动  PID=$($procs[0].Id)  耗时=${elapsed}s" "Green"

            # 等待 MCP 自动跟起来
            Write-Status ".." "等待 MCP Server 自动启动..." "DarkGray"
            $mcpElapsed = 0
            while ($mcpElapsed -lt 60) {
                Start-Sleep -Seconds 5
                $mcpElapsed += 5
                if (Test-McpConnection) {
                    Write-Status "OK" "MCP Server 就绪  端口=$McpPort" "Green"
                    $script:unityRecovering = $false
                    return $true
                }
            }

            # MCP 没自动起来，手动拉
            Write-Status "!!" "MCP 未自动启动，手动拉起..." "Yellow"
            $result = Restart-McpServer
            $script:unityRecovering = $false
            return $result
        }
    }

    Write-Status "!!" "Unity 启动超时（180s）" "Red"
    $script:unityRecovering = $false
    return $false
}

# ===== 主循环 =====
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Watchdog: Claude Code + Unity + MCP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  间隔:       ${Interval}s"
Write-Host "  Claude:     AutoKill=$AutoKill  卡死=${ClaudeStallMinutes}分钟无输出  恢复重试=$MaxClaudeRetries"
Write-Host "  Unity/MCP:  AutoRecover=$AutoRecover  端口=$McpPort"
Write-Host "  Ctrl+C 停止"
Write-Host ""

while ($true) {
    Write-Host ""
    Write-Status "==" "--- 检查轮次 $(Get-Date -Format 'HH:mm:ss') ---" "DarkGray"

    # ========== 1. Claude Code 检测（基于 session 文件活跃度）==========
    $procs = Get-ClaudeProcesses
    $sessions = Get-ActiveSessionFiles

    if ($procs.Count -eq 0) {
        Write-Status "--" "Claude Code: 无进程" "DarkGray"
    } else {
        Write-Status "OK" "Claude Code: $($procs.Count) 个进程" "Green"

        # 显示进程基本信息
        foreach ($p in $procs) {
            $memMB = [math]::Round($p.WorkingSet64 / 1MB, 0)
            Write-Host "    PID $($p.Id) | $(Format-Size $p.WorkingSet64)" -ForegroundColor Green
        }
    }

    # 核心判断：session 文件是否超过 15 分钟无更新
    if ($sessions.Count -eq 0) {
        if ($procs.Count -gt 0) {
            Write-Status ".." "Claude 会话: 无活跃 session 文件" "DarkGray"
        }
    } else {
        foreach ($sf in $sessions | Select-Object -First 3) {
            $minutesAgo = [math]::Round(((Get-Date) - $sf.LastWriteTime).TotalMinutes, 1)
            $sizeMB = [math]::Round($sf.Length / 1MB, 1)
            $sessionId = $sf.BaseName.Substring(0, 8)  # 显示 UUID 前 8 位
            $stalled = Test-SessionStalled $sf

            if ($stalled -and $procs.Count -gt 0) {
                # session 超时 + 进程还在 = 卡住（进程不在则是正常退出，不处理）
                Write-Host "    session $sessionId | ${sizeMB}MB | ${minutesAgo}m 无更新 | STALLED" -ForegroundColor Red

                if ($AutoKill -and -not $claudeAlreadyKilled.ContainsKey($sf.Name)) {
                    # 阶段 1：先通知，给用户 2 分钟手动处理
                    if (-not $claudeNotified.ContainsKey($sf.Name)) {
                        $claudeNotified[$sf.Name] = Get-Date
                        Write-Status "!!" "  检测到卡住，先通知用户（2 分钟内未恢复则自动 kill）" "Yellow"
                        Send-StallNotification $minutesAgo
                    } else {
                        # 阶段 2：通知已发出，检查是否已等 2 分钟
                        $waitedMinutes = ((Get-Date) - $claudeNotified[$sf.Name]).TotalMinutes
                        if ($waitedMinutes -ge 2) {
                            # 2 分钟过了还是卡着 → kill + 恢复
                            $claudeAlreadyKilled[$sf.Name] = $true
                            $claudeNotified.Remove($sf.Name)

                            Write-Status ">>" "  通知后 2 分钟仍未恢复，执行 kill + 自动恢复" "Magenta"

                            foreach ($p in $procs) {
                                Write-Status ">>" "  Auto-kill Claude PID=$($p.Id)" "Magenta"
                                try { Stop-Process -Id $p.Id -Force } catch {
                                    Write-Status "!!" "  Kill 失败: $_" "Red"
                                }
                            }

                            Start-Sleep -Seconds 2
                            $retryKey = $sf.Name
                            if (-not $claudeRetryCount.ContainsKey($retryKey)) { $claudeRetryCount[$retryKey] = 0 }
                            $claudeRetryCount[$retryKey]++

                            if ($claudeRetryCount[$retryKey] -le $MaxClaudeRetries) {
                                Write-Status ">>" "  自动恢复 ($($claudeRetryCount[$retryKey])/$MaxClaudeRetries)" "Cyan"
                                Invoke-ClaudeRecovery
                            } else {
                                Write-Status "!!" "  已达最大重试 ($MaxClaudeRetries)，不再自动恢复" "Red"
                            }
                        } else {
                            $remainSec = [math]::Round((2 - $waitedMinutes) * 60)
                            Write-Status ".." "  等待用户手动处理（${remainSec}s 后自动 kill）" "Yellow"
                        }
                    }
                }
            } elseif ($stalled) {
                # session 超时但进程已不在 — 正常退出，不处理
                Write-Host "    session $sessionId | ${sizeMB}MB | ${minutesAgo}m 前 | 已结束" -ForegroundColor DarkGray
            } else {
                $color = "Yellow"
                if ($minutesAgo -lt 1) { $color = "Green" } elseif ($minutesAgo -lt 5) { $color = "Cyan" }
                Write-Host "    session $sessionId | ${sizeMB}MB | ${minutesAgo}m 前更新 | OK" -ForegroundColor $color
            }
        }

        # 清理已恢复的会话标记（session 文件重新活跃时重置）
        $resetKeys = @($claudeAlreadyKilled.Keys | Where-Object {
            $sf = Get-Item (Join-Path $ClaudeSessionDir $_) -ErrorAction SilentlyContinue
            $sf -and -not (Test-SessionStalled $sf)
        })
        foreach ($k in $resetKeys) {
            $claudeAlreadyKilled.Remove($k)
            $claudeRetryCount.Remove($k)
            $claudeNotified.Remove($k)
        }
    }

    # ========== 2. Unity 检测 ==========
    if ($unityRecovering) {
        Write-Status ".." "Unity: 恢复中，跳过检测" "DarkGray"
    } else {
        $unityProcs = Get-UnityProcesses
        if ($unityProcs) {
            $upid = $unityProcs[0].Id
            $umem = [math]::Round($unityProcs[0].WorkingSet64 / 1MB, 0)
            Write-Status "OK" "Unity Editor: PID=$upid  内存=${umem}MB" "Green"
        } else {
            Write-Status "!!" "Unity Editor: 未运行（崩溃？）" "Red"
            if ($AutoRecover) {
                Restart-UnityEditor | Out-Null
            }
        }
    }

    # ========== 3. MCP 检测 ==========
    if ($unityRecovering) {
        Write-Status ".." "MCP Server: Unity 恢复中，跳过检测" "DarkGray"
    } else {
        $mcpProc = Get-McpServerProcess
        $mcpOk = Test-McpConnection

        if ($mcpProc -and $mcpOk) {
            Write-Status "OK" "MCP Server: PID=$($mcpProc.Id)  端口=$McpPort 可达" "Green"
            $mcpFailCount = 0
        } elseif ($mcpProc -and -not $mcpOk) {
            $mcpFailCount++
            Write-Status "!!" "MCP Server: 进程在但端口不可达 ($mcpFailCount/3)" "Yellow"
            if ($AutoRecover -and $mcpFailCount -ge 3) {
                Restart-McpServer | Out-Null
                $mcpFailCount = 0
            }
        } else {
            # 进程都不在
            $mcpFailCount++
            Write-Status "!!" "MCP Server: 未运行 ($mcpFailCount/2)" "Red"
            if ($AutoRecover -and $mcpFailCount -ge 2) {
                # Unity 在但 MCP 不在 → 只重启 MCP
                $unityProcs = Get-UnityProcesses
                if ($unityProcs) {
                    Restart-McpServer | Out-Null
                } else {
                    # Unity 也不在 → 重启 Unity（会带起 MCP）
                    Restart-UnityEditor | Out-Null
                }
                $mcpFailCount = 0
            }
        }
    }

    Start-Sleep -Seconds $Interval
}
