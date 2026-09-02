#!/usr/bin/env bash
# Capture the sandbox's actual state into DevComms/sandbox_report.txt so
# an agent session that cannot run podman can read it, instead of anyone
# pasting terminal output by hand.
#
# Runs selftest.sh and records its result alongside container status,
# image sizes, the daemon's own log, and anything the proxy refused.
#
# Usage:  ./report.sh [--instance NAME]
#
# The file is named per instance, so two instances never overwrite each
# other's report.
set -uo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"

OUT="DevComms/${AL_INSTANCE}_report.txt"
mkdir -p DevComms

{
  echo "# sandbox report — instance $AL_INSTANCE — $(date -Iseconds)"
  echo "#   runner $AL_RUNNER  proxy $AL_PROXY  agent $AL_AGENT_DIR"
  echo

  echo "## podman version"
  podman --version 2>&1 | sed 's/^/  /'
  echo

  echo "## images"
  podman images --filter reference="${AL_RUNNER_IMAGE%%:*}" --filter reference="${AL_PROXY_IMAGE%%:*}" \
      --format '  {{.Repository}}:{{.Tag}}  {{.Size}}  created {{.CreatedSince}}' 2>&1
  echo

  echo "## containers"
  podman ps -a --filter "name=^${AL_INSTANCE}-" \
      --format '  {{.Names}}  {{.Status}}  {{.Networks}}' 2>&1
  echo

  echo "## networks"
  podman network ls --format '  {{.Name}}  {{.Driver}}' 2>&1
  for n in "$AL_NET_INTERNAL" "$AL_NET_EGRESS"; do
      internal=$(podman network inspect "$n" --format '{{.Internal}}' 2>/dev/null)
      [ -n "$internal" ] && echo "  $n internal=$internal"
  done
  echo

  echo "## volumes — /logs and /out must be named volumes, or a restart discards them"
  podman volume ls --format '  volume: {{.Name}}  {{.Mountpoint}}' 2>&1
  if podman container exists "$AL_RUNNER"; then
      echo "  mounts inside $AL_RUNNER:"
      podman inspect "$AL_RUNNER" \
          --format '{{range .Mounts}}    {{.Type}}  {{.Name}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>&1
      for d in /logs /out; do
          n=$(podman exec "$AL_RUNNER" sh -c "ls -1 $d 2>/dev/null | wc -l")
          echo "  $d holds $n entries"
      done
  fi
  echo

  echo "## systemd (quadlet) — present only if ./install_quadlet.sh was run"
  UNITDIR="$HOME/.config/containers/systemd"
  if [ -d "$UNITDIR" ] && ls "$UNITDIR"/${AL_INSTANCE}-* >/dev/null 2>&1; then
      ls -1 "$UNITDIR" | sed 's/^/  unit file: /'
      for u in "$AL_PROXY" "$AL_RUNNER"; do
          state=$(systemctl --user is-active "$u.service" 2>&1)
          enabled=$(systemctl --user is-enabled "$u.service" 2>&1)
          echo "  $u.service  active=$state  enabled=$enabled"
      done
      echo "  lingering: $(loginctl show-user "$USER" --property=Linger 2>&1)"
      echo "  --- last 10 journal lines, $AL_RUNNER ---"
      journalctl --user -u "$AL_RUNNER" --no-pager -n 10 2>&1 | sed 's/^/    /'
  else
      echo "  not installed — containers are running from ./up.sh"
  fi
  echo

  echo "## selftest"
  if podman container exists "$AL_RUNNER"; then
      ./selftest.sh --instance "$AL_INSTANCE" 2>&1 | sed 's/^/  /'
      echo "  (selftest exit: ${PIPESTATUS[0]})"
  else
      echo "  SKIPPED — $AL_RUNNER does not exist. Run ./up.sh --instance $AL_INSTANCE first."
  fi
  echo

  echo "## daemon log (last 40 lines)"
  podman logs --tail 40 "$AL_RUNNER" 2>&1 | sed 's/^/  /' \
      || echo "  unavailable"
  echo

  echo "## proxy refusals (undeclared hostnames the runner reached for)"
  podman logs "$AL_PROXY" 2>&1 | grep -E 'DENIED' | tail -20 | sed 's/^/  /' \
      || echo "  none logged"
  echo

  echo "## toolchain versions INSIDE the runner"
  if podman container exists "$AL_RUNNER"; then
      podman exec "$AL_RUNNER" bash -lc '
        # go takes "version", not "--version"; everything else takes --version
        for c in python python3 python3.13 pip uv rustc cargo node npm javac gcc clang clang++ cmake ninja git rg fd plocate; do
          p=$(command -v "$c" 2>/dev/null) || { echo "  MISSING  $c"; continue; }
          echo "  $c -> $p  [$("$c" --version 2>&1 | grep -m1 .)]"
        done
        p=$(command -v go 2>/dev/null) && echo "  go -> $p  [$(go version)]" || echo "  MISSING  go"' 2>&1
  else
      echo "  SKIPPED — $AL_RUNNER not running"
  fi
} > "$OUT" 2>&1

echo "wrote $OUT"
echo
tail -n 30 "$OUT"
echo
echo "$OUT is gitignored: it records one machine's"
echo "real state. Read it in place, or copy it where it is needed."
