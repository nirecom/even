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
