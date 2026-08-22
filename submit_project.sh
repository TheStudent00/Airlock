#!/usr/bin/env bash
# Copy a whole directory into the sandbox and run something against it.
#
# The container has no view of your filesystem, so the project goes in as
# a COPY. The sandbox works on the snapshot; your originals cannot be
# touched by anything that runs in there.
#
# Usage:
#   ./submit_project.sh [--also <host-dir>] [--env KEY=VALUE] ... <host-dir> <command...>
#
# --also copies a SECOND directory in beside the first, for projects whose
# tests read from a co-located tree. Both land directly under /work, so a
# project that finds its companion by walking up its own path still does.
#
# Examples (any project directory works the same way):
#   ./submit_project.sh ~/code/MyProject pytest -q
#   ./submit_project.sh --also ~/code/MyProjectFixtures \
#                       ~/code/MyProject pytest Tools -q
#   ./submit_project.sh ~/code/MyOtherProject go test ./...
#
# The command runs with the FIRST directory as its working directory.
# Anything the command writes to /out comes back via ./pull.sh.
set -euo pipefail
cd "$(dirname "$0")"

ALSO=()
ENVS=()
while :; do
    case "${1:-}" in
      --also)
        shift
        d="${1:?--also needs a directory}"; shift
        [ -d "$d" ] || { echo "not a directory: $d" >&2; exit 1; }
        ALSO+=("${d%/}") ;;
      --env)
        shift
        e="${1:?--env needs KEY=VALUE}"; shift
        case "$e" in *=*) ENVS+=("$e") ;;
                      *) echo "--env wants KEY=VALUE, got: $e" >&2; exit 1 ;;
        esac ;;
      *) break ;;
    esac
done

SRC="${1:?usage: ./submit_project.sh [--also DIR]... <host-dir> <command...>}"; shift
[ $# -gt 0 ] || { echo "give a command to run in the project" >&2; exit 1; }
[ -d "$SRC" ] || { echo "not a directory: $SRC" >&2; exit 1; }
podman container exists sandbox-runner || { echo "sandbox-runner not running; ./up.sh first" >&2; exit 1; }

SRC="${SRC%/}"
NAME="$(basename "$SRC")"

copy_in() {
    local src="$1" name
    name="$(basename "$src")"
    echo "copying $src -> sandbox-runner:/work/$name"
    podman exec sandbox-runner rm -rf "/work/$name"
    podman cp "$src" "sandbox-runner:/work/$name"
    echo "  copied ($(podman exec sandbox-runner du -sh "/work/$name" | cut -f1))"
}

for d in ${ALSO+"${ALSO[@]}"}; do copy_in "$d"; done
copy_in "$SRC"
size=$(podman exec sandbox-runner du -sh "/work/$NAME" | cut -f1)

# Build a wrapper script. printf %q quotes each argument so a command with
# spaces or globs survives the trip intact.
WRAPPER=$(mktemp "/tmp/${NAME}_run_XXXX.sh")
{
    echo "#!/usr/bin/env bash"
    echo "set -o pipefail"
    echo "cd /work/$NAME || exit 1"
    for e in ${ENVS+"${ENVS[@]}"}; do
        printf 'export %q\n' "$e"
        echo "echo \"# env: $e\""
    done
    echo "echo \"# cwd: \$(pwd)\""
    echo "echo \"# cmd: $*\""
    echo "echo"
    printf '%q ' "$@"
    echo
    echo "rc=\$?"
    echo "echo"
    echo "echo \"# command exited \$rc\""
    echo "exit \$rc"
} > "$WRAPPER"

WNAME="$(basename "$WRAPPER")"
./submit.sh "$WRAPPER"
rm -f "$WRAPPER"

# ---- wait for it to finish, then save the log where it can be read ------
# The daemon writes a footer line ("# exit N in Ns" or "# KILLED ...") as
# the last thing it does, so the presence of that line means finished
# rather than still-running.
SAVE=DevComms/last_run.txt
mkdir -p DevComms
echo -n "running"
logname=""
for _ in $(seq 1 720); do   # up to 1 hour, matching the daemon's timeout
    logname=$(podman exec sandbox-runner sh -c \
        "ls -1 /logs 2>/dev/null | grep -F -- '$WNAME' | tail -1" || true)
    if [ -n "$logname" ] && podman exec sandbox-runner \
            grep -qE '^# (exit|KILLED)' "/logs/$logname" 2>/dev/null; then
        break
    fi
    echo -n "."
    sleep 5
done
echo

if [ -n "$logname" ]; then
    {
        echo "# last sandbox run — $(date -Iseconds)"
        echo "# project: $SRC  ($size copied to /work/$NAME)"
        echo "# command: $*"
        echo
        podman exec sandbox-runner cat "/logs/$logname"
        echo
        echo "## proxy refusals during/around this run"
        podman logs sandbox-proxy 2>&1 | grep -E 'DENIED' | tail -20 \
            || echo "  none"
    } > "$SAVE" 2>&1
    echo "saved -> $SAVE"
    echo "----------------------------------------------------------------"
    tail -n 40 "$SAVE"
    echo "----------------------------------------------------------------"
    echo
    echo "commit it if the session that submitted this cannot read the"
    echo "container directly:  git add -A && git commit -m \"run: $NAME\""
else
    echo "no log appeared for $WNAME — check ./logs.sh --daemon"
fi
echo
echo "results written to /out:  ./pull.sh ./results"
