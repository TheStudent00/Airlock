# log 004 — a status view names any OTHER busy instance

Date: 2026-09-03. Airlock's own record of one ruled change set. The
caller-side report of the same work (task 82) lives in the calling
project's log sequence; this file is the tool's record.

---

## 1. What changed, at the top level

| # | change | file |
|---|---|---|
| 1 | a new function, `known_instances(paths)`, is the one place the `airlock` CLI discovers instance names (from `instances/*.conf` and `~/AirlockRuns/*`); `Doctor.check_instances` now calls it instead of re-listing both sources itself | `airlock` |
| 2 | a new function, `other_busy_instances_line(paths)`, prints one line naming every OTHER instance with a lane queued or running; called from `_render_status`, so both `airlock status` and `airlock watch` show it | `airlock` |
| 3 | `airlock_instance_list()` in `instance.sh` now scans `~/AirlockRuns/*` as well as `instances/*.conf`, matching the CLI's two-source discovery | `instance.sh` |
| 4 | a new function, `airlock_other_busy_instances(root, current)`, walks every other known instance (via `airlock_instance_load`, in a subshell so it never touches the caller's own `AL_*` variables) and prints a line per busy one | `instance.sh` |
| 5 | `progress.sh` prints that line, headed `== other instances busy ==`, right after its own instance banner, before the batch summary | `progress.sh` |

## 2. Why

Measured 2026-09-03: "what is running and why cant i see it in Airlock
status?" `progress.sh` and `airlock status` have always reported one
instance — the one named by `--instance` / `AIRLOCK_INSTANCE`, `sandbox`
if neither is given. By the round-11 ruling every task runs in its own
instance (see `README.md` §Instances, "One instance per task"), so a
lane can be running the entire time in `t82` while the command someone
actually types — `bash progress.sh` with no flags — says `(nothing
running)`. The fix is generic: it belongs in Airlock, for every caller,
not in one project's wrapper around it.

## 3. What it does NOT do

- It does not change what the default view shows for its OWN instance —
  every existing line, in the same order, is unchanged below the new
  header.
- It does not query podman. Busy/idle is read the same way `down.sh`
  reads it — one scan of `<agent>/status/*.status` for `state=running`,
  plus a listing of `<agent>/drop/*.sh` for anything queued — so a
  reader is never told an instance is busy because a container merely
  exists.
- It never turns a status view into an error. An instance whose conf
  cannot be read, whose agent tree does not exist yet, or whose status
  directory is unreadable is silently skipped; the header line is
  printed only when at least one other instance has something to show,
  and is omitted entirely otherwise — never "0 other instances busy".

## 4. The one correction made while proving it

The first draft counted a running lane's script as ALSO queued, because
`daemon/watcher.py` leaves the script sitting in `/drop` for the whole
run and only archives it into `/drop/.done` on completion (this is the
daemon's existing behaviour, `run_script()` in `daemon/watcher.py`,
unchanged by this work). Both the python and the shell implementation
now exclude a script that is already reported `running` from the
queued count.

## 5. Proof — a second instance, a 60s lane, both views

Instance `t82` was brought up beside the default `sandbox` instance
(`instances/t82.conf`, gitignored, per-machine — proxy off, its own
persist volume, `watch = poll`, `script_timeout = 300`), a lane
printing `[n/6]` every 10 seconds for 60 seconds was submitted to it,
and both views were read while it was running.

Default instance, `bash progress.sh` (head):

```
== instance sandbox  (runner sandbox-runner, agent <airlock>/agent) ==

== other instances busy ==
  t82 (running: t82_sleep60b.sh)
  (this view is instance 'sandbox' — bash progress.sh --instance <name> [-w])

== batch summary ==
  batch:    task27  (id batch-20260901T154117Z)
```

Default instance, `python3 ./airlock status` (head):

```
  other instances busy: t82 (running: t82_sleep60b.sh)   (this view is instance 'sandbox' — airlock --instance <name> status, or bash <airlock>/progress.sh --instance <name>)

batch summary
```

The `t82` instance's own view, `AIRLOCK_INSTANCE=t82 bash progress.sh`:

```
== instance t82  (runner t82-runner, agent ~/AirlockRuns/t82/agent) ==

== batch summary ==
  no batch manifest present (~/AirlockRuns/t82/agent/batch.json) — showing all lanes below

== queued (waiting in ~/AirlockRuns/t82/agent/drop) ==
  t82_sleep60b.sh

== running ==
  t82_sleep60b.sh   started 2026-09-04T02:56:05+00:00
    log: ~/AirlockRuns/t82/agent/logs/20260904T025605Z__t82_sleep60b.sh.log
    [3/6] sleeping 10s
    last: [3/6] sleeping 10s
```

The lane finished (`state=done exit=0 elapsed_s=60.1`), `bash
down.sh --instance t82` removed the container, and the default view was
read again — the header is gone because nothing is queued or running in
`t82` any more (the instance's run tree still exists on disk; the check
is over its state files, not its existence):

```
== instance sandbox  (runner sandbox-runner, agent <airlock>/agent) ==

== batch summary ==
  batch:    task27  (id batch-20260901T154117Z)
```

Full unredacted transcripts (this machine's own paths) are in the
calling project's task-82 report.

## 6. Guard

```
$ bash <airlock>/scrub_check.sh
=== scrub_check: 7 pattern(s), 53 tracked file(s), 4 untracked-and-unignored file(s) ===
scrub_check: PASS - no personal or machine-identifying pattern found.
```

One round-trip was needed: the first draft of the code comments quoted
the operator's question with a name attached; `scrub_check.sh` caught
it (pattern for the maintainer's own handle) in `airlock`,
`instance.sh` and `progress.sh`. Fixed by dropping the attribution and
keeping the quote itself, dated but unattributed, matching how the rest
of the repo's comments record a ruling by date alone.
