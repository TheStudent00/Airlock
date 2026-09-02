#!/usr/bin/env bash
# Start ONE INSTANCE of the sandbox: its networks, its proxy, its runner.
#
# INSTANCES
#   `./up.sh` with no instance named starts the DEFAULT instance, `sandbox`
#   — the same containers, networks, volume and caps as always.
#
#   `./up.sh --instance trickle` starts a SECOND, independent sandbox
#   beside it: trickle-runner on trickle-internal, its own agent lane, its
#   own caps, reusing the same already-built image. Two instances run side
#   by side and never share a container, a network or a drop folder.
#
#   Every name is derived from the instance name in ./instance.sh, and an
#   instance's caps come from instances/<name>.conf (all keys optional; see
#   instances/sandbox.conf.example).
#
# NETWORK SHAPE
#   <instance>-egress    ordinary bridge, has a route out. ONLY the proxy is on it.
#   <instance>-internal  created with --internal, which means podman installs no
#                        route out of it at all. The runner is on this one only.
#
#   So the runner's only reachable peer is <instance>-proxy:3128, and the proxy
#   refuses any hostname absent from the instance's allowlist. There is no
#   second path to the internet to forget about. An instance configured
#   `proxy = no` has no proxy and no egress network at all.
#
# Usage:  ./up.sh [--instance NAME] [--cpus N]
#
# CPU SHARE
#   The runner starts with --cpus, DEFAULT 6 — the full share. RULED
#   2026-08-22: "default is full CPUs. user can throttle how they see fit."
#
#   Precedence, highest first:  --cpus N  >  AIRLOCK_CPUS  >  SANDBOX_CPUS
#   >  the `cpus` key in instances/<name>.conf  >  6.
#
#       ./up.sh --cpus 3                     throttle a long run
#       AIRLOCK_CPUS=3 ./up.sh               the same, by environment
#       ./up.sh --instance trickle --cpus 6  half of a 12-core machine, for
#                                            a second sandbox beside the first
#
#   Roughly halving the cores roughly doubles a run's wall clock. This
#   is a fixed share, not a feedback loop — it does not read temperature
#   or back off dynamically. Raise or lower it by hand.
#
#   SANDBOX_CPUS is the older spelling, inherited from the SandboxDesign
#   repo Airlock derives from. It is still honoured, AFTER AIRLOCK_CPUS.
#
#   The systemd path (install_quadlet.sh) reads the same instance conf, so
#   the two agree.
set -euo pipefail
cd "$(dirname "$0")"

source ./instance.sh
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"

while [ $# -gt 0 ]; do
    case "$1" in
        --cpus)
            AIRLOCK_CPUS_FLAG="${2:?--cpus needs a number}"
            export AIRLOCK_CPUS_FLAG
            shift 2
            ;;
        --cpus=*)
            AIRLOCK_CPUS_FLAG="${1#--cpus=}"
            export AIRLOCK_CPUS_FLAG
            shift
            ;;
        *)
            echo "unknown argument: $1" >&2
            echo "usage: ./up.sh [--instance NAME] [--cpus N]" >&2
            exit 2
            ;;
    esac
done

airlock_instance_load
echo "=== airlock up ==="
airlock_instance_banner
if [ -f "$AL_CONF" ]; then
    echo "  config:   $AL_CONF"
else
    echo "  config:   $AL_CONF (absent — every setting is at its built-in default)"
fi

podman network exists "$AL_NET_INTERNAL" || podman network create --internal "$AL_NET_INTERNAL"
if [ "$AL_USE_PROXY" = "yes" ]; then
    podman network exists "$AL_NET_EGRESS" || podman network create "$AL_NET_EGRESS"
fi

# ---- agent lane ----------------------------------------------------------
# An agent session may be able to write files on the host but not run
# podman. Binding these four directories from the host makes the hot folder
# reachable by a plain file write: the session writes agent/drop/x.sh, the
# daemon's close_write watch fires, and the session reads agent/status/x.sh.status
# and agent/out/ back. No shell on the session's side is involved.
AGENT_DIR="$AL_AGENT_DIR"
mkdir -p "$AGENT_DIR"/{drop,out,logs,status}

