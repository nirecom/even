#Requires -Version 5.1
param(
    [int]$Port = 3456,
    [string]$NetworkMode = 'auto',
    [switch]$Force,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$ConfigDir = if ($env:EVEN_TERMINAL_CONFIG_DIR) {
    $env:EVEN_TERMINAL_CONFIG_DIR
} else {
    Join-Path $env:USERPROFILE '.config\even-terminal'
}
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
$ConfigPath = Join-Path $ConfigDir 'config.json'

$cfgPort = $Port
$cfgToken = $null

if ((Test-Path $ConfigPath) -and -not $Force) {
    Write-Host "Config already exists: $ConfigPath (use -Force to overwrite)"
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $cfgPort = $cfg.port
    $cfgToken = $cfg.token
} else {
    $cmd = Get-Command even-terminal -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Error "even-terminal not found in PATH. Install: npm install -g @evenrealities/even-terminal"
        exit 1
    }
    # Get-Command returns the fnm multishell shim — a session-temporary path absent
    # under Task Scheduler. Resolve node.exe and cli.js directly from fnm's permanent
    # node-versions directory so the stored paths survive session restarts.
    $exePath     = $cmd.Source
    $exeArgsList = @()
    $fnmDataDir  = if ($env:FNM_DIR) { $env:FNM_DIR } else { Join-Path $env:APPDATA 'fnm' }
    $fnmBin      = Get-Command fnm -ErrorAction SilentlyContinue
    if ($fnmBin) {
        $ver = (& $fnmBin.Source current 2>$null).Trim()
        if ($ver -and $ver -ne 'none') {
            $nodeExe = Join-Path $fnmDataDir "node-versions\$ver\installation\node.exe"
            $cliJs   = Join-Path $fnmDataDir "node-versions\$ver\installation\node_modules\@evenrealities\even-terminal\bin\cli.js"
            if ((Test-Path $nodeExe) -and (Test-Path $cliJs)) {
                $exePath     = $nodeExe
                $exeArgsList = @($cliJs)
            }
        }
    }

    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $cfgToken = [Convert]::ToBase64String($bytes) -replace '\+','-' -replace '/','_' -replace '=',''

    $cfgData = [ordered]@{
        version         = 1
        executable      = $exePath
        executable_args = $exeArgsList
        token           = $cfgToken
        port            = $Port
        provider        = 'claude'
        network_mode    = $NetworkMode
        config_dir      = $ConfigDir
    }
    $cfgData | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-Host "Config created: $ConfigPath"
}

if ($DryRun) {
    Write-Host "DryRun: skipping Task Scheduler registration and initial start."
    return
}

$startScript = Join-Path $PSScriptRoot 'scripts\start.ps1'
$taskName = if ($env:EVEN_TERMINAL_TASK_NAME) { $env:EVEN_TERMINAL_TASK_NAME } else { 'EvenTerminalAutostart' }
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
               -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startScript`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings  = New-ScheduledTaskSettingsSet `
               -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "Task Scheduler registered: $taskName (ONLOGON)"

Start-Process powershell.exe `
    -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$startScript`"" `
    -WindowStyle Hidden

. "$PSScriptRoot\scripts\lib\probe-server.ps1"
$deadline = (Get-Date).AddSeconds(15)
$started  = $false
while ((Get-Date) -lt $deadline) {
    if (Test-EvenTerminalRunning -Port $cfgPort -TimeoutMs 200) { $started = $true; break }
    Start-Sleep -Milliseconds 500
}
if (-not $started) {
    Write-Warning "Server did not start within 15s. Check: $ConfigDir\logs\stdout.log"
    exit 1
}

$ip = $null
if (Get-Command tailscale -ErrorAction SilentlyContinue) {
    $ip = & tailscale ip -4 2>$null | Select-Object -First 1
}
if (-not $ip) {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.IPAddress -notlike '127.*' -and
                          $_.IPAddress -notlike '169.254.*' -and
                          $_.PrefixOrigin -ne 'WellKnown' } |
           Select-Object -First 1).IPAddress
}
Write-Host ""
Write-Host "=== Installation complete ==="
Write-Host "  Connect URL : http://$($ip):$($cfgPort)?token=$cfgToken"
Write-Host "  Log         : $ConfigDir\logs\stdout.log"
Write-Host ""
Write-Host "Open Even Hub on your G2 and scan the QR code shown in the server log,"
Write-Host "or paste the Connect URL directly into Even Hub."
