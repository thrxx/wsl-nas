# scripts/windows/Update-WSLPortProxy.ps1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Automatically updates Windows PortProxy to forward SMB (445) to the current WSL2 IP.
.DESCRIPTION
    Designed to be triggered by Task Scheduler on login/system startup.
    Detects WSL2 IP, removes stale portproxy rules, and creates a new forwarding rule.
.NOTES
    Run in PowerShell as Administrator. Compatible with PS 5.1 & 7+.
#>

param(
    [string]$WSL_DISTRO = "Ubuntu",
    [int]$PORT = 445
)

$ErrorActionPreference = "Stop"
Write-Host "[PortProxy] Updating rule for '$WSL_DISTRO' on port $PORT..." -ForegroundColor Cyan

# 1. Получаем IP WSL2
try {
    $RawOutput = wsl -d $WSL_DISTRO -e hostname -I 2>$null
    if (-not $RawOutput) { throw "Empty output" }
    # hostname -I может вернуть несколько IP через пробел, берём первый
    $WSL_IP = $RawOutput.Trim().Split(" ")[0]
} catch {
    Write-Warning "⚠️ Не удалось получить IP. Дистрибутив '$WSL_DISTRO' не запущен или WSL ещё инициализируется."
    exit 1
}

if (-not $WSL_IP -or $WSL_IP -eq "") {
    Write-Warning "⚠️ Пустой или некорректный IP. Пропуск обновления."
    exit 1
}

# 2. Удаляем старое правило (игнорируем ошибку, если его нет)
netsh interface portproxy delete v4tov4 listenport=$PORT listenaddress=0.0.0.0 2>$null

# 3. Создаём новое правило
netsh interface portproxy add v4tov4 listenport=$PORT listenaddress=0.0.0.0 connectport=$PORT connectaddress=$WSL_IP

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ PortProxy обновлён: 0.0.0.0:$PORT → ${WSL_IP}:$PORT" -ForegroundColor Green
} else {
    Write-Error "❌ Ошибка при выполнении netsh. Убедитесь, что скрипт запущен от Администратора."
    exit 1
}