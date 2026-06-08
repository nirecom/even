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

if ((Test-EvenTerminalRunning -Port $config.port).Running) {
    Write-Host "even-terminal already responding on port $($config.port); skipping."
    exit 0
}

$exePath = $config.executable
if (-not (Test-Path $exePath)) {
    Write-Error "Executable not found: $exePath. Re-run install.ps1 to regenerate config."
    exit 1
}

$net = Get-NetworkArgs -Mode $config.network_mode

$env:BRIDGE_TOKEN = $config.token
$env:PORT = $config.port

# Prepend executable_args (e.g. cli.js path) before the even-terminal flags.
$exeArgs = @()
if ($config.executable_args) { $exeArgs += $config.executable_args }
$exeArgs += @('--provider', $config.provider, '--port', $config.port)
if ($net.mode -eq 'tailscale') {
    $exeArgs += '--tailscale'
}
# auto/loopback/interface modes: no --interface flag.
# even-terminal binds to 0.0.0.0 and accepts connections from all NICs
# (LAN + NordVPN Meshnet + Tailscale). install.ps1 displays URLs for each
# active NIC via Get-ConnectUrls so the user can pick the right one.

$logDir = Join-Path $ConfigDir 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Start-Process -FilePath $exePath -ArgumentList $exeArgs `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $logDir 'stdout.log') `
    -RedirectStandardError  (Join-Path $logDir 'stderr.log')
