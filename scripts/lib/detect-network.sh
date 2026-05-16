# Returns space-separated pair: "<mode> <arg>"
# mode: tailscale | interface | loopback
# arg:  "" (tailscale/loopback) | "<NIC name>" (interface)
detect_network() {
    local mode="${1:-auto}"

    if [ "$mode" = "auto" ] || [ "$mode" = "tailscale" ]; then
        if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
            echo "tailscale "
            return 0
        fi
        if [ "$mode" = "tailscale" ]; then
            echo "ERROR: tailscale mode but no Tailscale found" >&2
            return 1
        fi
    fi

    [ "$mode" = "loopback" ] && { echo "loopback "; return 0; }

    local iface=""
    if [ "$(uname)" = "Darwin" ]; then
        iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
    else
        iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    fi
    [ -n "$iface" ] || { echo "ERROR: could not determine primary NIC" >&2; return 1; }
    echo "interface $iface"
}
