# scripts/windows/03_configure_windows.ps1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures Windows Host for WSL2 NAS: PortProxy, Firewall, and Task Scheduler.
.DESCRIPTION
    This script is part of the WSL-NAS automation suite.
    It sets up automatic port forwarding, firewall rules, and background tasks to keep the NAS accessible after reboot.
.NOTES
    Run in PowerShell as Administrator. Part of step 3/5 in the setup workflow.
#>

param(
    [string]$WSL_DISTRO = "Ubuntu",
    [int]$PORT = 445
)

$ErrorActionPreference = "Stop"
$ScriptDir = Join-Path $env:ProgramData "WSL-NAS"
$ProxyScriptName = "Update-WSLPortProxy.ps1"
$ProxyPath = Join-Path $ScriptDir $ProxyScriptName

Write-Host "[3/5] Configuring Windows Host..." -ForegroundColor Cyan

# 1. Create script directory
if (-not (Test-Path $ScriptDir)) {
    New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
}

# 2. Generate PortProxy update script
Write-Host "   Generating $ProxyScriptName..." -ForegroundColor DarkGray
$ProxyContent = @"
`$ErrorActionPreference = "Stop"
`$WSL_DISTRO = "$WSL_DISTRO"
`$PORT = $PORT

# Get WSL IP (first available)
`$IP = (wsl -d `$WSL_DISTRO -e hostname -I 2>`$null).Trim().Split(" ")[0]

if (-not `$IP -or `$IP -eq "") {
    Write-Warning "WSL is offline or has no IP. Skipping portproxy update."
    exit 1
}

# Remove old rule if exists, then add new one
netsh interface portproxy delete v4tov4 listenport=`$PORT listenaddress=0.0.0.0 2>`$null
netsh interface portproxy add v4tov4 listenport=`$PORT listenaddress=0.0.0.0 connectport=`$PORT connectaddress=`$IP

Write-Host "✅ PortProxy updated: 0.0.0.0:`$PORT -> `$IP:`$PORT"
"@
Set-Content -Path $ProxyPath -Value $ProxyContent -Encoding UTF8 -Force

# 3. Firewall Rule (Private profile only)
$RuleName = "WSL-NAS-SMB-Inbound"
$ExistingRule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if (-not $ExistingRule) {
    New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Protocol TCP -LocalPort $PORT -Action Allow -Profile Private | Out-Null
    Write-Host "   ✅ Firewall rule created (Private network only)" -ForegroundColor Green
} else {
    Write-Host "   ℹ Firewall rule already exists" -ForegroundColor Yellow
}

# 4. Task Scheduler: WSL Background Start
$TaskStartName = "WSL-NAS-Start"
if (-not (Get-ScheduledTask -TaskName $TaskStartName -ErrorAction SilentlyContinue)) {
    $ActionStart = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $WSL_DISTRO -e true"
    $TriggerStart = New-ScheduledTaskTrigger -AtLogOn
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskStartName -Action $ActionStart -Trigger $TriggerStart -Settings $Settings -RunLevel Highest -Force | Out-Null
    Write-Host "   ✅ Task created: $TaskStartName" -ForegroundColor Green
} else {
    Write-Host "   ℹ Task already exists: $TaskStartName" -ForegroundColor Yellow
}

# 5. Task Scheduler: PortProxy Auto-Update (with delay for network init)
$TaskProxyName = "WSL-NAS-PortProxy"
if (-not (Get-ScheduledTask -TaskName $TaskProxyName -ErrorAction SilentlyContinue)) {
    $ActionProxy = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ProxyPath`""
    $TriggerProxy = New-ScheduledTaskTrigger -AtLogOn -Delay (New-TimeSpan -Minutes 1)
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskProxyName -Action $ActionProxy -Trigger $TriggerProxy -Settings $Settings -RunLevel Highest -Force | Out-Null
    Write-Host "   ✅ Task created: $TaskProxyName (1 min delay)" -ForegroundColor Green
} else {
    Write-Host "   ℹ Task already exists: $TaskProxyName" -ForegroundColor Yellow
}

Write-Host "`n✅ Windows configuration complete." -ForegroundColor Green
Write-Host "   To apply immediately, run in PowerShell:" -ForegroundColor Cyan
Write-Host "   Start-ScheduledTask -TaskName `"$TaskStartName`"" -ForegroundColor DarkGray
Write-Host "   Start-ScheduledTask -TaskName `"$TaskProxyName`"" -ForegroundColor DarkGray