# Configured mounts come from this instance's mounts file — one
# `<host>:<container>[:mode]` per line, default read-only. See
# mounts.conf.example. No project's paths are named in this repo: Airlock is
# project-agnostic, and which directories a machine exposes is that
# machine's configuration.
#
# Read-only is the default because it keeps the design's core property — a run
# cannot alter the originals — while still testing against the real tree with
# no copy step. Products go to /out and the caller places them.
#
# Never mount a home directory wholesale: one multi-gigabyte tree in it will
# exhaust a caller's file descriptors and defeat the isolation besides.
MOUNT_ARGS=()
if [ -f "$AL_MOUNTS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"; line="$(echo "$line" | xargs)"
        [ -z "$line" ] && continue
        host="${line%%:*}"; rest="${line#*:}"
        cpath="${rest%%:*}"; mode="ro"
        case "$rest" in *:*) mode="${rest##*:}";; esac
        [ "$mode" = "rw" ] || mode="ro"
        expanded="${host/#\~/$HOME}"
        if [ ! -e "$expanded" ]; then
            echo "  MOUNT ERROR: no such path: $expanded ($AL_MOUNTS_FILE)" >&2
            exit 1
        fi
        MOUNT_ARGS+=(-v "$expanded:$cpath:$mode")
    done < "$AL_MOUNTS_FILE"
fi

# ---- proxy ---------------------------------------------------------------
if [ "$AL_USE_PROXY" = "yes" ]; then
    if podman container exists "$AL_PROXY"; then
        podman start "$AL_PROXY" >/dev/null
        echo "  $AL_PROXY already existed; started"
    else
        podman run -d --name "$AL_PROXY" \
            --network "$AL_NET_EGRESS" \
            --memory "$AL_PROXY_MEMORY" --cpus "$AL_PROXY_CPUS" --pids-limit "$AL_PROXY_PIDS" \
            --cap-drop=ALL --cap-add=SETUID --cap-add=SETGID \
            --security-opt no-new-privileges \
            "$AL_PROXY_IMAGE"
        podman network connect "$AL_NET_INTERNAL" "$AL_PROXY"
        echo "  $AL_PROXY started (on both networks)"
    fi
else
    echo "  proxy: none (instance is configured 'proxy = no' — no route out at all)"
fi

# ---- the proxy variables the runner inherits -----------------------------
# The image bakes in http_proxy=http://sandbox-proxy:3128, which is right
# for the default instance and wrong for every other one. They are set
# explicitly here from the instance's own proxy name, so the baked-in value
# is never what an instance relies on. For the default instance these are
# the same strings the image already carried.
PROXY_ENV=()
if [ "$AL_USE_PROXY" = "yes" ]; then
    PROXY_URL="http://$AL_PROXY:3128"
    PROXY_ENV=(-e "http_proxy=$PROXY_URL" -e "https_proxy=$PROXY_URL"
               -e "HTTP_PROXY=$PROXY_URL" -e "HTTPS_PROXY=$PROXY_URL")
else
    PROXY_ENV=(-e "http_proxy=" -e "https_proxy=" -e "HTTP_PROXY=" -e "HTTPS_PROXY=")
fi

# ---- the daemon this instance runs ---------------------------------------
# Unset by default: the daemon baked into the image is what runs, and the
# container spec is exactly what it always was. An instance that names
# `daemon_file` binds that host file read-only over the image's copy, which
# is how a daemon change reaches a running instance without a rebuild.
DAEMON_ARGS=()
if [ -n "${AL_DAEMON_FILE:-}" ]; then
    if [ ! -f "$AL_DAEMON_FILE" ]; then
        echo "  DAEMON ERROR: no such file: $AL_DAEMON_FILE (daemon_file in $AL_CONF)" >&2
        exit 1
    fi
    DAEMON_ARGS=(-v "$AL_DAEMON_FILE:/opt/daemon/watcher.py:ro")
    echo "  daemon:   $AL_DAEMON_FILE (bound over the image's copy)"
fi

