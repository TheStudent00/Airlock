#!/usr/bin/env bash
# Read run logs out of the sandbox.
#
# Usage:
#   ./logs.sh              list every run, newest last
#   ./logs.sh <substring>  print the newest log whose name contains it
#   ./logs.sh --daemon     the daemon's own output (what it saw and ran)
#   ./logs.sh --pull DIR   copy all logs out to DIR on the host
set -euo pipefail

case "${1:---list}" in
  --list|"")
    podman exec sandbox-runner sh -c 'ls -1 /logs 2>/dev/null' | sed 's/^/  /' \
        || echo "  no logs yet"
    ;;
  --daemon)
    podman logs sandbox-runner
    ;;
  --pull)
    DEST="${2:?usage: ./logs.sh --pull DIR}"
    mkdir -p "$DEST"
    podman cp sandbox-runner:/logs/. "$DEST"
    echo "copied to $DEST"
    ;;
  *)
    name=$(podman exec sandbox-runner sh -c "ls -1 /logs | grep -- '$1' | tail -1")
    [ -n "$name" ] || { echo "no log matching '$1'" >&2; exit 1; }
    echo "=== $name ==="
    podman exec sandbox-runner cat "/logs/$name"
    ;;
esac
