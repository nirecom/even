#!/usr/bin/env bash
# list_connect_urls PORT TOKEN
# Prints one line per active network endpoint:
#   <label> <ip> <url>
# Order: primary NIC (default-route interface) first, then all other
# Up interfaces with a non-loopback / non-APIPA IPv4 address.
# VPN-agnostic: any VPN adapter (WireGuard, OpenVPN, Tailscale, etc.)
# is included automatically via the OS interface list.
list_connect_urls() {
    local port="$1" token="$2"
    local primary_ip="" primary_iface=""

    # --- Primary NIC (default route) ---
    if [ "$(uname)" = "Darwin" ]; then
        primary_iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
        [ -n "$primary_iface" ] && primary_ip=$(ipconfig getifaddr "$primary_iface" 2>/dev/null || true)
    else
        # Linux: use `ip route get` for the src address and dev
        local route_out
        route_out=$(ip -4 -o route get 1.1.1.1 2>/dev/null)
        primary_ip=$(echo "$route_out" | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
        primary_iface=$(echo "$route_out" | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
        # Fallback: parse default route
        if [ -z "$primary_ip" ]; then
            primary_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
            [ -n "$primary_iface" ] && \
                primary_ip=$(ip -4 -o addr show dev "$primary_iface" 2>/dev/null \
                             | awk '{print $4; exit}' | cut -d/ -f1)
        fi
    fi

    if [ -n "$primary_ip" ]; then
        local label="${primary_iface:-LAN}"
        printf '%s %s http://%s:%s?token=%s\n' "$label" "$primary_ip" "$primary_ip" "$port" "$token"
    fi

    # --- Additional interfaces (VPNs, extra NICs) ---
    # Enumerate all Up interfaces with a routable IPv4, excluding primary
    if [ "$(uname)" = "Darwin" ]; then
        ifconfig 2>/dev/null | awk -v pif="$primary_iface" -v pip="$primary_ip" '
            /^[a-z]/ { iface = substr($1, 1, length($1)-1) }
            /inet / {
                ip = $2
                if (ip ~ /^127\./ || ip ~ /^169\.254\./) next
                if (iface == pif || ip == pip) next
                print iface, ip
            }
        ' | while IFS=' ' read -r iface ip; do
            printf '%s %s http://%s:%s?token=%s\n' "$iface" "$ip" "$ip" "$port" "$token"
        done
    else
        ip -4 -o addr show 2>/dev/null | awk -v pif="$primary_iface" -v pip="$primary_ip" '
            {
                split($4, a, "/"); ip = a[1]; iface = $2
                if (ip ~ /^127\./ || ip ~ /^169\.254\./) next
                if (iface == pif || ip == pip) next
                print iface, ip
            }
        ' | while IFS=' ' read -r iface ip; do
            printf '%s %s http://%s:%s?token=%s\n' "$iface" "$ip" "$ip" "$port" "$token"
        done
    fi
}
