# Tests: scripts/lib/resolve-display-ip.ps1, install.ps1
# Tags: display-ip, connect-url, wildcard-bind, e2e
# Pester tests for the wildcard-bind regression: install.ps1 must NOT print
# `<your-ip>` in the Connect URL when even-terminal binds to 0.0.0.0.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:ResolvePs1 = Join-Path $script:RepoRoot 'scripts\lib\resolve-display-ip.ps1'
    $script:ProbePs1   = Join-Path $script:RepoRoot 'scripts\lib\probe-server.ps1'

    . $script:ResolvePs1
    . $script:ProbePs1

    function script:Get-PrimaryNicIPv4 {
        try {
            $primary = Get-NetIPConfiguration -ErrorAction Stop |
                       Where-Object { $null -ne $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
                       Sort-Object { $_.IPv4DefaultGateway.RouteMetric } |
                       Select-Object -First 1
            if ($primary -and $primary.IPv4Address) {
                return (@($primary.IPv4Address) | Select-Object -First 1).IPAddress
            }
        } catch {}
        return $null
    }

    function script:Start-WildcardTcpListener {
        param([int]$Port)
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        return $listener
    }

    function script:Stop-TcpListener {
        param($Listener)
        try { $Listener.Stop() } catch {}
    }
}

Describe "Resolve-DisplayIP (scripts/lib/resolve-display-ip.ps1)" {

    Context "passthrough for specific routable IPs" {
        It "returns the BoundIP as-is when it is a non-loopback IPv4" {
            Resolve-DisplayIP -BoundIP '192.168.5.7' | Should -Be '192.168.5.7'
        }
        It "returns the BoundIP as-is when it is a Tailscale IPv4" {
            Resolve-DisplayIP -BoundIP '100.105.169.197' | Should -Be '100.105.169.197'
        }
    }

    Context "fallback for wildcard / loopback / empty" {
        It "falls back to primary NIC IPv4 when BoundIP=0.0.0.0" {
            $primary = Get-PrimaryNicIPv4
            if (-not $primary) {
                Set-ItResult -Skipped -Because "no primary NIC IPv4 available on this host"
                return
            }
            Resolve-DisplayIP -BoundIP '0.0.0.0' | Should -Be $primary
        }
        It "falls back to primary NIC IPv4 when BoundIP=127.0.0.1" {
            $primary = Get-PrimaryNicIPv4
            if (-not $primary) {
                Set-ItResult -Skipped -Because "no primary NIC IPv4 available on this host"
                return
            }
            Resolve-DisplayIP -BoundIP '127.0.0.1' | Should -Be $primary
        }
        It "falls back to primary NIC IPv4 when BoundIP is empty" {
            $primary = Get-PrimaryNicIPv4
            if (-not $primary) {
                Set-ItResult -Skipped -Because "no primary NIC IPv4 available on this host"
                return
            }
            Resolve-DisplayIP -BoundIP '' | Should -Be $primary
        }
        It "falls back to primary NIC IPv4 when BoundIP=::" {
            $primary = Get-PrimaryNicIPv4
            if (-not $primary) {
                Set-ItResult -Skipped -Because "no primary NIC IPv4 available on this host"
                return
            }
            Resolve-DisplayIP -BoundIP '::' | Should -Be $primary
        }
    }
}

Describe "Get-ConnectUrl (scripts/lib/resolve-display-ip.ps1)" {

    Context "URL composition" {
        It "embeds a specific BoundIP verbatim" {
            $url = Get-ConnectUrl -BoundIP '192.168.5.7' -Port 3456 -Token 'tok123'
            $url | Should -Be 'http://192.168.5.7:3456?token=tok123'
        }
        It "REGRESSION: never returns the [your-ip] placeholder when a primary NIC IPv4 exists, even when probe returned wildcard" {
            $primary = Get-PrimaryNicIPv4
            if (-not $primary) {
                Set-ItResult -Skipped -Because "no primary NIC IPv4 available on this host"
                return
            }
            $url = Get-ConnectUrl -BoundIP '0.0.0.0' -Port 3456 -Token 'tok123'
            $url | Should -Not -Match '<your-ip>'
            $url | Should -Match '^http://\d+\.\d+\.\d+\.\d+:3456\?token=tok123$'
        }
    }
}

Describe "install.ps1 wildcard-bind E2E (Connect URL must show real IP)" {

    Context "even-terminal listening on 0.0.0.0 (wildcard)" {
        BeforeAll {
            $script:Port = 34590
            $script:Listener = $null
        }
        AfterAll { Stop-TcpListener $script:Listener }

        It "REGRESSION: install.ps1 display block produces Connect URL with real IPv4 (not the [your-ip] placeholder)" {
            $primary = Get-PrimaryNicIPv4
            if (-not $primary) {
                Set-ItResult -Skipped -Because "no primary NIC IPv4 available on this host"
                return
            }
            $script:Listener = Start-WildcardTcpListener -Port $script:Port

            $probeResult = Test-EvenTerminalRunning -Port $script:Port
            $probeResult.Running | Should -BeTrue
            $probeResult.BoundIP | Should -Be '0.0.0.0'

            $url = Get-ConnectUrl -BoundIP $probeResult.BoundIP -Port $script:Port -Token 'e2etok'
            $url | Should -Not -Match '<your-ip>'
            $url | Should -Be "http://${primary}:${script:Port}?token=e2etok"
        }
    }
}
