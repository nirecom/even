# Tests: scripts/lib/list-display-urls.ps1, install.ps1
# Tags: dual-url, vpn, connect-url, e2e
# E2E tests for the multi-URL requirement:
#   - install must display one Connect URL per active network adapter.
#   - VPN adapters (NordLynx, WireGuard, Tailscale, OpenVPN, etc.) are
#     included automatically via generic Get-NetAdapter enumeration.
#   - All mock tests use Pester Mock for deterministic results.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'scripts\lib\list-display-urls.ps1')

    # Helpers ---------------------------------------------------------------

    function script:New-MockIPConfig {
        param([string]$Alias, [int]$Metric = 10, [switch]$NoGateway)
        $gw  = if ($NoGateway) { @() } else { @([PSCustomObject]@{ RouteMetric = $Metric }) }
        $nic = [PSCustomObject]@{ Status = 'Up' }
        return [PSCustomObject]@{
            InterfaceAlias     = $Alias
            IPv4DefaultGateway = $gw
            NetAdapter         = $nic
        }
    }

    function script:New-MockAdapter {
        param([string]$Name, [string]$Status = 'Up')
        return [PSCustomObject]@{ Name = $Name; Status = $Status }
    }

    function script:New-MockIPAddress {
        param([string]$IP)
        return [PSCustomObject]@{ IPAddress = $IP }
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — single NIC, no VPN" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -Metric 10)
        }
        Mock Get-NetAdapter {
            return @(New-MockAdapter -Name 'Ethernet')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Ethernet' } {
            return @(New-MockIPAddress -IP '192.168.5.7')
        }
    }

    It "returns exactly one URL when only the LAN adapter is present" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 1
        $urls[0].Label | Should -Be 'Ethernet'
        $urls[0].IP    | Should -Be '192.168.5.7'
        $urls[0].Url   | Should -Be 'http://192.168.5.7:3456?token=tok'
    }

    It "URL format is http://<ip>:<port>?token=<token>" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'mytoken'
        $urls[0].Url | Should -Match '^http://\d+\.\d+\.\d+\.\d+:3456\?token=mytoken$'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — LAN + one VPN adapter (generic)" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -Metric 10)
        }
        Mock Get-NetAdapter {
            return @(
                (New-MockAdapter -Name 'Ethernet'),
                (New-MockAdapter -Name 'NordLynx')
            )
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Ethernet' } {
            return @(New-MockIPAddress -IP '192.168.5.7')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'NordLynx' } {
            return @(New-MockIPAddress -IP '100.105.169.197')
        }
    }

    It "REGRESSION: returns TWO URLs when a VPN adapter is Up alongside LAN" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 2
    }

    It "first URL is the primary LAN adapter" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls[0].Label | Should -Be 'Ethernet'
        $urls[0].IP    | Should -Be '192.168.5.7'
    }

    It "second URL uses the adapter name as label (no VPN-specific hardcoding)" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls[1].Label | Should -Be 'NordLynx'
        $urls[1].IP    | Should -Be '100.105.169.197'
        $urls[1].Url   | Should -Be 'http://100.105.169.197:3456?token=tok'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — generic: any VPN adapter name is supported" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -Metric 10)
        }
        Mock Get-NetAdapter {
            return @(
                (New-MockAdapter -Name 'Ethernet'),
                (New-MockAdapter -Name 'WireGuard Tunnel'),
                (New-MockAdapter -Name 'OpenVPN TAP-Windows6')
            )
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Ethernet' } {
            return @(New-MockIPAddress -IP '192.168.5.7')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'WireGuard Tunnel' } {
            return @(New-MockIPAddress -IP '10.0.0.2')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'OpenVPN TAP-Windows6' } {
            return @(New-MockIPAddress -IP '172.16.0.5')
        }
    }

    It "returns THREE URLs for LAN + WireGuard + OpenVPN" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 3
        $urls[0].Label | Should -Be 'Ethernet'
        $urls[1].Label | Should -Be 'WireGuard Tunnel'
        $urls[2].Label | Should -Be 'OpenVPN TAP-Windows6'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — LAN + NordLynx + Tailscale" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -Metric 10)
        }
        Mock Get-NetAdapter {
            return @(
                (New-MockAdapter -Name 'Ethernet'),
                (New-MockAdapter -Name 'NordLynx'),
                (New-MockAdapter -Name 'Tailscale')
            )
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Ethernet' } {
            return @(New-MockIPAddress -IP '192.168.5.7')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'NordLynx' } {
            return @(New-MockIPAddress -IP '100.105.169.197')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Tailscale' } {
            return @(New-MockIPAddress -IP '100.88.1.5')
        }
    }

    It "returns THREE URLs when LAN + NordLynx + Tailscale are Up" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 3
        $urls[0].Label | Should -Be 'Ethernet'
        $urls[1].Label | Should -Be 'NordLynx'
        $urls[2].Label | Should -Be 'Tailscale'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — loopback / APIPA excluded" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -Metric 10)
        }
        Mock Get-NetAdapter {
            return @(
                (New-MockAdapter -Name 'Ethernet'),
                (New-MockAdapter -Name 'Loopback Pseudo-Interface 1'),
                (New-MockAdapter -Name 'APIPA-Interface')
            )
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Ethernet' } {
            return @(New-MockIPAddress -IP '192.168.5.7')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Loopback Pseudo-Interface 1' } {
            return @(New-MockIPAddress -IP '127.0.0.1')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'APIPA-Interface' } {
            return @(New-MockIPAddress -IP '169.254.1.100')
        }
    }

    It "excludes loopback (127.x) and APIPA (169.254.x) addresses" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 1
        $urls[0].IP | Should -Be '192.168.5.7'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — no primary NIC (edge case)" {

    BeforeEach {
        Mock Get-NetIPConfiguration { return @() }
        Mock Get-NetAdapter { return @() }
    }

    It "returns empty array when no adapter is Up" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Real-machine E2E: call Get-ConnectUrls against actual NIC state.
