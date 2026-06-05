# History

### Initial implementation: even-terminal autostart for G2 glasses (2026-05-16)
Background: Manual launch of `@evenrealities/even-terminal` and per-session QR re-scan was required to connect Even Realities G2 glasses to Claude Code. This repo automates startup at PC login with a fixed bridge token and stable Connect URL.
Changes: Added install/uninstall scripts symmetric across Windows (Task Scheduler ONLOGON) and POSIX (launchd on macOS, `systemctl --user` on Linux). Config SSOT at `~/.config/even-terminal/config.json` (chmod 600 on POSIX). Token delivered via `BRIDGE_TOKEN` env var (not CLI flag) to keep it out of `ps`-listings and Task Scheduler action arguments. Network mode `auto` re-evaluates Tailscale vs LAN at each start. Already-running detection uses TCP probe + HTTP GET accepting 200/401/404. Tests: 11 Pester (Windows) + 11 bats (POSIX) cases covering install/uninstall idempotency, token format, network detection, and probe behaviour.

### FEATURE: PR #3 — fix/fnm-fix (2026-06-06, 68c61057498dbe3a3d58127461100065d56e1a35, #3)
Background: fix: resolve fnm multishell shim path for Task Scheduler
Changes: fix(install.ps1, start.ps1): resolve fnm multishell shim path causing Task Scheduler launch failure. install.ps1 now resolves executable via npm prefix -g (permanent path). start.ps1 initializes fnm at startup so node/even-terminal are on PATH in minimal-PATH Task Scheduler environment, with fallback re-resolution if stored path is stale. <!-- compose-doc-append-sentinel: branch=fix/fnm-fix pr=#3 -->

### FEATURE: PR #5 — fix/fnm-fix3 (2026-06-06, 15b80864d490bd19e69931a1951aedb0ee8e4ee8, #5)
Background: fix: store node.exe+cli.js paths directly to survive Task Scheduler context
Changes: BUGFIX: fix fnm multishell shim path so even-terminal starts under Task Scheduler — store node.exe and cli.js absolute paths directly in config.json, bypassing fnm at launch time <!-- compose-doc-append-sentinel: branch=fix/fnm-fix3 pr=#5 -->
