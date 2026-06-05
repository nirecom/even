#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# Task Scheduler starts with a minimal PATH that excludes fnm shims.
# Initialize fnm so node/even-terminal are resolvable.
$fnmExe = Join-Path $env:LOCALAPPDATA 'fnm\fnm.exe'
if (Test-Path $fnmExe) {
    try {
        $fnmEnv = & $fnmExe env --shell powershell 2>$null
        if ($fnmEnv) { Invoke-Expression ($fnmEnv -join "`n") }
    } catch { }
}

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

$exePath = $config.executable
if (-not (Test-Path $exePath)) {
    # Stored path may be a stale fnm multishell shim. Try re-resolving after fnm init.
    $resolved = Get-Command even-terminal -ErrorAction SilentlyContinue
    if ($resolved) { $exePath = $resolved.Source } else {
        Write-Error "Executable not found: $exePath. Re-run install.ps1."
        exit 1
    }
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

Start-Process -FilePath $exePath -ArgumentList $exeArgs `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $logDir 'stdout.log') `
    -RedirectStandardError  (Join-Path $logDir 'stderr.log')
