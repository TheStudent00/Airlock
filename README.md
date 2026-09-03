# Airlock

An isolated execution sandbox with a command-line front door.

You hand Airlock a bash script. It runs inside a container that has a
capped CPU share, capped memory, size-capped scratch filesystems, every
Linux capability dropped, and **no route to the internet at all** except
a proxy that permits only hostnames you declared in advance. You get back
an exit code, a log, and whatever the script wrote to `/out`.

The name is the mechanism: a sealed chamber between two environments.
Work goes in one side, runs sealed, products come out the other.

```
<airlock>/airlock submit mylane.sh --batch nightly --weight 40
<airlock>/airlock status mylane.sh
```

Airlock is **not built for any one project**. One container image, one
drop/status/logs protocol, one egress gate, usable the same way by
anything. Nothing project-specific ships in this repo, and that is
structural rather than a matter of discipline — see [the
contract](#the-contract) below.

---

## Contents

| section | what it answers |
|---|---|
| [What it is, mechanically](#what-it-is-mechanically) | what actually happens when you submit a lane |
| [What it protects against](#what-it-protects-against) | which risk each cap addresses, and how it is enforced |
| [The contract](#the-contract) | what Airlock owns, what a project owns |
| [The `airlock` command](#the-airlock-command) | the command table, the refusals, the flags |
| [The shell scripts underneath](#the-shell-scripts-underneath) | everything the CLI does not cover |
| [Getting started](#getting-started) | first run, in order |
| [Using this from a project](#using-this-from-a-project) | what a project-side caller looks like today |
| [Progress, and the batch manifest](#progress-and-the-batch-manifest) | weighted completion and ETA across a set of lanes |
| [Instances](#instances) | running two or more sandboxes from one install |
| [Configuration](#configuration) | every knob, its default, where it lives |
| [The image inventory](#the-image-inventory) | what toolchains are baked in, verified |
| [Running it under systemd](#running-it-under-systemd) | surviving reboots |
| [Why lanes are submitted hidden-then-renamed](#why-lanes-are-submitted-hidden-then-renamed) | the half-written-file problem |
| [Keeping personal information out](#keeping-personal-information-out) | the guard that stops a name or a home path being published |
| [Files](#files) | what every tracked file is |
| [Licence](#licence) | what you may do with this |

---

## What it is, mechanically

- `bash <airlock>/up.sh` starts two containers: **`sandbox-runner`**
  (does the work) and **`sandbox-proxy`** (the only thing
  `sandbox-runner` can reach on the network).
- You put a bash script — a **lane** — into `<airlock>/agent/drop/`.
  `<airlock>/airlock submit` is the documented way; a direct file write
  and `<airlock>/submit.sh` both work too.
- A daemon (`<airlock>/daemon/watcher.py`) inside `sandbox-runner`
  watches that folder and runs each lane it sees, **serially**, one
  after another.
- You poll `<airlock>/agent/status/<name>.status` for the run's state
  (`state=running`, then `state=done exit=<rc>`).
- Whatever the lane printed lands in `<airlock>/agent/logs/`; whatever
  it wrote to `/out` lands in `<airlock>/agent/out/`.

That loop — write a script, a run happens, read a status file, read the
output — is the entire interface. There is no API, no queue client, no
language binding. **It is four folders and a naming convention**, and
that is deliberate: anything that can write a file can drive Airlock,
including an agent session that has no shell of its own.

`<airlock>` above is wherever you cloned this repo. Airlock assumes
nothing about where that is; every script resolves its own location, and
the only file that ever names a real path is `mounts.conf`, which is
per-machine and never committed.

## What it protects against

| risk | how it is enforced |
|---|---|
| a run eating the machine's CPU | `sandbox-runner` starts with `--cpus "$AIRLOCK_CPUS"`, default **6**. Lanes additionally run niced (`LANE_NICE`, default 15) so the host stays responsive |
| a run eating the machine's memory | `--memory 12g` on the runner, `--memory 512m` on the proxy |
| a run filling the host disk | `/work` and `/tmp` are tmpfs with fixed `size=` caps. A run that exceeds one fails loudly with `ENOSPC` inside the container instead of taking the host down with it |
| a run escalating privilege | both containers start `--cap-drop=ALL --security-opt no-new-privileges`. The proxy re-adds only `SETUID`/`SETGID`, which squid needs to drop to its own user |
| a run reaching the internet | `sandbox-runner` sits on a podman network created `--internal`, which means podman installs **no route out of it at all**. Its only reachable peer is `sandbox-proxy`, a default-deny squid that refuses any hostname absent from `proxy/allowlist.txt`. There is no second path to forget about — `selftest.sh` check 6 proves it by unsetting the proxy variables and trying anyway |
| a run damaging your source tree | nothing is visible inside the container until `mounts.conf` says so, and mounts default to **read-only**. Products go to `/out` and the caller places them |
| a run being executed half-written | lanes are written hidden and then renamed; see [below](#why-lanes-are-submitted-hidden-then-renamed) |
| a runaway that never finishes | the daemon applies a wall-clock ceiling per lane (`SCRIPT_TIMEOUT`, default 3600s). The operating system stops it; `airlock status` renders that outcome as **ABORT** |

None of these caps reads temperature or backs off dynamically. Every one
is a fixed number, changed by hand. See [Configuration](#configuration)
for where each lives.

**What it is not.** Airlock is a podman container with dropped
capabilities on an internal network. It is not a VM, not a hypervisor
boundary, and not a defence against a kernel exploit. It is a strong
answer to "this build script might do something stupid or expensive" and
a weak answer to "this code is actively hostile and well resourced".

## The contract

This is the seam the whole repo is arranged around. **A project keeps
whatever is project-specific in its own repo** — its own lane scripts,
its own generators, its own data — and only ever hands Airlock a bash
script to run.

| Airlock owns | a project owns |
|---|---|
| the container image and the toolchains baked into it | its own lane scripts — the bash files that actually do the work |
| the `drop` / `status` / `logs` / `out` protocol | the generators, compilers and probes those lane scripts call |
| the batch manifest format (`agent/batch.json`) and `progress.sh`'s reporting of it | its own data, fixtures and results |
| the egress allowlist *mechanism* (`allow.sh`, `proxy/allowlist.txt`) | which hostnames it needs added to that allowlist |
| the `mounts.conf` *mechanism* (how a mount line is read and applied) | its own entries in that machine's `mounts.conf` (per-machine, gitignored, never committed here) |

A project's lane is *dropped* here and archived into
`agent/drop/.done/` once it has run. It is never checked into this repo.
There is no `agent/templates/` directory, deliberately: a template is
where a project's script starts living in the tool's repo.

If you ever find a project-specific script, template or wording inside
Airlock outside `mounts.conf` and `proxy/allowlist.txt` — both
deliberately per-machine and gitignored — that is drift, not design.

## The `airlock` command

`<airlock>/airlock` is a single python3 file, standard library only, no
install step. It is the documented front door: it **checks a lane before
it becomes a run**, and it refuses rather than queueing something that
will fail in twenty minutes' time.

It is still a *client*. The file protocol underneath stays the truth: a
hand-drop into `agent/drop/` and every shell script below keep working
exactly as they do, with or without it. Nothing downstream may require
it to exist.

```
<airlock>/airlock --help
<airlock>/airlock doctor
```

| command | what it does |
|---|---|
| `airlock up [...]` | start the sandbox. Delegates to `up.sh` |
| `airlock down [--networks] [--force]` | stop and remove the containers. Delegates to `down.sh`, and so inherits its refusal while a lane is running |
| `airlock submit <lane.sh> (--batch <label> [--weight N] \| --no-batch)` | validate the lane, decide its batch, then drop it hidden-then-renamed into `agent/drop/` |
| `airlock status [<lane.sh>]` | compact view of one lane, or of the queue and the recent runs |
| `airlock watch [--interval N]` | the same view, refreshed (default every 2s) |
| `airlock allow <sub> [...]` | manage the egress allowlist. Delegates to `allow.sh` |
| `airlock doctor` | podman and container state, cores actually granted versus the configured cap, `quadlet` versus `up.sh` disagreement, non-`.sh` clutter in `agent/drop`, toolchains inside the runner, the allowlist, and free space — each finding with a severity and a one-line "what to do" |
| `airlock help` | the help text |

`up`, `down` and `allow` **delegate** to the shell scripts rather than
reimplementing them, so no podman flag is ever spelled twice. Each
delegation prints the exact command it is running.

### submit refuses, by name, with a non-zero exit

| # | refusal |
|---|---|
| 1 | the lane file does not exist |
| 2 | the lane file is not readable |
| 3 | its name does not end in `.sh` — the daemon would never run it, and it would sit in `agent/drop` forever |
| 4 | its name starts with `.` — `is_runnable()` ignores those permanently |
| 5 | there is no `agent/drop` directory to put it in |
| 6 | a lane of that name is already queued in `agent/drop` |
| 7 | a lane of that name is already archived in `agent/drop/.done` — reusing the name would overwrite the earlier run's status record |
| 8 | the file has no shebang |
| 9 | no batch decision was made — neither `--batch` nor `--no-batch` |
| 10 | `--batch` names a different label than `agent/batch.json` already carries, and `--new-batch` was not given |

Rows 1–4 and 6–8 are lane-level refusals, reported together so one run
tells you everything wrong with the lane. Rows 9 and 10 are decided
before the lane is read at all. **A batch decision is mandatory** — no
default — so a lane is never queued without a denominator to report
progress against.

Row 5 is the one addition to the list of nine that SandboxDesign's
`sandbox` documented: the code always refused a missing `agent/drop`,
but that path was never counted. The *behaviour* is carried across
unchanged; only the count is corrected.

### submit warns, and drops anyway

- the lane prints no `[n/total]`-style progress line, so `progress.sh`
  will show it as "running, no progress line in its log yet" for the
  whole run
- the shebang names something other than a shell (the daemon execs
  `/bin/bash <lane>` regardless, so the shebang is decoration)
- the file has CRLF line endings
- `--batch` was given with no `--weight`, so the lane counts as 1

### flags

| flag | what it means |
|---|---|
| `--batch <label>` | write or extend `agent/batch.json` under this label |
| `--no-batch` | drop with no manifest, deliberately |
| `--weight <n>` | this lane's weight in the batch, in whatever unit the batch uses |
| `--new-batch` | replace an existing manifest that carries a different label |
| `--dry-run` | validate and say what would happen; write nothing |
| `--root <dir>` | act on a different Airlock tree. Also `AIRLOCK_ROOT`. Precedence: `--root`, then `AIRLOCK_ROOT`, then `SANDBOX_DESIGN_ROOT`, then the directory `airlock` lives in |
| `--limit <n>` | how many finished lanes `status` lists (default 10) |
| `--interval <s>` | `watch` refresh period |

Exit codes: **0** success, **1** a refusal or a real fault about the
tree's contents, **2** a usage error.

`airlock` does not reimplement `progress.sh` — every view ends by
pointing at it. It does not replace `submit.sh` either: `submit.sh`
moves a lane with `podman cp` and is right when you have podman, while
`airlock submit` performs the hand-drop that needs none.

## The shell scripts underneath

Every script `cd`s to its own directory first, so all of these work from
anywhere once you use a full path.

| command | what it does |
|---|---|
| `bash <airlock>/build.sh` | builds both container images — **the only phase with open network access** |
| `bash <airlock>/up.sh` | creates the two networks and starts the proxy and runner |
| `bash <airlock>/down.sh [--networks] [--force]` | stops and removes the containers. **Refuses while a lane of that instance is running**, naming the lane; `--force` overrides |
| `bash <airlock>/selftest.sh` | one repo-hygiene check plus six checks that prove the sandbox behaves as designed: nothing publishable names a person or machine, daemon alive, a submitted lane actually runs, half-written files are not executed, an allowed host is reachable, an undeclared host is refused, and there is no second route out |
| `bash <airlock>/submit.sh <lane.sh> [--follow]` | hands one lane to the running sandbox with `podman cp` |
| `bash <airlock>/submit_project.sh [--also DIR] [--env K=V] <host-dir> <command...>` | copies a whole directory into `/work` and runs a command against the **copy** |
| `bash <airlock>/batch.sh <label> <lane.sh>:<weight> ...` | declares a batch manifest so `progress.sh` can report weighted completion and an ETA |
| `bash <airlock>/progress.sh [-w]` | one snapshot (or `-w` to refresh) of queued/running/finished lanes |
| `bash <airlock>/allow.sh list\|add\|remove\|sync\|denied` | manage the egress allowlist, and see what was refused |
| `bash <airlock>/logs.sh [substring\|--daemon\|--pull DIR]` | read run logs out of the sandbox |
| `bash <airlock>/pull.sh <dest-dir> [--logs]` | copy `/out` (and optionally `/logs`) back to the host |
| `bash <airlock>/report.sh` | writes container state, image sizes, the daemon log, proxy refusals and a selftest run into `DevComms/sandbox_report.txt` |
| `bash <airlock>/probe_host.sh` | inventories the host machine's toolchains, read-only, into `DevComms/host_inventory.txt` |
| `bash <airlock>/install_quadlet.sh [--remove]` | hands the sandbox to systemd |
| `bash <airlock>/scrub_check.sh [-q]` | refuses personal or machine-identifying strings in anything git would publish. See [Keeping personal information out](#keeping-personal-information-out) |

`DevComms/sandbox_report.txt` and `DevComms/host_inventory.txt` are
gitignored: they describe one machine, not the tool.

## Getting started

```
git clone <wherever this lives> airlock
cd airlock

cp proxy/allowlist.txt.example proxy/allowlist.txt   # required: the proxy
                                                     # default-denies
cp mounts.conf.example mounts.conf                   # optional: expose
                                                     # directories to runs
$EDITOR mounts.conf

bash ./build.sh        # builds both images; the only networked phase
bash ./up.sh           # starts the two containers
bash ./selftest.sh     # one hygiene check and six sandbox checks; all seven should PASS
./airlock doctor       # everything else it can tell you
```

`build.sh` takes a while — it is installing an entire multi-language
toolchain into the image so that no *run* ever needs the network for its
own setup.

## Using this from a project

A project drives Airlock by writing files. Concretely, today:

1. The project writes its own lane scripts — plain bash, one job each —
   and keeps them **in its own repo**. A lane might compile and run a
   test suite, or execute a long batch of probes against a read-only
   mount.
2. If several lanes are launched together, the project declares the
   batch first, so `progress.sh` can attribute weight from the very
   first snapshot. `airlock submit --batch <label> --weight <n>` writes
   and extends the manifest as it goes; `batch.sh` writes it in one shot.
3. The project submits each lane:
   `<airlock>/airlock submit path/to/lane.sh --batch <label> --weight <n>`.
4. The project polls `<airlock>/agent/status/<lane>.status` per lane
   (or runs `airlock status`, or watches `progress.sh` for the whole
   batch), then reads `<airlock>/agent/logs/` and `<airlock>/agent/out/`
   for results.

Point a project at its Airlock by exporting `AIRLOCK_ROOT`, or by
passing `--root`. Nothing else needs configuring on the project's side.

**This is a file-based protocol. There is no library wrapper.** No
importable module, no function calls — just files landing in folders
according to the naming convention above. A thin project-side client is
a possible future addition that has **not been designed or ruled on**;
nothing here should be read as a proposal for its shape.

## Progress, and the batch manifest

```
bash <airlock>/progress.sh          one snapshot
bash <airlock>/progress.sh -w       refresh every 2s
```

Always shows: queued lanes, the running lane with its latest progress
line, live processes inside `sandbox-runner`, and the ten most recently
finished lanes.

If a set of lanes was launched together as a **batch**, `progress.sh`
also prints a summary block at the top: lanes done / total, percentage
**by weight** (not by lane count — a large lane and a small lane are not
equal), elapsed time, and an ETA. The current lane gets its own
percentage, read from a `[n/total]`-style line in its log, and its own
ETA. Every ETA is labelled an estimate and prints "not enough data yet"
rather than a number computed from too little throughput.

The manifest:

```json
{
  "batch_id": "batch-20260822T140512Z",
  "label": "acceptance-sweep",
  "created": "2026-08-22T14:05:12+00:00",
  "lanes": [
    { "script": "verify.sh", "weight": 40 },
    { "script": "all.sh", "weight": 120 },
    { "script": "rust.sh", "weight": 60 }
  ]
}
```

`weight` is any unit comparable across the lanes in one batch —
work-item count is typical.

**One lane object per line matters.** `progress.sh`'s parser is
line-based, not a general JSON parser: a hand-edited manifest that wraps
a lane across several lines is silently read as no lane at all. Both
writers — `batch.sh` and `airlock submit` — emit the same byte-shape for
exactly this reason.

`progress.sh` matches each lane's `script` against
`agent/status/<script>.status`. With no manifest present it behaves
exactly as it otherwise does, plus one line noting the absence; a
missing or malformed manifest never makes it fail.

## Instances

An **instance** is one running sandbox: its own runner container, its own
proxy, its own networks, its own agent lane, its own caps. One Airlock
install runs as many as you ask for, side by side.

```
bash ./up.sh                                    the default instance, `sandbox`
bash ./up.sh --instance trickle --cpus 6        a second one, beside it
./airlock --instance trickle submit lane.sh --batch regen --weight 400
bash ./progress.sh --instance trickle -w
bash ./down.sh --instance trickle               takes down only that one
./airlock doctor                                lists every instance
```

**Airlock is never copied to get a second sandbox.** Before instances, a
project that needed one cloned this repo and rewrote the names in it — a
fork, with the tool's own bug fixes stranded on one side of it. That is
what an instance replaces.

### Every name comes from the instance name

| thing | name |
|---|---|
| runner container | `<instance>-runner` |
| proxy container | `<instance>-proxy` |
| internal network | `<instance>-internal` |
| egress network | `<instance>-egress` |
| systemd units | `<instance>-runner.service`, and so on |
| agent lane | `agent/` for `sandbox`; `~/AirlockRuns/<name>/agent/` for any other |

The derivation lives in **one file, `instance.sh`**, and nothing else spells
a container name. Every script sources it; the `airlock` CLI asks it rather
than reimplementing it, so the CLI and the scripts can never drift apart.

The default instance is `sandbox`, and its names are the names Airlock has
always used — `sandbox-runner`, `sandbox-proxy`, `sandbox-internal`,
`sandbox-egress`, `sandbox-persist`. An install that never names an instance
behaves exactly as it did before instances existed.

### An instance's settings

`instances/<name>.conf`, one `key = value` per line, `#` comments. **Every
key is optional**: what is not written falls back to the built-in default,
which is the value Airlock hardcoded before instances existed. The file is
per-machine and gitignored, exactly like `mounts.conf`. Copy
`instances/sandbox.conf.example` and edit.

A whole second sandbox is that file plus a flag. This one runs at half a
twelve-core machine, with no route out at all, sharing the default
instance's toolchain volume read-only:

```
cpus            = 6
memory          = 8g
proxy           = no
persist_volume  = sandbox-persist
persist_mode    = ro
```

### An instance's run tree lives outside the checkout

`agent/drop`, `agent/status`, `agent/logs` and `agent/out` are a **run
record**, not a tool file. The default instance keeps its tree at
`<airlock>/agent`, where it has always been. **Every other instance's tree
defaults to `~/AirlockRuns/<name>/agent`**, outside the checkout entirely,
and `up.sh` creates it on the first start. Nothing about a run then sits
beside source, and no ignore rule is load-bearing for keeping products out
of version control. The `agent_dir` key in `instances/<name>.conf` overrides
this for any instance, including the default one.

`airlock doctor` lists both places — `instances/*.conf` for an instance's
settings and `~/AirlockRuns/*` for its run tree — because either can exist
without the other: an instance needs no conf file at all, since every key
has a default, and such an instance leaves its only trace under
`~/AirlockRuns`.

### One instance per task, and why a jam stays local

**Execution inside one instance is serial, deliberately.** The daemon runs
one lane to completion before starting the next; concurrent heavy runs are
what exhaust the scratch tmpfs, and there is no `workers` key to change
that. The consequence is that a long lane holds up every lane behind it —
in **that instance**, and only there.

So the unit of separation is the instance: **one task, one instance.** Two
tasks that share an instance queue behind each other and, worse, can stop
each other — on 2026-09-02 one agent took a shared instance down at the end
of its own work while a second agent's lane was mid-run, and the second
agent saw no error, only a run that had stopped. `down.sh` now refuses in
exactly that situation, naming the running lane, and `--force` is the
deliberate override. A slow lane — a trickle — jams its own instance's
queue and nothing else on the machine: another instance has its own runner,
its own drop folder and its own caps, and never waits behind it.

### The image is shared, so a second instance never forces a rebuild

`runner_image` defaults to `sandbox-runner:latest` for **every** instance,
because an image is a build artifact rather than instance state. A second
instance starts on the image the first one built. Override it only if you
deliberately built a different one.

### Two instances cannot collide

They share no container, no network and no drop folder. `up.sh` refuses to
reuse a runner bound to a different agent tree, by name, rather than
silently watching the wrong folder. `airlock doctor` lists every instance
and whether each one is running, so "what else is on this machine" is never
a guess.

## Configuration

| setting | default | where it lives | how to change it |
|---|---|---|---|
| `AIRLOCK_CPUS` | **6** — the full share. Ruled 2026-08-22: the default is full, and the user throttles as they see fit | resolved by `instance.sh` at container start. Precedence: `up.sh --cpus N`, then `AIRLOCK_CPUS`, then `SANDBOX_CPUS`, then the `cpus` key in `instances/<name>.conf`, then 6 | `AIRLOCK_CPUS=3 bash ./up.sh` throttles a long run so it does not hold every core hot for hours; roughly halving the cores roughly doubles the wall clock. A fixed share, not a feedback loop. `SANDBOX_CPUS` is the older spelling and is still read, **after** `AIRLOCK_CPUS` |
| runner memory | `12g` | the `memory` key in `instances/<name>.conf` | one place. `up.sh` reads it, and `install_quadlet.sh` renders it into the systemd unit it installs, so the manual and the systemd path can no longer disagree |
| proxy memory / CPU | `512m` / `1` cpu | the `proxy_memory` and `proxy_cpus` keys | the proxy does no compute work; raising these is rarely useful |
| `/tmp` tmpfs cap | `2g` | the `tmp_size` key | raise deliberately if a run needs more |
| `/work` tmpfs cap | `4g` | the `work_size` key | same. This is also where `submit_project.sh` copies a project in, so a multi-gigabyte copy-in needs the cap raised first, or should use a read-only mount instead of a copy |
| `LANE_NICE` | `15` | the `lane_nice` key; read by `daemon/watcher.py` and applied via `os.nice()` before each lane execs | set it per instance. A lane still competes for CPU under the cpu cap, just gently |
| `SCRIPT_TIMEOUT` | `3600` seconds | the `script_timeout` key; read by `daemon/watcher.py` | set it per instance. On expiry the OS stops the run; the daemon records its own token in the status file and `airlock status` renders the outcome as **ABORT** |
| `AIRLOCK_INSTANCE` | `sandbox` — the default instance | env var read by `instance.sh` and by `airlock` | `--instance <name>` on any script or on `airlock` overrides it. Every container, network, volume and unit name is derived from it in `instance.sh`, and nowhere else |
| `instances/<name>.conf` | absent — every key falls back to its built-in default | `<airlock>/instances/`, gitignored, per-machine | `cp instances/sandbox.conf.example instances/<name>.conf` and edit. Keys: `cpus`, `memory`, `pids_limit`, `tmp_size`, `work_size`, `proxy`, `proxy_memory`, `proxy_cpus`, `proxy_pids_limit`, `allowlist_file`, `mounts_file`, `agent_dir`, `runner_image`, `proxy_image`, `persist_volume`, `persist_mode`, `lane_nice`, `script_timeout`, `watch` |
| `proxy` (per instance) | `yes` | the `proxy` key in `instances/<name>.conf` | `proxy = no` starts no proxy and no egress network: the instance has **no route out at all**. `selftest.sh` reports checks 4–6 as SKIP for such an instance instead of a verdict it cannot reach |
| `persist_volume` / `persist_mode` | `<instance>-persist`, `rw` | same file | point a second instance at another instance's volume with `persist_mode = ro` to share a toolchain it must not be able to alter |
| `AIRLOCK_WATCH` | `inotify` | the `watch` key in `instances/<name>.conf`; read by `daemon/watcher.py` | `poll` rescans `/drop` every `AIRLOCK_POLL_INTERVAL` seconds (default 2) and uses **no inotify resource at all**. `auto` tries inotify and falls back to polling, loudly, only on the ENOSPC that means the kernel has none left. See [When inotify runs out](#when-inotify-runs-out) |
| `AIRLOCK_ROOT` | unset — `airlock` uses its own directory | env var read by `airlock` | export it to point a project at a particular Airlock tree. `--root` overrides it; `SANDBOX_DESIGN_ROOT` is read after it |
| `mounts.conf` | none — no host directory is exposed | `<airlock>/mounts.conf`, gitignored, per-machine; an instance may name a different file with `mounts_file` | `cp mounts.conf.example mounts.conf` and edit. One `<host>:<container>[:mode]` per line, default read-only. **This file is the only place a real path is ever named**, and it is never committed |
| egress allowlist | none until you copy the example — the proxy default-denies | `<airlock>/proxy/allowlist.txt`, gitignored, per-machine; every instance shares it unless one names its own with `allowlist_file` | `cp proxy/allowlist.txt.example proxy/allowlist.txt`, then `bash ./allow.sh add <hostname>...`, which rewrites the file and reloads squid without restarting the container |

An instance's cpu setting is resolved in one place, and
`install_quadlet.sh` renders it into the systemd unit it installs, so the
manual and the systemd-managed sandbox run at the same speed by
construction. `airlock doctor` still compares the two on every run and
reports a WARN if they ever drift apart.

### When inotify runs out

The daemon's doorbell is inotify, and inotify has two per-user kernel
limits: how many **instances** may exist (`max_user_instances`, 128 on a
stock Ubuntu) and how many **watches** (`max_user_watches`, 65,536). An
editor indexing a large tree can hold tens of thousands of watches on its
own. When either is exhausted the call fails with `ENOSPC`, whose message
reads **"No space left on device"** — which is about the limit, not about
disk, and has misdirected at least one operator into diagnosing storage.

Measured on one machine, 2026-09-02, with the daemon refusing to start:

```
inotify INSTANCES open : 114 / 128
inotify WATCHES held   : 65470 / 65536
   62684 watches  <one editor>
```

`watch = poll` in an instance's conf replaces the doorbell with a `/drop`
rescan every two seconds. It needs no kernel resource at all. It is **off by
default** because it is strictly worse — a lane waits up to one interval
before starting — and nothing else about a run changes: same lane, same log,
same status file, same archive. `watch = auto` takes inotify when it can and
falls back with three loud log lines when it cannot.

Raising a kernel limit is a system settings change and Airlock never makes
one.

## The image inventory

Verified line by line against `<airlock>/Containerfile` on 2026-08-22.
Base image `docker.io/library/ubuntu:26.04`.

| category | what is installed |
|---|---|
| compilers / build tools | gcc-15, g++-15, clang-21, lld-21, llvm-21 (symlinked to unsuffixed names), build-essential, make, cmake, ninja-build, pkg-config |
| Python | Ubuntu's own `python3` **and** a separately installed Python 3.13 via `uv`, placed in a writable venv at `/opt/venv` that is first on `PATH` — so `python`, `python3` and `pip` all mean 3.13 inside the container. Ubuntu's own tooling still uses `/usr/bin/python3` by hardcoded path |
| Go | `golang-1.26`, on `PATH` via `/usr/lib/go-1.26/bin` |
| Rust | 1.96.1 via rustup (not apt-packaged), under `/opt/cargo` and `/opt/rustup` |
| Node | apt's `nodejs` and `npm`, with a best-effort upgrade to `npm@11` that is allowed to fail without failing the build |
| Java | `openjdk-25-jdk-headless` |
| other languages | ruby, perl, php-cli |
| misc tooling | git, jq, ripgrep, fd-find (symlinked to `fd`), plocate, inotify-tools, curl, wget, unzip, xz-utils, ca-certificates |

**Deliberately absent, by recorded decision (2026-07-30):** Haxe and
Flutter. The `Containerfile` says so in its own comment.

**Also absent, verified against the `Containerfile`, but not recorded
anywhere as a deliberate decision** — treat the omission as current
fact, not a ruled-on choice: .NET/dotnet, Anaconda/conda, Kotlin, Scala,
Swift, Dart, Zig, Nim, OCaml, Haskell, Julia, R, Lua.

**Unverified.** The Ubuntu package versions above are what the
`Containerfile` *requests*; the versions an actual build resolves to
were not observed, because `podman` was not available in the session
that wrote this document. `bash <airlock>/report.sh` prints the real
answer from a running container.

Adding a toolchain is a change to the `Containerfile` and a rebuild, not
a per-run configuration change.

## How the parts fit

```
  ┌────────────────────────────────────────────────────────┐
  │ host                                                   │
  │                                                        │
  │   airlock submit / submit.sh / a plain file write      │
  │                            │                           │
  │  ┌─────────────────────────▼───────────────────────┐   │
  │  │ sandbox-runner                                  │   │
  │  │   /drop   lanes land here, daemon watches it    │   │
  │  │   /status one status file per lane, by name     │   │
  │  │   /logs   one log per run                       │   │
  │  │   /work   scratch, cwd for every lane           │   │
  │  │   /out    products, read back by the caller     │   │
  │  │                                                 │   │
  │  │   network: sandbox-internal ONLY                │   │
  │  │   (created --internal: no route out exists)     │   │
  │  └──────────────────┬──────────────────────────────┘   │
  │                     │ http_proxy=sandbox-proxy:3128    │
  │  ┌──────────────────▼──────────────────────────────┐   │
  │  │ sandbox-proxy                                   │   │
  │  │   squid, default-deny                           │   │
  │  │   allows only hostnames in allowlist.txt        │   │
  │  │   never decrypts TLS — matches the plaintext    │   │
  │  │   "CONNECT host:443" line and tunnels or denies │   │
  │  │                                                 │   │
  │  │   networks: sandbox-internal + sandbox-egress   │   │
  │  └──────────────────┬──────────────────────────────┘   │
  └─────────────────────┼──────────────────────────────────┘
                        ▼
                    internet
```

The names above are the **default instance**'s. Every one of them is
derived from the instance name in `instance.sh`: a second instance named
`trickle` is `trickle-runner` on `trickle-internal` behind `trickle-proxy`,
running beside the first from the same install and the same image. See
[Instances](#instances).

The default instance keeps the `sandbox-` prefix it was built with, so
nothing that already uses Airlock has to change. **Consequence: do not run
Airlock's default instance and a SandboxDesign install at the same time** —
they would fight over the same container names. Naming an instance is now
the way out of that too. See `MIGRATING.md`.

## Running it under systemd

`./up.sh` starts containers that do not survive a reboot.
`./install_quadlet.sh` hands them to systemd instead — they come back on
boot and restart if the daemon stops:

```
bash ./install_quadlet.sh            # install units and start
systemctl --user status sandbox-runner
journalctl --user -u sandbox-runner -f
bash ./install_quadlet.sh --remove   # go back to ./up.sh
```

The installer generates the four agent-lane `Volume=` lines and any
`mounts.conf` lines **from this repo's own location** and splices them
into the installed copy. The unit files in the repo carry empty marker
blocks and no path at all, so a clone works wherever it lands.

Every other script works the same either way.

## Why lanes are submitted hidden-then-renamed

The kernel signals a new file when it is *created*, not when the writer
has finished. A daemon reacting to creation will sometimes execute a
script that is only half on disk.

Both `submit.sh` and `airlock submit` write the file as
`agent/drop/.name.sh` and then rename it to `agent/drop/name.sh`. The
daemon ignores every name starting with `.`, and reacts to the rename. A
rename inside one directory is atomic, so `agent/drop/name.sh` never
exists in a partial state. `selftest.sh` check 3 verifies this.

A direct write is also safe, because the daemon watches `close_write` as
well as `moved_to` — it fires when the writer closes the file, never
mid-write.

## Keeping personal information out

This repo is public. A development log, a captured transcript or a handoff
document can carry an absolute home path, an agent session mount path, an
email address or a person's name without anyone noticing until it is
already pushed.

`scrub_check.sh` is the guard. It scans **two** sets of files:

1. every **tracked** file - already publishable;
2. every **untracked but not ignored** file - `git add -A` would publish it
   next. This set matters: a working document sitting unignored in
   `DevComms/` is the likeliest accident.

It exits non-zero and lists every offender with file and line. The pattern
list lives in one place, near the top of the script, as `"<label>|<regex>"`
entries - add a line and both sets pick it up. What it looks for:

| pattern | why |
|---|---|
| `/home/<user>`, `/Users/<user>` | an absolute home path names the account that built the file. Use `~` or a repo-relative path |
| `/sessions/<name>` | an agent session mount prefix. It means nothing to a reader and identifies infrastructure; rewrite the sentence, do not leave a stub |
| an email address | usually pasted in from a config or a transcript |
| the maintainer's personal handle | the public identity for this line of work is `TheStudent00` / "The Student", which appears in the licence and is **not** scrubbed |
| a `name:uid:gid` subuid/subgid mapping | names a real account on a real machine |

Run it directly, or let `selftest.sh` check 0 run it:

```bash
bash ./scrub_check.sh
```

Machine-specific patterns that are themselves too sensitive to publish go
in `.scrub_patterns.local`, one `"<label>|<regex>"` per line. That file is
gitignored.

`scrub_check.sh` excludes itself from the match, because it necessarily
contains the patterns. It also carries a short, justified `ALLOW` list —
currently one entry, GitHub's `@users.noreply.github.com` commit address,
which is the *fix* for a leaked mailbox and has to stay quotable.

## Files

| file | what it is |
|---|---|
| `airlock` | the CLI. python3, stdlib only, executable |
| `instance.sh` | **the one place an instance's names and caps are derived.** Sourced by every shell script; read by `airlock` rather than reimplemented |
| `instances/sandbox.conf.example` | the template for `instances/<name>.conf`. The real `.conf` files, and each instance's own `instances/<name>/` tree, are per-machine and gitignored |
| `Containerfile` | the runner image; toolchains listed above |
| `daemon/watcher.py` | the hot-folder daemon. inotify through ctypes, no pip dependencies; writes `/status/<name>.status` per run and records `/work` headroom |
| `agent/` | the unattended lane: `drop/ status/ logs/ out/` bound from the host. See `agent/README.md` |
| `proxy/Containerfile.proxy`, `proxy/squid.conf`, `proxy/allowlist.txt.example` | the egress gate. The live `proxy/allowlist.txt` is per-machine and gitignored |
| `quadlet/*.container`, `quadlet/*.network`, `install_quadlet.sh` | systemd units, for running the sandbox as a managed service |
| `build.sh` `up.sh` `down.sh` `submit.sh` `logs.sh` `allow.sh` `pull.sh` `selftest.sh` | operator commands |
| `progress.sh` | snapshot of every lane; prints a batch summary when `agent/batch.json` is present |
| `batch.sh` | writes `agent/batch.json`, the manifest `progress.sh` reads |
| `submit_project.sh` | copy a host directory into `/work` and run a command against the copy |
| `report.sh` | container state and a selftest run, into `DevComms/sandbox_report.txt` |
| `probe_host.sh` | host toolchain inventory, read-only |
| `scrub_check.sh` | the publication guard: scans everything git would publish for personal or machine-identifying strings |
| `mounts.conf.example` | the template for `mounts.conf` |
| `MIGRATING.md` | moving a project from SandboxDesign to Airlock |
| `OTU GREEN LICENSE FOR UNIVERSAL WORKS.pdf` | **the licence.** The complete text, 10 pages |
| `LICENSE.md` | a pointer to that PDF. It restates no term of it |
| `DevComms/log_001_airlock_derivation.md` | how this repo was derived, what was left behind, and why |
| `DevComms/log_002_pii_scrub.md` | the personal-information scrub and the history rebuild: what was removed, the proof, the guard, and what publication does not undo |

## Licence

Airlock is released under the **OTU GREEN LICENSE FOR UNIVERSAL WORKS**
(`OTU-GL v8`), Version 8, 2026-04-27. Copyright (c) 2026 The Student.

The licence of record is `OTU GREEN LICENSE FOR UNIVERSAL WORKS.pdf` at
the root of this repository. `LICENSE.md` points at it and restates none
of its terms — read the PDF for anything you intend to rely on.

Airlock is derived from SandboxDesign, 2026-08-22.
