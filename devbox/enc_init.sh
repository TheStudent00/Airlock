#!/usr/bin/env bash
# devbox: create the encrypted store (gocryptfs) and mount its plain view.
#   ~/DevboxEnc          cipher directory (what the disk holds)
#   ~/DevboxMount        plain view (only while mounted)
#   ~/.config/devbox/key passphrase file, mode 600, never inside a repo
set -euo pipefail
ENC="${DEVBOX_ENC:-$HOME/DevboxEnc}"
MNT="${DEVBOX_MNT:-$HOME/DevboxMount}"
KEY="${DEVBOX_KEY:-$HOME/.config/devbox/key}"

if ! command -v gocryptfs >/dev/null; then
    echo "installing gocryptfs (needs sudo once)"
    sudo apt-get install -y gocryptfs
fi
mkdir -p "$ENC" "$MNT" "$(dirname "$KEY")"
if [ ! -s "$KEY" ]; then
    umask 077
    head -c 48 /dev/urandom | base64 | tr -d '\n' > "$KEY"
    chmod 600 "$KEY"
    echo "key written to $KEY (mode 600). BACK IT UP outside this machine:"
    echo "  without it the cipher directory is unreadable, by design."
fi
if [ ! -f "$ENC/gocryptfs.conf" ]; then
    gocryptfs -init -passfile "$KEY" -q "$ENC"
    echo "cipher directory initialised at $ENC"
fi
if mountpoint -q "$MNT"; then
    echo "already mounted at $MNT"
else
    gocryptfs -passfile "$KEY" -q "$ENC" "$MNT"
    echo "mounted: $MNT (plain view of $ENC)"
fi
mkdir -p "$MNT/Programming"
echo "next: bash copy.sh --dry-run"
