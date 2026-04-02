#Requires -Version 5.1
<#
.SYNOPSIS
    P1 服务管理脚本（起服 / 停服 / 状态查看）
    管理 P1GoServer 全部 Go 微服务

.EXAMPLE
    .\server.ps1 start                         # 启动所有服务
    .\server.ps1 stop                          # 停止所有服务
    .\server.ps1 status                        # 查看所有服务状态
    .\server.ps1 restart                       # 重启所有服务
    .\server.ps1 start db_server               # 只启动 db_server
    .\server.ps1 restart login_server proxy_server  # 重启指定服务
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("start", "stop", "status", "restart", "help")]
    [string]$Action,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$ServiceNames
)

$ErrorActionPreference = "Stop"

# ============================================================
# 配置区
# ============================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceDir = Split-Path -Parent $ScriptDir

$GoProjectDir = Join-Path $WorkspaceDir "P1GoServer"

$GoBinDir = Join-Path $GoProjectDir "bin"
$GoConfig = Join-Path $GoBinDir "config.toml"

$PidDir = Join-Path $WorkspaceDir "run"

# 服务列表（按启动优先级排序）
# 停服时按逆序关闭
$Services = @(
    # 第 1 级：注册中心（所有服务都依赖它，必须第一个启动）
    @{ Name = "register_server";   Priority = 1;  Desc = "服务注册中心" }
    # 第 2 级：数据库层
    @{ Name = "db_server";         Priority = 2;  Desc = "数据库层" }
    @{ Name = "dbproxy_server";    Priority = 3;  Desc = "数据库代理（依赖 db_server）" }
    # 第 3 级：核心业务（依赖注册中心 + 数据库层）
    @{ Name = "manager_server";    Priority = 4;  Desc = "场景调度" }
    @{ Name = "logic_server";      Priority = 5;  Desc = "核心游戏逻辑" }
    @{ Name = "scene_server";      Priority = 5;  Desc = "游戏世界实例" }
    # 第 4 级：社交/辅助业务
    @{ Name = "relation_server";   Priority = 6;  Desc = "玩家关系" }
    @{ Name = "team_server";       Priority = 6;  Desc = "队伍/公会" }
    @{ Name = "chat_server";       Priority = 6;  Desc = "聊天" }
    @{ Name = "login_server";      Priority = 7;  Desc = "登录认证" }
    @{ Name = "match_server";      Priority = 7;  Desc = "匹配" }
    @{ Name = "workshop_server";   Priority = 7;  Desc = "制作系统" }
    @{ Name = "mail_server";       Priority = 7;  Desc = "邮件" }
    @{ Name = "gm_server";        Priority = 7;  Desc = "GM 工具" }
    # 第 5 级：接入层（gateway 依赖 proxy，proxy 依赖注册中心）
    @{ Name = "proxy_server";      Priority = 8;  Desc = "服务代理" }
    @{ Name = "gateway_server";    Priority = 9;  Desc = "客户端网关（依赖 proxy）" }
)

# 启动间隔（秒）
$StartDelay = 1
# 停服时等待进程退出的超时时间（秒）
$StopTimeout = 10

# ============================================================
# 日志函数
# ============================================================

function Write-Info  { param([string]$Msg) Write-Host "[INFO]  $(Get-Date -Format 'HH:mm:ss') $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "[WARN]  $(Get-Date -Format 'HH:mm:ss') $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "[ERROR] $(Get-Date -Format 'HH:mm:ss') $Msg" -ForegroundColor Red }

# ============================================================
# 工具函数
# ============================================================

function Get-BinPath {
    param([hashtable]$Svc)
    return Join-Path $GoBinDir "$($Svc.Name).exe"
}

function Get-ConfigPath {
    # 支持 worktree 隔离：环境变量覆盖 config 路径
    if ($env:P1_CONFIG_PATH -and (Test-Path $env:P1_CONFIG_PATH)) {
        return $env:P1_CONFIG_PATH
    }
    return $GoConfig
}

function Get-LogDir {
    return Join-Path $GoProjectDir "log"
}

function Get-WorkDir {
    return $GoBinDir
}

function Get-PidFile {
    param([string]$Name)
    return Join-Path $PidDir "$Name.pid"
}

