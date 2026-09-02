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
# Usage:  ./submit.sh [--instance NAME] path/to/script.sh [--follow]
#
# --instance names which running sandbox to hand it to; the default
# instance is `sandbox`. See ./instance.sh.
set -euo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"


SCRIPT="${1:?usage: ./submit.sh path/to/script.sh [--follow]}"
[ -f "$SCRIPT" ] || { echo "no such file: $SCRIPT" >&2; exit 1; }
podman container exists "$AL_RUNNER" || { echo "$AL_RUNNER not running; ./up.sh --instance $AL_INSTANCE first" >&2; exit 1; }

BASE="$(basename "$SCRIPT")"
[[ "$BASE" == *.sh ]] || { echo "the daemon only runs *.sh files" >&2; exit 1; }

podman cp "$SCRIPT" "$AL_RUNNER:/drop/.$BASE"
podman exec "$AL_RUNNER" mv "/drop/.$BASE" "/drop/$BASE"
echo "submitted $BASE to $AL_RUNNER"

if [ "${2:-}" = "--follow" ]; then
    echo "--- daemon output (ctrl-c to stop following) ---"
    podman logs -f --since 5s "$AL_RUNNER"
fi
