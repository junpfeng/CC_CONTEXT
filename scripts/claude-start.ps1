<#
.SYNOPSIS
    一键启动 Claude Code + Watchdog 后台监控
.DESCRIPTION
    启动 watchdog 后台监控，然后打开 Claude Code 交互式会话。
    Claude 退出后 watchdog 继续运行（下次启动会自动检测跳过）。
.PARAMETER NoWatchdog
    不启动 watchdog，仅启动 claude
.PARAMETER WatchdogInterval
    watchdog 检查间隔（秒），默认 30
.EXAMPLE
    .\claude-start.ps1
    .\claude-start.ps1 -NoWatchdog
#>

param(
    [switch]$NoWatchdog,
    [int]$WatchdogInterval = 30
)

$scriptDir = $PSScriptRoot
$watchdogScript = "$scriptDir\claude-watchdog.ps1"

# 1. 启动 watchdog（如果未运行）
if (-not $NoWatchdog) {
    if (Test-Path $watchdogScript) {
        & $watchdogScript -AutoKill -Background -Interval $WatchdogInterval
    } else {
        Write-Host "警告: watchdog 脚本不存在: $watchdogScript" -ForegroundColor Yellow
    }
}

# 2. 启动 claude 交互式会话
Write-Host ""
& claude
