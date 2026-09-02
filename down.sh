#!/usr/bin/env bash
# Stop and remove ONE INSTANCE's containers. Images and networks are kept,
# so ./up.sh brings back a clean pair without rebuilding.
#
# Usage:  ./down.sh [--instance NAME] [--networks]
#         --networks also removes that instance's two networks
#
# Only the named instance is touched. `./down.sh` stops the default
# instance and leaves every other instance running.
set -uo pipefail
cd "$(dirname "$0")"

source ./instance.sh
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load

echo "=== airlock down ==="
airlock_instance_banner

for c in "$AL_RUNNER" "$AL_PROXY"; do
    if podman container exists "$c"; then
        podman rm -f "$c" >/dev/null && echo "  removed $c"
    fi
done

if [ "${1:-}" = "--networks" ]; then
    for n in "$AL_NET_INTERNAL" "$AL_NET_EGRESS"; do
        podman network exists "$n" && podman network rm "$n" >/dev/null \
            && echo "  removed network $n"
    done
fi
echo "done."
