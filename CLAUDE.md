# even — probe policy

Server detection uses OS LISTEN-state (`Get-NetTCPConnection` / `ss` / `netstat`), not IP enumeration.
This makes probing routing-exempt and VPN-agnostic (NordVPN Meshnet, WireGuard, Tailscale, wired LAN, Wi-Fi).
