#!/usr/bin/env bash
# scrub_check.sh - refuse to let personal information reach a public repo.
#
# Scans every file git would publish for a small list of patterns that
# identify a person or a machine rather than the tool. Exits non-zero and
# lists every offender, with file and line, so the fix is obvious.
#
# TWO SETS ARE SCANNED:
#   1. tracked files          - already publishable
#   2. untracked, NOT ignored - `git add -A` would publish them next
# The second set is not hypothetical: a handoff document sitting untracked
# and unignored is exactly how information leaves a machine by accident.
#
# Usage:  ./scrub_check.sh          normal
#         ./scrub_check.sh -q       only the summary line
#
# This file is scanned for hygiene like any other, but is EXCLUDED from the
# pattern match itself - it necessarily contains the patterns.

set -uo pipefail
cd "$(dirname "$0")"

QUIET=0
[ "${1:-}" = "-q" ] && QUIET=1

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "scrub_check: not a git checkout (or git missing) - nothing to scan."
    exit 0
fi

SELF="scrub_check.sh"

# ---------------------------------------------------------------------------
# THE PATTERN LIST - the one place to extend.
#
# Each entry is "<what it is>|<POSIX extended regex>". Add a line here and
# both scanned sets pick it up; nothing else needs editing.
#
# The maintainer's personal handle is assembled at runtime rather than
# written out, so that this tracked file does not itself carry the string
# it is meant to keep out of the repo. Extend HANDLES the same way.
# ---------------------------------------------------------------------------
h1=$(printf '%s%s' 'D' 'ee')

PATTERNS=(
  "absolute home path of a real account|/home/[a-z][a-z0-9_.-]*"
  "macOS home path of a real account|/Users/[A-Za-z][A-Za-z0-9_.-]*"
  "agent session mount path|/sessions/[a-z0-9][a-z0-9-]*"
  "email address|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
  "personal handle of the maintainer|(^|[^A-Za-z])${h1}([^A-Za-z]|$)"
  "subuid/subgid mapping naming a real account|[a-z][a-z0-9_-]*:[0-9]{4,}:[0-9]{4,}"
  # A disc-layout assumption, not a personal-information leak: it names
  # the maintainer's projects-directory convention (shell form and the
  # systemd %h specifier form). Written split across the alternation
  # below so this line itself does not carry the literal string it
  # scans for - see the note on the personal handle above for why that
  # matters for a tracked, public file.
  "disc-layout path assuming a specific projects directory|(~|%h)/Programming"
)

# Matches that are deliberately allowed. One extended regex per entry; a
# hit line matching any of these is not an offence. Keep this list short and
# justified - it is the only way a pattern above can be defeated.
ALLOW=(
  # GitHub's noreply commit address. It is the fix for a leaked personal
  # mailbox, not a leak, and it has to be quotable in README and DevComms.
  "[A-Za-z0-9-]+@users\.noreply\.github\.com"
)

# Optional per-machine additions, one "<label>|<regex>" per line. Gitignored,
# so a private pattern never becomes a published one.
EXTRA=".scrub_patterns.local"
if [ -f "$EXTRA" ]; then
    while IFS= read -r line; do
        case "$line" in ""|\#*) continue;; esac
        PATTERNS+=("$line")
    done < "$EXTRA"
fi

# ---------------------------------------------------------------------------

offenders=0

scan() {   # scan <set-label> <file>...
    local label="$1"; shift
    local f entry what re hits a
    for f in "$@"; do
        [ -f "$f" ] || continue
        [ "$f" = "$SELF" ] && continue
        for entry in "${PATTERNS[@]}"; do
            what="${entry%%|*}"; re="${entry#*|}"
            hits=$(grep -nIE "$re" -- "$f" 2>/dev/null) || continue
            for a in "${ALLOW[@]}"; do
                hits=$(printf '%s\n' "$hits" | grep -vE "$a" || true)
            done
            [ -n "$hits" ] || continue
            offenders=$((offenders + 1))
            if [ "$QUIET" -eq 0 ]; then
                echo "  FAIL  $f  [$label]"
                echo "        pattern: $what"
                printf '%s\n' "$hits" | sed 's/^/        /' | head -20
            fi
        done
    done
}

mapfile -t TRACKED < <(git ls-files)
mapfile -t LOOSE   < <(git ls-files --others --exclude-standard)

[ "$QUIET" -eq 0 ] && echo "=== scrub_check: ${#PATTERNS[@]} pattern(s), ${#TRACKED[@]} tracked file(s), ${#LOOSE[@]} untracked-and-unignored file(s) ==="

[ "${#TRACKED[@]}" -gt 0 ] && scan "tracked" "${TRACKED[@]}"
[ "${#LOOSE[@]}"   -gt 0 ] && scan "untracked, NOT ignored - would be published by git add -A" "${LOOSE[@]}"

if [ "$offenders" -eq 0 ]; then
    echo "scrub_check: PASS - no personal or machine-identifying pattern found."
    exit 0
fi

echo
echo "scrub_check: FAIL - $offenders file/pattern hit(s) above."
echo "  Fix the file, or - if it is a private working document - add it to"
echo "  .gitignore so it is never a candidate for publication."
exit 1
