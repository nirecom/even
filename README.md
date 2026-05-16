# even — autostart for Even Realities G2 + Claude Code

Auto-start [`@evenrealities/even-terminal`](https://www.npmjs.com/package/@evenrealities/even-terminal) on PC login so your Even Realities G2 glasses can connect to your Claude Code sessions without manual setup. Sets up Task Scheduler (Windows), launchd (macOS), or systemd user service (Linux) with a fixed token and stable connection URL.

## What it does

- Generates a fixed bridge token on first install (saved to `~/.config/even-terminal/config.json`).
- Registers an autostart entry that launches `even-terminal --provider claude` on login.
- Detects Tailscale at startup; falls back to the primary LAN interface when Tailscale is not available.
- Provides idempotent install / uninstall scripts symmetric across Windows and POSIX.

## Prerequisites

- **Node.js 18+** and `even-terminal` installed globally:
  ```
  npm install -g @evenrealities/even-terminal
  ```
- **Windows**: PowerShell 5.1+ (preinstalled on Windows 10/11).
- **POSIX**: `python3` (required); `jq` optional but speeds up config reads.
- **Tailscale** (optional): if installed and running at startup, the server binds to your Tailscale IP for cross-network access.

## Install

### Windows

Open PowerShell in this directory and run:

```powershell
.\install.ps1
```

This generates the token, registers `EvenTerminalAutostart` in Task Scheduler (ONLOGON), launches the server, and prints the Connect URL. Open the Even Hub app on your G2 and either scan the QR code shown in the server log or paste the Connect URL directly.

Options:
- `-Port <N>` — port to listen on (default 3456)
- `-NetworkMode <mode>` — `auto` (default) | `tailscale` | `lan` | `loopback`
- `-Force` — overwrite existing config
- `-DryRun` — skip Task Scheduler registration (testing only)

### macOS / Linux

```bash
./install.sh
```

Registers a launchd LaunchAgent on macOS or a `systemctl --user` service on Linux. Same options as Windows but with `--` flags: `--port`, `--network-mode`, `--force`, `--dry-run`.

On Linux, if you want the service to run when no user is logged in:

```bash
sudo loginctl enable-linger $USER
```

## Configuration

After install, the persistent config lives at `~/.config/even-terminal/config.json`:

| Field | Meaning |
|---|---|
| `executable` | Absolute path to `even-terminal` resolved at install time. |
| `token` | URL-safe bridge token (kept secret). |
| `port` | TCP port the server listens on. |
| `provider` | Always `claude`. |
| `network_mode` | `auto` / `tailscale` / `lan` / `loopback`. `auto` re-detects at each start. |

To change settings, edit `config.json` and either re-run install or restart the service:
- Windows: `Stop-ScheduledTask EvenTerminalAutostart; Start-ScheduledTask EvenTerminalAutostart`
- macOS: `launchctl unload ~/Library/LaunchAgents/com.user.even-terminal.plist && launchctl load ~/Library/LaunchAgents/com.user.even-terminal.plist`
- Linux: `systemctl --user restart even-terminal.service`

The config contains a secret token; do not commit or share it.

## Uninstall

```powershell
.\uninstall.ps1            # Windows
```

```bash
./uninstall.sh             # macOS / Linux
```

Options: `--keep-config` (POSIX) / `-KeepConfig` (Windows) preserves the config; `--dry-run` / `-DryRun` skips the service removal.

A `.bak` of the previous config is left next to the removed file.

## Troubleshooting

- **`even-terminal not found`**: confirm `npm install -g @evenrealities/even-terminal` succeeded and that the npm global bin is on `PATH`. With fnm or nvm, set a `default` Node version so service-context PATH includes the shim.
- **launchd cannot find Node**: launchd starts with a minimal `PATH`. The install script writes an `EnvironmentVariables` block, but if your `even-terminal` is under fnm/nvm, you may need to use a shim or wrap the launchd `ProgramArguments` accordingly.
- **systemd service stops at logoff**: enable lingering with `sudo loginctl enable-linger $USER`.
- **Port already in use**: the start script detects an HTTP server on the configured port and skips startup. Edit `config.json` to use a different port, then restart the service.
- **G2 cannot connect**: confirm the Connect URL's IP is reachable from G2 (use the Tailscale IP for cross-network access). Re-run `install.ps1`/`install.sh` to re-print the URL.

## Architecture

See [docs/architecture.md](docs/architecture.md) for design decisions (symmetric mirror layout, config SSOT, HTTP probe rationale, token delivery via `BRIDGE_TOKEN` env var).
