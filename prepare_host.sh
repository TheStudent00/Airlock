#!/usr/bin/env bash
# prepare_host.sh -- make a fresh Linux machine able to receive an Airlock
# bundle: install what unpack.sh needs, and configure rootless podman so the
# per-instance caps (--cpus, --memory, --pids-limit) are actually enforced.
#
#   bash prepare_host.sh --check     report only, change nothing
#   bash prepare_host.sh             install and configure (needs sudo)
#
# WHY THE CGROUP PART EXISTS
#   Rootless podman can only apply --cpus when systemd delegates the `cpu`
#   controller to the user slice. Some distributions delegate memory and pids
#   only; on those, every instance's cpus setting is silently ignored and one
#   lane can take the whole machine. This script READS the delegated
#   controllers and writes the drop-in only when cpu is missing.
set -euo pipefail
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

say()  { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

say "== what is here =="
say "  kernel        $(uname -sr)"
say "  distribution  $( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo unknown)"
say "  cores         $(nproc)"
say "  memory        $(free -g | awk '/^Mem:/{print $2" GB"}')"
say "  cgroup        $(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo unknown)  (cgroup2fs is what rootless caps need)"
for t in podman git rsync python3; do
    if have "$t"; then say "  $t$(printf '%*s' $((13-${#t})) '')$($t --version 2>&1 | head -1)"
    else say "  $t$(printf '%*s' $((13-${#t})) '')ABSENT"; fi
done
DELEG=/etc/systemd/system/user@.service.d/delegate.conf
if [ -f "$DELEG" ] && grep -q 'cpu' "$DELEG"; then say "  cpu delegation  configured ($DELEG)"; else say "  cpu delegation  NOT configured"; fi
say "  subuid range  $(grep "^$(id -un):" /etc/subuid 2>/dev/null || echo 'ABSENT -- rootless podman cannot map users')"
if [ -d /sys/fs/cgroup/user.slice ]; then
    say "  controllers delegated to this user: $(cat "/sys/fs/cgroup/user.slice/user-$(id -u).slice/cgroup.controllers" 2>/dev/null || echo unknown)"
fi

[ "$CHECK" = 1 ] && { say; say "check only; nothing changed."; exit 0; }

say
say "== installing =="
if have apt-get; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        podman uidmap passt slirp4netns aardvark-dns netavark \
        golang-github-containernetworking-plugin-dnsname \
        fuse-overlayfs dbus-user-session \
        git rsync python3 ca-certificates
else
    say "no apt-get here; install podman, uidmap, passt, fuse-overlayfs, git, rsync, python3 by hand, then re-run."
    exit 1
fi

say
say "== cgroup delegation for rootless caps =="
CTRL="$(cat "/sys/fs/cgroup/user.slice/user-$(id -u).slice/cgroup.controllers" 2>/dev/null || echo '')"
if echo "$CTRL" | grep -qw cpu; then
    say "  cpu is already delegated to this user ($CTRL); no drop-in needed"
else
    sudo mkdir -p "$(dirname "$DELEG")"
    printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | sudo tee "$DELEG" >/dev/null
    sudo systemctl daemon-reload
    say "  wrote $DELEG -- log out and back in for it to apply"
fi

say
say "== keep containers running when nobody is logged in =="
sudo loginctl enable-linger "$(id -un)"
say "  lingering enabled for $(id -un)"

say
say "done. Log out and back in (the delegation drop-in applies to a NEW user"
say "session), then re-run:  bash prepare_host.sh --check"
say "The controllers line must include cpu. Then run unpack.sh from the bundle."
