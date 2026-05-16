# History

### Initial implementation: even-terminal autostart for G2 glasses (2026-05-16)
Background: Manual launch of `@evenrealities/even-terminal` and per-session QR re-scan was required to connect Even Realities G2 glasses to Claude Code. This repo automates startup at PC login with a fixed bridge token and stable Connect URL.
Changes: Added install/uninstall scripts symmetric across Windows (Task Scheduler ONLOGON) and POSIX (launchd on macOS, `systemctl --user` on Linux). Config SSOT at `~/.config/even-terminal/config.json` (chmod 600 on POSIX). Token delivered via `BRIDGE_TOKEN` env var (not CLI flag) to keep it out of `ps`-listings and Task Scheduler action arguments. Network mode `auto` re-evaluates Tailscale vs LAN at each start. Already-running detection uses TCP probe + HTTP GET accepting 200/401/404. Tests: 11 Pester (Windows) + 11 bats (POSIX) cases covering install/uninstall idempotency, token format, network detection, and probe behaviour.
