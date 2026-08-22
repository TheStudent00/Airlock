# Migrating from SandboxDesign to Airlock

Airlock is a derivation of SandboxDesign, made project-agnostic by
construction and public-ready. **Almost nothing changes for a project
that already uses it.**

At least two projects are active users today. `PseudoCoupHQ` is the
main one; at least one other project drives the same sandbox. This
document is written so either can move without reading the derivation
log.

---

## The short version

| | |
|---|---|
| what changes | the command name: `sandbox` becomes `airlock` |
| what does not change | everything else |

---

## What does not change

**The file protocol.** Byte for byte, path for path.

| path, relative to the repo root | unchanged |
|---|---|
| `agent/drop/<lane>.sh` | yes |
| `agent/drop/.<lane>.sh` (the hidden-then-rename form) | yes |
| `agent/drop/.done/<stamp>__<lane>.sh` | yes |
| `agent/status/<lane>.sh.status` | yes |
| `agent/logs/<stamp>__<lane>.sh.log` | yes |
| `agent/out/` | yes |
| `agent/batch.json` | yes, including its one-lane-object-per-line byte-shape |

**The status file's key=value fields.** `state`, `exit`, `started`,
`finished`, `elapsed_s`, `log`, `work_free_mb_before`,
`work_free_mb_after`, `work_consumed_mb`, `verdict`, `script`. Same
names, same values, same atomic write.

**The manifest format.** `airlock submit --batch` and `batch.sh` both
write the shape `progress.sh` parses. A manifest written by one is read
by the other.

**Every shell script.** `up.sh`, `down.sh`, `build.sh`, `pull.sh`,
`submit.sh`, `submit_project.sh`, `batch.sh`, `progress.sh`, `allow.sh`,
`logs.sh`, `report.sh`, `selftest.sh`, `probe_host.sh`,
`install_quadlet.sh` — all present, all with the same names, arguments
and behaviour.

**The container, network, image and volume names.** `sandbox-runner`,
`sandbox-proxy`, `sandbox-internal`, `sandbox-egress`,
`sandbox-persist`, `sandbox-runner:latest`, `sandbox-proxy:latest`.
Deliberately unchanged — they were never the project-specific part, and
renaming them would have meant an image rebuild and a systemd
re-install for everyone migrating. See the warning below.

**The environment variables you already set.** `SANDBOX_CPUS` and
`SANDBOX_DESIGN_ROOT` are both still read. `AIRLOCK_CPUS` and
`AIRLOCK_ROOT` are the new spellings and win where both are set.

---

## What changes

### 1. The command name

| SandboxDesign | Airlock |
|---|---|
| `<sandboxdesign>/sandbox submit x.sh --batch b --weight 40` | `<airlock>/airlock submit x.sh --batch b --weight 40` |
| `<sandboxdesign>/sandbox status x.sh` | `<airlock>/airlock status x.sh` |
| `<sandboxdesign>/sandbox watch` | `<airlock>/airlock watch` |
| `<sandboxdesign>/sandbox doctor` | `<airlock>/airlock doctor` |
| `<sandboxdesign>/sandbox up` / `down` / `allow ...` | `<airlock>/airlock up` / `down` / `allow ...` |

Every flag, every refusal, every exit code is the same.

### 2. The CPU default and its spelling

`SANDBOX_CPUS` defaulted to 3 in SandboxDesign for part of 2026-08-22,
then to 6. Airlock ships with **6 — the full share** — as
`AIRLOCK_CPUS`, ruled 2026-08-22: the default is full, and the user
throttles as they see fit.

```
AIRLOCK_CPUS=3 bash <airlock>/up.sh     # throttle a long run
SANDBOX_CPUS=3 bash <airlock>/up.sh     # still works, read after AIRLOCK_CPUS
```

