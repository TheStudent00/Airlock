#!/usr/bin/env bash
# push_bundle.sh -- restore a bundle onto a remote machine over ssh, without
# the archives ever landing on that machine's disk.
#
#   bash push_bundle.sh --bundle <dir> --to <user@host> [--cpus N] [--memory Ng] [--up <instance>]...
#
# WHY THIS EXISTS BESIDE unpack.sh
#   unpack.sh restores a bundle the receiving machine can already see: a copy
#   on its disk, or a share mounted into it. When neither exists -- no
#   passthrough, no share, or simply not enough free space to hold the
#   archives beside what is restored from them -- this streams each archive
#   straight into podman on the far side. A 26 GB bundle then costs the
#   receiving machine only what it actually restores.
#
# The receiving machine needs what prepare_host.sh installs, and an ssh key
# already accepted: this script never handles a password.
set -euo pipefail
BUNDLE=""; TO=""; CPUS=""; MEM=""; UP=()
while [ $# -gt 0 ]; do
    case "$1" in
        --bundle) BUNDLE="$2"; shift 2 ;;
        --to) TO="$2"; shift 2 ;;
        --cpus) CPUS="$2"; shift 2 ;;
        --memory) MEM="$2"; shift 2 ;;
        --up) UP+=("$2"); shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done
[ -n "$BUNDLE" ] && [ -n "$TO" ] || { echo "usage: bash push_bundle.sh --bundle <dir> --to <user@host> [--cpus N] [--memory Ng] [--up <instance>]..." >&2; exit 2; }
BUNDLE="$(cd "$BUNDLE" && pwd)"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$TO")

say() { printf '%s\n' "$*"; }
say "== target =="
"${SSH[@]}" 'echo "  $(hostname), $(. /etc/os-release && echo "$PRETTY_NAME"), podman $(podman --version | cut -d" " -f3), $(df -h --output=avail / | tail -1 | xargs) free on /"'

TOOL_REL="$(cat "$BUNDLE/config/tool_path" 2>/dev/null || echo airlock)"
say
say "== 1/6 the tool =="
scp -o BatchMode=yes -q "$BUNDLE/airlock.bundle" "$TO:/tmp/airlock.bundle"
"${SSH[@]}" "set -e
    if [ -d \"\$HOME/$TOOL_REL/.git\" ]; then git -C \"\$HOME/$TOOL_REL\" fetch -q /tmp/airlock.bundle '+refs/heads/*:refs/remotes/bundle/*'
    else mkdir -p \"\$(dirname \"\$HOME/$TOOL_REL\")\"; git clone -q /tmp/airlock.bundle \"\$HOME/$TOOL_REL\"; fi
    mkdir -p \"\$HOME/$TOOL_REL\"/agent/{drop,out,logs,status}
    rm -f /tmp/airlock.bundle
    echo \"  tool at \$HOME/$TOOL_REL, head \$(git -C \"\$HOME/$TOOL_REL\" rev-parse --short HEAD)\""

say
say "== 2/6 images, streamed =="
for f in "$BUNDLE"/image_*.tar; do
    [ -f "$f" ] || continue
    say "  $(basename "$f")  $(du -h "$f" | cut -f1)"
    "${SSH[@]}" 'podman load' < "$f" | tail -1 | sed 's/^/    /'
done

say
say "== 3/6 volumes, streamed =="
for f in "$BUNDLE"/volume_*.tar; do
    [ -f "$f" ] || continue
    v="$(basename "$f" .tar)"; v="${v#volume_}"
    say "  $v  $(du -h "$f" | cut -f1)"
    "${SSH[@]}" "podman volume exists '$v' || podman volume create '$v' >/dev/null; podman volume import '$v' -" < "$f"
    say "    restored"
done

say
say "== 4/6 configuration =="
"${SSH[@]}" "mkdir -p \"\$HOME/$TOOL_REL/instances\" \"\$HOME/$TOOL_REL/proxy\""
scp -o BatchMode=yes -q "$BUNDLE"/config/instances/*.conf "$TO:\$HOME/$TOOL_REL/instances/" 2>/dev/null || true
[ -f "$BUNDLE/config/mounts.conf" ] && scp -o BatchMode=yes -q "$BUNDLE/config/mounts.conf" "$TO:\$HOME/$TOOL_REL/mounts.conf"
[ -f "$BUNDLE/config/proxy/allowlist.txt" ] && scp -o BatchMode=yes -q "$BUNDLE/config/proxy/allowlist.txt" "$TO:\$HOME/$TOOL_REL/proxy/allowlist.txt"
say "  $(ls "$BUNDLE"/config/instances/*.conf 2>/dev/null | wc -l) instance configurations, mounts file, allowlist"

say
say "== 5/6 projects, rsync =="
rsync -a --info=stats1 --exclude .packed_from_home -e "ssh -o BatchMode=yes" "$BUNDLE/projects/" "$TO:./" | sed 's/^/  /'

say
say "== 6/6 caps, absent mounts, and bring-up =="
"${SSH[@]}" "set -e
    cd \"\$HOME/$TOOL_REL\"
    if [ -n '$CPUS$MEM' ]; then
        for c in instances/*.conf; do
            [ -n '$CPUS' ] && sed -i -E 's/^(\s*cpus\s*=\s*)[0-9]+/\1$CPUS/' \"\$c\"
            [ -n '$MEM' ] && sed -i -E 's/^(\s*memory\s*=\s*)[0-9]+[gGmM]/\1$MEM/' \"\$c\"
        done
        echo \"  every instance configuration now: cpus=${CPUS:-unchanged} memory=${MEM:-unchanged}\"
    fi
    if [ -f mounts.conf ]; then
        n=0
        while IFS= read -r line; do
            case \"\$line\" in ''|'#'*) continue ;; esac
            host=\"\${line%%:*}\"; expanded=\"\${host/#\~/\$HOME}\"
            if [ ! -e \"\$expanded\" ]; then
                sed -i \"s|^\$(printf '%s' \"\$line\" | sed 's/[|.*^\$]/\\\\\\\\&/g')|# NOT ON THIS MACHINE, commented out by push_bundle.sh: &|\" mounts.conf
                echo \"  mount not here, commented out: \$host\"; n=\$((n+1))
            fi
        done < mounts.conf
        [ \"\$n\" -gt 0 ] && echo \"  \$n mount(s) absent; re-pack one if a task needs it\"
    fi
    true"
if [ ${#UP[@]} -gt 0 ]; then
    for i in "${UP[@]}"; do
        if [ "$i" = sandbox ]; then "${SSH[@]}" "cd \"\$HOME/$TOOL_REL\" && bash ./up.sh"
        else "${SSH[@]}" "cd \"\$HOME/$TOOL_REL\" && bash ./up.sh --instance '$i'"; fi
    done
else
    say "  nothing started. Start one with:  ssh $TO 'cd ~/$TOOL_REL && bash ./up.sh'"
fi
say
say "done."
