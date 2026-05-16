#Requires -Version 5.1
param([switch]$DryRun, [switch]$KeepConfig)
$ErrorActionPreference = 'Continue'

$taskName = if ($env:EVEN_TERMINAL_TASK_NAME) { $env:EVEN_TERMINAL_TASK_NAME } else { 'EvenTerminalAutostart' }

if (-not $DryRun) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        try { Stop-ScheduledTask -TaskName $taskName } catch {}
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Task unregistered: $taskName"
    } else {
        Write-Host "Task '$taskName' not found."
    }
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
        Where-Object { $_.CommandLine -like '*even-terminal*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

$ConfigDir = if ($env:EVEN_TERMINAL_CONFIG_DIR) {
    $env:EVEN_TERMINAL_CONFIG_DIR
} else { Join-Path $env:USERPROFILE '.config\even-terminal' }
$ConfigPath = Join-Path $ConfigDir 'config.json'

if (-not $KeepConfig -and (Test-Path $ConfigPath)) {
    Copy-Item $ConfigPath "$ConfigPath.bak" -Force
    Remove-Item $ConfigPath
    Write-Host "Config removed (backup: $ConfigPath.bak)"
}
Write-Host "Uninstalled."