`quadlet/sandbox-runner.container` also carries 6, so the manual and the
systemd-managed sandbox now agree. The disagreement SandboxDesign's
`doctor` warned about on every run is gone; the check remains, so a
future drift is still caught.

### 3. Where your project directories are declared

`quadlet/sandbox-runner.container` in SandboxDesign hardcoded
`Volume=%h/<sandboxdesign>/agent/drop:/drop` and three more.
Airlock's copy carries an empty `# >>> AGENT LANE` marker block instead;
`install_quadlet.sh` fills it from the repo's own location at install
time. **If you use the systemd path, re-run the installer.**

`mounts.conf` itself is unchanged in format and is still per-machine and
gitignored. Copy yours across.

### 4. What is no longer in the repo

- `agent/templates/pcv6_suite.sh` — and `agent/templates/` altogether. A
  project's lane script belongs in that project's repo. Move it there,
  and submit it with `airlock submit` like any other lane.
- `create_github_repo.sh` and `git_commit_push.sh` — one person's host
  workflow, hardcoding one path.
- SandboxDesign's `DevComms/` logs and captured run records. They stay
  readable in `<sandboxdesign>`, which is not modified by
  this migration.

---

## Do not run both at once

Airlock and SandboxDesign use **the same container and network names**.
Both `up.sh` scripts test `podman container exists sandbox-runner`
before starting anything, so whichever runs second will start the
*other* one — bound to the other repo's `agent/` directories. Lanes
would appear to vanish, and status files would never be written where
you are looking.

Bring one down before bringing the other up:

```
bash <sandboxdesign>/down.sh
bash <airlock>/up.sh
```

If you had installed the systemd units from SandboxDesign, remove them
first — they carry the old hardcoded agent-lane paths:

```
bash <sandboxdesign>/install_quadlet.sh --remove
bash <airlock>/install_quadlet.sh
```

---

## The migration, end to end

```
# 1. stop the old sandbox
bash <sandboxdesign>/down.sh
# ...or, if it was under systemd:
bash <sandboxdesign>/install_quadlet.sh --remove

# 2. carry your per-machine configuration across. Neither file is
#    tracked in either repo, so nothing is overwritten by a pull.
cp <sandboxdesign>/mounts.conf          <airlock>/mounts.conf
cp <sandboxdesign>/proxy/allowlist.txt  <airlock>/proxy/allowlist.txt

# 3. the images already exist and are unchanged; no rebuild is needed.
#    Rebuild only if you want to, or if you never built them:
#    bash <airlock>/build.sh

# 4. start it
bash <airlock>/up.sh
bash <airlock>/selftest.sh      # six checks, all should PASS
<airlock>/airlock doctor

# 5. point your project at it
export AIRLOCK_ROOT=<airlock>
```

Nothing is copied out of `<sandboxdesign>/agent/`. Old logs,
statuses and products stay where they are; Airlock starts with an empty
lane. If you want an old batch's history, read it in place.

## What to change in a project

Search the project for the string `sandbox` used as a *command*, and for
`SandboxDesign` used as a *path*. In practice that is:

| what to look for | what to replace it with |
|---|---|
| `<sandboxdesign>/sandbox` | `$AIRLOCK_ROOT/airlock` |
| `<sandboxdesign>/<script>.sh` | `$AIRLOCK_ROOT/<script>.sh` |
| `SANDBOX_DESIGN_ROOT=...` | `AIRLOCK_ROOT=...` (the old name still works) |
| a hardcoded `<sandboxdesign>/agent/status/...` poll path | `$AIRLOCK_ROOT/agent/status/...` — the tail of the path is identical |

Do **not** search-and-replace `sandbox-runner` or `sandbox-proxy`. Those
names are unchanged on purpose.

## SandboxDesign is not retired

`<sandboxdesign>` is untouched by this derivation. It still
works, and whether to retire it is the maintainer's call — see the
"awaiting the maintainer" list at the foot of `DevComms/log_001_airlock_derivation.md`.
