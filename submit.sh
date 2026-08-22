#!/usr/bin/env bash
# Hand a bash script to the running sandbox.
#
# HOW THE HANDOFF AVOIDS RUNNING A HALF-WRITTEN FILE
#   1. copy the file in under a HIDDEN name  (/drop/.name.sh)
#   2. rename it in place to the visible name (/drop/name.sh)
# The daemon ignores anything starting with "." and reacts to the rename.
# Rename within one directory is atomic, so /drop/name.sh never exists in
# a partial state.
#
# Usage:  ./submit.sh path/to/script.sh [--follow]
set -euo pipefail
cd "$(dirname "$0")"

SCRIPT="${1:?usage: ./submit.sh path/to/script.sh [--follow]}"
[ -f "$SCRIPT" ] || { echo "no such file: $SCRIPT" >&2; exit 1; }
podman container exists sandbox-runner || { echo "sandbox-runner not running; ./up.sh first" >&2; exit 1; }

BASE="$(basename "$SCRIPT")"
[[ "$BASE" == *.sh ]] || { echo "the daemon only runs *.sh files" >&2; exit 1; }

podman cp "$SCRIPT" "sandbox-runner:/drop/.$BASE"
podman exec sandbox-runner mv "/drop/.$BASE" "/drop/$BASE"
echo "submitted $BASE"

if [ "${2:-}" = "--follow" ]; then
    echo "--- daemon output (ctrl-c to stop following) ---"
    podman logs -f --since 5s sandbox-runner
fi
