#!/usr/bin/env bash
# Manage the egress allowlist. The canonical copy lives on the host at
# proxy/allowlist.txt; this pushes it into the running proxy and reloads
# squid in place (no restart, no dropped connections).
#
# Usage:
#   ./allow.sh [--instance NAME] ...   which sandbox's proxy; default `sandbox`
#   ./allow.sh list
#   ./allow.sh add pypi.org files.pythonhosted.org
#   ./allow.sh remove github.com
#   ./allow.sh sync            (push the host file as-is)
#   ./allow.sh denied          (show what the proxy has REFUSED — the
#                               undeclared reaches worth looking at)
set -euo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"

# The allowlist file is the instance's own (allowlist_file in its conf);
# by default every instance shares proxy/allowlist.txt.
FILE="$AL_ALLOWLIST"

push() {
    podman container exists "$AL_PROXY" || { echo "$AL_PROXY not running" >&2; exit 1; }
    podman cp "$FILE" "$AL_PROXY:/etc/squid/allowlist.txt"
    podman exec "$AL_PROXY" squid -k reconfigure -f /etc/squid/squid.conf
    echo "  allowlist pushed and squid reloaded"
}

case "${1:-list}" in
  list)
    grep -v '^\s*#' "$FILE" | grep -v '^\s*$' | sed 's/^/  /'
    ;;
  add)
    shift; [ $# -gt 0 ] || { echo "give at least one hostname" >&2; exit 1; }
    for d in "$@"; do
        # store with a leading dot so subdomains match too
        entry=".${d#.}"
        if grep -qxF "$entry" "$FILE"; then
            echo "  already present: $entry"
        else
            printf '%s\n' "$entry" >> "$FILE"
            echo "  added: $entry"
        fi
    done
    push
    ;;
  remove)
    shift; [ $# -gt 0 ] || { echo "give at least one hostname" >&2; exit 1; }
    for d in "$@"; do
        entry=".${d#.}"
        if grep -qxF "$entry" "$FILE"; then
            grep -vxF "$entry" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
            echo "  removed: $entry"
        else
            echo "  not present: $entry"
        fi
    done
    push
    ;;
  sync)
    push
    ;;
  denied)
    podman logs "$AL_PROXY" 2>&1 | grep -E 'TCP_DENIED|DENIED' | tail -40 \
        || echo "  no refusals logged"
    ;;
  *)
    sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
