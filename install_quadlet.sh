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
# Usage:
#   ./install_quadlet.sh            install and start
#   ./install_quadlet.sh --remove   stop, disable, and remove the units
set -uo pipefail
cd "$(dirname "$0")"
UNITDIR="$HOME/.config/containers/systemd"

# Everything this script prints also lands here, so a failure is readable
# after the fact instead of scrolling away in the terminal.
mkdir -p DevComms
exec > >(tee DevComms/quadlet_install.txt) 2>&1
trap 'sleep 0.3' EXIT   # let tee flush before the shell exits
echo "# install_quadlet.sh — $(date -Iseconds)"

UNITS=(sandbox-internal.network sandbox-egress.network
       sandbox-proxy.container sandbox-runner.container)

if [ "${1:-}" = "--remove" ]; then
    systemctl --user stop sandbox-runner.service sandbox-proxy.service 2>/dev/null || true
    systemctl --user stop sandbox-internal-network.service sandbox-egress-network.service 2>/dev/null || true
    for u in "${UNITS[@]}"; do rm -fv "$UNITDIR/$u"; done
    systemctl --user daemon-reload
    systemctl --user reset-failed 2>/dev/null || true
    echo "removed. ./up.sh still works for manual running."
    echo "note: the named volumes sandbox-logs and sandbox-out are kept."
    echo "      remove them with: podman volume rm sandbox-logs sandbox-out"
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
echo "  stopping any existing sandbox units"
systemctl --user stop sandbox-runner.service sandbox-proxy.service 2>/dev/null || true
systemctl --user stop sandbox-internal-network.service sandbox-egress-network.service 2>/dev/null || true
systemctl --user reset-failed sandbox-runner.service sandbox-proxy.service 2>/dev/null || true

echo "  removing containers and networks"
podman rm -f sandbox-runner sandbox-proxy 2>/dev/null >/dev/null || true
podman network rm sandbox-internal sandbox-egress 2>/dev/null >/dev/null || true

# ---- the agent lane ------------------------------------------------------
# The runner unit ships with an EMPTY agent-lane block, because Airlock
# carries no assumption about where it has been cloned. The four host binds
# are generated here, from this repo's own absolute location, and spliced
# into the INSTALLED copy. The repo copy is never modified.
REPO="$(pwd)"
AGENT_LINES="$(printf 'Volume=%s/agent/%s:/%s\n' \
    "$REPO" drop drop "$REPO" out out "$REPO" logs logs "$REPO" status status)"
mkdir -p "$REPO"/agent/{drop,out,logs,status}
echo "  agent lane bound from $REPO/agent:"
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
    local conf="mounts.conf" line host cpath mode expanded bad=0
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
    echo "  refusing to install: fix mounts.conf and re-run" >&2
    exit 1
}
if [ -z "$MOUNT_LINES" ]; then
    if [ -f mounts.conf ]; then
        echo "  note: mounts.conf has no entries — the runner will see only"
        echo "        the agent lane (/drop, /out, /logs, /status)."
    else
        echo "  note: no mounts.conf — copy mounts.conf.example to mounts.conf"
        echo "        to expose project directories. The agent lane still works."
    fi
else
    echo "  mounts from mounts.conf:"
    echo "$MOUNT_LINES" | sed 's/^Volume=/    /'
fi

mkdir -p "$UNITDIR"
for u in "${UNITS[@]}"; do
    if [ "$u" = "sandbox-runner.container" ]; then
        # Splice the generated block between the markers. awk rather than
        # sed: the mount lines contain slashes, and quoting them into a
        # sed replacement is how this kind of thing breaks silently.
        awk -v agent="$AGENT_LINES" -v block="$MOUNT_LINES" '
            /^# >>> AGENT LANE$/ { print; if (agent != "") print agent; skip=1; next }
            /^# <<< AGENT LANE$/ { skip=0 }
            /^# >>> MOUNTS$/ { print; if (block != "") print block; skip=1; next }
            /^# <<< MOUNTS$/ { skip=0 }
            !skip { print }
        ' "quadlet/$u" > "$UNITDIR/$u"
        chmod 0644 "$UNITDIR/$u"
    else
        install -m 0644 "quadlet/$u" "$UNITDIR/$u"
    fi
    echo "  installed $UNITDIR/$u"
done

systemctl --user daemon-reload

# Bring the networks up explicitly before the containers, so a failure
# here is reported as a network problem rather than as a container one.
echo "  starting networks"
for n in sandbox-internal-network sandbox-egress-network; do
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
for s in sandbox-proxy sandbox-runner; do
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
systemctl --user --no-pager --lines=0 status sandbox-proxy.service sandbox-runner.service \
    | grep -E 'sandbox-|Active:' | sed 's/^/  /'
echo
podman ps --filter name=sandbox- --format '  {{.Names}}  {{.Status}}'
echo
echo "From here on:"
echo "  systemctl --user restart sandbox-runner"
echo "  systemctl --user status  sandbox-runner"
echo "  journalctl --user -u sandbox-runner -f"
echo
echo "airlock, submit.sh, submit_project.sh, logs.sh, allow.sh, pull.sh"
echo "all still work."
echo "Verify with:  ./selftest.sh"
