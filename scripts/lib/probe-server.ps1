function Test-EvenTerminalRunning {
    param([int]$Port, [int]$TimeoutMs = 500)

    # Probe 127.0.0.1 plus every non-loopback, non-APIPA IPv4 on this host.
    # Enumerate here (not at call sites) to keep probe as the SSOT for
    # "is even-terminal reachable?" (core-principles.md §2).
    $candidates = @('127.0.0.1')
    $extra = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^127\.' -and
                       $_.IPAddress -notmatch '^169\.254\.' -and
                       $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -ExpandProperty IPAddress |
        Where-Object { $_ })  # guard against $null from empty pipeline
    $candidates += $extra | Where-Object { $_ -and $_ -notin $candidates }

    foreach ($ipAddr in $candidates) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $iar = $tcp.BeginConnect($ipAddr, $Port, $null, $null)
            if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { continue }
            $tcp.EndConnect($iar)
        } catch { continue } finally { $tcp.Close() }

        try {
            $resp = Invoke-WebRequest -Uri "http://$($ipAddr):$Port/" `
                      -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($resp.StatusCode -in @(200, 401, 404)) { return $true }
        } catch [System.Net.WebException] {
            $sc = [int]$_.Exception.Response.StatusCode
            if ($sc -in @(200, 401, 404)) { return $true }
        } catch {}
    }
    return $false
}
