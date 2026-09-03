#!/usr/bin/env bash
# THE ONE PLACE AN INSTANCE'S NAMES AND CAPS ARE DERIVED.
#
# WHAT AN INSTANCE IS
#   An instance is one running sandbox: its own runner container, its own
#   proxy, its own networks, its own agent lane, its own caps. Airlock is
#   an application, not a template to be copied per project — so a project
#   that needs a second sandbox beside the default one asks for an
#   instance, it does not clone this repo.
#
#   Every container, network, volume and systemd unit name is DERIVED from
#   the instance name, here, and nowhere else. No script below spells a
#   literal `sandbox-runner`.
#
# THE DEFAULT INSTANCE IS `sandbox`
#   With no instance named, the derived names are exactly the names Airlock
#   has always used — `sandbox-runner`, `sandbox-proxy`, `sandbox-internal`,
#   `sandbox-egress`, `sandbox-persist` — and every default below is the
#   value that was hardcoded before instances existed. An install that never
#   names an instance behaves identically.
#
# HOW AN INSTANCE IS NAMED, in precedence order
#   1. `--instance <name>` on any script or on the `airlock` command
#   2. the AIRLOCK_INSTANCE environment variable
#   3. `sandbox`
#
# WHERE AN INSTANCE'S SETTINGS LIVE
#   `instances/<name>.conf`, one `key = value` per line, `#` comments.
#   The file is OPTIONAL: every key falls back to the built-in default,
#   which is the pre-instance hardcoded value. The file is per-machine and
#   gitignored, exactly like `mounts.conf`. See `instances/sandbox.conf.example`.
#
# USAGE FROM A SCRIPT
#   source "$(dirname "$0")/instance.sh"
#   airlock_parse_instance "$@"; set -- "${AIRLOCK_ARGV[@]}"
#   airlock_instance_load
#   ... then use $AL_RUNNER, $AL_CPUS, and the rest.

# ---- 1. the instance name -------------------------------------------------

# airlock_parse_instance ARGS...
#   Strips `--instance <name>` (and `--instance=<name>`) out of the argument
#   list, sets AIRLOCK_INSTANCE from it, and leaves everything else in the
#   array AIRLOCK_ARGV for the caller to restore with `set --`.
airlock_parse_instance() {
    AIRLOCK_ARGV=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --instance)
                if [ $# -lt 2 ]; then
                    echo "REFUSE: --instance needs a name" >&2
                    return 2
                fi
                AIRLOCK_INSTANCE="$2"
                shift 2
                ;;
            --instance=*)
                AIRLOCK_INSTANCE="${1#--instance=}"
                shift
                ;;
            *)
                AIRLOCK_ARGV+=("$1")
                shift
                ;;
        esac
    done
    export AIRLOCK_INSTANCE
    return 0
}

# ---- 2. reading one key out of the instance's conf file -------------------

# _airlock_conf_get FILE KEY -> the value, or empty.
#   Format is `key = value`. Whitespace around either side is dropped, a
#   `#` starts a comment, and the LAST assignment of a key wins so a file
#   can be appended to.
_airlock_conf_get() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 0
    local line
    local found=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        case "$line" in
            *=*) ;;
            *) continue ;;
        esac
        local k="${line%%=*}"
        local v="${line#*=}"
        k="$(echo "$k" | xargs)"
        v="$(echo "$v" | xargs)"
        [ "$k" = "$key" ] || continue
        found="$v"
    done < "$file"
    printf '%s' "$found"
}

