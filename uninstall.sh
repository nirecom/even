#!/usr/bin/env bash
set -uo pipefail

DRY_RUN=0
KEEP_CONFIG=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --keep-config) KEEP_CONFIG=1; shift ;;
        *) shift ;;
    esac
done

if [ "$DRY_RUN" -eq 0 ]; then
    case "$(uname -s)" in
        Darwin)
            PLIST="$HOME/Library/LaunchAgents/com.user.even-terminal.plist"
            if [ -f "$PLIST" ]; then
                launchctl unload "$PLIST" 2>/dev/null || true
                rm "$PLIST"
            fi
            ;;
        Linux)
            systemctl --user disable --now even-terminal.service 2>/dev/null || true
            rm -f "$HOME/.config/systemd/user/even-terminal.service"
            systemctl --user daemon-reload
            ;;
    esac
fi

CONFIG_DIR="${EVEN_TERMINAL_CONFIG_DIR:-$HOME/.config/even-terminal}"
CONFIG_PATH="$CONFIG_DIR/config.json"
if [ "$KEEP_CONFIG" -eq 0 ] && [ -f "$CONFIG_PATH" ]; then
    cp "$CONFIG_PATH" "$CONFIG_PATH.bak"
    rm "$CONFIG_PATH"
    echo "Config removed (backup: $CONFIG_PATH.bak)"
fi
echo "Uninstalled."
