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

### FEATURE: PR #7 — fix/probe-timeout (2026-06-06, b5214a99c490e9a4d7ac2b922063b40c4500491c, #7)
Background: fix: increase install.ps1 probe timeout to 30s and make it non-fatal
Changes: fix(install.ps1): increase probe timeout from 15s to 30s and make it non-fatal — Get-NetworkArgs + Node cold-start regularly exceeded the 15s deadline; Task Scheduler registration succeeds regardless, so timeout is now a warning-only; Connect URL always printed (#6) <!-- compose-doc-append-sentinel: branch=fix/probe-timeout pr=#7 -->

### BUGFIX: PR #9 — fix/issue-8-probe (2026-06-06, e350702, #9)
Background: fix: probe all candidate IPv4 addresses to fix VPN-caused timeout (#8)
Changes: Both probe functions now enumerate 127.0.0.1 plus all non-loopback, non-APIPA IPv4 addresses on the host (PS: Get-NetIPAddress -AddressFamily IPv4; bash: ip addr / ifconfig fallback), probe each candidate with TCP+HTTP, and short-circuit on first success. Call sites (install.ps1, start.ps1, start.sh) unchanged. architecture.md updated; Pester and bats tests added. <!-- compose-doc-append-sentinel: branch=fix/issue-8-probe pr=#9 -->

### FEATURE: PR #11 — main (2026-06-07, bfeb03cd6dbf0308acd1cb01062da9587acf24bc, #11)
Background: fix: detect server via LISTEN-state to handle any NIC/VPN binding
Changes: BUGFIX #10: Replaced IP-enumeration server detection with OS LISTEN-state detection. Background: the multi-IP probe from PR #9 still failed under NordVPN Meshnet/WireGuard — virtual NICs block TCP self-connections, so every VPN address timed out at 200ms and exhausted the 30s window. Changes: `probe-server.ps1` now uses `Get-NetTCPConnection -LocalPort $Port -State Listen` (PS 4+, routing-exempt); `probe-server.sh` uses `ss -4tln` (Linux) / `netstat -an` (macOS/BSD fallback), both portable via dual colon/dot awk parser. LISTEN state is trusted alone when HTTP fails. Port validation guard added to bash entry points. New `CLAUDE.md` documents the universal probe policy. `docs/architecture.md` updated. <!-- compose-doc-append-sentinel: branch=main pr=#11 -->

### FEATURE: PR #13 — fix/fix-bound-ip (2026-06-08, 1bfe131550ad1be30f044ed3b8e7b6eb27500e31, #13)
Background: fix: display Connect URL using server's actual bound IP (#12)
Changes: fix #12: Connect URL IP source changed from independent tailscale/enumeration to server's actual LISTEN-state bound IP. Background: even-terminal binds via `--interface <LAN NIC>` (e.g. 192.168.5.7), but install.ps1 called `tailscale ip -4` independently — QR code in log showed LAN IP while Connect URL showed VPN IP (NordVPN Meshnet / NordLynx). Fix: probe-server.ps1 `Test-EvenTerminalRunning` now returns `@{ Running = $bool; BoundIP = $raw }` hashtable (raw LocalAddress from Get-NetTCPConnection LISTEN-state, already computed internally); probe-server.sh `probe_server` echoes `$bound_ip` on stdout on success; `_probe_server_legacy` emits nothing (honest empty). install.ps1 captures `$probeResult.BoundIP`; tailscale/Get-NetIPAddress block (lines 101-111) removed. install.sh captures `BOUND_IP=$(probe_server "$P")`; tailscale/ipconfig/ip block (lines 147-162) removed. Wildcard-bind fallback (`0.0.0.0`/`::`) maps to `<your-ip>` placeholder in both. start.ps1 fixed: hashtable is always truthy — added `.Running` check to guard. start.sh: probe stdout suppressed with `>/dev/null`. Tests: Pester assertions updated to `.Running | Should -Be*` + `.BoundIP | Should -Be`; bats `$output` assertions added for each contract (loopback→127.0.0.1, non-loopback→actual IP, legacy→empty). <!-- compose-doc-append-sentinel: branch=fix/fix-bound-ip pr=#13 -->
