# Resolve the IP to display in the Connect URL.
#
# Input: the BoundIP from Test-EvenTerminalRunning (raw LocalAddress).
# Returns:
#   - $BoundIP as-is when it is a specific routable IP.
#   - Primary default-route NIC IPv4 when BoundIP is wildcard / loopback / empty.
#   - $null when no primary NIC IPv4 can be resolved.
#
# Why two-stage: even-terminal sometimes binds to 0.0.0.0 (when started without
# --interface, or when a stale instance from a previous start.ps1 is still running).
# Wildcard is correct as a *detection* result but useless as a *display* URL.
# Detection (Test-EvenTerminalRunning) stays LISTEN-state-based per repo policy;
# display falls back to the same primary-NIC selection logic that Get-NetworkArgs
# uses when picking --interface for a fresh launch.
function Resolve-DisplayIP {
    param([string]$BoundIP)

    if ($BoundIP -and $BoundIP -notin @('0.0.0.0', '::', '127.0.0.1', '::1')) {
        return $BoundIP
    }

    $primary = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
               Where-Object { $null -ne $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
               Sort-Object { $_.IPv4DefaultGateway.RouteMetric } |
               Select-Object -First 1
    if (-not $primary) { return $null }

    $addr = @($primary.IPv4Address) | Select-Object -First 1
    if (-not $addr) { return $null }
    return $addr.IPAddress
}

function Get-ConnectUrl {
    param(
        [string]$BoundIP,
        [int]$Port,
        [string]$Token
    )
    $ip = Resolve-DisplayIP -BoundIP $BoundIP
    if (-not $ip) { $ip = '<your-ip>' }
    return "http://${ip}:${Port}?token=${Token}"
}
