#!/usr/bin/env bats
# Tests: scripts/lib/resolve-display-ip.sh, install.sh
# Tags: display-ip, connect-url, wildcard-bind, e2e

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    RESOLVE_SH="$REPO_ROOT/scripts/lib/resolve-display-ip.sh"
    PROBE_SH="$REPO_ROOT/scripts/lib/probe-server.sh"
    # shellcheck source=/dev/null
    source "$RESOLVE_SH"
    # shellcheck source=/dev/null
    source "$PROBE_SH"
}

teardown() {
    if [ -n "${TCP_PID:-}" ]; then
        kill "$TCP_PID" 2>/dev/null || true
        wait "$TCP_PID" 2>/dev/null || true
        TCP_PID=""
    fi
}

find_primary_ipv4() {
    local ip=""
    if [ "$(uname)" = "Darwin" ]; then
        local iface
        iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
        [ -n "$iface" ] && ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    else
        ip=$(ip -4 -o route get 1.1.1.1 2>/dev/null \
             | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
    fi
    printf '%s' "$ip"
}

@test "resolve_display_ip passes through a specific non-loopback IPv4" {
    run resolve_display_ip '192.168.5.7'
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.5.7" ]
}

@test "resolve_display_ip passes through a Tailscale IPv4" {
    run resolve_display_ip '100.105.169.197'
    [ "$status" -eq 0 ]
    [ "$output" = "100.105.169.197" ]
}

@test "resolve_display_ip falls back to primary NIC IPv4 when BoundIP=0.0.0.0" {
    primary="$(find_primary_ipv4)"
    [ -n "$primary" ] || skip "no primary NIC IPv4 available"
    run resolve_display_ip '0.0.0.0'
    [ "$status" -eq 0 ]
    [ "$output" = "$primary" ]
}

@test "resolve_display_ip falls back to primary NIC IPv4 when BoundIP=127.0.0.1" {
    primary="$(find_primary_ipv4)"
    [ -n "$primary" ] || skip "no primary NIC IPv4 available"
    run resolve_display_ip '127.0.0.1'
    [ "$status" -eq 0 ]
    [ "$output" = "$primary" ]
}

@test "resolve_display_ip falls back to primary NIC IPv4 when BoundIP is empty" {
    primary="$(find_primary_ipv4)"
    [ -n "$primary" ] || skip "no primary NIC IPv4 available"
    run resolve_display_ip ''
    [ "$status" -eq 0 ]
    [ "$output" = "$primary" ]
}

@test "build_connect_url embeds a specific BoundIP verbatim" {
    run build_connect_url '192.168.5.7' 3456 'tok123'
    [ "$status" -eq 0 ]
    [ "$output" = "http://192.168.5.7:3456?token=tok123" ]
}

@test "REGRESSION: build_connect_url never emits <your-ip> when primary NIC exists" {
    primary="$(find_primary_ipv4)"
    [ -n "$primary" ] || skip "no primary NIC IPv4 available"
    run build_connect_url '0.0.0.0' 3456 'tok123'
    [ "$status" -eq 0 ]
    [[ "$output" != *"<your-ip>"* ]]
    [[ "$output" =~ ^http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:3456\?token=tok123$ ]]
}

@test "REGRESSION (E2E): wildcard TCP listener -> build_connect_url returns real IPv4" {
    primary="$(find_primary_ipv4)"
    [ -n "$primary" ] || skip "no primary NIC IPv4 available"
    command -v nc >/dev/null 2>&1 || skip "nc not available"
    if command -v ss >/dev/null 2>&1; then :; elif command -v netstat >/dev/null 2>&1; then :; else
        skip "no ss or netstat available"
    fi
    port=34591
    nc -l "$port" >/dev/null 2>&1 &
    TCP_PID=$!
    sleep 1
    bound_ip=$(probe_server "$port") || skip "probe_server failed"
    [ -n "$bound_ip" ] || skip "probe returned empty BoundIP"
    url=$(build_connect_url "$bound_ip" "$port" 'e2etok')
    [[ "$url" != *"<your-ip>"* ]]
    [[ "$url" =~ ^http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:${port}\?token=e2etok$ ]]
}
