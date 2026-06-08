#Requires -Version 5.1
# Returns an array of @{ Label; IP; Url } for every active network endpoint.
# Used by install.ps1 to display Connect URLs (one per active NIC/VPN).
# Order: primary NIC (lowest-metric default-gateway) first, then all other
# Up adapters with a routable IPv4 address.
# VPN-agnostic: NordVPN (NordLynx), WireGuard, OpenVPN, Tailscale, etc.
# are included automatically — no adapter-name hardcoding.
function Get-ConnectUrls {
    param([int]$Port, [string]$Token)

    $result = [System.Collections.Generic.List[hashtable]]::new()

    # Determine primary adapter alias via lowest-metric default gateway
    $primaryCfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
                  Where-Object {
                      $_.IPv4DefaultGateway -and $_.IPv4DefaultGateway.Count -gt 0 -and
                      $_.NetAdapter -and $_.NetAdapter.Status -eq 'Up'
                  } |
                  Sort-Object { ($_.IPv4DefaultGateway | Select-Object -First 1).RouteMetric } |
                  Select-Object -First 1
    $primaryAlias = if ($primaryCfg) { $primaryCfg.InterfaceAlias } else { $null }

    # Enumerate ALL Up adapters; primary goes first
    $allUp = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    $ordered = @()
    if ($primaryAlias) { $ordered += @($allUp | Where-Object { $_.Name -eq $primaryAlias }) }
    $ordered += @($allUp | Where-Object { $_.Name -ne $primaryAlias })

    foreach ($adapter in $ordered) {
        $addr = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 `
                    -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.254\.' } |
                Select-Object -First 1
        if ($addr) {
            $ip = $addr.IPAddress
            $result.Add(@{ Label = $adapter.Name; IP = $ip
                           Url   = "http://${ip}:${Port}?token=${Token}" })
        }
    }

    return ,$result.ToArray()
}
