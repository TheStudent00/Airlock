#!/usr/bin/env bash
# Start the sandbox: two networks, two containers.
#
# NETWORK SHAPE
#   sandbox-egress    ordinary bridge, has a route out. ONLY the proxy is on it.
#   sandbox-internal  created with --internal, which means podman installs no
#                     route out of it at all. The runner is on this one only.
#
#   So the runner's only reachable peer is sandbox-proxy:3128, and the proxy
#   refuses any hostname absent from proxy/allowlist.txt. There is no second
#   path to the internet to forget about.
#
# Usage:  ./up.sh
#
# CPU SHARE
#   sandbox-runner starts with --cpus "$AIRLOCK_CPUS", DEFAULT 6 — the
#   full share. RULED 2026-08-22: "default is full CPUs. user can
#   throttle how they see fit."
#
#   To throttle a long run so it does not hold every core hot for hours:
#
#       AIRLOCK_CPUS=3 ./up.sh
#
#   Roughly halving the cores roughly doubles a run's wall clock. This
#   is a fixed share, not a feedback loop — it does not read temperature
#   or back off dynamically. Raise or lower it by hand.
#
#   SANDBOX_CPUS is the older spelling, inherited from the SandboxDesign
#   repo Airlock derives from. It is still honoured, AFTER AIRLOCK_CPUS,
#   so a project migrating over does not have to change its environment
#   on the same day it changes the command name.
#
#   The systemd path (quadlet/sandbox-runner.container) carries the same
#   full-share default, so the two agree.
set -euo pipefail
cd "$(dirname "$0")"

AIRLOCK_CPUS="${AIRLOCK_CPUS:-${SANDBOX_CPUS:-6}}"

podman network exists sandbox-egress   || podman network create sandbox-egress
podman network exists sandbox-internal || podman network create --internal sandbox-internal

# ---- agent lane ----------------------------------------------------------
# An agent session may be able to write files on the host but not run
# podman. Binding these four directories from the host makes the hot folder
# reachable by a plain file write: the session writes agent/drop/x.sh, the
# daemon's close_write watch fires, and the session reads agent/status/x.sh.status
# and agent/out/ back. No shell on the session's side is involved.
AGENT_DIR="$PWD/agent"
mkdir -p "$AGENT_DIR"/{drop,out,logs,status}

# Configured mounts come from ./mounts.conf — one `<host>:<container>[:mode]`
# per line, default read-only. See mounts.conf.example. No project's paths are
# named in this repo: Airlock is project-agnostic, and which directories a
# machine exposes is that machine's configuration.
#
# Read-only is the default because it keeps the design's core property — a run
# cannot alter the originals — while still testing against the real tree with
# no copy step. Products go to /out and the caller places them.
#
# Never mount a home directory wholesale: one multi-gigabyte tree in it will
# exhaust a caller's file descriptors and defeat the isolation besides.
MOUNT_ARGS=()
if [ -f "$(dirname "$0")/mounts.conf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"; line="$(echo "$line" | xargs)"
        [ -z "$line" ] && continue
        host="${line%%:*}"; rest="${line#*:}"
        cpath="${rest%%:*}"; mode="ro"
        case "$rest" in *:*) mode="${rest##*:}";; esac
        [ "$mode" = "rw" ] || mode="ro"
        expanded="${host/#\~/$HOME}"
        if [ ! -e "$expanded" ]; then
            echo "  MOUNT ERROR: no such path: $expanded (mounts.conf)" >&2
            exit 1
        fi
        MOUNT_ARGS+=(-v "$expanded:$cpath:$mode")
    done < "$(dirname "$0")/mounts.conf"
fi

# ---- proxy ---------------------------------------------------------------
if podman container exists sandbox-proxy; then
    podman start sandbox-proxy >/dev/null
    echo "  sandbox-proxy already existed; started"
else
    podman run -d --name sandbox-proxy \
        --network sandbox-egress \
        --memory 512m --cpus 1 --pids-limit 256 \
        --cap-drop=ALL --cap-add=SETUID --cap-add=SETGID \
        --security-opt no-new-privileges \
        sandbox-proxy:latest
    podman network connect sandbox-internal sandbox-proxy
    echo "  sandbox-proxy started (on both networks)"
fi

# ---- runner --------------------------------------------------------------
if podman container exists sandbox-runner; then
    podman start sandbox-runner >/dev/null
    echo "  sandbox-runner already existed; started"
else
    # Host binds for the agent lane; named volume only for /persist, which is
    # the one place state is MEANT to survive between runs.
    #
    # /work is a size-capped tmpfs. A run that tries to write more scratch than
    # the cap fails loudly inside the container with ENOSPC, instead of filling
    # the host disk — which is exactly how a generated-file extraction wedged a
    # session on 2026-07-30. Raising the cap is a deliberate act, not a default.
    #
    # --cpus "$AIRLOCK_CPUS": DEFAULT 6 (full share), see the CPU SHARE
    # note at the top of this file. AIRLOCK_CPUS=3 throttles a long run.
    podman run -d --name sandbox-runner \
        --network sandbox-internal \
        -v "$AGENT_DIR/drop":/drop \
        -v "$AGENT_DIR/out":/out \
        -v "$AGENT_DIR/logs":/logs \
        -v "$AGENT_DIR/status":/status \
        "${MOUNT_ARGS[@]}" \
        -v sandbox-persist:/persist \
        --memory 12g --cpus "$AIRLOCK_CPUS" --pids-limit 2048 \
        --cap-drop=ALL \
        --security-opt no-new-privileges \
        --tmpfs /tmp:rw,nosuid,nodev,size=2g \
        --tmpfs /work:rw,nosuid,nodev,size=4g \
        sandbox-runner:latest
    echo "  sandbox-runner started"
    echo "    cpus:     $AIRLOCK_CPUS (AIRLOCK_CPUS=3 to throttle a long run)"
    echo "    drop:     $AGENT_DIR/drop      (write x.sh here to run it)"
    echo "    status:   $AGENT_DIR/status    (x.sh.status — poll this)"
    echo "    out/logs: $AGENT_DIR/{out,logs}"
    if [ ${#MOUNT_ARGS[@]} -eq 0 ]; then
        echo "    mounts:   none (no mounts.conf — see mounts.conf.example)"
    else
        echo "    mounts:   from mounts.conf —"
        printf '      %s\n' "${MOUNT_ARGS[@]}" | grep -v '^\s*-v$'
    fi
fi

# ---- wait until the proxy can actually serve -----------------------------
# Squid needs a few seconds after the container starts before it is
# listening AND able to resolve upstream names. Returning from up.sh
# before then makes any immediately-following fetch fail for reasons that
# have nothing to do with the allowlist.
echo -n "  waiting for proxy to serve"
ready=0
for _ in $(seq 1 40); do
    if podman exec sandbox-runner bash -c \
        'curl -s -o /dev/null --max-time 4 https://pypi.org/simple/' 2>/dev/null; then
        ready=1; break
    fi
    echo -n "."
    sleep 1
done
echo
if [ "$ready" -eq 1 ]; then
    echo "  proxy is serving (allowlisted fetch succeeded)"
else
    echo "  WARNING: proxy did not serve an allowlisted fetch within 40s."
    echo "           check:  podman logs sandbox-proxy"
fi

echo
podman ps --filter name=sandbox- --format '  {{.Names}}  {{.Status}}  {{.Image}}'
echo
echo "next:  ./selftest.sh"
