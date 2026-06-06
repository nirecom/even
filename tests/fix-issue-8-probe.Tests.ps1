# Tests: scripts/lib/probe-server.ps1
# Tags: probe-server, listen-state, vpn
# Pester tests for Test-EvenTerminalRunning LISTEN-state detection (issue #10).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:ProbePs1   = Join-Path $script:RepoRoot 'scripts\lib\probe-server.ps1'
    $script:FakeServer = Join-Path $script:RepoRoot 'tests\fixtures\fake-even-terminal.js'

    . $script:ProbePs1

    function script:Start-FakeServer {
        param([int]$Port, [string]$Bind = $null)
        $nodeArgs = @($script:FakeServer, '--port', "$Port")
        if ($Bind) { $nodeArgs += @('--bind', $Bind) }
        $proc = Start-Process -FilePath 'node' -ArgumentList $nodeArgs -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 2
        return $proc
    }

    function script:Stop-FakeServer {
        param($Proc)
        if ($Proc -and -not $Proc.HasExited) {
            try { $Proc.Kill() } catch {}
            try { $Proc.WaitForExit(2000) | Out-Null } catch {}
        }
    }

    function script:Get-NonLoopbackIPv4 {
        try {
            $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                     Where-Object {
                         $_.IPAddress -ne '127.0.0.1' -and
                         -not $_.IPAddress.StartsWith('169.254.') -and
                         $_.PrefixOrigin -ne 'WellKnown'
                     } |
                     Select-Object -ExpandProperty IPAddress
            if ($addrs) { return @($addrs)[0] }
        } catch {}
        return $null
    }

    function script:Start-TcpListener {
        param([int]$Port)
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $listener
    }

    function script:Stop-TcpListener {
        param($Listener)
        try { $Listener.Stop() } catch {}
    }
}

Describe "Test-EvenTerminalRunning (probe-server.ps1 — LISTEN-state)" {

    Context "nothing listening" {
        It "returns false when nothing is listening on a closed port" {
            $closedPort = 34575
            Test-EvenTerminalRunning -Port $closedPort | Should -BeFalse
        }
    }

    Context "loopback bind (HTTP server)" {
        BeforeAll {
            $script:Port1 = 34560
            $script:Proc1 = $null
        }
        AfterAll { Stop-FakeServer $script:Proc1 }

        It "returns true when fake server listens on 127.0.0.1" {
            if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "node not available"
                return
            }
            $script:Proc1 = Start-FakeServer -Port $script:Port1
            Test-EvenTerminalRunning -Port $script:Port1 | Should -BeTrue
        }
    }

    Context "non-loopback bind (VPN-style)" {
        BeforeAll {
            $script:Port2 = 34562
            $script:Proc2 = $null
            $script:NonLB = Get-NonLoopbackIPv4
        }
        AfterAll { Stop-FakeServer $script:Proc2 }

        It "returns true when fake server binds to a non-loopback IPv4" {
            if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "node not available"
                return
            }
            if (-not $script:NonLB) {
                Set-ItResult -Skipped -Because "no non-loopback IPv4 available"
                return
            }
            $script:Proc2 = Start-FakeServer -Port $script:Port2 -Bind $script:NonLB
            Test-EvenTerminalRunning -Port $script:Port2 | Should -BeTrue
        }
    }

    Context "LISTEN-only path (raw TCP, no HTTP)" {
        BeforeAll {
            $script:Port3    = 34564
            $script:Listener = $null
        }
        AfterAll { Stop-TcpListener $script:Listener }

        It "returns true when a non-HTTP TCP listener occupies the port" {
            $script:Listener = Start-TcpListener -Port $script:Port3
            Test-EvenTerminalRunning -Port $script:Port3 | Should -BeTrue
        }
    }

    Context "timing budget" {
        It "closed-port probe completes within 2000ms" {
            $closedPort = 34578
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-EvenTerminalRunning -Port $closedPort
            $sw.Stop()
            $result | Should -BeFalse
            $sw.Elapsed.TotalMilliseconds | Should -BeLessThan 2000
        }
    }
}
