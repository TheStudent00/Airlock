#!/usr/bin/env bash
# Hand the sandbox over to systemd so it survives reboots and restarts
# itself if the daemon crashes.
#
# WHAT A QUADLET IS
#   A file describing a container, placed in a directory systemd watches.
#   systemd's podman generator reads it and produces a real service unit —
#   so `systemctl --user status sandbox-runner` works, the container comes
#   back after a reboot, and Restart=on-failure applies. It replaces the
#   older `podman generate systemd` approach.
#
# This REPLACES ./up.sh and ./down.sh as the way the containers run.
# The unit files live in the repo under quadlet/ and are copied to
# ~/.config/containers/systemd/, which is the directory systemd reads.
#
# INSTANCES
#   The four unit files in quadlet/ are TEMPLATES written for the default
#   instance. This script renders them for whichever instance is named,
#   substituting the instance's own container, network and volume names and
#   its own caps from instances/<name>.conf, and installs them under that
#   instance's names. The repo copies are never modified.
#
#   Two instances can therefore be installed side by side:
#     systemctl --user status sandbox-runner
#     systemctl --user status trickle-runner
#
# Usage:
#   ./install_quadlet.sh [--instance NAME]            install and start
#   ./install_quadlet.sh [--instance NAME] --remove   stop, disable, remove
set -uo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"

UNITDIR="$HOME/.config/containers/systemd"

# Everything this script prints also lands here, so a failure is readable
# after the fact instead of scrolling away in the terminal.
mkdir -p DevComms
exec > >(tee "DevComms/quadlet_install_${AL_INSTANCE}.txt") 2>&1
trap 'sleep 0.3' EXIT   # let tee flush before the shell exits
echo "# install_quadlet.sh — instance $AL_INSTANCE — $(date -Iseconds)"

# The template in quadlet/, and the name it is installed under. The pairs
# are identical for the default instance, which is why installing `sandbox`
# writes exactly the files it always wrote.
TEMPLATES=(sandbox-internal.network sandbox-egress.network
           sandbox-proxy.container sandbox-runner.container)
UNITS=("$AL_NET_INTERNAL.network" "$AL_NET_EGRESS.network"
       "$AL_PROXY.container" "$AL_RUNNER.container")

if [ "${1:-}" = "--remove" ]; then
    systemctl --user stop "$AL_RUNNER.service" "$AL_PROXY.service" 2>/dev/null || true
    systemctl --user stop "$AL_NET_INTERNAL-network.service" "$AL_NET_EGRESS-network.service" 2>/dev/null || true
    for u in "${UNITS[@]}"; do rm -fv "$UNITDIR/$u"; done
    systemctl --user daemon-reload
    systemctl --user reset-failed 2>/dev/null || true
    echo "removed. ./up.sh --instance $AL_INSTANCE still works for manual running."
    echo "note: the named volume $AL_PERSIST is kept."
    echo "      remove it with: podman volume rm $AL_PERSIST"
    exit 0
fi

# Containers started by systemd --user stop when the last session for the
# user ends, unless lingering is enabled. Without this the sandbox dies
# when you log out and does not come back on boot.
if ! loginctl show-user "$USER" --property=Linger 2>/dev/null | grep -q 'Linger=yes'; then
    echo "  enabling lingering (needed for boot-time start; may prompt for sudo)"
    sudo loginctl enable-linger "$USER"
fi

# ---- tear down whatever is currently running -----------------------------
# ORDER MATTERS, and getting it wrong is what broke the 10:07 install.
#
# A `.network` file becomes a oneshot service that creates the network and
# then stays "active" to record that it did. If we delete the network with
# `podman network rm` while that service still reads as active, systemd
# believes the network exists, skips recreating it, and the container's
# `podman run --network sandbox-egress` fails with exit 125.
#
# So: stop the network SERVICES first, and only then remove the networks.
echo "  stopping any existing units for instance $AL_INSTANCE"
systemctl --user stop "$AL_RUNNER.service" "$AL_PROXY.service" 2>/dev/null || true
systemctl --user stop "$AL_NET_INTERNAL-network.service" "$AL_NET_EGRESS-network.service" 2>/dev/null || true
systemctl --user reset-failed "$AL_RUNNER.service" "$AL_PROXY.service" 2>/dev/null || true

