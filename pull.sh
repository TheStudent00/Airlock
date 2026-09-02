#!/usr/bin/env bash
# Copy whatever the sandbox produced back to the host.
#
#   /out   is the agreed drop-off point: a script that wants to hand
#          something back writes it there.
#   /logs  is every run's captured output.
#
# Usage:
#   ./pull.sh [--instance NAME] <dest-dir>            everything in /out
#   ./pull.sh <dest-dir> --logs     /out and /logs
set -euo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"

DEST="${1:?usage: ./pull.sh <dest-dir> [--logs]}"
podman container exists "$AL_RUNNER" || { echo "$AL_RUNNER not running" >&2; exit 1; }

mkdir -p "$DEST/out"
if podman exec "$AL_RUNNER" sh -c '[ -n "$(ls -A /out 2>/dev/null)" ]'; then
    podman cp "$AL_RUNNER:/out/." "$DEST/out"
    echo "  /out  -> $DEST/out"
else
    echo "  /out is empty (nothing was written there)"
fi

if [ "${2:-}" = "--logs" ]; then
    mkdir -p "$DEST/logs"
    podman cp "$AL_RUNNER:/logs/." "$DEST/logs"
    echo "  /logs -> $DEST/logs"
fi

find "$DEST" -type f | head -20 | sed 's/^/    /'
