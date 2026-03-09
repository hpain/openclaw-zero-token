<#
.SYNOPSIS
    OpenClaw Gateway 服务启动管理脚本 (Native PowerShell)
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateDir = Join-Path $scriptDir ".openclaw-zero-state"
$configFile = Join-Path $stateDir "openclaw.json"
$pidFile = Join-Path $scriptDir ".gateway.pid"
$port = 3001
$logDir = Join-Path $scriptDir "logs"
$tmpLog = Join-Path $logDir "openclaw-zero-gateway.log"

$nodeExe = Get-Command "node" | Select-Object -ExpandProperty Definition -ErrorAction SilentlyContinue
if (-not $nodeExe) {
    Write-Host "✗ 未找到 node，请先安装 Node.js: https://nodejs.org" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$exampleConfig = Join-Path $scriptDir ".openclaw-state.example\openclaw.json"
if (-not (Test-Path $configFile)) {
    if (Test-Path $exampleConfig) {
        Copy-Item -Path $exampleConfig -Destination $configFile
        Write-Host "已从示例复制配置文件: $exampleConfig -> $configFile"
    } else {
        Set-Content -Path $configFile -Value "{}"
        Write-Host "已创建空配置文件: $configFile"
    }
}

# 提取 Token
$gatewayToken = ""
try {
    if (Test-Path $configFile) {
        $configContent = Get-Content $configFile -Raw | ConvertFrom-Json
        $gatewayToken = $configContent.gateway.auth.token
    }
} catch { }

if (-not $gatewayToken) {
    $gatewayToken = $env:OPENCLAW_GATEWAY_TOKEN
}

function Stop-Gateway {
    if (Test-Path $pidFile) {
        $oldPid = Get-Content $pidFile | ForEach-Object { $_.Trim() }
        if ($oldPid -match '^\d+$') {
            $running = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($running) {
                Write-Host "停止旧进程 (PID: $oldPid)..."
                Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            }
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    # 杀死占用端口进程
    try {
        $portUsers = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($portUsers) {
            foreach ($conn in $portUsers) {
                $pidToKill = $conn.OwningProcess
                if ($pidToKill -ne 0 -and $pidToKill -ne 4) {
                    Write-Host "停止占用端口 $port 的进程 (PID: $pidToKill)..."
                    Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Seconds 1
        }
    } catch { }
}

function Start-Gateway {
    $env:OPENCLAW_CONFIG_PATH = $configFile
    $env:OPENCLAW_STATE_DIR = $stateDir
    $env:OPENCLAW_GATEWAY_PORT = $port

    $nodeVersion = & $nodeExe --version 2>$null
    Write-Host "系统: Windows | Node: $nodeVersion"
    Write-Host "启动 Gateway 服务..."
    Write-Host "配置文件: $env:OPENCLAW_CONFIG_PATH"
    Write-Host "状态目录: $env:OPENCLAW_STATE_DIR"
    Write-Host "日志文件: $tmpLog"
    Write-Host "端口: $port"
    Write-Host ""

    $indexMjs = Join-Path $scriptDir "dist\index.mjs"
    $cmdArgs = @($indexMjs, "gateway", "--port", "$port")
    
    $proc = Start-Process -FilePath $nodeExe -ArgumentList $cmdArgs -RedirectStandardOutput $tmpLog -RedirectStandardError $tmpLog -WindowStyle Hidden -PassThru
    $procId = $proc.Id
    Set-Content -Path $pidFile -Value $procId

    Write-Host -NoNewline "等待 Gateway 就绪..."
    $webUiReady = $false
    for ($i = 1; $i -le 30; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-Host "`nGateway 已就绪 (${i}s)"
                $webUiReady = $true
                break
            }
        } catch { }
        
        $running = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if (-not $running -or $proc.HasExited) {
            Write-Host "`nGateway 进程已退出，启动失败" -ForegroundColor Red
            Get-Content $tmpLog -Tail 15
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            exit 1
        }
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 1
    }

    $running = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($running -and -not $proc.HasExited) {
        if (-not $webUiReady) {
            Write-Host "`n⚠ Web 服务检测未成功，Gateway 可能尚未就绪，请稍后手动打开 Web UI" -ForegroundColor Yellow
        }
        $webUiUrl = "http://127.0.0.1:$port/#token=$gatewayToken"
        Write-Host "Gateway 服务已启动 (PID: $procId)" -ForegroundColor Green
        Write-Host "Web UI: $webUiUrl"
        
        if ($webUiReady) {
            Write-Host "正在打开浏览器..."
            Start-Process -FilePath $webUiUrl
        } else {
            Write-Host "请手动在浏览器中打开上述地址"
        }
    } else {
        Write-Host "Gateway 服务启动失败，请查看日志:" -ForegroundColor Red
        Get-Content $tmpLog -Tail 15
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

function Invoke-Gateway {
    $env:OPENCLAW_CONFIG_PATH = $configFile
    $env:OPENCLAW_STATE_DIR = $stateDir
    $env:OPENCLAW_GATEWAY_PORT = $port

    $nodeVersion = & $nodeExe --version 2>$null
    Write-Host "系统: Windows | Node: $nodeVersion"
    Write-Host "以前台交互模式启动 Gateway 服务..."
    Write-Host "配置文件: $env:OPENCLAW_CONFIG_PATH"
    Write-Host "状态目录: $env:OPENCLAW_STATE_DIR"
    Write-Host "端口: $port"
    Write-Host ""
    Write-Host "Web UI: http://127.0.0.1:$port/#token=$gatewayToken"
    Write-Host "提示: 按 Ctrl+C 停止服务"
    Write-Host "----------------------------------------"

    $indexMjs = Join-Path $scriptDir "dist\index.mjs"
    $cmdArgs = @($indexMjs, "gateway", "--port", "$port")
    
    & $nodeExe $cmdArgs
}

$command = "start"
if ($args.Count -gt 0) { $command = $args[0] }

switch ($command) {
    "start" {
        Stop-Gateway
        Start-Gateway
    }
    "stop" {
        Stop-Gateway
        Write-Host "Gateway 服务已停止"
    }
    "restart" {
        Stop-Gateway
        Start-Gateway
    }
    "run" {
        Stop-Gateway
        Invoke-Gateway
    }
    "status" {
        if (Test-Path $pidFile) {
            $oldPid = Get-Content $pidFile | ForEach-Object { $_.Trim() }
            $running = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($running) {
                Write-Host "Gateway 服务运行中 (PID: $oldPid)" -ForegroundColor Green
                Write-Host "Web UI: http://127.0.0.1:$port/#token=$gatewayToken"
            } else {
                Write-Host "Gateway 服务未运行 (PID 文件存在但进程已退出)" -ForegroundColor Yellow
            }
        } else {
            $portUsers = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($portUsers) {
                $pidToKill = $portUsers[0].OwningProcess
                Write-Host "端口 $port 被进程 $pidToKill 占用，但不是本脚本启动的 Gateway" -ForegroundColor Yellow
            } else {
                Write-Host "Gateway 服务未运行"
            }
        }
    }
    default {
        Write-Host "用法: .\server.ps1 {start|stop|restart|status|run}"
        Write-Host ""
        Write-Host "命令说明:"
        Write-Host "  start   - 后台运行"
        Write-Host "  stop    - 停止后台服务"
        Write-Host "  restart - 重启后台服务"
        Write-Host "  status  - 查看状态"
        Write-Host "  run     - 前台交互式运行 (实时显示日志)"
        exit 1
    }
}
