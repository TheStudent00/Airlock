#!/usr/bin/env bash
# Show progress for EVERY lane: queued, running (with its latest progress
# line), and recently finished.  Answers "can I see progress?" without
# knowing which log file is newest.
#
# If agent/batch.json is present (see batch.sh), a short summary block is
# printed FIRST: overall completion by weight across the whole batch, plus
# the current lane's own percentage and a per-lane ETA. All of the detail
# below is unchanged either way. With no manifest, this prints one note
# and otherwise behaves exactly as it always has.
#
# Usage:
#   bash <airlock>/progress.sh          one snapshot
#   bash <airlock>/progress.sh -w       refresh every 2 s
#   bash <airlock>/progress.sh --instance trickle [-w]
#                                       a different instance; default `sandbox`
set -uo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"

DROP="$AL_AGENT_DIR/drop"
LOGS="$AL_AGENT_DIR/logs"
STATUS="$AL_AGENT_DIR/status"
BATCH_JSON="$AL_AGENT_DIR/batch.json"

# ---- other instances ------------------------------------------------------
#
# Measured 2026-09-03: "what is running and why cant i see it in Airlock
# status?" By the round-11 ruling every task runs in its own instance, so
# a busy OTHER instance is invisible from the default view unless this is
# printed. See airlock_other_busy_instances in instance.sh — it reuses
# airlock_instance_list for discovery and airlock_instance_load for each
# instance's agent tree, so this never re-derives either.
print_other_instances() {
  local busy
  busy=$(airlock_other_busy_instances "$AL_ROOT" "$AL_INSTANCE")
  if [ -n "$busy" ]; then
    echo "== other instances busy =="
    echo "$busy" | sed 's/^/  /'
    echo "  (this view is instance '$AL_INSTANCE' — bash $0 --instance <name> [-w])"
    echo
  fi
}

# ---- batch summary --------------------------------------------------------
#
# agent/batch.json (written by batch.sh, BEFORE lanes are dropped) records
# a label, a created timestamp, and one weight per lane — probe count or any
# comparable unit, so a big lane and a tiny lane are not counted equally.
# Everything here is read-only and best-effort: a missing or malformed
# manifest degrades to a one-line note, never an error.
#
# The parser below expects each lane as ONE line, e.g.
#   { "script": "a2_verify.sh", "weight": 40 },
# which is exactly what batch.sh writes. Hand-edited JSON that wraps a lane
# across multiple lines will not be read correctly, but will not error
# either — it just will not contribute to the summary.

# fmt_hms SECONDS -> "H:MM:SS", or "n/a" for "", "NA", or non-numeric input.
fmt_hms() {
  local s="${1:-}"
  case "$s" in
    ''|NA) echo "n/a"; return ;;
    *[!0-9]*) echo "n/a"; return ;;
  esac
  local h=$((s / 3600)) m=$(((s % 3600) / 60)) sec=$((s % 60))
  printf '%02d:%02d:%02d' "$h" "$m" "$sec"
}

# fmt_weight VALUE -> integer if it is one, else 2 decimals.
fmt_weight() {
  awk -v v="${1:-0}" 'BEGIN{ if (v == int(v)) printf "%d", v; else printf "%.2f", v }' 2>/dev/null \
    || echo "${1:-0}"
}

# compute_pct_eta DONE TOTAL ELAPSED_S -> "PCT ETA_S" (ETA_S is NA if there
# is not enough data: nothing done yet, or under 5s of elapsed time, which
# is too little to trust a rate). This is the one throughput calc, reused
# for both the overall batch and the current lane — same formula, same
# honesty rule, in one place.
compute_pct_eta() {
  awk -v d="${1:-0}" -v t="${2:-0}" -v e="${3:-}" 'BEGIN{
    if (t+0 <= 0) { pct = "0.0" } else { pct = sprintf("%.1f", (d/t)*100) }
    if (e == "" || e+0 < 5 || d+0 <= 0) { eta = "NA" }
    else {
      rate = d/e
      rem = t-d; if (rem < 0) rem = 0
      if (rate <= 0) { eta = "NA" } else { eta = sprintf("%.0f", rem/rate) }
    }
    print pct, eta
  }'
}

