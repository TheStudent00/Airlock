#!/usr/bin/env bash
# devbox: stop the container if it runs, then unmount the plain view.
# The cipher directory stays; nothing is deleted here, ever.
set -euo pipefail
MNT="${DEVBOX_MNT:-$HOME/DevboxMount}"
if podman ps --format '{{.Names}}' | grep -qx devbox; then
    podman stop devbox >/dev/null && echo "container devbox stopped"
fi
if mountpoint -q "$MNT"; then
    fusermount -u "$MNT" && echo "unmounted: $MNT"
else
    echo "not mounted: $MNT"
fi
