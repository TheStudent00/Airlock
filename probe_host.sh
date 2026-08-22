#!/usr/bin/env bash
# Inventory the host machine so a sandboxed session can see what is
# installed. The sandbox has no view of your filesystem beyond what
# mounts.conf exposes, so it cannot run this itself.
#
# Writes DevComms/host_inventory.txt inside this repo, which a session
# with this repo attached CAN read. That file is gitignored: it is a
# record of one machine, not part of the tool.
#
# Safe: reads only. Installs nothing, changes nothing.
#
# Usage:  ./probe_host.sh

# This repo, wherever it has been cloned. No machine's layout is assumed.
REPO="$(cd "$(dirname "$0")" && pwd)"
OUT="$REPO/DevComms/host_inventory.txt"
mkdir -p "$REPO/DevComms"
: > "$OUT"

say() { printf '%s\n' "$*" >> "$OUT"; }

say "# host inventory — generated $(date -Iseconds)"
say ""

say "## system"
say "kernel:   $(uname -srm)"
say "distro:   $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
say "cpu:      $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
say "cores:    $(nproc)"
say "memory:   $(free -h | awk '/^Mem:/{print $2}')"
say "disk (/): $(df -h / | awk 'NR==2{print $4" free of "$2}')"
say ""

say "## cpu security features (relevant to shadow stack / CFI discussion)"
for f in user_shstk ibt smep smap ibrs stibp ssbd sev sme; do
    grep -qw "$f" /proc/cpuinfo && say "  present: $f"
done
say ""

say "## container runtime"
for c in podman buildah skopeo crun runc docker; do
    p=$(command -v "$c" 2>/dev/null) || continue
    say "  $c -> $p  [$("$c" --version 2>/dev/null | head -1)]"
done
say "  rootless subuid: $(grep "^$USER:" /etc/subuid 2>/dev/null || echo 'NONE — rootless podman will not work')"
say "  rootless subgid: $(grep "^$USER:" /etc/subgid 2>/dev/null || echo 'NONE')"
say "  cgroups v2:      $([ -f /sys/fs/cgroup/cgroup.controllers ] && echo yes || echo no)"
say "  unpriv userns:   $(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo 'n/a (enabled by default)')"
say ""

say "## toolchains"
# command -v NAME prints the full path of NAME if the shell can run it,
# and exits nonzero if it cannot. POSIX-standard replacement for `which`.
probe() {
    local c="$1"; shift
    local p; p=$(command -v "$c" 2>/dev/null) || return
    local v; v=$("$c" "$@" 2>&1 | grep -m1 . )   # first NON-BLANK line (perl -v starts blank)
    say "  $c -> $p  [$v]"
}
probe python3 --version
probe pip --version
probe pipx --version
probe uv --version
probe conda --version
probe go version
probe rustc --version
probe cargo --version
probe rustup --version
probe dart --version
probe flutter --version
probe haxe --version
probe haxelib version
probe neko -version
probe node --version
probe npm --version
probe pnpm --version
probe yarn --version
probe deno --version
probe bun --version
probe tsc --version
probe java -version
probe javac -version
probe kotlinc -version
probe scala -version
probe mvn --version
probe gradle --version
probe sbt --version
probe gcc --version
probe g++ --version
probe clang --version
probe make --version
probe cmake --version
probe ninja --version
probe meson --version
probe pkg-config --version
probe git --version
probe gh --version
probe ruby --version
probe perl --version
probe php --version
probe lua -v
probe zig version
probe nim --version
probe ocaml -version
probe ghc --version
probe cabal --version
probe julia --version
probe Rscript --version
probe swift --version
probe dotnet --version
probe emcc --version
probe adb --version
say ""

say "## sdk directories that often exist without a command on PATH"
for d in ~/Android ~/Android/Sdk ~/.sdkman ~/.rustup ~/.cargo ~/flutter \
         ~/.pub-cache ~/haxe ~/.haxelib /opt/flutter /opt/haxe \
         /usr/lib/jvm /usr/lib/android-sdk; do
    [ -e "$d" ] && say "  exists: $d"
done
say ""

say "## file-search tooling (from the index discussion)"
for c in plocate locate updatedb fd fdfind rg tracker3 tracker; do
    p=$(command -v "$c" 2>/dev/null) && say "  $c -> $p"
done
say ""

say "## apt packages matching common toolchain names"
if command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W -f='${Package}\n' 2>/dev/null \
      | grep -Ei '^(gcc|g\+\+|clang|llvm|golang|rust|python3|openjdk|kotlin|nodejs|dart|haxe|neko|podman|buildah|crun|inotify-tools|plocate)' \
      | sort | sed 's/^/  /' >> "$OUT"
fi

echo "wrote $OUT"
echo
echo "Review it. It is gitignored - it describes this machine, not the tool."
