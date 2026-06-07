#!/usr/bin/env bats
# Tests: scripts/lib/probe-server.sh
# Tags: probe-server, listen-state, vpn
# bats tests for probe_server LISTEN-state detection (issue #10).

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    PROBE_SH="$REPO_ROOT/scripts/lib/probe-server.sh"
    FAKE_SERVER="$REPO_ROOT/tests/fixtures/fake-even-terminal.js"
    # shellcheck source=/dev/null
    source "$PROBE_SH"

    if command -v ss >/dev/null 2>&1; then
        LISTEN_TOOL="ss"
    elif command -v netstat >/dev/null 2>&1; then
        LISTEN_TOOL="netstat"
    else
        LISTEN_TOOL=""
    fi
}

teardown() {
    if [ -n "${FAKE_PID:-}" ]; then
        kill "$FAKE_PID" 2>/dev/null || true
        wait "$FAKE_PID" 2>/dev/null || true
        FAKE_PID=""
    fi
    if [ -n "${TCP_PID:-}" ]; then
        kill "$TCP_PID" 2>/dev/null || true
        wait "$TCP_PID" 2>/dev/null || true
        TCP_PID=""
    fi
}

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

@test "probe_server returns 1 and no stdout when nothing is listening" {
    [ -n "$LISTEN_TOOL" ] || skip "no ss or netstat available"
    port=34571
    run probe_server "$port"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "probe_server returns 0 and stdout=127.0.0.1 when fake server listens on loopback" {
    [ -n "$LISTEN_TOOL" ] || skip "no ss or netstat available"
    command -v node >/dev/null 2>&1 || skip "node not available"
    port=34572
    node "$FAKE_SERVER" --port "$port" --bind 127.0.0.1 >/tmp/fake-even-lb-$$.log 2>&1 &
    FAKE_PID=$!
    sleep 2
    run probe_server "$port"
    [ "$status" -eq 0 ]
    [ "$output" = "127.0.0.1" ]
}

@test "probe_server returns 0 and stdout=\$ip when fake server binds to non-loopback IPv4" {
    [ -n "$LISTEN_TOOL" ] || skip "no ss or netstat available"
    command -v node >/dev/null 2>&1 || skip "node not available"
    ip="$(find_non_loopback_ipv4)"
    [ -n "$ip" ] || skip "no non-loopback IPv4 address available"
    port=34573
    node "$FAKE_SERVER" --port "$port" --bind "$ip" >/tmp/fake-even-nlb-$$.log 2>&1 &
    FAKE_PID=$!
    sleep 2
    run probe_server "$port"
    [ "$status" -eq 0 ]
    [ "$output" = "$ip" ]
}

@test "probe_server returns 0 with non-empty stdout for raw TCP listener (LISTEN-only, no HTTP)" {
    [ -n "$LISTEN_TOOL" ] || skip "no ss or netstat available"
    command -v nc >/dev/null 2>&1 || skip "nc not available for raw TCP listener"
    port=34574
    nc -l "$port" >/dev/null 2>&1 &
    TCP_PID=$!
    sleep 1
    run probe_server "$port"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "probe_server legacy fallback returns 0 and empty stdout when netstat absent but nc available" {
    command -v ss >/dev/null 2>&1 && skip "ss present; LISTEN-state path used instead"
    command -v netstat >/dev/null 2>&1 && skip "netstat present; netstat path used instead"
    command -v nc >/dev/null 2>&1 || skip "nc not available for legacy fallback test"
    command -v node >/dev/null 2>&1 || skip "node not available"
    port=34575
    node "$FAKE_SERVER" --port "$port" --bind 127.0.0.1 >/tmp/fake-even-legacy-$$.log 2>&1 &
    FAKE_PID=$!
    sleep 2
    run probe_server "$port"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