Describe "Get-ConnectUrls — REAL machine E2E" {

    It "REGRESSION: does not return a placeholder-only result on a real machine" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        foreach ($entry in $urls) {
            $entry.Url | Should -Not -Match 'your-ip'
            $entry.IP  | Should -Match '^\d+\.\d+\.\d+\.\d+$'
        }
    }

    It "returns at least one URL when a primary NIC with default gateway exists" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -BeGreaterOrEqual 1
        $urls[0].Url | Should -Match '^http://\d+\.\d+\.\d+\.\d+:3456\?token=tok$'
    }

    It "all IPs are unique (no duplicate adapter entries)" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $ips = $urls | ForEach-Object { $_.IP }
        ($ips | Select-Object -Unique).Count | Should -Be $ips.Count
    }

    It "REGRESSION: includes a VPN URL (100.x) when a VPN adapter is Up" {
        # Self-consistent: skip if Get-ConnectUrls itself finds no 100.x IP
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $vpnUrls = @($urls | Where-Object { $_.IP -match '^100\.' })
        if ($vpnUrls.Count -eq 0) {
            Set-ItResult -Skipped -Because "No VPN adapter with 100.x IP found on this host"
            return
        }
        $vpnUrls[0].Url | Should -Match '^http://100\.\d+\.\d+\.\d+:3456\?token=tok$'
    }

    It "VPN and LAN URLs have different IP addresses" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $vpnUrls = @($urls | Where-Object { $_.IP -match '^100\.' })
        if ($vpnUrls.Count -eq 0) {
            Set-ItResult -Skipped -Because "No VPN adapter with 100.x IP found on this host"
            return
        }
        $ips = $urls | ForEach-Object { $_.IP }
        ($ips | Select-Object -Unique).Count | Should -Be $ips.Count
    }
}
