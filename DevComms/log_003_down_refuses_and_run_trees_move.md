# log 003 — `down` refuses while a lane runs; run trees move outside the checkout

Date: 2026-09-02. Airlock's own record of one ruled change set. The
caller-side report of the same work lives in the calling project's log
sequence; this file is the tool's record.

---

# 1. What changed, at the top level

| # | change | file |
|---|---|---|
| 1 | `down.sh` refuses while any lane of that instance is recorded `running`, naming the lane; `--force` overrides | `down.sh` |
| 2 | a non-default instance's agent tree defaults to `~/AirlockRuns/<name>/agent`, outside the checkout | `instance.sh`, `airlock` |
| 3 | `airlock doctor` lists `~/AirlockRuns/*` beside `instances/*.conf`, and says which of the two each instance was found in | `airlock` |
| 4 | the `daemon_file` key and its `up.sh` block are gone, after the rebuild that made them unnecessary | `instance.sh`, `up.sh` |
| 5 | the README gains the run-tree section and the one-instance-per-task section | `README.md` |
| 6 | `instances/sandbox.conf.example` documents the new `agent_dir` derivation and records that `daemon_file` was removed | `instances/sandbox.conf.example` |

Serial execution is unchanged and there is no `workers` key. That is the
ruled position, not an omission: the daemon runs one lane to completion
before starting the next, and the unit of separation is the instance.

# 2. Why `down` refuses

The daemon writes `state=running` into `<agent>/status/<lane>.status` when a
lane starts and rewrites the same file with `state=done` when it ends. One
scan of that folder therefore answers "is this instance busy" without asking
podman anything.

The event this addresses, 2026-09-02: one agent finished its work and took a
shared instance down while a second agent's lane was 23 seconds into a run.
The lane stopped mid-flight, its status file was left saying `running`, and
the submitter saw no error anywhere — only a run that had stopped. Neither
agent could see the other's queue before acting.

`--force` is the deliberate override, and is also the way past a status file
left saying `running` by a run that has already stopped: the check cannot
tell a stale record from a live run, and the container is being removed
either way.

`airlock down` delegates to `down.sh` and so inherits both the refusal and
the flag; the refusal is written once, in the shell script.

# 3. Why run trees moved out of the checkout

`drop`, `status`, `logs` and `out` hold a **run record**, not a tool file.
Under the old default a second instance's tree sat at
`instances/<name>/agent` — inside the checkout, kept out of version control
only by an ignore rule. `~/AirlockRuns/<name>/agent` needs no such rule: a
commit daemon walking the checkout never sees a run's products at all.

The default instance is unchanged and keeps `<root>/agent`. The `agent_dir`
key still overrides the derivation for any instance.

An instance can exist with no conf file at all, since every key has a
default — such an instance leaves its only trace under `~/AirlockRuns`,
which is why `doctor` now lists both places.

# 4. Trees created under the older default

Nothing was moved and nothing was deleted. A tree already at
`instances/<name>/agent` keeps working by naming itself in that instance's
own conf file:

```
agent_dir = instances/<name>/agent
```

That is a per-machine, gitignored file, so this is a machine's own record of
its own legacy tree. The `instances/*/` ignore stanza stays for exactly
these.

# 5. `daemon_file` is retired

The key bound a host copy of `daemon/watcher.py` read-only over the image's
`/opt/daemon/watcher.py`, so a daemon change could reach a running instance
before a rebuild. It was documented from the day it was written as a bridge
to be dropped after the next `build.sh`. That build has happened; the image
carries the current daemon, and the key, its `instance.sh` block and its
`up.sh` block are all removed.
