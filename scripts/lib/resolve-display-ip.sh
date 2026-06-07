# Resolve the IP to display in the Connect URL.
#
# Input ($1): bound_ip from probe_server (raw LISTEN-state LocalAddress).
# Stdout:
#   - bound_ip as-is when it is a specific routable IP.
#   - Primary default-route NIC IPv4 when bound_ip is wildcard / loopback / empty.
#   - Empty when no primary NIC IPv4 can be resolved.
# Exit code: always 0 (callers detect failure via empty stdout).
#
# Why two-stage: see resolve-display-ip.ps1 header.
resolve_display_ip() {
    local bound_ip="${1:-}"

    case "$bound_ip" in
        ''|0.0.0.0|::|127.0.0.1|::1) ;;
        *) printf '%s\n' "$bound_ip"; return 0 ;;
    esac

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
    [ -n "$ip" ] && printf '%s\n' "$ip"
    return 0
}

build_connect_url() {
    local bound_ip="$1" port="$2" token="$3"
    local ip
    ip=$(resolve_display_ip "$bound_ip")
    [ -n "$ip" ] || ip="<your-ip>"
    printf 'http://%s:%s?token=%s\n' "$ip" "$port" "$token"
}