# ---- runner --------------------------------------------------------------
# An existing container is STARTED, never rebound: podman fixes a container's
# binds when it is created. So before reusing one, check that it is bound to
# THIS instance's agent folders.
#
# The failure this exists to stop, seen 2026-08-22: a runner created by a
# different checkout of this design kept watching that checkout's agent/drop.
# podman reported it running, its toolchains answered, and lanes queued here
# were simply never seen — for twenty minutes, with no error anywhere.
if podman container exists "$AL_RUNNER"; then
    bound_drop=$(podman inspect "$AL_RUNNER" \
        --format '{{range .Mounts}}{{if eq .Destination "/drop"}}{{.Source}}{{end}}{{end}}' \
        2>/dev/null || echo "")
    if [ -n "$bound_drop" ] && [ "$bound_drop" != "$AGENT_DIR/drop" ]; then
        echo "  REFUSING to reuse $AL_RUNNER: it is bound to another tree." >&2
        echo "    its /drop:      $bound_drop" >&2
        echo "    this instance:  $AGENT_DIR/drop" >&2
        echo "    Lanes queued here would never be seen. Remove it and rerun:" >&2
        echo "      podman rm -f $AL_RUNNER $AL_PROXY && bash $0 --instance $AL_INSTANCE" >&2
        exit 1
    fi
    podman start "$AL_RUNNER" >/dev/null
    echo "  $AL_RUNNER already existed; started (bound to $AGENT_DIR/drop)"
else
    # Host binds for the agent lane; named volume only for /persist, which is
    # the one place state is MEANT to survive between runs.
    #
    # /work is a size-capped tmpfs. A run that tries to write more scratch than
    # the cap fails loudly inside the container with ENOSPC, instead of filling
    # the host disk — which is exactly how a generated-file extraction wedged a
    # session on 2026-07-30. Raising the cap is a deliberate act, not a default.
    podman run -d --name "$AL_RUNNER" \
        --network "$AL_NET_INTERNAL" \
        -v "$AGENT_DIR/drop":/drop \
        -v "$AGENT_DIR/out":/out \
        -v "$AGENT_DIR/logs":/logs \
        -v "$AGENT_DIR/status":/status \
        "${MOUNT_ARGS[@]}" \
        -v "$AL_PERSIST:/persist:$AL_PERSIST_MODE" \
        "${DAEMON_ARGS[@]}" \
        "${PROXY_ENV[@]}" \
        -e "LANE_NICE=$AL_LANE_NICE" \
        -e "SCRIPT_TIMEOUT=$AL_SCRIPT_TIMEOUT" \
        -e "AIRLOCK_WATCH=$AL_WATCH" \
        --memory "$AL_MEMORY" --cpus "$AL_CPUS" --pids-limit "$AL_PIDS" \
        --cap-drop=ALL \
        --security-opt no-new-privileges \
        --tmpfs "/tmp:rw,nosuid,nodev,size=$AL_TMP_SIZE" \
        --tmpfs "/work:rw,nosuid,nodev,size=$AL_WORK_SIZE" \
        "$AL_RUNNER_IMAGE"
    echo "  $AL_RUNNER started"
    echo "    cpus:     $AL_CPUS (--cpus 3 or AIRLOCK_CPUS=3 to throttle a long run)"
    echo "    memory:   $AL_MEMORY   /tmp $AL_TMP_SIZE   /work $AL_WORK_SIZE"
    echo "    persist:  $AL_PERSIST ($AL_PERSIST_MODE)"
    echo "    watch:    $AL_WATCH"
    echo "    drop:     $AGENT_DIR/drop      (write x.sh here to run it)"
    echo "    status:   $AGENT_DIR/status    (x.sh.status — poll this)"
    echo "    out/logs: $AGENT_DIR/{out,logs}"
    if [ ${#MOUNT_ARGS[@]} -eq 0 ]; then
        echo "    mounts:   none (no $AL_MOUNTS_FILE — see mounts.conf.example)"
    else
        echo "    mounts:   from $AL_MOUNTS_FILE —"
        printf '      %s\n' "${MOUNT_ARGS[@]}" | grep -v '^\s*-v$'
    fi
fi

# ---- wait until the proxy can actually serve -----------------------------
# Squid needs a few seconds after the container starts before it is
# listening AND able to resolve upstream names. Returning from up.sh
# before then makes any immediately-following fetch fail for reasons that
# have nothing to do with the allowlist.
if [ "$AL_USE_PROXY" = "yes" ]; then
    echo -n "  waiting for proxy to serve"
    ready=0
    for _ in $(seq 1 40); do
        if podman exec "$AL_RUNNER" bash -c \
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
        echo "           check:  podman logs $AL_PROXY"
    fi
fi

echo
podman ps --filter "name=^${AL_INSTANCE}-" --format '  {{.Names}}  {{.Status}}  {{.Image}}'
echo
if [ "$AL_INSTANCE" = "sandbox" ]; then
    echo "next:  ./selftest.sh"
else
    echo "next:  ./selftest.sh --instance $AL_INSTANCE"
fi
