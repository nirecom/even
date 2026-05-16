# Returns a hashtable: @{ mode = 'tailscale'|'interface'|'loopback'; arg = $null|'<NIC name>' }
function Get-NetworkArgs {
    param([string]$Mode = 'auto')

    if ($Mode -in @('auto', 'tailscale')) {
        $tsAdapter = Get-NetAdapter -Name 'Tailscale*' -ErrorAction SilentlyContinue |
                     Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        if ($tsAdapter) {
            return @{ mode = 'tailscale'; arg = $null }
        }
        if ($Mode -eq 'tailscale') {
            throw "tailscale mode requested but no Up Tailscale adapter found"
        }
    }

    if ($Mode -eq 'loopback') {
        return @{ mode = 'loopback'; arg = $null }
    }

    $primary = Get-NetIPConfiguration |
               Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } |
               Sort-Object { $_.IPv4DefaultGateway.RouteMetric } |
               Select-Object -First 1
    if (-not $primary) { throw "No primary IPv4 NIC with default gateway found" }
    return @{ mode = 'interface'; arg = $primary.InterfaceAlias }
}
