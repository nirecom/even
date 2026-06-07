#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/read-config.sh"
. "$SCRIPT_DIR/lib/detect-network.sh"
. "$SCRIPT_DIR/lib/probe-server.sh"

CONFIG_DIR="${EVEN_TERMINAL_CONFIG_DIR:-$HOME/.config/even-terminal}"
CONFIG_PATH="$CONFIG_DIR/config.json"
[ -f "$CONFIG_PATH" ] || {
    echo "Config not found: $CONFIG_PATH. Run ./install.sh first." >&2
    exit 1
}

EXE=$(read_config "$CONFIG_PATH" executable)
TOKEN=$(read_config "$CONFIG_PATH" token)
PORT=$(read_config "$CONFIG_PATH" port)
PROVIDER=$(read_config "$CONFIG_PATH" provider)
NETWORK_MODE=$(read_config "$CONFIG_PATH" network_mode)

if probe_server "$PORT" >/dev/null; then
    echo "even-terminal already responding on port $PORT; skipping."
    exit 0
fi

[ -x "$EXE" ] || {
    echo "Executable not found: $EXE. Re-run install.sh." >&2
    exit 1
}

NET_PAIR=$(detect_network "$NETWORK_MODE")
NET_MODE=$(echo "$NET_PAIR" | awk '{print $1}')
NET_ARG=$(echo "$NET_PAIR" | awk '{print $2}')

export BRIDGE_TOKEN="$TOKEN"
export PORT

ARGS=(--provider "$PROVIDER" --port "$PORT")
case "$NET_MODE" in
    tailscale) ARGS+=(--tailscale) ;;
    # auto/loopback/interface: no --interface; even-terminal binds 0.0.0.0
    # and accepts connections from all NICs.
esac

mkdir -p "$CONFIG_DIR/logs"
exec "$EXE" "${ARGS[@]}" \
    >>"$CONFIG_DIR/logs/stdout.log" \
    2>>"$CONFIG_DIR/logs/stderr.log"
