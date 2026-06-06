#!/usr/bin/env bats
# Tests: scripts/lib/probe-server.sh
# Tags: probe-server, multi-ip, vpn
# bats tests for probe_server multi-IP behavior (issue #8).

# Top-level skip guard: must have an IPv4 enumeration tool available.
command -v ip >/dev/null 2>&1 || command -v ifconfig >/dev/null 2>&1 || skip "no IPv4 enumeration tool"

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    PROBE_SH="$REPO_ROOT/scripts/lib/probe-server.sh"
    FAKE_SERVER="$REPO_ROOT/tests/fixtures/fake-even-terminal.js"
    # shellcheck source=/dev/null
    source "$PROBE_SH"
}

teardown() {
    if [ -n "${FAKE_PID:-}" ]; then
        kill "$FAKE_PID" 2>/dev/null || true
        wait "$FAKE_PID" 2>/dev/null || true
        FAKE_PID=""
    fi
}

# Discover a non-loopback, non-APIPA IPv4 address. Echo it on stdout if found.
find_non_loopback_ipv4() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip="$(ip -4 -o addr show 2>/dev/null \
              | awk '{print $4}' \
              | cut -d/ -f1 \
              | grep -v '^127\.' \
              | grep -v '^169\.254\.' \
              | head -n1)"
    elif command -v ifconfig >/dev/null 2>&1; then
        ip="$(ifconfig 2>/dev/null \
              | awk '/inet / {print $2}' \
              | sed 's/^addr://' \
              | grep -v '^127\.' \
              | grep -v '^169\.254\.' \
              | head -n1)"
    fi
    printf '%s' "$ip"
}

@test "probe_server returns 1 when nothing is listening" {
    # Pick a port in the reserved test range unlikely to be in use.
    port=34571
    run probe_server "$port"
    [ "$status" -eq 1 ]
}

@test "probe_server returns 0 when fake server binds to non-loopback IPv4" {
    if ! command -v node >/dev/null 2>&1; then
        skip "node not available"
    fi
    ip="$(find_non_loopback_ipv4)"
    if [ -z "$ip" ]; then
        skip "no non-loopback IPv4 address available"
    fi
    port=34573
    node "$FAKE_SERVER" --port "$port" --bind "$ip" >/tmp/fake-even-$$.log 2>&1 &
    FAKE_PID=$!
    sleep 2
    run probe_server "$port"
    [ "$status" -eq 0 ]
}
