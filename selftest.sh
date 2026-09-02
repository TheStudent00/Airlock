#!/usr/bin/env bash
# Prove the sandbox actually behaves as designed. Six checks, each
# printing PASS or FAIL and the evidence it judged on, preceded by one
# repo-hygiene check that needs no container.
#
# Check 0 delegates to scrub_check.sh: no tracked or about-to-be-tracked
# file may carry a personal or machine-identifying string. It is here
# because it is the one check that must never be forgotten before a push,
# and it is cheap. It reports OK and moves on outside a git checkout.
#
# EVERY SCRIPT NAME CARRIES A UNIQUE RUN ID. /logs persists for the life
# of the container, so a check that globbed a fixed name (hello.sh.log)
# would match a log left by an EARLIER selftest and pass even if the
# daemon had aborted. The run id makes each check read only its own run.
#
# Usage:  ./selftest.sh [--instance NAME]
#
# Checks 4, 5 and 6 are about the egress gate. An instance configured
# `proxy = no` has no gate to test, so those three report SKIP instead of
# a verdict they cannot reach.
set -uo pipefail
cd "$(dirname "$0")"

source "$(dirname "$0")/instance.sh"
airlock_parse_instance "$@"
set -- "${AIRLOCK_ARGV[@]}"
airlock_instance_load "$(cd "$(dirname "$0")" && pwd)"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
RUNID="$(date +%Y%m%d%H%M%S)$$"
pass=0; fail=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
skip() { echo "  SKIP  $1"; }
no()   { echo "  FAIL  $1"; echo "        evidence: $2"; fail=$((fail+1)); }

# Read the log belonging to THIS run of the named check, or empty.
readlog() {
    podman exec "$AL_RUNNER" sh -c \
        "cat /logs/*${1}_${RUNID}.sh.log 2>/dev/null" 2>/dev/null || true
}

echo "  (instance $AL_INSTANCE — runner $AL_RUNNER, agent $AL_AGENT_DIR)"
echo "  (run id $RUNID — every check below reads only its own fresh log)"

echo "=== 0. no personal or machine-identifying string is publishable ==="
if [ -f ./scrub_check.sh ]; then
    out=$(bash ./scrub_check.sh 2>&1)
    if [ $? -eq 0 ]; then
        ok "scrub_check found nothing publishable that names a person or machine"
    else
        no "scrub_check found publishable personal information" "$(printf '\n%s' "$out" | sed 's/^/          /')"
    fi
else
    no "scrub_check.sh is missing" "the repo-hygiene guard is not present"
fi

echo "=== 1. daemon is alive and watching ==="
out=$(podman logs "$AL_RUNNER" 2>&1 | grep -m1 'watching /drop' || true)
[ -n "$out" ] && ok "daemon reported watching /drop" || no "no 'watching /drop' line" "$(podman logs --tail 5 "$AL_RUNNER" 2>&1)"

echo "=== 2. a submitted script actually runs (this exercises inotify) ==="
cat > "$TMP/hello_${RUNID}.sh" <<EOF
echo "SENTINEL_${RUNID}"
python3 --version; python3.13 --version; go version; rustc --version; node --version; javac -version
EOF
./submit.sh --instance "$AL_INSTANCE" "$TMP/hello_${RUNID}.sh" >/dev/null
sleep 5
out=$(readlog hello)
echo "$out" | grep -q "SENTINEL_${RUNID}" && ok "script ran, output captured" || no "sentinel not found in this run's log" "${out:-<no log for run $RUNID>}"
echo "$out" | sed 's/^/        | /' | head -12

echo "=== 3. half-written files are NOT executed ==="
podman exec "$AL_RUNNER" sh -c "echo 'echo SHOULD_NOT_RUN_${RUNID}' > /drop/.pending_${RUNID}.sh"
sleep 3
out=$(podman exec "$AL_RUNNER" sh -c "grep -rl SHOULD_NOT_RUN_${RUNID} /logs 2>/dev/null" || true)
[ -z "$out" ] && ok "hidden .pending file was ignored" || no "hidden file was executed" "$out"
podman exec "$AL_RUNNER" rm -f "/drop/.pending_${RUNID}.sh"

echo "=== 4. an ALLOWED domain is reachable through the proxy ==="
if [ "$AL_USE_PROXY" != "yes" ]; then
  skip "instance $AL_INSTANCE has no proxy (proxy = no); checks 4-6 do not apply"
else
cat > "$TMP/netok_${RUNID}.sh" <<'EOF'
for attempt in 1 2 3 4 5; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://pypi.org/simple/)
  echo "attempt $attempt: http_code=$code"
  case "$code" in 200|30[0-9]) echo "allowed_status=$code"; exit 0;; esac
  sleep 3
done
echo "allowed_status=FAILED"
EOF
./submit.sh --instance "$AL_INSTANCE" "$TMP/netok_${RUNID}.sh" >/dev/null; sleep 30
out=$(readlog netok)
echo "$out" | grep -qE 'allowed_status=(200|30[0-9])' && ok "pypi.org reachable via proxy" || no "allowlisted domain unreachable" "$(printf '\n%s' "${out:-<no log>}" | sed 's/^/          /')"

echo "=== 5. an UNDECLARED domain is refused ==="
cat > "$TMP/netno_${RUNID}.sh" <<'EOF'
curl -s -o /dev/null -w "denied_status=%{http_code}\n" --max-time 15 https://example.com/ || echo "denied_status=CURL_FAILED"
EOF
./submit.sh --instance "$AL_INSTANCE" "$TMP/netno_${RUNID}.sh" >/dev/null; sleep 12
out=$(readlog netno)
echo "$out" | grep -qE 'denied_status=(403|CURL_FAILED)' && ok "example.com refused by proxy" || no "UNDECLARED DOMAIN WAS REACHABLE" "${out:-<no log>}"

echo "=== 6. there is no second route out (proxy bypass is impossible) ==="
cat > "$TMP/netdirect_${RUNID}.sh" <<'EOF'
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  curl -s -o /dev/null -w "direct_status=%{http_code}\n" --max-time 12 https://example.com/ \
  || echo "direct_status=NO_ROUTE"
EOF
./submit.sh --instance "$AL_INSTANCE" "$TMP/netdirect_${RUNID}.sh" >/dev/null; sleep 18
out=$(readlog netdirect)
echo "$out" | grep -q 'direct_status=NO_ROUTE' && ok "no direct egress with proxy vars unset" || no "RUNNER HAS A DIRECT ROUTE OUT" "${out:-<no log>}"
fi

echo
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ] || exit 1