function Ensure-Dirs {
    $dirs = @(
        (Join-Path $GoProjectDir "log\out"), (Join-Path $GoProjectDir "log\err"),
        $PidDir
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# 获取服务 PID，验证进程是否存活且为目标服务
function Get-ServicePid {
    param([string]$Name)
    $pidFile = Get-PidFile $Name
    if (Test-Path $pidFile) {
        try {
            $raw = (Get-Content $pidFile -Raw).Trim()
            if (-not $raw -or $raw -notmatch '^\d+$') { throw "invalid pid" }
            $procId = [int]$raw

            $proc = Get-Process -Id $procId -ErrorAction Stop
            if ($proc.HasExited) { throw "exited" }

            # 校验进程名，防止 PID 复用后误判其他进程为目标服务
            if ($proc.ProcessName -eq $Name) {
                return $procId
            }
        } catch { }
        # 进程已死或不匹配，清理 PID 文件
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function Test-ServiceRunning {
    param([string]$Name)
    return ($null -ne (Get-ServicePid $Name))
}

function Find-ServiceEntry {
    param([string]$Name)
    foreach ($svc in $Services) {
        if ($svc.Name -eq $Name) { return $svc }
    }
    return $null
}

# ============================================================
# 核心操作
# ============================================================

function Start-GameService {
    param([hashtable]$Svc)
    $name = $Svc.Name

    if (Test-ServiceRunning $name) {
        $procId = Get-ServicePid $name
        Write-Warn "$name 已在运行 (PID: $procId)，跳过"
        return $true
    }

    $binPath = Get-BinPath $Svc
    $configPath = Get-ConfigPath
    $logBase = Get-LogDir
    $workDir = Get-WorkDir

    if (-not (Test-Path $binPath)) {
        Write-Err "$name 可执行文件不存在: $binPath"
        return $false
    }
    if (-not (Test-Path $configPath)) {
        Write-Err "配置文件不存在: $configPath"
        return $false
    }

    $outLog = Join-Path $logBase "out\$name.log"
    $errLog = Join-Path $logBase "err\$name.log"

    # 启动进程（各服务统一使用 -config flag 指定配置文件）
    # WorkingDirectory 设为 bin/ 目录，确保配置中的相对路径正确解析
    $proc = Start-Process -FilePath $binPath -ArgumentList "-config", $configPath `
        -WorkingDirectory $workDir `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
        -WindowStyle Hidden -PassThru

    # 写入 PID 文件
    $proc.Id | Out-File -FilePath (Get-PidFile $name) -Encoding ascii -NoNewline

    # 短暂等待检查是否立即崩溃
    Start-Sleep -Milliseconds 500
    try {
        $check = Get-Process -Id $proc.Id -ErrorAction Stop
        if (-not $check.HasExited) {
            Write-Info "$name 启动成功 (PID: $($proc.Id))"
            return $true
        }
    } catch { }

    Remove-Item (Get-PidFile $name) -Force -ErrorAction SilentlyContinue
    Write-Err "$name 启动失败，请检查日志: $errLog"
    return $false
}

function Stop-GameService {
    param([string]$Name)

    $procId = Get-ServicePid $Name
    if ($null -eq $procId) {
        Write-Warn "$Name 未在运行"
        return
    }

    Write-Info "正在停止 $Name (PID: $procId)..."

    try {
        # Go 服务是控制台程序，监听 SIGTERM/SIGINT
        # Windows 下 taskkill（不带 /F）会发送 CTRL_CLOSE_EVENT，触发优雅关闭
        $null = taskkill /PID $procId 2>&1

        # 等待进程退出
        $proc = Get-Process -Id $procId -ErrorAction Stop
        $exited = $proc.WaitForExit($StopTimeout * 1000)

        if (-not $exited) {
            Write-Warn "$Name 未在 ${StopTimeout}s 内退出，强制终止"
            taskkill /F /PID $procId 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500
        }
    } catch {
        # 进程可能已经退出
    }

    Remove-Item (Get-PidFile $Name) -Force -ErrorAction SilentlyContinue
    Write-Info "$Name 已停止"
}

function Show-ServiceStatus {
    param([hashtable]$Svc)
    $name = $Svc.Name

    $procId = Get-ServicePid $name
    if ($null -ne $procId) {
        $memMB = "?"
        try {
            $proc = Get-Process -Id $procId -ErrorAction Stop
            $memMB = "{0:N1}" -f ($proc.WorkingSet64 / 1MB)
        } catch { }

        # 获取进程监听的 TCP 端口
        $ports = ""
        try {
            $conns = Get-NetTCPConnection -OwningProcess $procId -State Listen -ErrorAction Stop
            $portList = $conns | ForEach-Object { $_.LocalPort } | Sort-Object -Unique
            $ports = ($portList -join ",")
        } catch { }

        Write-Host "  " -NoNewline
        Write-Host "●" -ForegroundColor Green -NoNewline
        Write-Host (" {0,-22}" -f $name) -NoNewline
        Write-Host "  运行中" -ForegroundColor Green -NoNewline
        Write-Host -NoNewline "  PID: $("{0,-8}" -f $procId)  MEM: $("{0,-10}" -f "$memMB MB")"
        if ($ports) {
            Write-Host "  PORT: $ports" -ForegroundColor DarkYellow
        } else {
            Write-Host ""
        }
    } else {
        Write-Host "  " -NoNewline
        Write-Host "○" -ForegroundColor Red -NoNewline
        Write-Host (" {0,-22}" -f $name) -NoNewline
        Write-Host "  已停止" -ForegroundColor Red
    }
}

# ============================================================
# 批量操作
# ============================================================

function Resolve-TargetServices {
    param([string[]]$Names)
    if ($null -eq $Names -or $Names.Count -eq 0) {
        return $Services
    }
    $result = @()
    foreach ($n in $Names) {
        $entry = Find-ServiceEntry $n
        if ($null -eq $entry) {
            Write-Err "未知服务: $n"
            Write-Host "可用服务:" -ForegroundColor Yellow
            foreach ($s in $Services) { Write-Host "  $($s.Name)" }
            exit 1
        }
        $result += $entry
    }
    return $result
}

function Invoke-Start {
    param([string[]]$Names)
    $targets = @(Resolve-TargetServices $Names)
    $total = $targets.Count
    $succeeded = 0
    $failed = 0

    Write-Info "准备启动 $total 个服务..."
    Ensure-Dirs

    for ($i = 0; $i -lt $total; $i++) {
        if (Start-GameService $targets[$i]) { $succeeded++ } else { $failed++ }
        if ($i -lt $total - 1) { Start-Sleep -Seconds $StartDelay }
    }

    Write-Host ""
    Write-Info "启动完成: 成功 $succeeded, 失败 $failed, 共 $total"
}

function Invoke-Stop {
    param([string[]]$Names)
    $targets = @(Resolve-TargetServices $Names)
    $total = $targets.Count

    Write-Info "准备停止 $total 个服务..."

    # 逆序停服
    for ($i = $total - 1; $i -ge 0; $i--) {
        Stop-GameService $targets[$i].Name
    }

    Write-Host ""
    Write-Info "所有服务已停止"
}

function Invoke-Status {
    param([string[]]$Names)
    $targets = @(Resolve-TargetServices $Names)
    $running = 0
    $stopped = 0

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  P1 服务状态" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    foreach ($svc in $targets) {
        if (Test-ServiceRunning $svc.Name) { $running++ } else { $stopped++ }
        Show-ServiceStatus $svc
    }

    Write-Host ""
    Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host -NoNewline "  运行: "
    Write-Host -NoNewline $running -ForegroundColor Green
    Write-Host -NoNewline "  停止: "
    Write-Host -NoNewline $stopped -ForegroundColor Red
    Write-Host "  共计: $($running + $stopped)"
    Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""
}

function Invoke-Restart {
    param([string[]]$Names)
    Invoke-Stop $Names
    Write-Host ""
    Start-Sleep -Seconds 1
    Invoke-Start $Names
}

# ============================================================
# 入口
# ============================================================

function Show-Help {
    Write-Host ""
    Write-Host "P1 服务管理脚本" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "用法:" -ForegroundColor Yellow
    Write-Host "  .\server.ps1 <命令> [服务名...]"
    Write-Host ""
    Write-Host "命令:" -ForegroundColor Yellow
    Write-Host "  start     启动服务（按优先级顺序）"
    Write-Host "  stop      停止服务（按优先级逆序）"
    Write-Host "  restart   重启服务（先停后启）"
    Write-Host "  status    查看服务运行状态"
    Write-Host "  help      显示此帮助信息"
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  .\server.ps1 start                          # 启动所有服务"
    Write-Host "  .\server.ps1 stop                           # 停止所有服务"
    Write-Host "  .\server.ps1 status                         # 查看所有服务状态"
    Write-Host "  .\server.ps1 start db_server                # 只启动 db_server"
    Write-Host "  .\server.ps1 restart login_server proxy_server  # 重启指定服务"
    Write-Host ""
    Write-Host "可用服务:" -ForegroundColor Yellow
    foreach ($svc in $Services) {
        Write-Host ("  {0,-22} {1}" -f $svc.Name, $svc.Desc)
    }
    Write-Host ""
}

switch ($Action) {
    "start"   { Invoke-Start $ServiceNames }
    "stop"    { Invoke-Stop $ServiceNames }
    "status"  { Invoke-Status $ServiceNames }
    "restart" { Invoke-Restart $ServiceNames }
    "help"    { Show-Help }
}
