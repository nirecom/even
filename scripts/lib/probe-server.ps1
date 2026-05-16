function Test-EvenTerminalRunning {
    param([int]$Port, [int]$TimeoutMs = 500)

    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $tcp.EndConnect($iar)
    } catch { return $false } finally { $tcp.Close() }

    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" `
                  -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        return $resp.StatusCode -in @(200, 401, 404)
    } catch [System.Net.WebException] {
        $sc = [int]$_.Exception.Response.StatusCode
        return $sc -in @(200, 401, 404)
    } catch { return $false }
}
