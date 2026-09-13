#!/usr/bin/env bash
# devbox: mount the plain view (after a reboot or an unmount).
set -euo pipefail
ENC="${DEVBOX_ENC:-$HOME/DevboxEnc}"
MNT="${DEVBOX_MNT:-$HOME/DevboxMount}"
KEY="${DEVBOX_KEY:-$HOME/.config/devbox/key}"
mkdir -p "$MNT"
if mountpoint -q "$MNT"; then echo "already mounted at $MNT"; exit 0; fi
gocryptfs -passfile "$KEY" -q "$ENC" "$MNT"
echo "mounted: $MNT"
