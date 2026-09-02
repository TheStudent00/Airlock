#!/usr/bin/env bash
# Read run logs out of the sandbox.
#
# Usage:
#   ./logs.sh [--instance NAME] ...   which sandbox to read; default `sandbox`
#   ./logs.sh              list every run, newest last
#   ./logs.sh <substring>  print the newest log whose name contains it
#   ./logs.sh --daemon     the daemon's own output (what it saw and ran)
#   ./logs.sh --pull DIR   copy all logs out to DIR on the host
set -euo pipefail

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"


case "${1:---list}" in
  --list|"")
    podman exec "$AL_RUNNER" sh -c 'ls -1 /logs 2>/dev/null' | sed 's/^/  /' \
        || echo "  no logs yet"
    ;;
  --daemon)
    podman logs "$AL_RUNNER"
    ;;
  --pull)
    DEST="${2:?usage: ./logs.sh --pull DIR}"
    mkdir -p "$DEST"
    podman cp "$AL_RUNNER:/logs/." "$DEST"
    echo "copied to $DEST"
    ;;
  *)
    name=$(podman exec "$AL_RUNNER" sh -c "ls -1 /logs | grep -- '$1' | tail -1")
    [ -n "$name" ] || { echo "no log matching '$1'" >&2; exit 1; }
    echo "=== $name ==="
    podman exec "$AL_RUNNER" cat "/logs/$name"
    ;;
esac
