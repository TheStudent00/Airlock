#!/usr/bin/env bash
# devbox entrypoint: start the repo-daemon in the background (a container
# has no systemd), then hand over to the command (a shell by default).
set -u
DAEMON="$HOME/Programming/PRIVATE/RepoDaemon/repo_daemon.py"
if [ -f "$DAEMON" ] && [ -z "${DEVBOX_NO_DAEMON:-}" ]; then
    mkdir -p "$HOME/.local/state/repo-daemon"
    nohup python3 "$DAEMON" run >> "$HOME/.local/state/repo-daemon/devbox.log" 2>&1 &
    echo "repo-daemon started inside devbox (log: ~/.local/state/repo-daemon/devbox.log)"
fi
exec "$@"
