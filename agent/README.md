# agent/ — the unattended lane

Four host-bound directories that let a process with **no shell of its
own** run commands inside the sandbox. An agent session, a CI step, or
anything else that can write a file but cannot run podman turns a file
write into a sandbox run.

| directory | mounts at | direction | who writes |
|---|---|---|---|
| `drop/` | `/drop` | in | the caller writes `x.sh` here |
| `status/` | `/status` | out | the daemon writes `x.sh.status` |
| `logs/` | `/logs` | out | the daemon writes `<stamp>__x.sh.log` |
| `out/` | `/out` | out | the lane script writes its products here |

All four are tracked as directories and ignored as contents — each holds
a `.gitignore` of `*` and `!.gitignore`, so a fresh clone has them
present and empty.

## The loop

1. The caller puts a lane script at `<airlock>/agent/drop/run_thing.sh`.
   The documented way is `<airlock>/airlock submit run_thing.sh --batch
   <label> --weight <n>`, which validates it first and refuses ten
   named ways. A direct write is also safe — the daemon watches
   `close_write` as well as `moved_to`, so it fires when the writer
   closes the file, never mid-write. (`<airlock>/submit.sh` uses the
   hidden-then-rename path because `podman cp` needs it.)
2. The daemon runs it, `cwd=/work`, **serially** — `run_script()` is
   called synchronously from the single event loop, so two scripts
   dropped together run one after the other. Concurrent heavy runs are
   what exhaust scratch space.
3. The caller polls `<airlock>/agent/status/run_thing.sh.status`, a path
   derivable from the script name alone (the log's name embeds a run
   timestamp and so cannot be predicted). Key=value lines, written
   atomically:

   `state=running` on start, then `state=done`, `exit=<rc>`,
   `elapsed_s`, `log=<path>`, `work_consumed_mb`.

   `<airlock>/airlock status <lane.sh>` reads exactly that file and
   renders it, including mapping the timeout outcome to **ABORT**.
4. Products in `<airlock>/agent/out/` are read by the caller and placed
   into the real tree by the caller — which is why project mounts can
   stay read-only.

## What a dropped script can see

- **Whatever `mounts.conf` exposes**, at the container paths that file
  names, **read-only by default**. Nothing is exposed until a machine's
  own `mounts.conf` says so; the repo ships only
  `<airlock>/mounts.conf.example`. Read-only is the default because it
  is what makes "a run cannot damage the original" true rather than
  hoped. Write products to `/out`.
- `/work` — scratch, tmpfs, **capped** (see CONFIGURATION in
  `<airlock>/README.md`). Exceeding the cap fails loudly with ENOSPC in
  the container rather than filling the host disk. Wiped on restart.
  This is also where `<airlock>/submit_project.sh` copies a project, so
  a multi-gigabyte copy-in fails at the cap — expose such a tree
  read-only through `mounts.conf` instead, which needs no copy.
- `/persist` — a named volume that survives restarts. Opt-in, for
  iterating on something expensive across runs. Deliberately not the
  default: persistence carries corruption forward, which copy-per-run
  cannot.
- The network only through the allowlist proxy
  (`bash <airlock>/allow.sh denied` names anything refused).

## What does not live here

**No lane scripts.** A lane belongs to the project that wrote it and
lives in that project's own repo; it is *dropped* into `drop/` and
archived into `drop/.done/` once it has run. There is no `templates/`
directory in Airlock, deliberately — a template is where a project's
script starts living in the tool's repo, and that is the drift this
repo exists to make impossible.

## Progress

`bash <airlock>/progress.sh` (add `-w` to refresh) shows every lane:
queued, running with its latest `[n/total]` line, live processes inside
the container, and the ten most recently finished. If a batch manifest
was declared it prints weighted completion and an ETA on top. See
"Progress, and the batch manifest" in `<airlock>/README.md`.