# _airlock_abs PATH ROOT -> PATH made absolute.
#   `~` expands to the home directory; a relative path is taken as relative
#   to the Airlock root, so a conf file may say `mounts.conf` and mean the
#   one beside it.
_airlock_abs() {
    local p="$1"
    local root="$2"
    p="${p/#\~/$HOME}"
    case "$p" in
        /*) printf '%s' "$p" ;;
        *) printf '%s/%s' "$root" "$p" ;;
    esac
}

# _airlock_pick VALUE_FROM_CONF DEFAULT -> the first that is non-empty.
_airlock_pick() {
    if [ -n "${1:-}" ]; then
        printf '%s' "$1"
    else
        printf '%s' "${2:-}"
    fi
}

# ---- 3. the load ----------------------------------------------------------

# airlock_instance_load [ROOT]
#   ROOT defaults to the directory this file lives in. Sets every AL_* below.
airlock_instance_load() {
    AL_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    AL_INSTANCE="${AIRLOCK_INSTANCE:-sandbox}"

    case "$AL_INSTANCE" in
        *[!a-zA-Z0-9_-]*|"")
            echo "REFUSE: instance name '$AL_INSTANCE' is not [A-Za-z0-9_-]+" >&2
            return 2
            ;;
    esac

    AL_CONF="$AL_ROOT/instances/$AL_INSTANCE.conf"

    # --- the derived names. THIS IS THE ONLY PLACE THEY ARE SPELLED. ---
    AL_RUNNER="$AL_INSTANCE-runner"
    AL_PROXY="$AL_INSTANCE-proxy"
    AL_NET_INTERNAL="$AL_INSTANCE-internal"
    AL_NET_EGRESS="$AL_INSTANCE-egress"
    AL_UNIT_PREFIX="$AL_INSTANCE"

    # --- the agent lane -------------------------------------------------
    # The default instance keeps `<root>/agent`, unchanged. Any other
    # instance gets its own tree so two instances never share a drop
    # folder — one derivation rule, not a per-name special case.
    #
    # A non-default instance's tree lives OUTSIDE the checkout, at
    # $HOME/AirlockRuns/<name>/agent (ruled 2026-09-02). A drop/status/logs/
    # out tree is a RUN RECORD, not a tool file: keeping it out of the
    # checkout means no ignore rule is load-bearing, and a commit daemon
    # walking the checkout never sees a run's products at all. `up.sh`
    # creates it. The `agent_dir` key overrides this for any instance.
    local default_agent
    if [ "$AL_INSTANCE" = "sandbox" ]; then
        default_agent="$AL_ROOT/agent"
    else
        default_agent="$HOME/AirlockRuns/$AL_INSTANCE/agent"
    fi
    AL_AGENT_DIR="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" agent_dir)" "$default_agent")"
    AL_AGENT_DIR="$(_airlock_abs "$AL_AGENT_DIR" "$AL_ROOT")"

    # --- images ---------------------------------------------------------
    # The image is a BUILD ARTIFACT, not instance state: a second instance
    # reuses the image the first one built, so no instance ever forces a
    # rebuild. Override per instance only if you built a different image.
    AL_RUNNER_IMAGE="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" runner_image)" "sandbox-runner:latest")"
    AL_PROXY_IMAGE="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" proxy_image)" "sandbox-proxy:latest")"

    # --- the persist volume ---------------------------------------------
    AL_PERSIST="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" persist_volume)" "$AL_INSTANCE-persist")"
    AL_PERSIST_MODE="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" persist_mode)" "rw")"
    [ "$AL_PERSIST_MODE" = "ro" ] || AL_PERSIST_MODE="rw"

    # --- caps -----------------------------------------------------------
    # cpus precedence: --cpus on up.sh (the caller sets AIRLOCK_CPUS_FLAG),
    # then AIRLOCK_CPUS, then the older SANDBOX_CPUS, then the conf file,
    # then 6 — the full share, ruled 2026-08-22.
    AL_CPUS="${AIRLOCK_CPUS_FLAG:-${AIRLOCK_CPUS:-${SANDBOX_CPUS:-}}}"
    AL_CPUS="$(_airlock_pick "$AL_CPUS" "$(_airlock_conf_get "$AL_CONF" cpus)")"
    AL_CPUS="$(_airlock_pick "$AL_CPUS" "6")"

    AL_MEMORY="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" memory)" "12g")"
    AL_PIDS="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" pids_limit)" "2048")"
    AL_TMP_SIZE="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" tmp_size)" "2g")"
    AL_WORK_SIZE="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" work_size)" "4g")"

    AL_PROXY_MEMORY="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" proxy_memory)" "512m")"
    AL_PROXY_CPUS="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" proxy_cpus)" "1")"
    AL_PROXY_PIDS="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" proxy_pids_limit)" "256")"

    # --- the egress gate -------------------------------------------------
    # `proxy = no` means: no proxy container, no egress network, no route
    # out at all. The runner still sits on its own --internal network.
    AL_USE_PROXY="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" proxy)" "yes")"
    case "$AL_USE_PROXY" in
        no|off|false|0) AL_USE_PROXY="no" ;;
        *) AL_USE_PROXY="yes" ;;
    esac

    # --- per-machine files -----------------------------------------------
    AL_MOUNTS_FILE="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" mounts_file)" "$AL_ROOT/mounts.conf")"
    AL_MOUNTS_FILE="$(_airlock_abs "$AL_MOUNTS_FILE" "$AL_ROOT")"
    AL_ALLOWLIST="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" allowlist_file)" "$AL_ROOT/proxy/allowlist.txt")"
    AL_ALLOWLIST="$(_airlock_abs "$AL_ALLOWLIST" "$AL_ROOT")"

    # --- what the daemon inside the runner is told ------------------------
    AL_LANE_NICE="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" lane_nice)" "15")"
    AL_SCRIPT_TIMEOUT="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" script_timeout)" "3600")"
    # `watch = inotify` (the default) or `watch = poll`. See daemon/watcher.py:
    # poll exists for a machine that has run out of inotify INSTANCES, which
    # is a per-user kernel limit (/proc/sys/fs/inotify/max_user_instances)
    # and is nothing to do with disk space, despite the ENOSPC it reports.
    #
    # There was a `daemon_file` key here until 2026-09-02: it bound a host
    # file read-only over the image's /opt/daemon/watcher.py, so a daemon
    # change could reach a running instance before a rebuild. It was
    # documented as a bridge to be dropped after the next build.sh; that
    # build has happened and the key is gone. A daemon change is a
    # Containerfile-level change and reaches instances through build.sh.
    AL_WATCH="$(_airlock_pick "$(_airlock_conf_get "$AL_CONF" watch)" "inotify")"
    case "$AL_WATCH" in
        poll|polling) AL_WATCH="poll" ;;
        *) AL_WATCH="inotify" ;;
    esac

    export AL_ROOT AL_INSTANCE AL_CONF
    export AL_RUNNER AL_PROXY AL_NET_INTERNAL AL_NET_EGRESS AL_UNIT_PREFIX
    export AL_AGENT_DIR AL_RUNNER_IMAGE AL_PROXY_IMAGE
    export AL_PERSIST AL_PERSIST_MODE
    export AL_CPUS AL_MEMORY AL_PIDS AL_TMP_SIZE AL_WORK_SIZE
    export AL_PROXY_MEMORY AL_PROXY_CPUS AL_PROXY_PIDS AL_USE_PROXY
    export AL_MOUNTS_FILE AL_ALLOWLIST
    export AL_LANE_NICE AL_SCRIPT_TIMEOUT AL_WATCH AL_DAEMON_FILE
    return 0
}

# airlock_instance_list -> one instance name per line.
#   Every `instances/*.conf` on disk, plus `sandbox`, which always exists
#   because its every setting has a built-in default.
airlock_instance_list() {
    local root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    {
        echo "sandbox"
        local f
        for f in "$root"/instances/*.conf; do
            [ -e "$f" ] || continue
            local b
            b="$(basename "$f")"
            echo "${b%.conf}"
        done
    } | sort -u
}

# airlock_instance_banner -> the one line every script prints so a reader
# always knows which instance an output belongs to.
airlock_instance_banner() {
    echo "  instance: $AL_INSTANCE   runner: $AL_RUNNER   agent: $AL_AGENT_DIR"
}
