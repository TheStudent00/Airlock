#!/usr/bin/env bash
# remote_lane.sh -- drive an Airlock install on ANOTHER machine from this one,
# over ssh, with the same lane protocol: submit a lane, wait for it, read its
# log, and mirror a working folder in both directions around it.
#
#   export AIRLOCK_REMOTE=<user@host>            or pass --to
#   export AIRLOCK_REMOTE_ROOT=<path under the remote home to the tool>   or pass --airlock
#
#   bash remote_lane.sh [--to U@H] [--airlock REL] <command> ...
#
#   sync-to   <rel-dir>                        this machine's $HOME/<rel-dir>/ -> remote, newer wins, nothing deleted
#   sync-back <rel-dir>                        remote <rel-dir>/ -> this machine's $HOME/<rel-dir>/, newer wins, nothing deleted
#   conf      <local instances/NAME.conf>      copy one instance configuration to the remote install
#   up        --instance I                     remote up.sh --instance I
#   down      --instance I                     remote down.sh --instance I
#   submit    --instance I --batch B --weight W <local lane.sh>
#                                              copy the lane, then the remote CLI's submit
#   status    --instance I [lane.sh]           the remote CLI's status
#   wait      --instance I <lane.sh> [--timeout S]
#                                              poll the lane's status file until state=done, at most S seconds (default 100:
#                                              an agent's tool call is cut at 120 s and moved to the background, and the
#                                              agent then loses the wait — so repeat short waits, never one long one)
#   log       --instance I <lane.sh>           print the newest log for that lane
#
# The lane's ARTIFACTS are whatever the lane wrote under the remote copy of
# the project; sync-back brings them here. The lane SCRIPT is kept on this
# machine, in the repo, as the standing rule requires; the copy on the far
# side is a working copy.
set -euo pipefail
TO="${AIRLOCK_REMOTE:-}"; ROOT="${AIRLOCK_REMOTE_ROOT:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --to) TO="$2"; shift 2 ;;
        --airlock) ROOT="$2"; shift 2 ;;
        *) break ;;
    esac
done
[ -n "$TO" ] && [ -n "$ROOT" ] || { echo "need --to <user@host> (or AIRLOCK_REMOTE) and --airlock <rel path> (or AIRLOCK_REMOTE_ROOT)" >&2; exit 2; }
CMD="${1:-}"; shift || true
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$TO")
RSYNC_SSH="ssh -o BatchMode=yes"

need_instance() { [ -n "${INSTANCE:-}" ] || { echo "--instance is required" >&2; exit 2; }; }
agent_dir() {   # the remote agent tree for an instance, as up.sh derives it
    if [ "$1" = sandbox ]; then echo "$ROOT/agent"; else echo "AirlockRuns/$1/agent"; fi
}
parse_instance() {
    INSTANCE=""; BATCH=""; WEIGHT=""; TIMEOUT=100; REST=()   # wait: at most 100 s per call; an agent tool moves a longer call to the background and the caller loses it
    while [ $# -gt 0 ]; do
        case "$1" in
            --instance) INSTANCE="$2"; shift 2 ;;
            --batch) BATCH="$2"; shift 2 ;;
            --weight) WEIGHT="$2"; shift 2 ;;
            --timeout) TIMEOUT="$2"; shift 2 ;;
            *) REST+=("$1"); shift ;;
        esac
    done
}

case "$CMD" in
    sync-to)
        rel="${1:?rel-dir}"; "${SSH[@]}" "mkdir -p '$rel'"
        rsync -au --info=stats1 -e "$RSYNC_SSH" "$HOME/$rel/" "$TO:$rel/" | grep -E "^Number of (regular files transferred|created)|^Total transferred" | sed 's/^/  /' ;;
    sync-back)
        rel="${1:?rel-dir}"; mkdir -p "$HOME/$rel"
        rsync -au --info=stats1 -e "$RSYNC_SSH" "$TO:$rel/" "$HOME/$rel/" | grep -E "^Number of (regular files transferred|created)|^Total transferred" | sed 's/^/  /' ;;
    conf)
        f="${1:?instances/NAME.conf}"; scp -o BatchMode=yes -q "$f" "$TO:$ROOT/instances/$(basename "$f")"; echo "  $(basename "$f") in place on $TO" ;;
    up)
        parse_instance "$@"; need_instance
        if [ "$INSTANCE" = sandbox ]; then "${SSH[@]}" "cd '$ROOT' && bash ./up.sh"; else "${SSH[@]}" "cd '$ROOT' && bash ./up.sh --instance '$INSTANCE'"; fi ;;
    down)
        parse_instance "$@"; need_instance
        "${SSH[@]}" "cd '$ROOT' && bash ./down.sh --instance '$INSTANCE'" ;;
    submit)
        parse_instance "$@"; need_instance
        lane="${REST[0]:?lane.sh}"; [ -f "$lane" ] || { echo "no such lane: $lane" >&2; exit 2; }
        "${SSH[@]}" "mkdir -p '$ROOT/.remote_lanes'"
        scp -o BatchMode=yes -q "$lane" "$TO:$ROOT/.remote_lanes/$(basename "$lane")"
        args=(--instance "$INSTANCE" submit ".remote_lanes/$(basename "$lane")")   # relative to the remote tool root, which the ssh command cds into
        [ -n "$BATCH" ] && args+=(--batch "$BATCH") || args+=(--no-batch)
        [ -n "$WEIGHT" ] && args+=(--weight "$WEIGHT")
        "${SSH[@]}" "cd '$ROOT' && python3 ./airlock $(printf '%q ' "${args[@]}")" ;;
    status)
        parse_instance "$@"; need_instance
        "${SSH[@]}" "cd '$ROOT' && python3 ./airlock --instance '$INSTANCE' status ${REST[0]:+$(basename "${REST[0]}")}" ;;
    wait)
        parse_instance "$@"; need_instance
        lane="$(basename "${REST[0]:?lane.sh}")"; A="$(agent_dir "$INSTANCE")"
        echo "  waiting on $lane (instance $INSTANCE, up to ${TIMEOUT}s)"
        "${SSH[@]}" "t=0; until grep -q '^state=done' '$A/status/$lane.status' 2>/dev/null; do sleep 15; t=\$((t+15)); [ \$t -ge $TIMEOUT ] && { echo '  TIMEOUT: still running'; exit 3; }; done
            grep -E '^(exit|elapsed_s|work_consumed_mb|verdict)=' '$A/status/$lane.status' | sed 's/^/  /'
            echo '  ---- log ----'; cat \"\$(ls -t '$A/logs/'*__$lane.log | head -1)\"" || { rc=$?; [ $rc -eq 3 ] && echo "  (still running: call wait again; progress: $("${SSH[@]}" "grep -o '\[[0-9]*/[0-9]*\]' \"\$(ls -t '$A/logs/'*__$lane.log 2>/dev/null | head -1)\" 2>/dev/null | tail -1")"; exit $rc; } ;;
    log)
        parse_instance "$@"; need_instance
        lane="$(basename "${REST[0]:?lane.sh}")"; A="$(agent_dir "$INSTANCE")"
        "${SSH[@]}" "cat \"\$(ls -t '$A/logs/'*__$lane.log | head -1)\"" ;;
    *) sed -n 2,30p "$0"; exit 2 ;;
esac
