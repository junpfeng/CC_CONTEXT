<#
.SYNOPSIS
    重启 Unity Editor 和 ai-game-developer MCP 服务
.DESCRIPTION
    检测并恢复 Unity / MCP 连接：
    - unity   : 重启 Unity Editor（关闭→重新打开项目）
    - mcp     : 仅重启 MCP 服务进程（unity-mcp-server）
    - all     : 全部重启
    - status  : 查看当前状态
.PARAMETER Action
    操作：status | mcp | unity | all（默认 status）
.PARAMETER Force
    强制 kill（不等待正常退出）
.EXAMPLE
    .\unity-restart.ps1 status
    .\unity-restart.ps1 mcp
    .\unity-restart.ps1 unity
    .\unity-restart.ps1 all -Force
#>

param(
    [ValidateSet("status", "mcp", "unity", "all")]
    [string]$Action = "status",
    [switch]$Force
)

$ErrorActionPreference = "Continue"

# ===== 配置 =====
$UnityExe = "E:\workspace\Unity\Editor\Unity.exe"
$ProjectPath = "E:\workspace\PRJ\P1\freelifeclient"
$McpServerPath = "$ProjectPath\Library\mcp-server\win-x64\unity-mcp-server.exe"
$McpPort = 8080

# ===== 工具函数 =====
function Write-Status($icon, $msg, $color = "White") {
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $icon " -NoNewline -ForegroundColor DarkGray
    Write-Host $msg -ForegroundColor $color
}

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

function Show-Status {
    Write-Host ""
    Write-Host "===== Unity / MCP 状态 =====" -ForegroundColor Cyan

    # Unity
    $unityProcs = Get-UnityProcesses
    if ($unityProcs) {
        foreach ($p in $unityProcs) {
            $memMB = [math]::Round($p.WorkingSet64 / 1MB, 0)
            Write-Status "OK" "Unity Editor  PID=$($p.Id)  内存=${memMB}MB" "Green"
        }
    } else {
        Write-Status "!!" "Unity Editor  未运行" "Red"
    }

    # MCP Server (unity-mcp-server)
    $mcpProc = Get-McpServerProcess
    if ($mcpProc) {
        Write-Status "OK" "MCP Server    PID=$($mcpProc.Id)  端口=$McpPort" "Green"
    } else {
        Write-Status "!!" "MCP Server    未运行" "Red"
    }

    # MCP 连接测试
    $connected = Test-McpConnection
    if ($connected) {
        Write-Status "OK" "MCP 连接      localhost:$McpPort 可达" "Green"
    } else {
        Write-Status "!!" "MCP 连接      localhost:$McpPort 不可达" "Red"
    }

    Write-Host ""
    return @{
        UnityRunning = ($null -ne $unityProcs -and $unityProcs.Count -gt 0)
        McpRunning   = ($null -ne $mcpProc)
        McpReachable = $connected
    }
}

function Stop-UnityEditor {
    $procs = Get-UnityProcesses
    if (-not $procs) {
        Write-Status "--" "Unity 未运行，跳过关闭" "DarkGray"
        return
    }

    foreach ($p in $procs) {
        if ($Force) {
            Write-Status ">>" "强制 kill Unity PID=$($p.Id)" "Yellow"
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        } else {
            Write-Status ">>" "正常关闭 Unity PID=$($p.Id)（等待保存）" "Yellow"
            $p.CloseMainWindow() | Out-Null
        }
    }

    # 等待退出
    $timeout = 60
    if ($Force) { $timeout = 10 }
    Write-Status ".." "等待 Unity 退出（最多 ${timeout}s）..." "DarkGray"
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        $remaining = Get-UnityProcesses
        if (-not $remaining) {
            Write-Status "OK" "Unity 已退出" "Green"
            return
        }
    }

    # 超时强制 kill
    $remaining = Get-UnityProcesses
    if ($remaining) {
        Write-Status "!!" "Unity 未正常退出，强制 kill" "Red"
        $remaining | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
    }
}

function Stop-McpServer {
    $proc = Get-McpServerProcess
    if (-not $proc) {
        Write-Status "--" "MCP Server 未运行，跳过" "DarkGray"
        return
    }
    Write-Status ">>" "关闭 MCP Server PID=$($proc.Id)" "Yellow"
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Status "OK" "MCP Server 已关闭" "Green"
}

function Start-UnityEditor {
    Write-Status ">>" "启动 Unity Editor..." "Yellow"
    Write-Status ".." "项目: $ProjectPath" "DarkGray"

    Start-Process -FilePath $UnityExe -ArgumentList "-projectpath", $ProjectPath

    # 等待 Unity 窗口出现
    Write-Status ".." "等待 Unity 启动（可能需要 1-3 分钟）..." "DarkGray"
    $elapsed = 0
    $timeout = 180
    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 5
        $elapsed += 5
        $procs = Get-UnityProcesses
        if ($procs) {
            Write-Status "OK" "Unity Editor 已启动  PID=$($procs[0].Id)" "Green"

            # 等待 MCP Server 自动启动（Unity 插件会自动拉起）
            Write-Status ".." "等待 MCP Server 自动启动..." "DarkGray"
            $mcpElapsed = 0
            while ($mcpElapsed -lt 60) {
                Start-Sleep -Seconds 3
                $mcpElapsed += 3
                if (Test-McpConnection) {
                    Write-Status "OK" "MCP Server 就绪  端口=$McpPort" "Green"
                    return
                }
            }
            Write-Status "!!" "MCP Server 未自动启动，尝试手动启动..." "Yellow"
            Start-McpServer
            return
        }
    }
    Write-Status "!!" "Unity 启动超时（${timeout}s），请手动检查" "Red"
}

function Start-McpServer {
    if (-not (Test-Path $McpServerPath)) {
        Write-Status "!!" "MCP Server 可执行文件不存在: $McpServerPath" "Red"
        return
    }

    Write-Status ">>" "手动启动 MCP Server..." "Yellow"
    Start-Process -FilePath $McpServerPath -ArgumentList "port=$McpPort", "plugin-timeout=10000", "client-transport=streamableHttp", "authorization=none" -WindowStyle Hidden

    Start-Sleep -Seconds 3
    if (Test-McpConnection) {
        Write-Status "OK" "MCP Server 就绪  端口=$McpPort" "Green"
    } else {
        Write-Status "!!" "MCP Server 启动但连接不上，请检查 Unity 是否正常" "Red"
    }
}

# ===== 主逻辑 =====
Write-Host ""
Write-Host "===== Unity Restart Tool =====" -ForegroundColor Cyan
Write-Host "  操作: $Action $(if($Force){'(Force)'})" -ForegroundColor White
Write-Host ""

switch ($Action) {
    "status" {
        Show-Status | Out-Null
    }
    "mcp" {
        Stop-McpServer
        Start-McpServer
    }
    "unity" {
        Stop-UnityEditor
        Start-UnityEditor
    }
    "all" {
        Stop-McpServer
        Stop-UnityEditor
        Start-UnityEditor
    }
}

Write-Host ""
Write-Host "===== 最终状态 =====" -ForegroundColor Cyan
Show-Status | Out-Null
