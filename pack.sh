#!/usr/bin/env bash
# pack.sh -- bundle THIS Airlock install so another machine can run the same
# sandboxes from a folder: the tool (as a git bundle), the built images, the
# per-machine configuration, the persist volume, and the host directories the
# mounts file exposes. Nothing project-specific is named here: what gets
# packed is read from this install's own mounts.conf and instances/*.conf.
#
#   bash pack.sh --out <dir> [--no-persist] [--no-projects] [--skip <path-substring>]...
#
# Restore on the other machine with unpack.sh from inside <dir>.
set -euo pipefail
cd "$(dirname "$0")"
AL_ROOT="$(pwd)"

OUT=""; WITH_PERSIST=1; WITH_PROJECTS=1; SKIP=(); EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --no-persist) WITH_PERSIST=0; shift ;;
        --no-projects) WITH_PROJECTS=0; shift ;;
        --skip) SKIP+=("$2"); shift 2 ;;
        --extra) EXTRA+=("$2"); shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done
[ -n "$OUT" ] || { echo "usage: bash pack.sh --out <dir> [--no-persist] [--no-projects] [--skip <substring>]... [--extra <host dir>]..." >&2; exit 2; }
mkdir -p "$OUT/config/instances" "$OUT/config/proxy" "$OUT/projects"
OUT="$(cd "$OUT" && pwd)"
MAN="$OUT/MANIFEST.txt"
: > "$MAN"
note() { echo "$*" | tee -a "$MAN"; }
note "airlock bundle, packed $(date -u +%Y-%m-%dT%H:%M:%SZ) from $(hostname)"

# ---- 1. the tool: a git bundle of every branch ---------------------------
note "[1/5] tool: git bundle"
git bundle create "$OUT/airlock.bundle" --all
note "  airlock.bundle  $(du -h "$OUT/airlock.bundle" | cut -f1)  head=$(git rev-parse --short HEAD)"

