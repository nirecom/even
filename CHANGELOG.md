# Changelog

## Unreleased

### Added
- Initial release: autostart scripts for `@evenrealities/even-terminal` on Windows (Task Scheduler), macOS (launchd), and Linux (systemd user service).
- `install` / `uninstall` scripts symmetric across Windows (`.ps1`) and POSIX (`.sh`) with `--port`, `--network-mode`, `--force`, `--dry-run` flags.
- Auto network detection: prefers Tailscale, falls back to primary LAN interface, re-evaluated at each start.
- Connect URL printed after install for pasting into Even Hub.

### FEATURE: PR #3 (2026-06-06)
Background: fix: resolve fnm multishell shim path for Task Scheduler
Changes: Fixed Windows startup failure when Node is managed by fnm: `install.ps1` now stores the permanent npm global path instead of the session-temporary fnm multishell shim, and `start.ps1` initializes fnm before launch so the Task Scheduler service can find `even-terminal`.

### FEATURE: PR #5 (2026-06-06)
Background: fix: store node.exe+cli.js paths directly to survive Task Scheduler context
Changes: Fixed: even-terminal now starts reliably at login on Windows — the installer stores the permanent node.exe path instead of a session-temporary fnm shim, so Task Scheduler can launch it without fnm on PATH

### FEATURE: PR #7 (2026-06-06)
Background: fix: increase install.ps1 probe timeout to 30s and make it non-fatal
Changes: Fixed: `install.ps1 -Force` no longer exits with "Server did not start within 15s" when Node cold-start exceeds the old deadline. Probe timeout extended to 30s and made non-fatal — the Connect URL is now always printed after install.

### BUGFIX: PR #9 (2026-06-06)
Background: fix: probe all candidate IPv4 addresses to fix VPN-caused timeout (#8)
Changes: Fixed: `install.ps1 -Force` no longer shows "WARNING: Server did not start within 30s" when a VPN (NordVPN, etc.) is active. The probe now checks all local IPv4 addresses — `127.0.0.1` plus any VPN/LAN interfaces — so even-terminal is found regardless of which network interface it binds to.

### FEATURE: PR #11 (2026-06-07)
Background: fix: detect server via LISTEN-state to handle any NIC/VPN binding
Changes: Fixed: `install.ps1 -Force` no longer reports "Server did not start within 30s" when `even-terminal` is bound to a VPN IP (NordVPN Meshnet, WireGuard, Tailscale, or any non-loopback NIC). Server detection now queries the OS kernel LISTEN-state table directly — no TCP self-connection needed.

### FEATURE: PR #13 (2026-06-08)
Background: fix: display Connect URL using server's actual bound IP (#12)
Changes: Fixed: Connect URL printed by `install.ps1`/`install.sh` now shows the same IP as the QR code in the server log. Previously the URL used the Tailscale IP while the QR code showed the actual LAN bind IP, causing a mismatch under NordVPN Meshnet (NordLynx adapter) and any setup where even-terminal binds to a different interface than Tailscale.
