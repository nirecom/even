# Changelog

## Unreleased

### Added
- Initial release: autostart scripts for `@evenrealities/even-terminal` on Windows (Task Scheduler), macOS (launchd), and Linux (systemd user service).
- `install` / `uninstall` scripts symmetric across Windows (`.ps1`) and POSIX (`.sh`) with `--port`, `--network-mode`, `--force`, `--dry-run` flags.
- Auto network detection: prefers Tailscale, falls back to primary LAN interface, re-evaluated at each start.
- Connect URL printed after install for pasting into Even Hub.
