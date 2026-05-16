#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\detect-network.ps1"
. "$PSScriptRoot\lib\probe-server.ps1"

$ConfigDir = if ($env:EVEN_TERMINAL_CONFIG_DIR) {
    $env:EVEN_TERMINAL_CONFIG_DIR
} else {
    Join-Path $env:USERPROFILE '.config\even-terminal'
}
$ConfigPath = Join-Path $ConfigDir 'config.json'

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config not found: $ConfigPath. Run install.ps1 first."
    exit 1
}
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if (Test-EvenTerminalRunning -Port $config.port) {
    Write-Host "even-terminal already responding on port $($config.port); skipping."
    exit 0
}

if (-not (Test-Path $config.executable)) {
    Write-Error "Executable not found: $($config.executable). Re-run install.ps1."
    exit 1
}

$net = Get-NetworkArgs -Mode $config.network_mode

$env:BRIDGE_TOKEN = $config.token
$env:PORT = $config.port

$exeArgs = @('--provider', $config.provider, '--port', $config.port)
if ($net.mode -eq 'tailscale') {
    $exeArgs += '--tailscale'
} elseif ($net.mode -eq 'interface') {
    $exeArgs += @('--interface', $net.arg)
}
if ($config.executable_args) {
    $exeArgs += $config.executable_args
}

$logDir = Join-Path $ConfigDir 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Start-Process -FilePath $config.executable -ArgumentList $exeArgs `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $logDir 'stdout.log') `
    -RedirectStandardError  (Join-Path $logDir 'stderr.log')
