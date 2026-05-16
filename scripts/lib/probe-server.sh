probe_server() {
    local port="$1"
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
        *) return 1 ;;
    esac
}
