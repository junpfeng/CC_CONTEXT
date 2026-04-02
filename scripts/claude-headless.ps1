<#
.SYNOPSIS
    非交互式运行 Claude Code，实时显示执行过程，默认跳过所有权限确认
.PARAMETER Prompt
    任务描述（必填）
.PARAMETER Safe
    安全模式，不跳过权限确认
.PARAMETER ExtraArgs
    传给 claude 的额外参数（如 --max-turns 5）
.EXAMPLE
    .\claude-headless.ps1 "检查代码中的 bug"
    .\claude-headless.ps1 "重构 auth 模块" -ExtraArgs "--max-turns","5"
    .\claude-headless.ps1 "分析日志" -Safe
    .\claude-headless.ps1 "测试" -NoWatchdog
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Prompt,
    [switch]$Safe,
    [switch]$NoWatchdog,
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Continue"

if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
    Write-Host "错误: claude 未找到" -ForegroundColor Red
    exit 1
}

# 自动启动 watchdog（已运行则跳过）
if (-not $NoWatchdog) {
    $watchdogScript = "$PSScriptRoot\claude-watchdog.ps1"
    if (Test-Path $watchdogScript) {
        & $watchdogScript -AutoKill -Background
    }
}

# 日志
$logDir = "$PSScriptRoot\..\logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "$logDir\claude-headless-${ts}.json"

# claude 参数
$claudeArgs = @("-p", $Prompt, "--output-format", "stream-json", "--verbose")
if (-not $Safe) { $claudeArgs += "--dangerously-skip-permissions" }
$claudeArgs += $ExtraArgs

$permLabel = "跳过权限确认"
if ($Safe) { $permLabel = "安全模式" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code 非交互式执行" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  任务: $Prompt"
Write-Host "  权限: $permLabel"
Write-Host "  日志: $logFile"
if ($ExtraArgs.Count -gt 0) { Write-Host "  额外: $($ExtraArgs -join ' ')" }
Write-Host ""

# 运行 claude，逐行解析
& claude @claudeArgs 2>$null | ForEach-Object {
    $line = $_

    # 写日志
    Add-Content -Path $logFile -Value $line -Encoding UTF8

    # 解析 JSON
    $obj = $null
    try { $obj = ($line | ConvertFrom-Json) } catch { return }
    if (-not $obj.type) { return }

    switch ($obj.type) {
        "assistant" {
            if (-not $obj.message -or -not $obj.message.content) { break }
            foreach ($block in $obj.message.content) {
                switch ($block.type) {
                    "thinking" {
                        if ($block.thinking) {
                            $display = $block.thinking
                            if ($display.Length -gt 200) { $display = $display.Substring(0, 200) + "..." }
                            Write-Host ("[思考] " + $display) -ForegroundColor DarkGray
                        }
                    }
                    "text" {
                        if ($block.text) { Write-Host $block.text }
                    }
                    "tool_use" {
                        $inputStr = ""
                        try { $inputStr = ($block.input | ConvertTo-Json -Compress) } catch {}
                        if ($inputStr.Length -gt 120) { $inputStr = $inputStr.Substring(0, 120) + "..." }
                        Write-Host ("[工具] " + $block.name + " -> " + $inputStr) -ForegroundColor Cyan
                    }
                }
            }
        }
        "result" {
            if ($obj.result) {
                Write-Host ""
                Write-Host "========================================" -ForegroundColor Green
                Write-Host "  执行完成" -ForegroundColor Green
                Write-Host "========================================" -ForegroundColor Green
                Write-Host $obj.result
            }
        }
    }
}

Write-Host ""
Write-Host ("日志: " + $logFile) -ForegroundColor DarkGray
