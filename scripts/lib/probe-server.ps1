function Test-EvenTerminalRunning {
    param([int]$Port, [int]$TimeoutMs = 500)

    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen `
                     -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) { return $false }

    $raw = $listeners[0].LocalAddress
    $ipAddr = if ($raw -in @('0.0.0.0', '::', '::1')) { '127.0.0.1' } else { $raw }

    try {
        $resp = Invoke-WebRequest -Uri "http://$($ipAddr):$Port/" `
                  -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        if ($resp.StatusCode -in @(200, 401, 404)) { return $true }
    } catch [System.Net.WebException] {
        $sc = [int]$_.Exception.Response.StatusCode
        if ($sc -in @(200, 401, 404)) { return $true }
    } catch {}

    return $true
}
