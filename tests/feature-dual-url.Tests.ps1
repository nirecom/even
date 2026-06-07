# Tests: scripts/lib/list-display-urls.ps1, install.ps1
# Tags: dual-url, nordlynx, meshnet, connect-url, e2e
# E2E tests for the dual-URL requirement:
#   - When NordLynx (NordVPN Meshnet) is active, install must display BOTH
#     the LAN URL and the Meshnet URL.
#   - When NordLynx is inactive, only the LAN URL is displayed.
#   - All tests use Pester Mock so results are deterministic regardless of
#     the host's actual network state.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'scripts\lib\list-display-urls.ps1')

    # Shared mock helpers -------------------------------------------------------

    # Minimal PSCustomObject that mimics Get-NetIPConfiguration output.
    function script:New-MockIPConfig {
        param([string]$Alias, [string]$IP, [int]$Metric = 10)
        $addr = [PSCustomObject]@{ IPAddress = $IP }
        $gw   = [PSCustomObject]@{ RouteMetric = $Metric }
        $nic  = [PSCustomObject]@{ Status = 'Up' }
        return [PSCustomObject]@{
            InterfaceAlias      = $Alias
            IPv4Address         = @($addr)
            IPv4DefaultGateway  = @($gw)
            NetAdapter          = $nic
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
Describe "Get-ConnectUrls — NordLynx inactive" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -IP '192.168.5.7')
        }
        Mock Get-NetAdapter { return $null }
        Mock Get-NetIPAddress { return $null }
    }

    It "returns exactly one URL (LAN) when NordLynx is not present" {
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
Describe "Get-ConnectUrls — NordLynx active (regression gate)" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -IP '192.168.5.7')
        }
        Mock Get-NetAdapter -ParameterFilter { $Name -like 'NordLynx*' } {
            return @(New-MockAdapter -Name 'NordLynx')
        }
        Mock Get-NetAdapter -ParameterFilter { $Name -like 'Tailscale*' } {
            return $null
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'NordLynx' } {
            return @(New-MockIPAddress -IP '100.105.169.197')
        }
    }

    It "REGRESSION: returns TWO URLs (LAN + NordVPN Meshnet) when NordLynx is Up" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 2
    }

    It "first URL is the LAN URL" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls[0].Label | Should -Be 'Ethernet'
        $urls[0].IP    | Should -Be '192.168.5.7'
    }

    It "second URL is the NordVPN Meshnet URL" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls[1].Label | Should -Be 'NordVPN Meshnet'
        $urls[1].IP    | Should -Be '100.105.169.197'
        $urls[1].Url   | Should -Be 'http://100.105.169.197:3456?token=tok'
    }

    It "NordVPN Meshnet URL is in the correct http format" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls[1].Url | Should -Match '^http://100\.\d+\.\d+\.\d+:3456\?token=tok$'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — Tailscale active" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -IP '192.168.5.7')
        }
        Mock Get-NetAdapter -ParameterFilter { $Name -like 'NordLynx*' } {
            return $null
        }
        Mock Get-NetAdapter -ParameterFilter { $Name -like 'Tailscale*' } {
            return @(New-MockAdapter -Name 'Tailscale')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Tailscale' } {
            return @(New-MockIPAddress -IP '100.88.1.5')
        }
    }

    It "returns TWO URLs (LAN + Tailscale) when Tailscale is Up" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 2
        $urls[1].Label | Should -Be 'Tailscale'
        $urls[1].IP    | Should -Be '100.88.1.5'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — NordLynx AND Tailscale both active" {

    BeforeEach {
        Mock Get-NetIPConfiguration {
            return @(New-MockIPConfig -Alias 'Ethernet' -IP '192.168.5.7')
        }
        Mock Get-NetAdapter -ParameterFilter { $Name -like 'NordLynx*' } {
            return @(New-MockAdapter -Name 'NordLynx')
        }
        Mock Get-NetAdapter -ParameterFilter { $Name -like 'Tailscale*' } {
            return @(New-MockAdapter -Name 'Tailscale')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'NordLynx' } {
            return @(New-MockIPAddress -IP '100.105.169.197')
        }
        Mock Get-NetIPAddress -ParameterFilter { $InterfaceAlias -eq 'Tailscale' } {
            return @(New-MockIPAddress -IP '100.88.1.5')
        }
    }

    It "returns THREE URLs when both VPN adapters are Up" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 3
        $urls[0].Label | Should -Be 'Ethernet'
        $urls[1].Label | Should -Be 'NordVPN Meshnet'
        $urls[2].Label | Should -Be 'Tailscale'
    }
}

# ---------------------------------------------------------------------------
Describe "Get-ConnectUrls — no primary NIC (edge case)" {

    BeforeEach {
        Mock Get-NetIPConfiguration { return @() }
        Mock Get-NetAdapter { return $null }
        Mock Get-NetIPAddress { return $null }
    }

    It "returns empty array when no NIC has a default gateway" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Real-machine E2E: call Get-ConnectUrls directly against actual NIC state.
# No mocking — these tests validate the full path on the real host.
Describe "Get-ConnectUrls — REAL machine E2E" {

    It "REGRESSION: does not return a placeholder-only result on a real machine with at least one NIC" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        foreach ($entry in $urls) {
            $entry.Url | Should -Not -Match 'your-ip'
            $entry.IP  | Should -Match '^\d+\.\d+\.\d+\.\d+$'
        }
    }

    It "returns at least one LAN URL when a primary NIC with default gateway exists" {
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $urls.Count | Should -BeGreaterOrEqual 1
        $urls[0].Url | Should -Match '^http://\d+\.\d+\.\d+\.\d+:3456\?token=tok$'
    }

    It "REGRESSION: includes a NordVPN Meshnet URL (100.x) when NordLynx adapter is Up" {
        $nlAdapter = Get-NetAdapter -Name 'NordLynx*' -ErrorAction SilentlyContinue |
                     Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        if (-not $nlAdapter) {
            Set-ItResult -Skipped -Because "NordLynx adapter is not Up on this host"
            return
        }
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $meshnetEntry = $urls | Where-Object { $_.Label -eq 'NordVPN Meshnet' }
        $meshnetEntry | Should -Not -BeNullOrEmpty
        $meshnetEntry.IP  | Should -Match '^100\.'
        $meshnetEntry.Url | Should -Match '^http://100\.\d+\.\d+\.\d+:3456\?token=tok$'
    }

    It "NordVPN Meshnet URL and LAN URL are different addresses" {
        $nlAdapter = Get-NetAdapter -Name 'NordLynx*' -ErrorAction SilentlyContinue |
                     Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        if (-not $nlAdapter) {
            Set-ItResult -Skipped -Because "NordLynx adapter is not Up on this host"
            return
        }
        $urls = Get-ConnectUrls -Port 3456 -Token 'tok'
        $ips = $urls | ForEach-Object { $_['IP'] }
        ($ips | Select-Object -Unique).Count | Should -Be $ips.Count
    }
}
