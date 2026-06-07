#Requires -Version 5.1
# Returns an array of @{ Label; IP; Url } for every active network endpoint.
# Used by install.ps1 to display Connect URLs (one per active NIC/VPN).
# Order: primary LAN NIC first, then VPN endpoints (NordLynx, Tailscale).
function Get-ConnectUrls {
    param([int]$Port, [string]$Token)

    $result = [System.Collections.Generic.List[hashtable]]::new()

    # --- Primary LAN NIC ---
    $primary = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
               Where-Object {
                   $null -ne $_.IPv4DefaultGateway -and
                   $_.NetAdapter.Status -eq 'Up' -and
                   $_.InterfaceAlias -notlike 'NordLynx*' -and
                   $_.InterfaceAlias -notlike 'Tailscale*'
               } |
               Sort-Object { $_.IPv4DefaultGateway.RouteMetric } |
               Select-Object -First 1
    if ($primary) {
        $addr = @($primary.IPv4Address) | Select-Object -First 1
        if ($addr) {
            $ip = $addr.IPAddress
            $result.Add(@{ Label = $primary.InterfaceAlias; IP = $ip
                           Url = "http://${ip}:${Port}?token=${Token}" })
        }
    }

    # --- NordVPN Meshnet (NordLynx adapter) ---
    $nlAdapter = Get-NetAdapter -Name 'NordLynx*' -ErrorAction SilentlyContinue |
                 Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if ($nlAdapter) {
        $nlAddr = Get-NetIPAddress -InterfaceAlias $nlAdapter.Name `
                      -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Select-Object -First 1
        if ($nlAddr) {
            $ip = $nlAddr.IPAddress
            $result.Add(@{ Label = 'NordVPN Meshnet'; IP = $ip
                           Url = "http://${ip}:${Port}?token=${Token}" })
        }
    }

    # --- Tailscale ---
    $tsAdapter = Get-NetAdapter -Name 'Tailscale*' -ErrorAction SilentlyContinue |
                 Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if ($tsAdapter) {
        $tsAddr = Get-NetIPAddress -InterfaceAlias $tsAdapter.Name `
                      -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Select-Object -First 1
        if ($tsAddr) {
            $ip = $tsAddr.IPAddress
            $result.Add(@{ Label = 'Tailscale'; IP = $ip
                           Url = "http://${ip}:${Port}?token=${Token}" })
        }
    }

    return ,$result.ToArray()
}
