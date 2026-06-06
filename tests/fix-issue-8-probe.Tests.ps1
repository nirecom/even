# Tests: scripts/lib/probe-server.ps1
# Tags: probe-server, multi-ip, vpn
# Pester tests for Test-EvenTerminalRunning multi-IP probe behavior.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:ProbePs1   = Join-Path $script:RepoRoot 'scripts\lib\probe-server.ps1'
    $script:FakeServer = Join-Path $script:RepoRoot 'tests\fixtures\fake-even-terminal.js'

    # Dot-source the function under test (same pattern as feature-even-autostart.Tests.ps1).
    . $script:ProbePs1

    function script:Get-NonLoopbackIPv4 {
        # Returns a non-loopback, non-APIPA (169.254.x.x) IPv4 address, or $null.
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

    function script:Get-CandidateIpCount {
        # Mirrors probe-server.ps1 enumeration: 127.0.0.1 + non-loopback, non-APIPA,
        # non-WellKnown IPv4 addresses. Used for the timing-budget assertion.
        $count = 1  # 127.0.0.1
        try {
            $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                     Where-Object {
                         $_.IPAddress -notmatch '^127\.' -and
                         $_.IPAddress -notmatch '^169\.254\.' -and
                         $_.PrefixOrigin -ne 'WellKnown'
                     } |
                     Select-Object -ExpandProperty IPAddress
            if ($addrs) { $count += (@($addrs)).Count }
        } catch {}
        return $count
    }

    function script:Start-FakeServer {
        param(
            [int]$Port,
            [string]$Bind = $null
        )
        $args = @($script:FakeServer, '--port', "$Port")
        if ($Bind) { $args += @('--bind', $Bind) }
        $proc = Start-Process -FilePath 'node' -ArgumentList $args -PassThru -WindowStyle Hidden
        # Give the server a moment to bind.
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
}

Describe "Test-EvenTerminalRunning (probe-server.ps1)" {

    Context "loopback bind" {
        BeforeAll {
            $script:Port1 = 34560
            $script:Proc1 = $null
        }
        AfterAll {
            Stop-FakeServer $script:Proc1
        }

        It "returns true when fake server is listening on 127.0.0.1" {
            if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "node not available"
                return
            }
            $script:Proc1 = Start-FakeServer -Port $script:Port1
            Test-EvenTerminalRunning -Port $script:Port1 | Should -BeTrue
        }
    }

    Context "nothing listening" {
        It "returns false when nothing is listening on a closed port" {
            # Pick a port unlikely to be in use within the reserved test range.
            $closedPort = 34575
            Test-EvenTerminalRunning -Port $closedPort | Should -BeFalse
        }
    }

    Context "non-loopback bind (VPN-style)" {
        BeforeAll {
            $script:Port2 = 34562
            $script:Proc2 = $null
            $script:NonLoopback = Get-NonLoopbackIPv4
        }
        AfterAll {
            Stop-FakeServer $script:Proc2
        }

        It "returns true when fake server binds to a non-loopback IPv4" {
            if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "node not available"
                return
            }
            if (-not $script:NonLoopback) {
                Set-ItResult -Skipped -Because "no non-loopback IPv4 address available"
                return
            }
            $script:Proc2 = Start-FakeServer -Port $script:Port2 -Bind $script:NonLoopback
            Test-EvenTerminalRunning -Port $script:Port2 | Should -BeTrue
        }
    }

    Context "timing budget" {
        It "closed-port probe completes within (TimeoutMs * candidateCount * 2)" {
            $closedPort = 34578
            $timeoutMs  = 200
            $candidates = Get-CandidateIpCount
            $budget     = $timeoutMs * $candidates * 2

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-EvenTerminalRunning -Port $closedPort -TimeoutMs $timeoutMs
            $sw.Stop()

            $result | Should -BeFalse
            $sw.Elapsed.TotalMilliseconds | Should -BeLessThan $budget
        }
    }
}
