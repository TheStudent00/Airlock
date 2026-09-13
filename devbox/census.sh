#!/usr/bin/env bash
# devbox census: how big is each top-level folder of ~/Programming, and
# which ones the copy skips. Run before copy.sh. Changes nothing.
set -euo pipefail
SRC="${1:-$HOME/Programming}"
EXCL_FILE="$(dirname "$0")/exclude.txt"
echo "== $SRC, per top-level folder (apparent size), skipped ones marked =="
total=0; kept=0
while IFS= read -r d; do
    name=$(basename "$d")
    mb=$(du -sm --apparent-size "$d" 2>/dev/null | cut -f1)
    total=$((total + mb))
    mark="      "
    if grep -qxF "$name/" "$EXCL_FILE" || grep -qxF "$name" "$EXCL_FILE"; then
        mark="SKIP  "
    else
        kept=$((kept + mb))
    fi
    printf "%s %8d MB  %s\n" "$mark" "$mb" "$name"
done < <(find "$SRC" -mindepth 1 -maxdepth 1 -printf "%p\n" | sort)
echo
printf "total %d MB; copied after the top-level skips %d MB\n" "$total" "$kept"
echo "(the patterns inside repos -- node_modules, target, build, .stage_tmp --"
echo " are skipped too; see exclude.txt; the dry run prints the real number)"
