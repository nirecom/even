#!/usr/bin/env bats
# Tests: scripts/lib/list-display-urls.sh, install.sh
# Tags: dual-url, nordlynx, meshnet, connect-url, e2e
# POSIX-side E2E tests for the dual-URL requirement:
#   - list_connect_urls returns LAN URL with correct format
#   - list_connect_urls includes Tailscale URL when tailscale is active
#   - No placeholder text (<your-ip>) in output when a NIC is available

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    LIST_SH="$REPO_ROOT/scripts/lib/list-display-urls.sh"
    # shellcheck source=/dev/null
    source "$LIST_SH"

    # Scratch dir for fake binaries used to mock network commands
    FAKE_BIN="$(mktemp -d)"
}

teardown() {
    rm -rf "${FAKE_BIN:-}"
}

# Inject FAKE_BIN at front of PATH so stub binaries shadow real ones
_with_fake_path() {
    PATH="$FAKE_BIN:$PATH" "$@"
}

# Helper: resolve the primary LAN IP the same way the production code does,
# so tests that depend on the real machine's state stay in sync.
_real_lan_ip() {
    local ip=""
    if [ "$(uname)" = "Darwin" ]; then
        local iface
        iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
        [ -n "$iface" ] && ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    else
        ip=$(ip -4 -o route get 1.1.1.1 2>/dev/null \
             | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
        if [ -z "$ip" ]; then
            local iface
            iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
            [ -n "$iface" ] && ip=$(ip -4 -o addr show dev "$iface" 2>/dev/null \
                                    | awk '{print $4; exit}' | cut -d/ -f1)
        fi
    fi
    printf '%s' "$ip"
}

# ---------------------------------------------------------------------------
# URL format tests (real machine — skip when no primary NIC available)
# ---------------------------------------------------------------------------

@test "list_connect_urls emits at least one URL when a primary NIC exists" {
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"
    run list_connect_urls 3456 'tok'
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 1 ]
}

@test "list_connect_urls URL format is http://<ip>:<port>?token=<token>" {
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"
    run list_connect_urls 3456 'mytoken'
    [ "$status" -eq 0 ]
    first_url=$(echo "$output" | awk '{print $3}' | head -n1)
    [[ "$first_url" =~ ^http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:3456\?token=mytoken$ ]]
}

@test "REGRESSION: list_connect_urls never emits placeholder text when a NIC exists" {
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"
    run list_connect_urls 3456 'tok'
    [ "$status" -eq 0 ]
    [[ "$output" != *"<your-ip>"* ]]
    [[ "$output" != *"your-ip"* ]]
}

@test "list_connect_urls first entry IP matches the primary NIC IP" {
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"
    run list_connect_urls 3456 'tok'
    [ "$status" -eq 0 ]
    first_ip=$(echo "$output" | awk '{print $2}' | head -n1)
    [ "$first_ip" = "$lan_ip" ]
}

@test "list_connect_urls each output line has exactly three fields: label ip url" {
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"
    run list_connect_urls 3456 'tok'
    [ "$status" -eq 0 ]
    while IFS= read -r line; do
        field_count=$(echo "$line" | awk '{print NF}')
        [ "$field_count" -eq 3 ]
    done <<< "$output"
}

# ---------------------------------------------------------------------------
# Tailscale stub tests (mock tailscale binary via FAKE_BIN)
# ---------------------------------------------------------------------------

@test "list_connect_urls includes Tailscale URL when tailscale is active (stubbed)" {
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"

    # Stub: tailscale status exits 0 (connected), tailscale ip -4 returns 100.88.1.5
    cat > "$FAKE_BIN/tailscale" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    status) exit 0 ;;
    ip)     echo "100.88.1.5" ;;
    *)      exit 1 ;;
esac
EOF
    chmod +x "$FAKE_BIN/tailscale"

    run _with_fake_path bash -c "
        source '$REPO_ROOT/scripts/lib/list-display-urls.sh'
        list_connect_urls 3456 'tok'
    "
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 2 ]
    ts_line=$(echo "$output" | grep '^Tailscale')
    [ -n "$ts_line" ]
    ts_ip=$(echo "$ts_line" | awk '{print $2}')
    [ "$ts_ip" = "100.88.1.5" ]
    ts_url=$(echo "$ts_line" | awk '{print $3}')
    [ "$ts_url" = "http://100.88.1.5:3456?token=tok" ]
}

@test "list_connect_urls excludes Tailscale when tailscale status returns non-zero (stubbed)" {
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"

    # Stub: tailscale status exits 1 (disconnected)
    cat > "$FAKE_BIN/tailscale" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$FAKE_BIN/tailscale"

    run _with_fake_path bash -c "
        source '$REPO_ROOT/scripts/lib/list-display-urls.sh'
        list_connect_urls 3456 'tok'
    "
    [ "$status" -eq 0 ]
    ts_line=$(echo "$output" | grep '^Tailscale' || true)
    [ -z "$ts_line" ]
}

@test "list_connect_urls LAN URL is listed before Tailscale URL (order)" {
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"

    cat > "$FAKE_BIN/tailscale" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    status) exit 0 ;;
    ip)     echo "100.88.1.5" ;;
    *)      exit 1 ;;
esac
EOF
    chmod +x "$FAKE_BIN/tailscale"

    run _with_fake_path bash -c "
        source '$REPO_ROOT/scripts/lib/list-display-urls.sh'
        list_connect_urls 3456 'tok'
    "
    [ "$status" -eq 0 ]
    first_label=$(echo "$output" | head -n1 | awk '{print $1}')
    [ "$first_label" = "LAN" ]
    last_label=$(echo "$output" | tail -n1 | awk '{print $1}')
    [ "$last_label" = "Tailscale" ]
}

# ---------------------------------------------------------------------------
# Real-machine E2E: Tailscale (skip when not active)
# ---------------------------------------------------------------------------

@test "REGRESSION: includes a Tailscale URL (100.x) when tailscale is Up on real machine" {
    command -v tailscale >/dev/null 2>&1 || skip "tailscale binary not available"
    tailscale status >/dev/null 2>&1 || skip "tailscale is not connected on this host"
    ts_ip_real=$(tailscale ip -4 2>/dev/null || true)
    [ -n "$ts_ip_real" ] || skip "tailscale IP not available"

    run list_connect_urls 3456 'tok'
    [ "$status" -eq 0 ]
    ts_line=$(echo "$output" | grep '^Tailscale' || true)
    [ -n "$ts_line" ]
    ts_ip=$(echo "$ts_line" | awk '{print $2}')
    [[ "$ts_ip" =~ ^100\. ]]
    ts_url=$(echo "$ts_line" | awk '{print $3}')
    [[ "$ts_url" =~ ^http://100\.[0-9]+\.[0-9]+\.[0-9]+:3456\?token=tok$ ]]
}

@test "Tailscale URL and LAN URL are different addresses on real machine" {
    command -v tailscale >/dev/null 2>&1 || skip "tailscale binary not available"
    tailscale status >/dev/null 2>&1 || skip "tailscale is not connected on this host"
    ts_ip_real=$(tailscale ip -4 2>/dev/null || true)
    [ -n "$ts_ip_real" ] || skip "tailscale IP not available"
    lan_ip="$(_real_lan_ip)"
    [ -n "$lan_ip" ] || skip "no primary NIC IPv4 available"

    run list_connect_urls 3456 'tok'
    [ "$status" -eq 0 ]
    ip_count=$(echo "$output" | awk '{print $2}' | sort -u | wc -l | tr -d ' ')
    line_count="${#lines[@]}"
    [ "$ip_count" -eq "$line_count" ]
}
