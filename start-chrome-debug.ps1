<#
.SYNOPSIS
    启动 Chrome 调试模式（用于 OpenClaw 连接）
.DESCRIPTION
    自动查找 Windows 上的 Chrome 浏览器，杀掉现有占用 9222 端口的进程，
    并启动一个新的带调试端口和独立用户目录的 Chrome 实例。
#>

$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "  启动 Chrome 调试模式 (Native PowerShell)"
Write-Host "=========================================="
Write-Host ""

# ─── 查找 Chrome 路径 ──────────────────────────────────────────
$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    "$env:ProgramFiles\Chromium\Application\chrome.exe"
)

$chromeExe = $null
foreach ($p in $chromePaths) {
    if (Test-Path $p) {
        $chromeExe = $p
        break
    }
}

if (-not $chromeExe) {
    Write-Host "✗ 未找到 Chrome / Chromium，请先安装后重试" -ForegroundColor Red
    Write-Host "下载: https://www.google.com/chrome/"
    exit 1
}

$userDataDir = "$env:LOCALAPPDATA\Chrome-OpenClaw-Debug"

Write-Host "系统: Windows"
Write-Host "Chrome: $chromeExe"
Write-Host "用户数据目录: $userDataDir"
Write-Host ""

# ─── 关闭占用 9222 端口的现有进程 ──────────────────────────────
Write-Host "检查是否有进程占用 9222 端口..."
try {
    $portUsers = Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue
    if ($portUsers) {
        Write-Host "检测到端口被占用，正在关闭进程..."
        foreach ($conn in $portUsers) {
            $pidToKill = $conn.OwningProcess
            if ($pidToKill -ne 0 -and $pidToKill -ne 4) {
                Write-Host "正在终止 PID: $pidToKill"
                Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Seconds 2
    }
} catch {
    # 忽略错误
}

# 确保没有任何带有 --remote-debugging-port=9222 的 chrome 在运行
$chromeProcs = Get-WmiObject Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -match "remote-debugging-port=9222" }
if ($chromeProcs) {
    Write-Host "检测到已有调试 Chrome，正在关闭..."
    foreach ($proc in $chromeProcs) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

# ─── 启动 Chrome ───────────────────────────────────────────────
$logFile = "$env:TEMP\chrome-debug.log"

Write-Host "正在启动 Chrome 调试模式..."
Write-Host "端口: 9222"
Write-Host ""

$args = @(
    "--remote-debugging-port=9222",
    "--user-data-dir=`"$userDataDir`"",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    "--disable-sync",
    "--disable-translate",
    "--disable-features=TranslateUI",
    "--remote-allow-origins=*"
)

Start-Process -FilePath $chromeExe -ArgumentList $args -RedirectStandardOutput $logFile -RedirectStandardError $logFile -WindowStyle Hidden

Write-Host "Chrome 日志: $logFile"

# ─── 等待启动 ──────────────────────────────────────────────────
Write-Host -NoNewline "等待 Chrome 启动..."
$started = $false
for ($i = 0; $i -lt 15; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $started = $true
            break
        }
    } catch {
        # ignored
    }
    Write-Host -NoNewline "."
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Host ""

# ─── 检查结果 ──────────────────────────────────────────────────
if ($started) {
    try {
        $versionInfoJson = Invoke-RestMethod -Uri "http://127.0.0.1:9222/json/version" -ErrorAction SilentlyContinue
        $versionInfo = $versionInfoJson.Browser
    } catch {
        $versionInfo = "未知版本"
    }

    Write-Host "✓ Chrome 调试模式启动成功！" -ForegroundColor Green
    Write-Host ""
    Write-Host "Chrome 版本: $versionInfo"
    Write-Host "调试端口: http://127.0.0.1:9222"
    Write-Host "用户数据目录: $userDataDir"
    Write-Host ""
    Write-Host "正在打开各 Web 平台登录页（便于授权）..."

    $webUrls = @(
        "https://claude.ai/new",
        "https://chatgpt.com",
        "https://www.doubao.com/chat/",
        "https://chat.qwen.ai",
        "https://www.kimi.com",
        "https://gemini.google.com/app",
        "https://grok.com",
        "https://chat.deepseek.com/",
        "https://chatglm.cn",
        "https://chat.z.ai/"
    )

    foreach ($url in $webUrls) {
        $urlArgs = @("--remote-debugging-port=9222", "--user-data-dir=`"$userDataDir`"", "`"$url`"")
        Start-Process -FilePath $chromeExe -ArgumentList $urlArgs -WindowStyle Hidden
        Start-Sleep -Milliseconds 500
    }

    Write-Host "✓ 已打开: Claude, ChatGPT, Doubao, Qwen, Kimi, Gemini, Grok, GLM（DeepSeek 在第 5 步单独登录）" -ForegroundColor Green
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "下一步操作："
    Write-Host "=========================================="
    Write-Host "1. 在各标签页中登录需要使用的平台"
    Write-Host "2. 确保 config 中 browser.attachOnly=true 且 browser.cdpUrl=http://127.0.0.1:9222"
    Write-Host "3. 运行 .\onboard.ps1 选择对应平台完成授权（将复用此浏览器）"
    Write-Host ""
    Write-Host "=========================================="
} else {
    Write-Host "✗ Chrome 启动失败" -ForegroundColor Red
    Write-Host ""
    Write-Host "请检查："
    Write-Host "  1. Chrome 路径: $chromeExe"
    Write-Host "  2. 端口 9222 是否被占用"
    Write-Host "  3. 启动日志: $logFile"
    exit 1
}
