#!/usr/bin/env bash
# Write agent/batch.json — the batch manifest progress.sh reads to compute
# overall completion by weight and a throughput-based ETA, across a set of
# lanes launched together.
#
# Write this BEFORE dropping any of the lane scripts, so progress.sh can
# attribute weight correctly from the very first snapshot.
#
# WEIGHT is any comparable unit across the lanes in one batch — probe count
# is typical — so a big lane and a tiny lane are not counted equally toward
# "percent complete".
#
# Usage:
#   bash <airlock>/batch.sh <label> <lane.sh>:<weight> [<lane2.sh>:<weight2> ...]
#
# Example:
#   bash <airlock>/batch.sh acceptance-sweep \
#       a2_verify.sh:40 bs_all.sh:120 ac_rust.sh:60
#
# See README.md ("Batch manifest") for the manifest shape this writes.
set -uo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"


usage() {
  echo "usage: bash batch.sh <label> <lane.sh>:<weight> [<lane2.sh>:<weight2> ...]" >&2
  exit 1
}

LABEL="${1:-}"
[ -n "$LABEL" ] || usage
shift
[ "$#" -ge 1 ] || usage

BATCH_ID="batch-$(date -u +%Y%m%dT%H%M%SZ)"
CREATED="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"

mkdir -p agent
TMP="$AL_AGENT_DIR/.batch.json.tmp.$$"

{
  echo "{"
  printf '  "batch_id": "%s",\n' "$BATCH_ID"
  printf '  "label": "%s",\n' "$LABEL"
  printf '  "created": "%s",\n' "$CREATED"
  echo "  \"lanes\": ["
  last="$#"
  i=0
  for pair in "$@"; do
    i=$((i + 1))
    script="${pair%%:*}"
    weight="${pair#*:}"
    if [ -z "$script" ] || [ "$script" = "$pair" ] || [ -z "$weight" ]; then
      echo "malformed lane spec (want script.sh:weight): $pair" >&2
      rm -f "$TMP"
      exit 1
    fi
    case "$weight" in
      ''|*[!0-9.]*)
        echo "weight must be numeric: $pair" >&2
        rm -f "$TMP"
        exit 1
        ;;
    esac
    if [ "$i" -lt "$last" ]; then
      printf '    { "script": "%s", "weight": %s },\n' "$script" "$weight"
    else
      printf '    { "script": "%s", "weight": %s }\n' "$script" "$weight"
    fi
  done
  echo "  ]"
  echo "}"
} > "$TMP"

mv "$TMP" "$AL_AGENT_DIR/batch.json"
echo "wrote $AL_AGENT_DIR/batch.json  (batch $BATCH_ID, label '$LABEL', $# lane(s))"
