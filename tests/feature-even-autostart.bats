#!/usr/bin/env bats
# bats tests for even-terminal autostart (POSIX)
# Source files under test (not yet implemented):
#   install.sh, scripts/start.sh, uninstall.sh
# These tests will fail until the sources exist — that is expected.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    INSTALL_SH="$REPO_ROOT/install.sh"
    START_SH="$REPO_ROOT/scripts/start.sh"
    UNINSTALL_SH="$REPO_ROOT/uninstall.sh"
    FAKE_SERVER="$REPO_ROOT/tests/fixtures/fake-even-terminal.js"

    EVEN_TERMINAL_CONFIG_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'et-test')"
    export EVEN_TERMINAL_CONFIG_DIR

    # Provide a fake `even-terminal` on PATH so install.sh's resolution succeeds.
    FAKE_BIN="$EVEN_TERMINAL_CONFIG_DIR/bin"
    mkdir -p "$FAKE_BIN"
    cat >"$FAKE_BIN/even-terminal" <<'SH'
#!/usr/bin/env bash
echo "fake-even-terminal $@"
SH
    chmod 755 "$FAKE_BIN/even-terminal"
    ORIGINAL_PATH="$PATH"
    export PATH="$FAKE_BIN:$PATH"
}

teardown() {
    if [ -n "${FAKE_PID:-}" ]; then
        kill "$FAKE_PID" 2>/dev/null || true
        wait "$FAKE_PID" 2>/dev/null || true
    fi
    [ -n "${ORIGINAL_PATH:-}" ] && export PATH="$ORIGINAL_PATH"
    if [ -n "${EVEN_TERMINAL_CONFIG_DIR:-}" ] && [ -d "$EVEN_TERMINAL_CONFIG_DIR" ]; then
        rm -rf "$EVEN_TERMINAL_CONFIG_DIR"
    fi
}

require_source() {
    if [ ! -f "$1" ]; then
        skip "source not yet implemented: $1"
    fi
}

@test "install.sh --dry-run creates config.json" {
    require_source "$INSTALL_SH"
    run bash "$INSTALL_SH" --dry-run
    [ -f "$EVEN_TERMINAL_CONFIG_DIR/config.json" ]
}

@test "install.sh config has required fields" {
    require_source "$INSTALL_SH"
    run bash "$INSTALL_SH" --dry-run
    cfg="$EVEN_TERMINAL_CONFIG_DIR/config.json"
    [ -f "$cfg" ]
    grep -q '"version"' "$cfg"
    grep -q '"executable"' "$cfg"
    grep -q '"token"' "$cfg"
    grep -q '"port"' "$cfg"
    grep -q '"provider"' "$cfg"
    grep -q '"network_mode"' "$cfg"
    grep -q '"config_dir"' "$cfg"
}

@test "install.sh token is at least 30 chars" {
    require_source "$INSTALL_SH"
    run bash "$INSTALL_SH" --dry-run
    cfg="$EVEN_TERMINAL_CONFIG_DIR/config.json"
    token="$(sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg")"
    [ -n "$token" ]
    [ "${#token}" -ge 30 ]
    # url-safe base64 character set
    [[ "$token" =~ ^[A-Za-z0-9_-]+$ ]]
}

@test "install.sh config.json has mode 600" {
    require_source "$INSTALL_SH"
    run bash "$INSTALL_SH" --dry-run
    cfg="$EVEN_TERMINAL_CONFIG_DIR/config.json"
    [ -f "$cfg" ]
    # Cross-platform stat: try GNU then BSD.
    mode="$(stat -c '%a' "$cfg" 2>/dev/null || stat -f '%Lp' "$cfg" 2>/dev/null || echo '')"
    [ "$mode" = "600" ]
}

@test "install.sh --dry-run does not register service" {
    require_source "$INSTALL_SH"
    run bash "$INSTALL_SH" --dry-run
    # macOS: no LaunchAgent plist for our label.
    if command -v launchctl >/dev/null 2>&1; then
        ! launchctl list 2>/dev/null | grep -qi 'even-terminal'
    fi
    # Linux: no user systemd unit active for our service.
    if command -v systemctl >/dev/null 2>&1; then
        ! systemctl --user is-active even-terminal.service >/dev/null 2>&1
    fi
}

@test "install.sh idempotent: second run without --force skips" {
    require_source "$INSTALL_SH"
    run bash "$INSTALL_SH" --dry-run
    cfg="$EVEN_TERMINAL_CONFIG_DIR/config.json"
    [ -f "$cfg" ]
    before="$(cat "$cfg")"
    run bash "$INSTALL_SH" --dry-run
    after="$(cat "$cfg")"
    [ "$before" = "$after" ]
}

@test "install.sh --port 4567 saves custom port" {
    require_source "$INSTALL_SH"
    run bash "$INSTALL_SH" --dry-run --port 4567
    cfg="$EVEN_TERMINAL_CONFIG_DIR/config.json"
    grep -q '"port"[[:space:]]*:[[:space:]]*4567' "$cfg"
}

@test "start.sh exits 1 when config not found" {
    require_source "$START_SH"
    empty="$EVEN_TERMINAL_CONFIG_DIR/empty"
    mkdir -p "$empty"
    EVEN_TERMINAL_CONFIG_DIR="$empty" run bash "$START_SH"
    [ "$status" -eq 1 ]
}

@test "start.sh skips when fake server is running" {
    require_source "$START_SH"
    if ! command -v node >/dev/null 2>&1; then
        skip "node not available"
    fi
    port=34568
    cat >"$EVEN_TERMINAL_CONFIG_DIR/config.json" <<EOF
{
  "version": 1,
  "executable": "node",
  "executable_args": [],
  "token": "test-token-aaaaaaaaaaaaaaaaaaaaaa",
  "port": $port,
  "provider": "claude",
  "network_mode": "auto",
  "config_dir": "$EVEN_TERMINAL_CONFIG_DIR"
}
EOF
    node "$FAKE_SERVER" --port "$port" >"$EVEN_TERMINAL_CONFIG_DIR/fake.log" 2>&1 &
    FAKE_PID=$!
    # Give the server a moment to bind.
    sleep 2
    run bash "$START_SH"
    [ "$status" -eq 0 ]
    [[ "$output" =~ (already|running|skip) ]]
}

@test "uninstall.sh --keep-config preserves config" {
    require_source "$UNINSTALL_SH"
    cat >"$EVEN_TERMINAL_CONFIG_DIR/config.json" <<'EOF'
{"version":1,"executable":"x","executable_args":[],"token":"t","port":3456,"provider":"claude","network_mode":"auto","config_dir":"/tmp"}
EOF
    run bash "$UNINSTALL_SH" --dry-run --keep-config
    [ -f "$EVEN_TERMINAL_CONFIG_DIR/config.json" ]
}

@test "uninstall.sh removes config and creates .bak" {
    require_source "$UNINSTALL_SH"
    cat >"$EVEN_TERMINAL_CONFIG_DIR/config.json" <<'EOF'
{"version":1,"executable":"x","executable_args":[],"token":"t","port":3456,"provider":"claude","network_mode":"auto","config_dir":"/tmp"}
EOF
    run bash "$UNINSTALL_SH" --dry-run
    [ ! -f "$EVEN_TERMINAL_CONFIG_DIR/config.json" ]
    [ -f "$EVEN_TERMINAL_CONFIG_DIR/config.json.bak" ]
}
