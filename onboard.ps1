<#
.SYNOPSIS
    OpenClaw onboard 向导启动脚本 (Native PowerShell)
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateDir = Join-Path $scriptDir ".openclaw-zero-state"
$configFile = Join-Path $stateDir "openclaw.json"

# ─── 检查 Node.js ────────────────────────────────────────────
$nodeExe = Get-Command "node" | Select-Object -ExpandProperty Definition -ErrorAction SilentlyContinue
if (-not $nodeExe) {
    Write-Host "✗ 未找到 node，请先安装 Node.js: https://nodejs.org" -ForegroundColor Red
    exit 1
}

$nodeVersion = & $nodeExe --version 2>$null
Write-Host "系统: Windows | Node: $nodeVersion"

# ─── 初始化目录与配置 ─────────────────────────────────────────
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir | Out-Null
}

$exampleConfig = Join-Path $scriptDir ".openclaw-state.example\openclaw.json"
if (-not (Test-Path $configFile)) {
    if (Test-Path $exampleConfig) {
        Copy-Item -Path $exampleConfig -Destination $configFile
        Write-Host "已从示例复制配置文件: $exampleConfig -> $configFile"
    } else {
        Set-Content -Path $configFile -Value "{}"
        Write-Host "已创建空配置文件: $configFile（建议从 .openclaw-state.example\openclaw.json 复制完整配置）"
    }
}

$env:OPENCLAW_CONFIG_PATH = $configFile
$env:OPENCLAW_STATE_DIR = $stateDir
$env:OPENCLAW_GATEWAY_PORT = "3001"

Write-Host "配置文件: $env:OPENCLAW_CONFIG_PATH"
Write-Host "状态目录: $env:OPENCLAW_STATE_DIR"
Write-Host "端口: $env:OPENCLAW_GATEWAY_PORT"
Write-Host ""

# ─── 运行 ────────────────────────────────────────────────────
$indexMjs = Join-Path $scriptDir "dist\index.mjs"

if ($args.Count -eq 0) {
    Write-Host "启动 onboard 向导..."
    & $nodeExe $indexMjs onboard
} else {
    & $nodeExe $indexMjs $args
}
