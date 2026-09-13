#!/usr/bin/env bash
# devbox: copy ~/Programming into the encrypted plain view, skipping the
# large third-party trees (exclude.txt). The host copy is not touched.
#   bash copy.sh --dry-run     prints what would go, and the size
#   bash copy.sh               copies (re-runnable: rsync brings deltas)
set -euo pipefail
SRC="${DEVBOX_SRC:-$HOME/Programming}"
MNT="${DEVBOX_MNT:-$HOME/DevboxMount}"
EXCL="$(dirname "$0")/exclude.txt"
DST="$MNT/Programming"
mountpoint -q "$MNT" || { echo "plain view not mounted: run enc_init.sh or mount.sh first"; exit 1; }
mkdir -p "$DST"
DRY=""; [ "${1:-}" = "--dry-run" ] && DRY="--dry-run"
# -a keeps modes and times; -H keeps hard links; --delete is NOT used:
# nothing is ever removed from the copy by this script.
rsync -aH $DRY --info=stats2,progress2 --exclude-from="$EXCL" "$SRC/" "$DST/"
echo
if [ -n "$DRY" ]; then
    echo "dry run: nothing copied. Run without --dry-run to copy."
else
    echo "copied into $DST"
    echo "next: bash build.sh, then bash run.sh"
fi
