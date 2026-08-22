#!/usr/bin/env bash
# Stop and remove both containers. Images and networks are kept, so
# ./up.sh brings back a clean pair without rebuilding.
#
# Usage:  ./down.sh [--networks]   (--networks also removes the networks)
set -uo pipefail
cd "$(dirname "$0")"

for c in sandbox-runner sandbox-proxy; do
    if podman container exists "$c"; then
        podman rm -f "$c" >/dev/null && echo "  removed $c"
    fi
done

if [ "${1:-}" = "--networks" ]; then
    for n in sandbox-internal sandbox-egress; do
        podman network exists "$n" && podman network rm "$n" >/dev/null \
            && echo "  removed network $n"
    done
fi
echo "done."