echo "  removing this instance's containers and networks"
podman rm -f "$AL_RUNNER" "$AL_PROXY" 2>/dev/null >/dev/null || true
podman network rm "$AL_NET_INTERNAL" "$AL_NET_EGRESS" 2>/dev/null >/dev/null || true

# ---- the agent lane ------------------------------------------------------
# The runner unit ships with an EMPTY agent-lane block, because Airlock
# carries no assumption about where it has been cloned. The four host binds
# are generated here, from this repo's own absolute location, and spliced
# into the INSTALLED copy. The repo copy is never modified.
REPO="$(pwd)"
AGENT_LINES="$(printf 'Volume=%s/%s:/%s\n' \
    "$AL_AGENT_DIR" drop drop "$AL_AGENT_DIR" out out \
    "$AL_AGENT_DIR" logs logs "$AL_AGENT_DIR" status status)"
mkdir -p "$AL_AGENT_DIR"/{drop,out,logs,status}
echo "  agent lane bound from $AL_AGENT_DIR:"
echo "$AGENT_LINES" | sed 's/^Volume=/    /'

# ---- configured mounts ---------------------------------------------------
# The runner unit ships with an EMPTY mount block too, because this repo is
# project-agnostic. The machine's actual directories come from
# ./mounts.conf and are generated into the installed copy here.
#
# A missing or unreadable host path is a hard stop, not a warning: podman
# would otherwise create an empty directory at that path and the run would
# "succeed" against nothing, which is the failure that wastes an hour.
render_mounts() {   # -> stdout, the Volume= lines
    local conf="$AL_MOUNTS_FILE" line host cpath mode expanded bad=0
    [ -f "$conf" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(echo "$line" | xargs)"
        [ -z "$line" ] && continue
        host="${line%%:*}"
        local rest="${line#*:}"
        cpath="${rest%%:*}"
        mode="ro"
        case "$rest" in *:*) mode="${rest##*:}";; esac
        [ "$mode" = "rw" ] || mode="ro"
        expanded="${host/#\~/$HOME}"
        if [ ! -e "$expanded" ]; then
            echo "  MOUNT ERROR: no such path: $expanded  (from $conf)" >&2
            bad=1; continue
        fi
        echo "Volume=$expanded:$cpath:$mode"
    done < "$conf"
    return $bad
}

MOUNT_LINES="$(render_mounts)" || {
    echo "  refusing to install: fix $AL_MOUNTS_FILE and re-run" >&2
    exit 1
}
if [ -z "$MOUNT_LINES" ]; then
    if [ -f "$AL_MOUNTS_FILE" ]; then
        echo "  note: $AL_MOUNTS_FILE has no entries — the runner will see only"
        echo "        the agent lane (/drop, /out, /logs, /status)."
    else
        echo "  note: no $AL_MOUNTS_FILE — copy mounts.conf.example to it"
        echo "        to expose project directories. The agent lane still works."
    fi
else
    echo "  mounts from $AL_MOUNTS_FILE:"
    echo "$MOUNT_LINES" | sed 's/^Volume=/    /'
fi

