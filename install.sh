#!/usr/bin/env bash
set -euo pipefail

PORT=3456
NETWORK_MODE=auto
FORCE=0
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --network-mode) NETWORK_MODE="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

CONFIG_DIR="${EVEN_TERMINAL_CONFIG_DIR:-$HOME/.config/even-terminal}"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
CONFIG_PATH="$CONFIG_DIR/config.json"
LOG_DIR="$CONFIG_DIR/logs"
mkdir -p "$LOG_DIR"

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
START_SCRIPT="$REPO_ROOT/scripts/start.sh"
chmod +x "$START_SCRIPT"

if [ -f "$CONFIG_PATH" ] && [ "$FORCE" -eq 0 ]; then
    echo "Config already exists: $CONFIG_PATH (use --force to overwrite)"
else
    EXE_PATH=$(command -v even-terminal 2>/dev/null || true)
    if [ -z "$EXE_PATH" ]; then
        echo "ERROR: even-terminal not found in PATH." >&2
        echo "  Install: npm install -g @evenrealities/even-terminal" >&2
        exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 required for install. Install python3 and retry." >&2
        exit 1
    fi

    EXE_PATH=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$EXE_PATH")

    TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

    python3 - "$EXE_PATH" "$TOKEN" "$PORT" "$NETWORK_MODE" "$CONFIG_DIR" "$CONFIG_PATH" <<'PYEOF'
import json, os, sys
exe_path, token, port, network_mode, config_dir, config_path = sys.argv[1:7]
cfg = {
    "version": 1,
    "executable": exe_path,
    "executable_args": [],
    "token": token,
    "port": int(port),
    "provider": "claude",
    "network_mode": network_mode,
    "config_dir": config_dir,
}
with open(config_path, "w") as f:
    json.dump(cfg, f, indent=2)
os.chmod(config_path, 0o600)
PYEOF
    echo "Config created: $CONFIG_PATH"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "DryRun: skipping service registration."
    exit 0
fi

UNAME=$(uname -s)
case "$UNAME" in
  Darwin)
    PLIST="$HOME/Library/LaunchAgents/com.user.even-terminal.plist"
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.user.even-terminal</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>${START_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${LOG_DIR}/launchd.out.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/launchd.err.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>EVEN_TERMINAL_CONFIG_DIR</key><string>${CONFIG_DIR}</string>
  </dict>
</dict></plist>
EOF2
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "launchd loaded: $PLIST"
    ;;
  Linux)
    UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_DIR/even-terminal.service" <<EOF2
[Unit]
Description=even-terminal autostart for G2 glasses
After=network-online.target

[Service]
Type=simple
Environment=EVEN_TERMINAL_CONFIG_DIR=${CONFIG_DIR}
ExecStart=/bin/bash ${START_SCRIPT}
Restart=on-failure
RestartSec=10
StandardOutput=append:${LOG_DIR}/stdout.log
StandardError=append:${LOG_DIR}/stderr.log

[Install]
WantedBy=default.target
EOF2
    systemctl --user daemon-reload
    systemctl --user enable --now even-terminal.service
    if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
        echo "note: enable lingering for autostart when not logged in:"
        echo "  sudo loginctl enable-linger $USER"
    fi
    echo "systemd service installed."
    ;;
  *)
    echo "Unsupported platform: $UNAME" >&2
    exit 1
    ;;
esac

. "$REPO_ROOT/scripts/lib/probe-server.sh"
P=$(python3 -c "import json; print(json.load(open('$CONFIG_PATH'))['port'])")
TOKEN_VAL=$(python3 -c "import json; print(json.load(open('$CONFIG_PATH'))['token'])")
STARTED=0
for _ in $(seq 1 30); do
    if probe_server "$P"; then STARTED=1; break; fi
    sleep 0.5
done
if [ "$STARTED" -ne 1 ]; then
    echo "Warning: server did not start within 15s. Check: $LOG_DIR/stdout.log" >&2
    exit 1
fi

IP=""
if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
    IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
fi
if [ -z "$IP" ]; then
    case "$UNAME" in
        Darwin)
            IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true) ;;
        Linux)
            if command -v ip >/dev/null 2>&1; then
                IP=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
            else
                IP=$(hostname -I 2>/dev/null | awk '{print $1}')
            fi ;;
    esac
fi

echo ""
echo "=== Installation complete ==="
echo "  Connect URL : http://${IP:-<your-ip>}:${P}?token=${TOKEN_VAL}"
echo "  Log         : $LOG_DIR/stdout.log"
echo ""
echo "Open Even Hub on your G2 and scan the QR code shown in the server log,"
echo "or paste the Connect URL directly into Even Hub."