print_batch_summary() {
  echo "== batch summary =="
  if [ ! -f "$BATCH_JSON" ]; then
    echo "  no batch manifest present ($BATCH_JSON) — showing all lanes below"
    echo
    return
  fi

  local label id created
  label=$(grep -m1 '"label"'    "$BATCH_JSON" 2>/dev/null | sed -E 's/.*"label"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  id=$(grep -m1    '"batch_id"' "$BATCH_JSON" 2>/dev/null | sed -E 's/.*"batch_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  created=$(grep -m1 '"created"' "$BATCH_JSON" 2>/dev/null | sed -E 's/.*"created"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')

  local lane_lines
  lane_lines=$(grep -E '"script"[[:space:]]*:' "$BATCH_JSON" 2>/dev/null || true)

  local -a names=() weights=()
  if [ -n "$lane_lines" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local s w
      s=$(echo "$line" | sed -E 's/.*"script"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
      w=$(echo "$line" | sed -E 's/.*"weight"[[:space:]]*:[[:space:]]*([0-9]+\.?[0-9]*).*/\1/')
      [ -z "$s" ] && continue
      case "$w" in ''|*[!0-9.]*) w=0 ;; esac
      names+=("$s"); weights+=("$w")
    done <<< "$lane_lines"
  fi

  local total_lanes=${#names[@]}
  if [ "$total_lanes" -eq 0 ]; then
    echo "  $BATCH_JSON present but no lanes could be read from it — showing all lanes below"
    echo
    return
  fi

  local total_w=0 done_w=0 lanes_done=0
  local running_name="" running_started="" running_weight=0
  local i s w st state
  for ((i = 0; i < total_lanes; i++)); do
    s="${names[i]}"; w="${weights[i]}"
    total_w=$(awk -v a="$total_w" -v b="$w" 'BEGIN{printf "%.6f", a+b}')
    st="$STATUS/$s.status"
    if [ -f "$st" ]; then
      state=$(sed -n 's/^state=//p' "$st")
      if [ "$state" = "done" ]; then
        done_w=$(awk -v a="$done_w" -v b="$w" 'BEGIN{printf "%.6f", a+b}')
        lanes_done=$((lanes_done + 1))
      elif [ "$state" = "running" ]; then
        running_name="$s"
        running_started=$(sed -n 's/^started=//p' "$st")
        running_weight="$w"
      fi
    fi
  done

  local now_epoch created_epoch elapsed_s pct eta_s
  now_epoch=$(date +%s)
  created_epoch=$(date -d "$created" +%s 2>/dev/null || echo "")
  if [ -n "$created_epoch" ]; then
    elapsed_s=$((now_epoch - created_epoch))
    [ "$elapsed_s" -lt 0 ] && elapsed_s=0
  else
    elapsed_s=""
  fi
  read -r pct eta_s <<< "$(compute_pct_eta "$done_w" "$total_w" "$elapsed_s")"

  echo "  batch:    ${label:-(unlabeled)}  (id ${id:-unknown})"
  echo "  overall:  $lanes_done/$total_lanes lanes done   weight $(fmt_weight "$done_w")/$(fmt_weight "$total_w")  (${pct}% by weight)"
  if [ -n "$elapsed_s" ]; then
    echo "  elapsed:  $(fmt_hms "$elapsed_s")"
  else
    echo "  elapsed:  n/a (created timestamp missing or unreadable)"
  fi
  if [ "$lanes_done" -eq "$total_lanes" ]; then
    echo "  ETA all:  already complete"
  elif [ "$eta_s" = "NA" ]; then
    echo "  ETA all:  not enough data yet (estimate needs at least one finished lane and 5s+ elapsed)"
  else
    echo "  ETA all:  ~$(fmt_hms "$eta_s") remaining  (estimate, from throughput so far)"
  fi
  [ "$lanes_done" -eq "$total_lanes" ] && echo "  status:   batch complete"

  if [ -n "$running_name" ]; then
    local log cur_line n tot lane_pct lane_eta started_epoch lane_elapsed
    log=$(ls -t "$LOGS"/*"__${running_name}.log" 2>/dev/null | head -1)
    cur_line=""
    if [ -n "${log:-}" ]; then
      cur_line=$(tail -c 4000 "$log" 2>/dev/null | tr '\r' '\n' | grep -oE '\[[0-9]+/[0-9]+\]' | tail -1)
    fi
    if [ -n "$cur_line" ]; then
      n=$(echo "$cur_line" | sed -E 's/\[([0-9]+)\/([0-9]+)\]/\1/')
      tot=$(echo "$cur_line" | sed -E 's/\[([0-9]+)\/([0-9]+)\]/\2/')
      started_epoch=$(date -d "$running_started" +%s 2>/dev/null || echo "")
      if [ -n "$started_epoch" ]; then
        lane_elapsed=$((now_epoch - started_epoch))
        [ "$lane_elapsed" -lt 0 ] && lane_elapsed=0
      else
        lane_elapsed=""
      fi
      read -r lane_pct lane_eta <<< "$(compute_pct_eta "$n" "$tot" "$lane_elapsed")"
      echo "  current:  $running_name  $n/$tot  (${lane_pct}%)"
      if [ "$lane_eta" = "NA" ]; then
        echo "  ETA lane: not enough data yet"
      else
        echo "  ETA lane: ~$(fmt_hms "$lane_eta") remaining  (estimate)"
      fi
    else
      echo "  current:  $running_name  (running, no [n/total] progress line in its log yet)"
    fi
  fi
  echo
}

snapshot() {
  echo "== instance $AL_INSTANCE  (runner $AL_RUNNER, agent $AL_AGENT_DIR) =="
  echo
  print_other_instances
  print_batch_summary

  echo "== queued (waiting in $DROP) =="
  if compgen -G "$DROP/*.sh" > /dev/null; then
      ls -t "$DROP"/*.sh | while read -r f; do echo "  $(basename "$f")"; done
  else
      echo "  (none)"
  fi
  echo

  echo "== running =="
  local any=0
  if compgen -G "$STATUS/*.status" > /dev/null; then
    for s in "$STATUS"/*.status; do
      grep -q '^state=running' "$s" 2>/dev/null || continue
      any=1
      name=$(sed -n 's/^script=//p' "$s")
      started=$(sed -n 's/^started=//p' "$s")
      log=$(ls -t "$LOGS"/*"__${name}.log" 2>/dev/null | head -1)
      echo "  $name   started $started"
      if [ -n "${log:-}" ]; then
        echo "    log: $log"
        # last line that looks like progress, else just the last line
        tail -c 4000 "$log" | tr '\r' '\n' \
          | grep -E '\[[0-9]+/[0-9]+\]|restart|ETA|done/total' | tail -1 \
          | sed 's/^/    /'
        tail -n 1 "$log" | sed 's/^/    last: /'
      fi
    done
  fi
  [ "$any" = 0 ] && echo "  (nothing running)"
  echo

  echo "== live processes inside $AL_RUNNER (top by CPU) =="
  if command -v podman > /dev/null 2>&1; then
      podman exec "$AL_RUNNER" ps -eo pid,pcpu,etime,comm,args --sort=-pcpu 2>/dev/null \
        | head -12 | sed 's/^/  /' \
        || echo "  (container not up, or ps unavailable inside it)"
  else
      echo "  (podman not on PATH)"
  fi
  echo

  echo "== finished, 10 most recent =="
  if compgen -G "$STATUS/*.status" > /dev/null; then
    for s in $(ls -t "$STATUS"/*.status | head -10); do
      name=$(sed -n 's/^script=//p' "$s")
      st=$(sed -n 's/^state=//p' "$s")
      ex=$(sed -n 's/^exit=//p' "$s")
      el=$(sed -n 's/^elapsed_s=//p' "$s")
      fin=$(sed -n 's/^finished=//p' "$s")
      printf '  %-28s %-8s exit=%-4s %8ss  %s\n' "$name" "$st" "$ex" "$el" "$fin"
    done
  else
    echo "  (no status files)"
  fi
}

if [ "${1:-}" = "-w" ]; then
  while true; do clear; date -Iseconds; echo; snapshot; sleep 2; done
else
  snapshot
fi
