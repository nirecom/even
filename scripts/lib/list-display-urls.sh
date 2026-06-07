#!/usr/bin/env bash
# list_connect_urls PORT TOKEN
# Prints one URL per line for every active network endpoint:
#   <label> <ip> <url>
# Order: primary LAN first, then VPN (Tailscale on POSIX; NordLynx is Windows-only).
list_connect_urls() {
    local port="$1" token="$2"

    # --- Primary LAN NIC ---
    local lan_ip=""
    if [ "$(uname)" = "Darwin" ]; then
        local iface
        iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
        [ -n "$iface" ] && lan_ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    else
        lan_ip=$(ip -4 -o route get 1.1.1.1 2>/dev/null \
                 | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
        if [ -z "$lan_ip" ]; then
            local iface
            iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
            [ -n "$iface" ] && lan_ip=$(ip -4 -o addr show dev "$iface" 2>/dev/null \
                                        | awk '{print $4; exit}' | cut -d/ -f1)
        fi
    fi
    if [ -n "$lan_ip" ]; then
        printf 'LAN %s http://%s:%s?token=%s\n' "$lan_ip" "$lan_ip" "$port" "$token"
    fi

    # --- Tailscale (POSIX) ---
    if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
        local ts_ip
        ts_ip=$(tailscale ip -4 2>/dev/null || true)
        if [ -n "$ts_ip" ]; then
            printf 'Tailscale %s http://%s:%s?token=%s\n' "$ts_ip" "$ts_ip" "$port" "$token"
        fi
    fi
}
