# Read a single field from config.json.
# Prefers jq; falls back to python3.
# Usage: read_config <path> <field>
read_config() {
    local path="$1" field="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -r ".${field} // empty" "$path"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get(sys.argv[2])
print('' if v is None else v)
" "$path" "$field"
    else
        echo "ERROR: neither jq nor python3 found. Install one to continue." >&2
        return 1
    fi
}
