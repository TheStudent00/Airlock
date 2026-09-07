#!/usr/bin/env bash
# unpack.sh -- restore a bundle written by pack.sh on THIS machine and bring
# the sandboxes up. Run from inside the bundle folder.
#
#   bash unpack.sh [--airlock <dir>] [--home <dir>] [--cpus N] [--memory Ng] [--up <instance>]...
#
#   --airlock   where the tool checkout goes      (default ~/Programming/Airlock)
#   --home      where projects/ is restored to     (default $HOME; paths in
#               mounts.conf were written as ~/..., so keeping the same layout
#               means mounts.conf needs no edit)
#   --cpus/--memory  override every instance conf's caps (a bigger machine)
#   --up        instances to start now (repeatable); none = start nothing
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AL="$HOME/Programming/Airlock"; DEST_HOME="$HOME"; CPUS=""; MEM=""; UP=()
while [ $# -gt 0 ]; do
    case "$1" in
        --airlock) AL="$2"; shift 2 ;;
        --home) DEST_HOME="$2"; shift 2 ;;
        --cpus) CPUS="$2"; shift 2 ;;
        --memory) MEM="$2"; shift 2 ;;
        --up) UP+=("$2"); shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done
command -v podman >/dev/null || { echo "podman is not installed (apt install podman)"; exit 1; }
command -v git >/dev/null || { echo "git is not installed"; exit 1; }
command -v rsync >/dev/null || { echo "rsync is not installed"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is not installed"; exit 1; }

echo "[1/6] tool -> $AL"
if [ -d "$AL/.git" ]; then git -C "$AL" pull --ff-only "$HERE/airlock.bundle" HEAD 2>/dev/null || git -C "$AL" fetch "$HERE/airlock.bundle" '+refs/heads/*:refs/remotes/bundle/*'
else mkdir -p "$(dirname "$AL")"; git clone -q "$HERE/airlock.bundle" "$AL"; fi
# the four run-record dirs must exist and be empty on a fresh clone
mkdir -p "$AL/agent/drop" "$AL/agent/out" "$AL/agent/logs" "$AL/agent/status"

echo "[2/6] images -> podman load"
for f in "$HERE"/image_*.tar; do [ -f "$f" ] && podman load -q -i "$f"; done
podman images --format '  {{.Repository}}:{{.Tag}} {{.Size}}' | grep -E 'sandbox|runner|proxy' || true

echo "[3/6] config"
mkdir -p "$AL/instances" "$AL/proxy"
cp "$HERE"/config/instances/*.conf "$AL/instances/" 2>/dev/null || true
[ -f "$HERE/config/mounts.conf" ] && cp "$HERE/config/mounts.conf" "$AL/mounts.conf"
[ -f "$HERE/config/proxy/allowlist.txt" ] && cp "$HERE/config/proxy/allowlist.txt" "$AL/proxy/allowlist.txt"
if [ -n "$CPUS$MEM" ]; then
    for c in "$AL"/instances/*.conf; do
        [ -n "$CPUS" ] && sed -i -E "s/^(\s*cpus\s*=\s*)[0-9]+/\1$CPUS/" "$c"
        [ -n "$MEM" ] && sed -i -E "s/^(\s*memory\s*=\s*)[0-9]+[gGmM]/\1$MEM/" "$c"
    done
    echo "  every instance conf now: cpus=${CPUS:-unchanged} memory=${MEM:-unchanged}"
fi
if [ "$DEST_HOME" != "$HOME" ] && [ -f "$AL/mounts.conf" ]; then
    sed -i "s#^~/#$DEST_HOME/#" "$AL/mounts.conf"; echo "  mounts.conf rewritten from ~/ to $DEST_HOME/"
fi

echo "[4/6] persist volumes -> podman volume import"
for f in "$HERE"/volume_*.tar; do
    [ -f "$f" ] || continue
    v="$(basename "$f" .tar)"; v="${v#volume_}"
    podman volume exists "$v" 2>/dev/null || podman volume create "$v" >/dev/null
    podman volume import "$v" "$f"; echo "  $v restored"
done

echo "[5/6] projects -> $DEST_HOME"
if [ -d "$HERE/projects" ]; then
    rsync -a "$HERE/projects/" "$DEST_HOME/" --exclude .packed_from_home
    echo "  $(find "$HERE/projects" -mindepth 2 -maxdepth 2 -type d | wc -l) top-level project dirs restored"
fi

echo "[6/6] up"
cd "$AL"
if [ ${#UP[@]} -eq 0 ]; then
    echo "  nothing started. Start one with: bash $AL/up.sh --instance <name>   then   bash $AL/selftest.sh"
else
    for i in "${UP[@]}"; do
        if [ "$i" = sandbox ]; then bash ./up.sh; else bash ./up.sh --instance "$i"; fi
    done
    ./airlock doctor || true
fi
