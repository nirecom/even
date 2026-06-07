probe_server() {
    local port="$1"
    case "$port" in ''|*[!0-9]*) return 1 ;; esac
    local bound_ip=""

    if command -v ss >/dev/null 2>&1; then
        bound_ip=$(ss -4tln 2>/dev/null \
            | awk -v p=":$port" '$4 ~ p"$" { sub(/:[^:]*$/, "", $4); print $4; exit }')
    elif command -v netstat >/dev/null 2>&1; then
        bound_ip=$(netstat -an 2>/dev/null \
            | awk -v p="$port" '
                /LISTEN/ && ($4 ~ ":"p"$" || $4 ~ "\."p"$") {
                    addr = $4
                    sub(/[:.][0-9]+$/, "", addr)
                    if (addr == "*") addr = "0.0.0.0"
                    print addr; exit
                }')
    else
        _probe_server_legacy "$port"
        return
    fi

    [ -n "$bound_ip" ] || return 1

    local http_ip
    case "$bound_ip" in
        0.0.0.0|"*"|"") http_ip="127.0.0.1" ;;
        *)               http_ip="$bound_ip" ;;
    esac

    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
        "http://$http_ip:$port/" 2>/dev/null || echo 000)
    case "$code" in
        200|401|404) printf '%s\n' "$bound_ip"; return 0 ;;
    esac

    printf '%s\n' "$bound_ip"
    return 0
}

# legacy path: no LISTEN-state IP available; callers receive empty stdout
_probe_server_legacy() {
    local port="$1"
    case "$port" in ''|*[!0-9]*) return 1 ;; esac
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 1 127.0.0.1 "$port" 2>/dev/null || return 1
    else
        timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null || return 1
    fi
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
        "http://127.0.0.1:$port/" 2>/dev/null || echo 000)
    case "$code" in
        200|401|404) return 0 ;;
    esac
    return 1
}
