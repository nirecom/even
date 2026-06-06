probe_server() {
    local port="$1"

    local candidates="127.0.0.1"
    local extra=""
    if command -v ip >/dev/null 2>&1; then
        extra=$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 |
                awk '!/^127\./ && !/^169\.254\./')
    elif command -v ifconfig >/dev/null 2>&1; then
        extra=$(ifconfig -a 2>/dev/null | awk '/inet / && $2 !~ /^127\./ && $2 !~ /^169\.254\./ {print $2}')
    fi
    # Dedup: guards against future filter changes that could allow duplicates
    for ip in $extra; do
        case " $candidates " in
            *" $ip "*) ;;
            *) candidates="$candidates $ip" ;;
        esac
    done

    for ip in $candidates; do
        if command -v nc >/dev/null 2>&1; then
            nc -z -w 1 "$ip" "$port" 2>/dev/null || continue
        else
            timeout 1 bash -c "exec 3<>/dev/tcp/$ip/$port" 2>/dev/null || continue
        fi
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
               "http://$ip:$port/" 2>/dev/null || echo 000)
        case "$code" in
            200|401|404) return 0 ;;
        esac
    done
    return 1
}
