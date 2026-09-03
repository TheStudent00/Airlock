#!/usr/bin/env bash
# Stop and remove ONE INSTANCE's containers. Images and networks are kept,
# so ./up.sh brings back a clean pair without rebuilding.
#
# Usage:  ./down.sh [--instance NAME] [--networks] [--force]
#         --networks also removes that instance's two networks
#         --force    take the instance down even while a lane is running
#
# Only the named instance is touched. `./down.sh` stops the default
# instance and leaves every other instance running.
#
# IT REFUSES WHILE A LANE IS RUNNING (added 2026-09-02, ruled)
#   Before removing anything, this reads the instance's own status folder —
#   <agent>/status/<lane>.status, the file the daemon writes — and looks for
#   `state=running`. If it finds one it names the lane and exits 1 without
#   touching a container.
#
#   The event that motivates it: on 2026-09-02 one agent took a shared
#   instance down at the end of its own work while a second agent's lane was
#   23 seconds into a run. The lane stopped mid-flight, its status file was
#   left saying `running`, and the second agent saw no error anywhere — the
#   run had simply stopped. Neither agent could see the other's queue.
#
#   The refusal is per instance, which is also the answer to the general
#   case: one instance per task, so a `down` only ever asks about lanes that
#   belong to the task issuing it.
#
#   `--force` is the deliberate override, and is also the way past a status
#   file left saying `running` by a run that was already stopped (a stale
#   record blocks nothing else, but this check cannot tell it from a live
#   run — the container is being removed either way).
set -uo pipefail
cd "$(dirname "$0")"

source ./instance.sh
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load

WANT_NETWORKS=0
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --networks) WANT_NETWORKS=1; shift ;;
        --force)    FORCE=1; shift ;;
        *)
            echo "unknown argument: $1" >&2
            echo "usage: ./down.sh [--instance NAME] [--networks] [--force]" >&2
            exit 2
            ;;
    esac
done

echo "=== airlock down ==="
airlock_instance_banner

# ---- refuse while a lane of THIS instance is running ----------------------
# The daemon writes `state=running` when a lane starts and rewrites the same
# file with `state=done` when it ends, so one grep over the folder answers
# "is this instance busy" without asking podman anything.
RUNNING_LANES=()
STATUS_DIR="$AL_AGENT_DIR/status"
if [ -d "$STATUS_DIR" ]; then
    for f in "$STATUS_DIR"/*.status; do
        [ -e "$f" ] || continue
        if grep -qx 'state=running' "$f"; then
            base="$(basename "$f")"
            RUNNING_LANES+=("${base%.status}")
        fi
    done
fi

if [ ${#RUNNING_LANES[@]} -gt 0 ] && [ "$FORCE" -eq 0 ]; then
    echo "  REFUSING to take '$AL_INSTANCE' down: a lane is running." >&2
    for lane in "${RUNNING_LANES[@]}"; do
        echo "    running lane:  $lane" >&2
        echo "      status file: $STATUS_DIR/$lane.status" >&2
    done
    echo "    Removing the runner now stops that lane mid-flight, and the" >&2
    echo "    submitter sees no error — only a run that stopped." >&2
    echo "    Wait for it, or override deliberately:" >&2
    echo "      bash $0 --instance $AL_INSTANCE --force" >&2
    exit 1
fi

if [ ${#RUNNING_LANES[@]} -gt 0 ]; then
    echo "  --force: taking it down with ${#RUNNING_LANES[@]} lane(s) recorded running:"
    printf '    %s\n' "${RUNNING_LANES[@]}"
fi

for c in "$AL_RUNNER" "$AL_PROXY"; do
    if podman container exists "$c"; then
        podman rm -f "$c" >/dev/null && echo "  removed $c"
    fi
done

if [ "$WANT_NETWORKS" -eq 1 ]; then
    for n in "$AL_NET_INTERNAL" "$AL_NET_EGRESS"; do
        podman network exists "$n" && podman network rm "$n" >/dev/null \
            && echo "  removed network $n"
    done
fi
echo "done."