# ---- 2. the images, as they are built here (no rebuild on the far side) --
note "[2/5] images: podman save"
IMAGES=$( { grep -h '^\s*runner_image\|^\s*proxy_image' instances/*.conf 2>/dev/null | sed 's/#.*//' | awk -F= '{gsub(/ /,"",$2); print $2}'; echo sandbox-runner:latest; echo sandbox-proxy:latest; } | sort -u )
for img in $IMAGES; do
    if podman image exists "localhost/$img" 2>/dev/null || podman image exists "$img" 2>/dev/null; then
        f="$OUT/image_$(echo "$img" | tr '/:' '__').tar"
        podman save --format oci-archive -o "$f" "$img"
        note "  $img  ->  $(basename "$f")  $(du -h "$f" | cut -f1)"
    else
        note "  $img  ABSENT here, not packed"
    fi
done

# ---- 3. per-machine configuration -----------------------------------------
note "[3/5] config: instances, mounts, allowlist"
cp instances/*.conf "$OUT/config/instances/" 2>/dev/null || true
[ -f mounts.conf ] && cp mounts.conf "$OUT/config/mounts.conf"
[ -f proxy/allowlist.txt ] && cp proxy/allowlist.txt "$OUT/config/proxy/allowlist.txt"
echo "${AL_ROOT#$HOME/}" > "$OUT/config/tool_path"
note "  $(ls "$OUT/config/instances" | wc -l) instance confs; mounts.conf $([ -f mounts.conf ] && echo yes || echo no); allowlist $([ -f proxy/allowlist.txt ] && echo yes || echo no)"

# ---- 4. the persist volume (toolchains installed at run time live here) ---
if [ "$WITH_PERSIST" = 1 ]; then
    note "[4/5] persist volume: podman volume export"
    VOLS=$( { grep -h '^\s*persist_volume' instances/*.conf 2>/dev/null | sed 's/#.*//' | awk -F= '{gsub(/ /,"",$2); print $2}'; echo sandbox-persist; } | sort -u )
    for v in $VOLS; do
        if podman volume exists "$v" 2>/dev/null; then
            podman volume export "$v" -o "$OUT/volume_$v.tar"
            note "  $v  ->  volume_$v.tar  $(du -h "$OUT/volume_$v.tar" | cut -f1)"
        else
            note "  $v  ABSENT here, not packed"
        fi
    done
else
    note "[4/5] persist volume: skipped (--no-persist)"
fi

# ---- 5. the host directories mounts.conf exposes ---------------------------
if [ "$WITH_PROJECTS" = 1 ] && [ -f mounts.conf ]; then
    note "[5/5] projects: every host path in mounts.conf, copied with rsync"
    while IFS= read -r line; do
        line="${line%%#*}"; line="$(echo "$line" | xargs)"; [ -z "$line" ] && continue
        host="${line%%:*}"
        expanded="${host/#\~/$HOME}"
        skip=0; for s in "${SKIP[@]:-}"; do [ -n "$s" ] && [[ "$expanded" == *"$s"* ]] && skip=1; done
        if [ "$skip" = 1 ]; then note "  $host  SKIPPED (--skip)"; continue; fi
        if [ ! -d "$expanded" ]; then note "  $host  MISSING here"; continue; fi
        rel="${expanded#$HOME/}"
        mkdir -p "$OUT/projects/$(dirname "$rel")"
        rsync -a --delete "$expanded/" "$OUT/projects/$rel/"
        note "  $host  ->  projects/$rel  $(du -sh "$OUT/projects/$rel" | cut -f1)"
    done < mounts.conf
    for x in "${EXTRA[@]:-}"; do
        [ -n "$x" ] || continue
        expanded="${x/#\~/$HOME}"
        if [ ! -d "$expanded" ]; then note "  $x  MISSING here (--extra)"; continue; fi
        rel="${expanded#$HOME/}"
        mkdir -p "$OUT/projects/$(dirname "$rel")"
        rsync -a --delete "$expanded/" "$OUT/projects/$rel/"
        note "  $x  ->  projects/$rel  $(du -sh "$OUT/projects/$rel" | cut -f1)  (--extra)"
    done
    echo "$HOME" > "$OUT/projects/.packed_from_home"
    # A symlink whose target was not packed cannot be restored and stops some
    # copy tools outright ("symlinks are not supported by backend"). Report and
    # remove them rather than shipping a link to nothing.
    while IFS= read -r dead; do
        [ -n "$dead" ] || continue
        note "  DANGLING, removed: ${dead#$OUT/}  ->  $(readlink "$dead")"
        rm -f "$dead"
    done < <(find "$OUT/projects" -xtype l)
    # Every surviving symlink becomes a copy of what it points at. A bundle
    # with no symlinks in it can be moved by ANY tool: several copy backends
    # (network shares, GUI file managers, object storage) refuse a symlink
    # outright with "symlinks are not supported by backend".
    n=0
    while IFS= read -r link; do
        [ -n "$link" ] || continue
        tgt="$(readlink -f "$link")"
        rm -f "$link"; cp -a "$tgt" "$link"; n=$((n+1))
    done < <(find "$OUT/projects" -type l)
    [ "$n" -gt 0 ] && note "  $n symlink(s) replaced by a copy of the file, so the bundle holds no symlinks"
else
    note "[5/5] projects: skipped"
fi

cp unpack.sh prepare_host.sh MOVING.md "$OUT/" 2>/dev/null || cp unpack.sh "$OUT/unpack.sh"
# A size list, so a transfer that truncates a file is caught before anything
# is restored from it. 26 GB over a network share is exactly where this bites.
( cd "$OUT" && find . -maxdepth 1 -type f ! -name SIZES.txt -printf '%s %f\n' | sort -k2 > SIZES.txt )
note "wrote SIZES.txt ($(wc -l < "$OUT/SIZES.txt") files); verify after copying with:  bash unpack.sh --verify"
note "total $(du -sh "$OUT" | cut -f1)"
note "next: copy $OUT to the other machine and run: bash unpack.sh"