# render_instance reads a template on stdin and writes the instance's own
# unit on stdout: every `sandbox-` name becomes this instance's name, and
# the caps come from instances/<name>.conf. For the default instance every
# substitution is a no-op, so the installed file is byte-identical to the
# template plus the generated blocks — which is what it has always been.
render_instance() {
    sed -e "s|sandbox-internal|$AL_NET_INTERNAL|g" \
        -e "s|sandbox-egress|$AL_NET_EGRESS|g" \
        -e "s|localhost/sandbox-runner:latest|localhost/$AL_RUNNER_IMAGE|g" \
        -e "s|localhost/sandbox-proxy:latest|localhost/$AL_PROXY_IMAGE|g" \
        -e "s|sandbox-runner|$AL_RUNNER|g" \
        -e "s|sandbox-proxy|$AL_PROXY|g" \
        -e "s|^Volume=sandbox-persist:/persist$|Volume=$AL_PERSIST:/persist:$AL_PERSIST_MODE|" \
        -e "s|^Memory=12g$|Memory=$AL_MEMORY|" \
        -e "s|^Memory=512m$|Memory=$AL_PROXY_MEMORY|" \
        -e "s|^PidsLimit=2048$|PidsLimit=$AL_PIDS|" \
        -e "s|^PidsLimit=256$|PidsLimit=$AL_PROXY_PIDS|" \
        -e "s|^Tmpfs=/tmp:rw,nosuid,nodev,size=2g$|Tmpfs=/tmp:rw,nosuid,nodev,size=$AL_TMP_SIZE|" \
        -e "s|^Tmpfs=/work:rw,nosuid,nodev,size=4g$|Tmpfs=/work:rw,nosuid,nodev,size=$AL_WORK_SIZE|" \
        -e "s|^PodmanArgs=--cpus=6$|PodmanArgs=--cpus=$AL_CPUS|" \
        -e "s|^PodmanArgs=--cpus=1$|PodmanArgs=--cpus=$AL_PROXY_CPUS|"
}

mkdir -p "$UNITDIR"
for i in "${!UNITS[@]}"; do
    t="${TEMPLATES[$i]}"
    u="${UNITS[$i]}"
    if [ "$t" = "sandbox-runner.container" ]; then
        # Splice the generated block between the markers. awk rather than
        # sed: the mount lines contain slashes, and quoting them into a
        # sed replacement is how this kind of thing breaks silently.
        awk -v agent="$AGENT_LINES" -v block="$MOUNT_LINES" '
            /^# >>> AGENT LANE$/ { print; if (agent != "") print agent; skip=1; next }
            /^# <<< AGENT LANE$/ { skip=0 }
            /^# >>> MOUNTS$/ { print; if (block != "") print block; skip=1; next }
            /^# <<< MOUNTS$/ { skip=0 }
            !skip { print }
        ' "quadlet/$t" | render_instance > "$UNITDIR/$u"
        chmod 0644 "$UNITDIR/$u"
    else
        render_instance < "quadlet/$t" > "$UNITDIR/$u"
        chmod 0644 "$UNITDIR/$u"
    fi
    echo "  installed $UNITDIR/$u   (from quadlet/$t)"
done

systemctl --user daemon-reload

# Bring the networks up explicitly before the containers, so a failure
# here is reported as a network problem rather than as a container one.
echo "  starting networks"
for n in "$AL_NET_INTERNAL-network" "$AL_NET_EGRESS-network"; do
    if systemctl --user start "$n.service"; then
        echo "    $n.service started"
    else
        echo "    FAILED to start $n.service"
        systemctl --user --no-pager --lines=15 status "$n.service" | sed 's/^/      /'
    fi
done
echo "  networks known to podman now:"
podman network ls --format '    {{.Name}}'

echo "  starting containers"
for s in "$AL_PROXY" "$AL_RUNNER"; do
    if systemctl --user start "$s.service"; then
        echo "    $s.service started"
    else
        echo "    FAILED to start $s.service — diagnostics follow"
        systemctl --user --no-pager --lines=20 status "$s.service" | sed 's/^/      /'
        journalctl --user -u "$s.service" --no-pager -n 20 | sed 's/^/      /'
    fi
done

echo
echo "=== unit status ==="
systemctl --user --no-pager --lines=0 status "$AL_PROXY.service" "$AL_RUNNER.service" \
    | grep -E "${AL_INSTANCE}-|Active:" | sed 's/^/  /'
echo
podman ps --filter "name=^${AL_INSTANCE}-" --format '  {{.Names}}  {{.Status}}'
echo
echo "From here on:"
echo "  systemctl --user restart $AL_RUNNER"
echo "  systemctl --user status  $AL_RUNNER"
echo "  journalctl --user -u $AL_RUNNER -f"
echo
echo "airlock, submit.sh, submit_project.sh, logs.sh, allow.sh, pull.sh"
echo "all still work."
echo "Verify with:  ./selftest.sh --instance $AL_INSTANCE"
