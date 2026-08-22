# log 001 — Airlock, derived from SandboxDesign

Written 2026-08-22. Airlock is a derivation of
`<sandboxdesign>`, made public-ready and project-agnostic
**by construction**. The name was ruled by the maintainer on
2026-08-22, for the mechanism: a sealed chamber between two
environments — work goes in one side, runs sealed, products come out
the other.

`<sandboxdesign>` is **not** modified, moved or
retired by this work. There is active work against it; retiring it is
the maintainer's call and appears in the awaiting-maintainer list at the
foot of this log.

## Why this repo exists

The maintainer, 2026-08-22, having said it several times before:

> the SandboxDesign main repo is not meant to be a project specific
> solution... SandboxDesign serves many purposes, not just PCHQ... i
> really dont want to have to discuss the project-agnostic nature of
> the sandbox container.

`<sandboxdesign>/DevComms/log_002_documentation_scope_correction.md`
records the last time this was fixed by rewriting prose, and its own
awaiting-maintainer list names the two things prose could not fix:
`agent/templates/pcv6_suite.sh` and the PseudoCoup sections of
`agent/README.md`. Airlock fixes those structurally: they are not in
this repo, so there is nothing to drift back into.

Three changes of stance, same machinery:

| # | stance | what it means here |
|---|---|---|
| 1 | the CLI is the front door | `airlock` is the documented way in. The file protocol underneath is still the truth and a hand-drop still works, but the docs lead with the command |
| 2 | project-agnostic by construction | nothing project-specific ships. No lane script, no template, no project name in any tracked file |
| 3 | public-ready | a stranger can read `README.md` and use it. No disc-layout assumption in any code path; no personal path and no person's name in a tracked file |

## Vocabulary

PseudoCoupHQ's `CLAUDE.md` was read first and
binds everything below — code, comments, help text, output strings,
docs and the commit message. Two bans are live in this work:

- The super-node / sub-node / co-node / sub-tree vocabulary. No
  occurrence of the banned words was introduced.
- The process-outcome ban. `daemon/watcher.py` writes
  `KILLED after <n>s timeout` into `agent/status/<lane>.status`. That
  spelling is the daemon's own and stays untouched **in the file**;
  `airlock status` renders that outcome as **ABORT** in its own output
  and names the raw token it came from. This is carried across from
  SandboxDesign unchanged, where it was already ruled.

---

## §2 structural overview — `airlock`

Bare names, `attributes:` and `methods:` headers, TAB indentation, no
logic. Plan names ARE code identifiers. This is the shape the derived
CLI carries; it is the shape
`<sandboxdesign>/DevComms/log_003_cli_plan_and_build.md`
settled today, and no name in it is replaced. What changes is spelling
of the tool, the environment variable and the help text, not structure.

```
class Finding
	attributes:
		severity
		subject
		detail
		remedy
	methods:
		line
		row

class Paths
	attributes:
		root
		drop
		done
		status
		logs
		out
		batch_file
		allowlist
		quadlet_runner
	methods:
		resolve
		script

class Lane
	attributes:
		source_path
		name
		weight
	methods:
		validate
		drop_into

class Batch
	attributes:
		batch_id
		label
		created
		lanes
	methods:
		read
		add_lane
		write
		summary

class LaneStatus
	attributes:
		name
		fields
		state
		exit_code
		started
		elapsed_s
		log_path
		verdict
	methods:
		read
		read_all
		host_log
		display_state
		progress_line
		row

class Doctor
	attributes:
		findings
	methods:
		run
		check_container
		check_cores
		check_drop_clean
		check_toolchains
		check_allowlist
		check_disk
		report

module functions
	self_root
	emit_table
	delegate
	podman_inspect
	up
	down
	submit
	status
	watch
	allow
	doctor
	usage
	main
```

### static or instance, unchanged from the source

| name | kind | why |
|---|---|---|
| `Paths.resolve` | `@staticmethod` | there is no instance until it returns one |
| `Batch.read` | `@staticmethod` | reads a file to produce an instance |
| `LaneStatus.read`, `LaneStatus.read_all` | `@staticmethod` | same, singular and plural |
| every `Doctor.check_*` | `@staticmethod` | each takes `paths`, returns a fresh list of `Finding`, touches no `Doctor` state |
| `Doctor.run`, `Doctor.report` | instance | `findings` is the Doctor's own accumulated state |
| everything in `module functions` | plain function | none of them has state |

### the one new module function

`self_root` is the only identifier added to the plan the source CLI
settled. It answers "where does this file live", so `usage()` can print
a real, correct, machine-independent path in its examples instead of
the hardcoded `<sandboxdesign>/sandbox` the source printed.
That hardcoded path is exactly the public-readiness defect stance 3
exists to remove, and it appears in help text, which is output, so it
could not be fixed by configuration alone.

### what changes inside the derived CLI, and nothing else

| change | from | to |
|---|---|---|
| program name in every string it prints | `sandbox` | `airlock` |
| root environment variable | `SANDBOX_DESIGN_ROOT` | `AIRLOCK_ROOT`, with `SANDBOX_DESIGN_ROOT` still honoured after it |
| cpu environment variable read by `doctor` | `SANDBOX_CPUS` | `AIRLOCK_CPUS`, with `SANDBOX_CPUS` still honoured after it |
| the no-tree refusal | `no SandboxDesign tree at <path>` | `no Airlock tree at <path>` |
| paths printed in `usage()` | `<sandboxdesign>/...` | derived from `self_root()` |

Not changed, deliberately: every `submit` refusal and every warning
(the nine refusals SandboxDesign's log 003 named, plus the tenth its
code always had and never counted — `no drop directory`; the behaviour
is identical, only the count is corrected), the four
warnings, the severity vocabulary REFUSE / FAULT / WARN / NOTE / OK,
the exit codes (0 success, 1 refusal or real fault, 2 usage error), the
hidden-then-rename drop, the ABORT mapping, the delegation to `up.sh` /
`down.sh` / `allow.sh`, and — the one that has a test of its own below
— `Batch.write`'s byte-shape.

### the container, network, image and volume names do NOT change

`sandbox-runner`, `sandbox-proxy`, `sandbox-internal`, `sandbox-egress`,
`sandbox-persist` and the image tags `sandbox-runner:latest` /
`sandbox-proxy:latest` keep their spellings. Three reasons:

1. `MIGRATING.md` is required to say that *what changes* is the
   command name. Renaming the containers would
   make it "the command name, and rebuild both images, and re-install
   the systemd units, and re-point every project's tooling".
2. `progress.sh`, `selftest.sh`, `allow.sh`, `report.sh`, `logs.sh`,
   `pull.sh`, `submit.sh` and `submit_project.sh` all spell those names.
   Renaming them means rewriting eight carried-across scripts, which
   contradicts carrying code across whole.
3. The names are already project-agnostic. They were never the defect.

The consequence has a cost and it is named in `MIGRATING.md`: **do not
run SandboxDesign and Airlock at the same time.** Both `up.sh` scripts test
`podman container exists sandbox-runner`, so whichever ran second would
start the other's container, bound to the other's `agent/` directories.

---

## Fate of every file in `<sandboxdesign>`

Read in full before this table was written. "Carried whole" means
byte-identical. "Carried, edited" lists the edit; for every carried
shell script and for `daemon/watcher.py` the edits are confined to
comments and the executable text is proved identical in the testing
section below.

### carried

| source file | fate in `<airlock>` | reason |
|---|---|---|
| `down.sh` | carried whole | no personal path, no project name, no rename needed |
| `allow.sh` | carried whole | same |
| `logs.sh` | carried whole | same |
| `build.sh` | carried whole | same |
| `pull.sh` | carried whole | same |
| `selftest.sh` | carried, edited (one comment word) | it is the proof the isolation holds and must not be weakened by editing, so the only change is a vocabulary one: a comment said the daemon might be "dead", which is banned for a process. Now "had aborted". Executable text byte-identical |
| `submit.sh` | carried whole | **deviation from the brief's carry list, recorded deliberately.** `selftest.sh` calls `./submit.sh` six times and `submit_project.sh` calls it once. Leaving it behind would leave two carried scripts calling a file that does not exist. It is also the podman-side drop that `airlock submit` explicitly does not replace |
| `proxy/Containerfile.proxy` | carried whole | mechanism only |
| `proxy/squid.conf` | carried whole | mechanism only |
| `proxy/allowlist.txt.example` | carried whole | already a neutral baseline of language-ecosystem hosts |
| `quadlet/sandbox-egress.network` | carried whole | mechanism only |
| `quadlet/sandbox-internal.network` | carried whole | mechanism only |
| `quadlet/sandbox-proxy.container` | carried whole | mechanism only |
| `agent/.gitignore` | carried whole | the runtime-state convention, unchanged |
| `agent/drop/.gitignore`, `agent/logs/.gitignore`, `agent/status/.gitignore`, `agent/out/.gitignore` | carried whole | `* / !.gitignore` — this IS the "fresh clone works" structure the brief asks for |
| `up.sh` | carried, edited | `AIRLOCK_CPUS` added as the new spelling, `SANDBOX_CPUS` still honoured after it, default **6** (full share, ruled by the maintainer 2026-08-22). Header comment rewritten to match |
| `progress.sh` | carried, edited (comments only) | two usage-comment lines carried `<sandboxdesign>/progress.sh`. Executable text byte-identical — proved in testing |
| `batch.sh` | carried, edited (comments only) | same two-line problem in its usage block |
| `submit_project.sh` | carried, edited (comments and one hint line) | its neutral examples still assumed a specific projects-directory name (`MyProject` under it), which bakes one machine's layout into a public example; a comment used a banned relation word for a co-located tree; and its closing hint named `git_commit_push.sh`, which is not carried across |
| `report.sh` | carried, edited (comments only) | its closing hint named `./git_commit_push.sh`, which is not carried across |
| `probe_host.sh` | carried, edited (one code line) | `REPO=<sandboxdesign>` hardcoded one machine's layout in **code**. Now derived from the script's own directory |
| `install_quadlet.sh` | carried, edited | must now render the agent-lane `Volume=` lines from the repo's own location instead of relying on a hardcoded path inside the unit file |
| `quadlet/sandbox-runner.container` | carried, edited | its four `Volume=%h/<sandboxdesign>/agent/...` lines were the single worst disc-layout assumption in the repo. Replaced by `# >>> AGENT LANE` / `# <<< AGENT LANE` markers, filled by `install_quadlet.sh` — the same mechanism the `MOUNTS` markers already used |
| `daemon/watcher.py` | carried, edited (comments only) | two comments named a person; one used a banned word for the outcome where the OS stops a process. Its own `KILLED after <n>s timeout` **data token stays exactly as it is** — changing it would break `airlock status`'s ABORT mapping and `submit_project.sh`'s completion detection. Executable text byte-identical — proved in testing |
| `Containerfile` | carried, edited (comments only) | comments named a person, a file that is not carried across, and one project's file counts; one used a banned word for stopping a build |
| `mounts.conf.example` | carried, edited (comments only) | said "SandboxDesign itself is meant to be a project-agnostic template"; examples assumed a specific projects-directory name in the path |

### renamed and rewritten

| source file | fate | reason |
|---|---|---|
| `sandbox` | → `airlock` | stance 1. Same shape, same nine refusals, same manifest byte-shape; renamed internal references and public-ready help text |
| `README.md` | → rewritten | stance 3. Written for a stranger, leading with `airlock`, with the contract, command table, configuration, verified image inventory and a "using this from a project" section |
| `agent/README.md` | → rewritten | its "What a dropped script can see" and "Templates" sections were written around `/projects/PseudoCoup_v6`, `/projects/PseudoCoup_v5` and `templates/pcv6_suite.sh`. `log_002`'s awaiting-maintainer list asked whether it should get the same pass. In Airlock the question does not arise: the file describes the mechanism only |
| `.gitignore` | → rewritten | extended to ignore every runtime directory under `agent/` and every machine-specific file |

### deliberately left behind

| source file | why it is not in Airlock |
|---|---|
| `agent/templates/pcv6_suite.sh` | a PseudoCoup_v6 lane script. This is the literal instance of the maintainer's complaint — a project's own script living in the tool's repo. It belongs to the project that owns it |
| `agent/templates/` | the directory is not created at all. With `pcv6_suite.sh` gone there is nothing generic to put in it, and an empty `templates/` is an invitation for the same drift to recur |
| `mounts.conf` | per-machine configuration naming one machine's real project trees. Correctly gitignored in the source; `mounts.conf.example` is carried and is the documentation |
| `proxy/allowlist.txt` | per-machine live egress policy. Gitignored in the source; `proxy/allowlist.txt.example` is carried |
| `agent/batch.json`, `agent/drop/.done/*`, `agent/logs/*`, `agent/out/*`, `agent/status/*` | runtime state of one machine's runs. `agent/out/` alone held 480 products |
| `create_github_repo.sh` | hardcodes `REPO=<sandboxdesign>`, names one person, and creates a **private** repo. Whether Airlock is published, and under what visibility, is the maintainer's decision — see the awaiting-maintainer list. The two commands needed are in `MIGRATING.md` |
| `git_commit_push.sh` | hardcodes the same path and describes one person's workflow with `DevComms/next_commit_message.txt` |
| `DevComms/log_001_cpu_cap_and_batch_progress.md`, `DevComms/log_002_documentation_scope_correction.md`, `DevComms/log_003_cli_plan_and_build.md`, `DevComms/log_003_shape_pass2.py` | SandboxDesign's development record. It belongs to that repo and stays readable there; this log cites it by full path where it matters |
| `DevComms/host_inventory.txt` | an inventory of one real machine — every toolchain, every SDK directory, the CPU model |
| `DevComms/last_run.txt`, `DevComms/quadlet_install.txt`, `DevComms/sandbox_report.txt` | captured output of real runs on one real machine, naming its real paths. `log_002` left these tracked in the source and flagged them; Airlock simply does not carry them, and `.gitignore` keeps their equivalents out |
| `DevComms/next_commit_message.txt` | a handoff file for `git_commit_push.sh`, which is not carried |
| `__pycache__/`, `DevComms/__pycache__/`, `daemon/__pycache__/` | build artefacts |

### new in Airlock

| file | what it is |
|---|---|
| `MIGRATING.md` | for a project already using SandboxDesign: what changes (the command name), what does not (the file protocol, every path under `agent/`), and the exact commands |
| `LICENSE.md` | a placeholder. The licence is the maintainer's to pick — see the awaiting-maintainer list |
| `DevComms/log_001_airlock_derivation.md` | this file |
| `DevComms/log_001_shape_pass2.py` | the pass-2 snapshot, so the middle pass is auditable rather than asserted. Same convention as `<sandboxdesign>/DevComms/log_003_shape_pass2.py` |

---

## Pass 2 — the shape

Recorded at `DevComms/log_001_shape_pass2.py`: every class and function
of `airlock` with its real signature and its docstring, and `raise
NotImplementedError` for a body. It compiles clean. It matches the §2
overview above identifier for identifier.

The three-pass rule governs what is **written**, not what is **moved**.
Code carried across from `<sandboxdesign>` is
carried whole in one step; there is no meaning in stubbing out a file
that already exists and already works.

## Pass 3 — the logic

Filled in last. What follows is the evidence.

---

## Testing

`podman` is not on `PATH` in this session, so nothing that needs a
running container could be exercised. Everything below was run against
a throwaway tree under `/tmp`. **Nothing under
`<sandboxdesign>/agent` was written to**, and
`<sandboxdesign>` was not modified at all.

Paths in the rendered output below are shown in the form they take on
a real install, one repo per top-level entry rather than the mount
path this run actually used. The run itself saw them through a
temporary agent session mount prefix, which carries no meaning outside
that session.

### the fixtures

Two throwaway trees:

| tree | what is in it |
|---|---|
| `/tmp/airlock_fake` | `agent/drop` (one queued lane, one duplicate-name lane, one piece of non-`.sh` clutter, a `.done/` holding an archived lane), `agent/status` (one finished, one running, one stopped-by-the-OS), `agent/logs` with matching `[n/total]` lines, `agent/out`, `proxy/allowlist.txt` with 3 hostnames, a `quadlet/sandbox-runner.container` carrying the real `PodmanArgs=--cpus=6`, an `up.sh` carrying the real `AIRLOCK_CPUS:-${SANDBOX_CPUS:-6}` line, stand-in `up.sh`/`down.sh`/`allow.sh` for the delegation test, **the real unmodified `progress.sh`**, **the real `batch.sh`**, and ten lane fixtures |
| `/tmp/airlock_broken` | the same with `agent/` and `proxy/` missing outright, to force FAULTs and a non-zero exit |

### static checks

`bash -n` on every shell script in `<airlock>`:

```
  syntax OK  allow.sh          syntax OK  progress.sh
  syntax OK  batch.sh          syntax OK  pull.sh
  syntax OK  build.sh          syntax OK  report.sh
  syntax OK  down.sh           syntax OK  selftest.sh
  syntax OK  install_quadlet.sh syntax OK submit.sh
  syntax OK  logs.sh           syntax OK  submit_project.sh
  syntax OK  probe_host.sh     syntax OK  up.sh
```

`python3 -m py_compile`:

```
  compiles   airlock
  compiles   daemon/watcher.py
  compiles   DevComms/log_001_shape_pass2.py
```

### carried across whole — byte-identical, verified with `cmp`

```
  identical  down.sh                              identical  quadlet/sandbox-egress.network
  identical  allow.sh                             identical  quadlet/sandbox-internal.network
  identical  logs.sh                              identical  quadlet/sandbox-proxy.container
  identical  build.sh                             identical  agent/.gitignore
  identical  pull.sh                              identical  agent/drop/.gitignore
  identical  submit.sh                            identical  agent/logs/.gitignore
  identical  proxy/Containerfile.proxy             identical  agent/status/.gitignore
  identical  proxy/squid.conf                      identical  agent/out/.gitignore
  identical  proxy/allowlist.txt.example
```

### carried with comment edits — executable text identical

Comparing both files with comment lines and blank lines stripped:

```
  code identical  progress.sh
  code identical  batch.sh
```

The remaining carried files differ only in text a reader sees, never in
what runs. Every difference, in full:

| file | the whole difference |
|---|---|
| `daemon/watcher.py` | one docstring line that named a person on the host, rewritten to `anything else on the host`; one comment line rewritten to remove a banned word for the OS-stopped outcome |
| `submit_project.sh` | four example lines that named a specific projects directory → `~/code/...`; one comment word (`sibling` → `co-located tree`); two closing `echo` lines that named `git_commit_push.sh` |
| `report.sh` | two closing `echo` lines that named `git_commit_push.sh` |
| `probe_host.sh` | `REPO=<sandboxdesign>` → `REPO="$(cd "$(dirname "$0")" && pwd)"`, plus two closing `echo` lines |
| `selftest.sh` | one comment word |
| `Containerfile` | comment block only |
| `mounts.conf.example` | comment block only |

### vocabulary sweep over every tracked file

```
  parent      0      death       0
  child       0      died        0
  children    0      dead        0
  sibling     0
  ancestor    0
  descendant  0
  orphan      0
```

`KILLED` survives in seven places, every one of them the daemon's own
data token or a reference to it — `daemon/watcher.py` writes it,
`airlock` reads it to render **ABORT**, and `submit_project.sh` greps
for it to know a run has finished. Changing it would break all three.

Also swept clean across every tracked file: `PseudoCoup`, `PCHQ`,
`PseudoIR`, `pcv6`, the absolute home path of the account that built it,
and agent session mount paths. The remaining hits are
confined to `DevComms/log_001_airlock_derivation.md` (this file, which
must name what it left behind and where), `LICENSE.md` (which is
required to name the candidate licence's location) and `MIGRATING.md`
(which is required to name the repo being migrated from).

---

### `airlock --help`

```
$ <airlock>/airlock --help
airlock - the command-line front door to an Airlock sandbox.

Airlock runs a bash script inside a container with a capped cpu
share, capped memory, size-capped scratch filesystems, every
capability dropped, and no route to the internet except a proxy
that permits only hostnames declared in advance.

The file protocol underneath stays the truth: agent/drop ->
agent/status -> agent/logs -> agent/out. This program checks
before it writes. A hand-drop, and every shell script in this
repo, keep working with or without it.

this repo: <airlock>

usage:
  <airlock>/airlock <command> [...]
  python3 <airlock>/airlock <command> [...]

commands
| command | what it does |
|---|---|
| up [...] | start the sandbox - delegates to up.sh, so --cpus/--memory/tmpfs caps have one spelling |
| down [--networks] | stop and remove the containers - delegates to down.sh |
| submit <lane.sh> ... | validate a lane, decide its batch, then drop it into agent/drop |
| status [<lane.sh>] | compact view of one lane, or of the queue and recent runs |
| watch [--interval N] | the same view, refreshed (default every 2s) |
| allow <sub> [...] | manage the egress allowlist - delegates to allow.sh |
| doctor | check podman, cores, drop clutter, toolchains, allowlist, disk |
| help | this text |

submit flags
| flag | what it means |
|---|---|
| --batch <label> | write or extend agent/batch.json under this label. Required, unless --no-batch |
| --no-batch | drop with no manifest, deliberately. progress.sh then has no denominator for this lane |
| --weight <n> | this lane's weight in the batch, in whatever unit the batch uses. Defaults to 1, with a warning |
| --new-batch | replace an existing manifest that carries a different label |
| --dry-run | validate and say what would happen; write nothing |

submit refuses, by name, with a non-zero exit, when:
  - the lane file does not exist
  - the lane file is not readable
  - its name does not end in .sh
  - its name starts with '.'
  - there is no drop directory to put it in
  - a lane of that name is already queued in agent/drop
  - a lane of that name is already archived in agent/drop/.done
  - the file has no shebang
  - no batch decision was made (neither --batch nor --no-batch)
  - --batch names a different label than agent/batch.json already
    carries, without --new-batch

submit warns, and drops anyway, when:
  - the lane prints no [n/total]-style progress line
  - the shebang is not a shell (the daemon execs /bin/bash regardless)
  - the file has CRLF line endings
  - --batch was given with no --weight

global flags
| flag | what it means |
|---|---|
| --root <dir> | act on a different Airlock tree. Also AIRLOCK_ROOT, and SANDBOX_DESIGN_ROOT after it for anyone migrating from SandboxDesign. Precedence: --root, then AIRLOCK_ROOT, then SANDBOX_DESIGN_ROOT, then the directory this file lives in |
| --help, -h, help | this text |

what this program does NOT do:
  - it does not replace submit.sh. submit.sh moves a lane with
    podman cp and is right when you have podman; this writes the
    same hidden-then-rename hand-drop, which needs no podman.
  - it does not reimplement progress.sh. For the full view, including
    live processes inside the container:
      bash <airlock>/progress.sh     one snapshot
      bash <airlock>/progress.sh -w  refreshing
[exit 0]
```

Note `this repo:` and both `usage:` lines. Those are computed by
`self_root()`; the source CLI printed a hardcoded home directory there.

---

### every refusal, rendered

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/nope.sh --no-batch
REFUSED: /tmp/airlock_fake/lanes/nope.sh was not dropped.

  REFUSE nope.sh: no such lane file: /tmp/airlock_fake/lanes/nope.sh
         what to do: check the path, or write the lane first
[exit 1]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/unreadable.sh --no-batch
REFUSED: /tmp/airlock_fake/lanes/unreadable.sh was not dropped.

  REFUSE unreadable.sh: lane file is not readable: /tmp/airlock_fake/lanes/unreadable.sh
         what to do: chmod u+r /tmp/airlock_fake/lanes/unreadable.sh
[exit 1]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/wrong_ext.txt --no-batch
REFUSED: /tmp/airlock_fake/lanes/wrong_ext.txt was not dropped.

  REFUSE wrong_ext.txt: the daemon only runs *.sh; wrong_ext.txt would never be executed and would sit in /tmp/airlock_fake/agent/drop forever
         what to do: rename it to end in .sh
[exit 1]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/.hidden.sh --no-batch
REFUSED: /tmp/airlock_fake/lanes/.hidden.sh was not dropped.

  REFUSE .hidden.sh: a name starting with '.' is ignored forever by daemon/watcher.py is_runnable(); it would sit in /tmp/airlock_fake/agent/drop and no agent session can unlink it
         what to do: rename the lane so it does not start with '.'
[exit 1]
```

```
$ airlock --root /tmp/airlock_broken submit /tmp/airlock_fake/lanes/good_lane.sh --no-batch
REFUSED: /tmp/airlock_fake/lanes/good_lane.sh was not dropped.

  REFUSE good_lane.sh: no drop directory: /tmp/airlock_broken/agent/drop
         what to do: bash /tmp/airlock_broken/up.sh (it creates the agent lane directories)
[exit 1]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/dup.sh --no-batch
REFUSED: /tmp/airlock_fake/lanes/dup.sh was not dropped.

  REFUSE dup.sh: a lane of this name is already queued (or running) at /tmp/airlock_fake/agent/drop/dup.sh
         what to do: wait for it, or give this lane a different name

also noticed (would not on their own have refused):
  WARN   dup.sh: no [n/total]-style progress print found in /tmp/airlock_fake/lanes/dup.sh; progress.sh reads exactly that for the current lane's percentage and ETA, so this lane will show as 'running, no [n/total] progress line in its log yet' for its whole run
         what to do: print a line containing [$i/$total] as the lane advances
[exit 1]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/archived.sh --no-batch
REFUSED: /tmp/airlock_fake/lanes/archived.sh was not dropped.

  REFUSE archived.sh: a lane of this name has already run: /tmp/airlock_fake/agent/drop/.done/20260822T000000Z__archived.sh
         what to do: reusing the name overwrites /tmp/airlock_fake/agent/status/archived.sh.status, losing the earlier run's record - give this lane a new name
[exit 1]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/noshebang.sh --no-batch
REFUSED: /tmp/airlock_fake/lanes/noshebang.sh was not dropped.

  REFUSE noshebang.sh: no shebang on the first line of /tmp/airlock_fake/lanes/noshebang.sh (saw 'echo "[1/1] no shebang here"')
         what to do: add #!/usr/bin/env bash as the first line
[exit 1]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/good_lane.sh
REFUSE: no batch decision.
        Every lane needs a denominator or an explicit refusal of one, so nothing is dropped silently again.
        Give --batch <label> [--weight N] to write or extend /tmp/airlock_fake/agent/batch.json,
        or --no-batch to drop this lane with no manifest.
[exit 2]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/good_lane.sh --batch other-sweep --weight 80
REFUSED: /tmp/airlock_fake/agent/batch.json already carries the batch 'fake-sweep', not 'other-sweep'.
         batch 'fake-sweep' (id batch-20260822T143044Z, created 2026-08-22T13:40:44+00:00): 4 lane(s), total weight 250
         Use --batch fake-sweep to join it, or --new-batch to replace the manifest deliberately.
[exit 1]
```

### the four warnings, which do not refuse

Both run with `--dry-run`, so nothing was written.

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/python_lane.sh --batch fake-sweep --weight 5 --dry-run
  WARN   python_lane.sh: the shebang names 'python3', but daemon/watcher.py execs /bin/bash <lane> unconditionally, so this lane will be run by bash whatever the shebang says
         what to do: make the lane a bash script that calls python3, or accept that the shebang is decoration here
  WARN   python_lane.sh: no [n/total]-style progress print found in /tmp/airlock_fake/lanes/python_lane.sh; progress.sh reads exactly that for the current lane's percentage and ETA, so this lane will show as 'running, no [n/total] progress line in its log yet' for its whole run
         what to do: print a line containing [$i/$total] as the lane advances

dry run: would have extended /tmp/airlock_fake/agent/batch.json
  batch 'fake-sweep' (id batch-20260822T143044Z, created 2026-08-22T13:40:44+00:00): 5 lane(s), total weight 255

dry run: /tmp/airlock_fake/lanes/python_lane.sh would have been dropped as /tmp/airlock_fake/agent/drop/python_lane.sh
[exit 0]
```

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/crlf_lane.sh --batch fake-sweep --dry-run
  WARN   crlf_lane.sh: CRLF line endings in /tmp/airlock_fake/lanes/crlf_lane.sh; bash fails on the trailing \r in ways that read as nonsense in the log
         what to do: convert to LF, e.g. sed -i 's/\r$//' /tmp/airlock_fake/lanes/crlf_lane.sh
  WARN   crlf_lane.sh: no --weight given, so this lane counts as 1 against the batch total; a big lane and a tiny lane then weigh the same in /tmp/airlock_fake/agent/batch.json
         what to do: give --weight <n>, in whatever unit the other lanes of this batch use

dry run: would have extended /tmp/airlock_fake/agent/batch.json
  batch 'fake-sweep' (id batch-20260822T143044Z, created 2026-08-22T13:40:44+00:00): 5 lane(s), total weight 251

dry run: /tmp/airlock_fake/lanes/crlf_lane.sh would have been dropped as /tmp/airlock_fake/agent/drop/crlf_lane.sh
[exit 0]
```

---

### a successful `submit --batch`

The manifest already on disk was written by the **real `batch.sh`**,
carried across from SandboxDesign:

```
$ bash /tmp/airlock_fake/batch.sh fake-sweep ct_first.sh:40 ct_second.sh:120 ct_stopped.sh:60 ct_queued.sh:30
wrote agent/batch.json  (batch batch-20260822T143044Z, label 'fake-sweep', 4 lane(s))
```

`airlock submit` then joined it:

```
$ airlock --root /tmp/airlock_fake submit /tmp/airlock_fake/lanes/good_lane.sh --batch fake-sweep --weight 80
extended /tmp/airlock_fake/agent/batch.json
  batch 'fake-sweep' (id batch-20260822T143044Z, created 2026-08-22T13:40:44+00:00): 5 lane(s), total weight 330

dropped /tmp/airlock_fake/agent/drop/good_lane.sh
  from:     /tmp/airlock_fake/lanes/good_lane.sh
  written hidden as /tmp/airlock_fake/agent/drop/.good_lane.sh first, then renamed - the daemon never sees a partial file
  poll:     /tmp/airlock_fake/agent/status/good_lane.sh.status
  log:      /tmp/airlock_fake/agent/logs/<stamp>__good_lane.sh.log
  products: /tmp/airlock_fake/agent/out

  airlock status good_lane.sh
  full detail: bash /tmp/airlock_fake/progress.sh   (-w to refresh)
[exit 0]
```

Note `batch_id` and `created` are preserved — extending a manifest does
not restamp it.

### the byte-shape, which is the compatibility that matters

The manifest after `airlock submit` rewrote it. The first four lane
lines were originally written by `batch.sh`; the fifth by `airlock`.
Same indent, same key order, same comma placement, one lane object per
line — which is exactly what `progress.sh`'s line-based parser requires
and what a `json.dump` would have quietly broken.

```
{
  "batch_id": "batch-20260822T143044Z",
  "label": "fake-sweep",
  "created": "2026-08-22T13:40:44+00:00",
  "lanes": [
    { "script": "ct_first.sh", "weight": 40 },
    { "script": "ct_second.sh", "weight": 120 },
    { "script": "ct_stopped.sh", "weight": 60 },
    { "script": "ct_queued.sh", "weight": 30 },
    { "script": "good_lane.sh", "weight": 80 }
  ]
}
```

`cat -A` on the lane lines, to show there is no trailing whitespace and
no difference in indentation between the two writers:

```
      { "script": "ct_first.sh", "weight": 40 },<LF>
      { "script": "ct_second.sh", "weight": 120 },<LF>
      { "script": "ct_stopped.sh", "weight": 60 },<LF>
      { "script": "ct_queued.sh", "weight": 30 },<LF>
      { "script": "good_lane.sh", "weight": 80 }<LF>
```

---

### the real, unmodified `progress.sh` reading an `airlock`-written manifest

This is the compatibility test that was verified for SandboxDesign's
`sandbox` today and must not regress. The file exercised is a copy of
`<sandboxdesign>/progress.sh` with nothing changed
— proved before it was run:

```
$ sha256sum <sandboxdesign>/progress.sh /tmp/airlock_fake/progress.sh
3ce68f1483276817282a44badf7be5b2b0acd0a86e3414b66a5559cca56ac489  <sandboxdesign>/progress.sh
3ce68f1483276817282a44badf7be5b2b0acd0a86e3414b66a5559cca56ac489  /tmp/airlock_fake/progress.sh
$ cmp <sandboxdesign>/progress.sh /tmp/airlock_fake/progress.sh
  cmp: byte-identical
```

```
$ bash /tmp/airlock_fake/progress.sh
== batch summary ==
  batch:    fake-sweep  (id batch-20260822T143044Z)
  overall:  2/5 lanes done   weight 100/330  (30.3% by weight)
  elapsed:  00:50:44
  ETA all:  ~01:56:41 remaining  (estimate, from throughput so far)
  current:  ct_second.sh  47/120  (39.2%)
  ETA lane: ~00:16:40 remaining  (estimate)

== queued (waiting in agent/drop) ==
  good_lane.sh
  ct_queued.sh
  dup.sh

== running ==
  ct_second.sh   started 2026-08-22T14:20:44+00:00
    log: agent/logs/20260822T001000Z__ct_second.sh.log
    [47/120] elapsed=600s
    last: [47/120] elapsed=600s

== live processes inside sandbox-runner (top by CPU) ==
  (podman not on PATH)

== finished, 10 most recent ==
  ct_stopped.sh                done     exit=-1     3600.0s  2026-08-22T14:07:24+00:00
  ct_second.sh                 running  exit=             s
  ct_first.sh                  done     exit=0       300.0s  2026-08-22T13:47:24+00:00
[exit 0]
```

**It parsed.** Total weight 330 includes the 80 that `airlock submit`
added; the lane `good_lane.sh` that `airlock` dropped appears under
`queued`; the denominator, the percentage and both ETAs are computed
from a manifest `airlock` rewrote. The byte-shape holds.

---

### `airlock status`

```
$ airlock --root /tmp/airlock_fake status
  batch 'fake-sweep' (id batch-20260822T143044Z, created 2026-08-22T13:40:44+00:00): 5 lane(s), total weight 330
  manifest: /tmp/airlock_fake/agent/batch.json

queued in /tmp/airlock_fake/agent/drop
| lane |
|---|
| ct_queued.sh |
| dup.sh |
| good_lane.sh |

running
| lane | state | exit | elapsed | progress |
|---|---|---|---|---|
| ct_second.sh | running | - | - | [47/120] |

most recent 2 finished, out of 3 in /tmp/airlock_fake/agent/status
| lane | state | exit | elapsed | progress |
|---|---|---|---|---|
| ct_stopped.sh | ABORT | -1 | 3600.0s | [9/500] |
| ct_first.sh | done | 0 | 300.0s | [120/120] |

  one lane in full: airlock status <lane.sh>
  full detail: bash /tmp/airlock_fake/progress.sh   (-w to refresh)
[exit 0]
```

### the ABORT mapping, and the untouched status file

```
$ airlock --root /tmp/airlock_fake status ct_stopped.sh
  batch 'fake-sweep' (id batch-20260822T143044Z, created 2026-08-22T13:40:44+00:00): 5 lane(s), total weight 330
  manifest: /tmp/airlock_fake/agent/batch.json

  lane:     ct_stopped.sh
  state:    ABORT
            the daemon recorded this as 'KILLED after 3600s timeout'; ABORT is this program's word for the outcome where the operating system stopped the run
  exit:     -1
  started:  2026-08-22T13:07:24+00:00
  elapsed:  3600.0s
  progress: [9/500]
  log:      /tmp/airlock_fake/agent/logs/20260822T002000Z__ct_stopped.sh.log
  status:   /tmp/airlock_fake/agent/status/ct_stopped.sh.status

  full detail: bash /tmp/airlock_fake/progress.sh   (-w to refresh)
[exit 0]
```

The status file itself is not rewritten. The daemon's own token stays as
the daemon's:

```
$ cat /tmp/airlock_fake/agent/status/ct_stopped.sh.status
  script=ct_stopped.sh
  state=done
  exit=-1
  started=2026-08-22T13:07:24+00:00
  finished=2026-08-22T14:07:24+00:00
  elapsed_s=3600.0
  log=/logs/20260822T002000Z__ct_stopped.sh.log
  verdict=KILLED after 3600s timeout
```

---

### `airlock doctor`, with findings

```
$ airlock --root /tmp/airlock_fake doctor
doctor: /tmp/airlock_fake
```

| severity | check | what was seen | what to do |
|---|---|---|---|
| WARN | agent/drop clutter | /tmp/airlock_fake/agent/drop/notes.txt is not a runnable lane, so daemon/watcher.py will ignore it forever | rm '/tmp/airlock_fake/agent/drop/notes.txt' - it has to be done on the host, because a lane running inside the sandbox cannot unlink it (/drop is a bind mount the lane may write to but should not tidy) |
| WARN | agent/out free space | 2.9 GB free on the filesystem holding /tmp/airlock_fake/agent/out (69% of it used) | consider pruning /tmp/airlock_fake/agent/out |
| NOTE | podman | podman is not on PATH here, so every container check is skipped; the file checks below all ran | expected inside an agent session that has no container runtime; on the host it means podman is not installed |
| NOTE | AIRLOCK_CPUS | /tmp/airlock_fake/up.sh defaults to 6 cpu(s) | AIRLOCK_CPUS=3 bash /tmp/airlock_fake/up.sh throttles a long run; the older SANDBOX_CPUS spelling is still read, after AIRLOCK_CPUS |
| NOTE | granted cores | cannot read what sandbox-runner was actually granted (podman inspect unavailable or the container is not there) | - |
| NOTE | agent/drop queue | 3 lane(s) waiting in /tmp/airlock_fake/agent/drop: ct_queued.sh, dup.sh, good_lane.sh | - |
| NOTE | toolchains | skipped - podman is not on PATH, so nothing can be asked of the container | the last recorded answer is in /tmp/airlock_fake/DevComms/sandbox_report.txt |
| NOTE | agent/out contents | 0 entr(y/ies) in /tmp/airlock_fake/agent/out; nothing prunes this automatically | - |
| NOTE | /work headroom | the most recent lane (ct_second.sh) recorded 3800 MB free in the container's /work tmpfs | the cap is set by --tmpfs /work in /tmp/airlock_fake/up.sh and Tmpfs= in /tmp/airlock_fake/quadlet/sandbox-runner.container |
| OK | quadlet vs up.sh | /tmp/airlock_fake/quadlet/sandbox-runner.container and /tmp/airlock_fake/up.sh agree on 6 cpu(s) | - |
| OK | egress allowlist | 3 hostname(s) allowed, in /tmp/airlock_fake/proxy/allowlist.txt | bash /tmp/airlock_fake/allow.sh list, or bash /tmp/airlock_fake/allow.sh denied to see what was refused |

```
  2 WARN, 7 NOTE, 2 OK
  exit 0 - no real faults. WARN and NOTE are for reading, not for stopping.
[exit 0]
```

The `quadlet vs up.sh` row is now **OK**. In SandboxDesign this was a
WARN on every single run, and it was the first item on log 002's and log
003's awaiting-maintainer lists. The 2026-08-22 full-share ruling settles
it:
`up.sh` defaults to 6 and the quadlet unit hardcodes 6, so they agree.
The check is kept, so a future drift is still caught.

### `doctor` against the broken tree — non-zero exit

```
$ airlock --root /tmp/airlock_broken doctor
doctor: /tmp/airlock_broken
```

| severity | check | what was seen | what to do |
|---|---|---|---|
| FAULT | agent/drop | no drop directory at /tmp/airlock_broken/agent/drop - there is nowhere to submit a lane | bash /tmp/airlock_broken/up.sh |
| FAULT | egress allowlist | no allowlist at /tmp/airlock_broken/proxy/allowlist.txt; the proxy default-denies, so every hostname the runner reaches for will be refused | cp /tmp/airlock_broken/proxy/allowlist.txt.example /tmp/airlock_broken/proxy/allowlist.txt then bash /tmp/airlock_broken/allow.sh sync |
| FAULT | agent/out | no out directory at /tmp/airlock_broken/agent/out - a lane's products have nowhere to land | bash /tmp/airlock_broken/up.sh |
| NOTE | podman | podman is not on PATH here, so every container check is skipped; the file checks below all ran | expected inside an agent session that has no container runtime; on the host it means podman is not installed |
| NOTE | AIRLOCK_CPUS | /tmp/airlock_broken/up.sh defaults to 6 cpu(s) | AIRLOCK_CPUS=3 bash /tmp/airlock_broken/up.sh throttles a long run; the older SANDBOX_CPUS spelling is still read, after AIRLOCK_CPUS |
| NOTE | granted cores | cannot read what sandbox-runner was actually granted (podman inspect unavailable or the container is not there) | - |
| NOTE | toolchains | skipped - podman is not on PATH, so nothing can be asked of the container | the last recorded answer is in /tmp/airlock_broken/DevComms/sandbox_report.txt |
| NOTE | /work headroom | no lane in /tmp/airlock_broken/agent/status has recorded /work headroom yet | - |
| OK | quadlet vs up.sh | /tmp/airlock_broken/quadlet/sandbox-runner.container and /tmp/airlock_broken/up.sh agree on 6 cpu(s) | - |

```
  3 FAULT, 5 NOTE, 1 OK
  exit 1 - 3 real fault(s) above.
[exit 1]
```

---

### the environment variables, both spellings

```
$ AIRLOCK_ROOT=/tmp/airlock_fake airlock status ct_first.sh
  lane:     ct_first.sh
  state:    done
  exit:     0
  started:  2026-08-22T13:42:24+00:00
  elapsed:  300.0s
  progress: [120/120]
  log:      /tmp/airlock_fake/agent/logs/20260822T000000Z__ct_first.sh.log
  status:   /tmp/airlock_fake/agent/status/ct_first.sh.status
[exit 0]

$ SANDBOX_DESIGN_ROOT=/tmp/airlock_fake airlock status ct_first.sh
  lane:     ct_first.sh
  state:    done
  status:   /tmp/airlock_fake/agent/status/ct_first.sh.status
```

```
$ AIRLOCK_CPUS=3 airlock --root /tmp/airlock_fake doctor | grep 'cpu setting'
| NOTE | AIRLOCK_CPUS | a cpu setting of 3 is present in this environment; it applies only to a container started from here | - |

$ SANDBOX_CPUS=2 airlock --root /tmp/airlock_fake doctor | grep 'cpu setting'
| NOTE | AIRLOCK_CPUS | a cpu setting of 2 is present in this environment; it applies only to a container started from here | - |
```

### delegation, proved

```
$ airlock --root /tmp/airlock_fake up --cpus 3
running: bash /tmp/airlock_fake/up.sh --cpus 3
(this CLI delegates so container flags have one source of truth: /tmp/airlock_fake/up.sh)

[fake up.sh] args: --cpus 3
[exit 0]

$ airlock --root /tmp/airlock_fake allow list
running: bash /tmp/airlock_fake/allow.sh list
(this CLI delegates so container flags have one source of truth: /tmp/airlock_fake/allow.sh)

[fake allow.sh] args: list
[exit 0]
```

### bad input

```
$ airlock --root /tmp/nope status
    REFUSE: --root is not a directory: /tmp/nope                       [exit 2]

$ airlock --root /tmp/airlock_fake nosuchcommand
    REFUSE: no such command: nosuchcommand
            known: allow, doctor, down, status, submit, up, watch
            airlock --help                                            [exit 2]

$ airlock --root /tmp/airlock_fake allow
    REFUSE: allow needs a subcommand.
            list | add <host>... | remove <host>... | sync | denied
            it is /tmp/airlock_fake/allow.sh that does the work; this only passes it on.
                                                                       [exit 2]

$ airlock --root /tmp/airlock_fake doctor extra
    REFUSE: doctor takes no arguments, got extra                       [exit 2]

$ airlock --root /tmp/airlock_fake submit a.sh b.sh --no-batch
    REFUSE: submit takes exactly one lane file, got 2
            usage: airlock submit <lane.sh> (--batch <label> [--weight N] | --no-batch)
                                                                       [exit 2]
```

---

### the quadlet agent-lane splice

The single worst disc-layout assumption in the source repo was four
hardcoded `Volume=` lines inside a tracked unit file. The repo copy now
carries empty markers and no path at all:

```
$ grep -n 'Volume=\|>>> \|<<< ' quadlet/sandbox-runner.container
  31:# >>> AGENT LANE
  32:# <<< AGENT LANE
  46:# >>> MOUNTS
  47:# <<< MOUNTS
  50:Volume=sandbox-persist:/persist
```

`install_quadlet.sh`'s awk splice was run against a clone at
`/tmp/qtest` with a two-line `mounts.conf`, to show what it writes into
`~/.config/containers/systemd/`:

```
  31:# >>> AGENT LANE
  32:Volume=/tmp/qtest/agent/drop:/drop
  33:Volume=/tmp/qtest/agent/out:/out
  34:Volume=/tmp/qtest/agent/logs:/logs
  35:Volume=/tmp/qtest/agent/status:/status
  36:# <<< AGENT LANE
  50:# >>> MOUNTS
  51:Volume=<home>/code/MyProject:/projects/MyProject:ro
  52:Volume=/tmp:/scratch:rw
  53:# <<< MOUNTS
  56:Volume=sandbox-persist:/persist
  68:PodmanArgs=--cpus=6
```

Diffing the repo copy against the rendered copy: **only `Volume=` lines
were added.** Nothing else in the unit changed.

### what could not be tested

| capability | why |
|---|---|
| `up.sh`, `down.sh`, `build.sh`, `pull.sh`, `logs.sh`, `report.sh`, `selftest.sh`, `submit.sh`, `submit_project.sh` end to end | `podman` is not on `PATH` in this session. All were checked with `bash -n`, and every one is byte-identical or comment-only-different from a file that works today in `<sandboxdesign>` |
| `install_quadlet.sh` end to end | needs `systemctl --user` and `podman`. Its one genuinely new mechanism, the agent-lane splice, was exercised in isolation above |
| `airlock doctor`'s container, toolchain and granted-core checks | each needs a running container. Each degrades to a NOTE, which is visible in both rendered runs above |
| the resolved package versions in the built image | needs a build. The README marks them **unverified** and points at `report.sh` |
| `airlock watch` | it is `status` on a timer with a `sleep` loop; running it here would have produced a screen-clearing frame rather than readable evidence. The `status` body it renders is exercised above |


---

## decided, recorded for audit

- **`airlock`** — one executable python3
  file, stdlib only, shebang, `chmod +x`. It is the documented front
  door. Runs both as `airlock <command>` and as
  `python3 airlock <command>`; both were run.
- **The file protocol is unchanged and remains the truth.** Every path
  under `agent/`, every status key, every log name, the
  hidden-then-rename drop, and the batch manifest byte-shape are
  identical to SandboxDesign's. A hand-drop still works. Nothing
  downstream requires `airlock` to exist.
- **`Batch.write` still matches `batch.sh` byte-shape**, one lane object
  per line. Verified by having the real `batch.sh` write four lanes,
  `airlock submit` add a fifth, and then running the **real, unmodified,
  sha256-verified `progress.sh`** against the result. It parsed and
  attributed weight correctly.
- **Ten refusal paths, four warnings**, every one rendered above from a
  real run. SandboxDesign's log 003 documented nine refusals; the tenth
  (`no drop directory`) was always in the code and never counted. The
  behaviour is carried across unchanged; only the count is corrected.
- **The batch decision stays mandatory.** No default.
- **Severity vocabulary** REFUSE / FAULT / WARN / NOTE / OK and the exit
  codes (0 / 1 / 2) are unchanged.
- **ABORT mapping unchanged.** `airlock status` renders the OS-stopped
  outcome as ABORT and names the daemon's own token as the raw value it
  came from. Nothing rewrites the status file, and the token itself is
  untouched in `daemon/watcher.py` — three separate consumers depend on
  its exact spelling.
- **`up`, `down`, `allow` still delegate** to the shell scripts. No
  podman flag is spelled in python.
- **`submit` still does not delegate to `submit.sh`**, and `submit.sh`
  is carried across. This is a deliberate deviation from the brief's
  carry list: `selftest.sh` calls `./submit.sh` six times and
  `submit_project.sh` once, so leaving it behind would have left two
  carried scripts calling a file that does not exist.
  `submit_project.sh` is carried for the same class of reason — it is
  generic, `log_002` already neutralised its examples, and dropping it
  would remove a documented capability with no replacement.
- **`AIRLOCK_CPUS` is the new spelling, default 6, the full share**
  (ruled 2026-08-22). `SANDBOX_CPUS` is read **after** it, so a
  migrating project's environment keeps working. Documented in `up.sh`'s
  header, in `README.md`'s configuration table, in `MIGRATING.md`, and
  in `airlock doctor`'s own remedy text.
- **`AIRLOCK_ROOT` is the new root spelling**, with
  `SANDBOX_DESIGN_ROOT` read after it. Documented in `--help` as a real
  flag, not a hidden test hook.
- **The `quadlet` versus `up.sh` cpu disagreement is closed.** Both are
  6. It was the first item on log 002's and log 003's
  awaiting-maintainer lists; the full-share ruling settles it as a
  consequence. `doctor` still compares them, so a future drift is still caught, and it now
  reports OK rather than WARN on every run.
- **The container, network, image and volume names keep the `sandbox-`
  prefix.** Reasons in the §2 section above. Reversible, but it would
  cost an image rebuild and a systemd re-install for every migrating
  user. The consequence — do not run both installs at once — is stated
  in `README.md` and in `MIGRATING.md`.
- **`quadlet/sandbox-runner.container` no longer names any path.** The
  four agent-lane `Volume=` lines are generated by
  `install_quadlet.sh` from the repo's own location and spliced into the
  installed copy, using the same marker mechanism the `MOUNTS` block
  already used. This was the single worst disc-layout assumption in
  the source repo.
- **`probe_host.sh` no longer hardcodes a repo path.** `REPO` is derived
  from the script's own directory.
- **Nothing project-specific ships.** `agent/templates/pcv6_suite.sh` is
  left behind, and `agent/templates/` is not created at all — an empty
  templates directory is an invitation for the same drift.
  `agent/README.md` is rewritten to describe the mechanism only. The
  full sweep for project names over every tracked file is above.
- **No personal path and no person's name in a tracked file**, with
  three deliberate exceptions, each required and each named: this log
  (which must say what it left behind and where), `LICENSE.md` (which
  must name where the candidate licence lives), and `MIGRATING.md`
  (which must name the repo being migrated from).
- **`.gitignore` keeps a fresh clone working.** The four
  `agent/*/.gitignore` files holding `*` and `!.gitignore` are carried
  across unchanged and are the structure that does it; the top-level
  `.gitignore` restates it explicitly for a stranger reading one file,
  and adds the four `DevComms/` run-record files that `log_002` left
  tracked in the source repo.
- **Three passes, in order.** The §2 overview and the fate table were
  written into this file before any file existed in the tree. The shape
  pass is snapshotted at
  `DevComms/log_001_shape_pass2.py`
  (real signatures, docstrings, `raise NotImplementedError`, compiles
  clean). Logic and docs last. Code **moved** from SandboxDesign was
  moved whole in one step — the three-pass rule governs what is written.
- **Vocabulary conforms to
  PseudoCoupHQ's `CLAUDE.md`** throughout — this
  repo's code, comments, help text, output strings, docs and its commit
  message. Four carried-across files needed a one-word comment fix
  (`selftest.sh`, `daemon/watcher.py`, `Containerfile`,
  `submit_project.sh`); the sweep results are above.
- **`<sandboxdesign>` was not modified.** Verified:
  no file under it was written, and its `agent/` tree was never touched.
  One stray `agent/batch.json` was created inside `Airlock` during
  testing when a carried script `cd`'d to its own directory; it was
  removed, and the test was re-run against `/tmp` instead.
- **`git init`, one initial commit, no remote, no push.**
  `create_github_repo.sh` was deliberately not carried across.


## awaiting the maintainer

Three, kept minimal.

- **The licence.** `LICENSE.md` is a
  placeholder saying so. PseudoCoupHQ's `OTU GREEN LICENSE
  FOR UNIVERSAL WORKS.pdf` exists in this line of work, and the identical
  document sits beside `PseudoCoup_v6`, `PseudoCoup_v5`, `PseudoIR` and
  `PlanPlan` — it may be the intended one. It has not been applied,
  because applying a licence outlasts the session that did it.
- **Whether to retire `<sandboxdesign>`.** It is
  untouched and still works. Airlock is a derivation, not a replacement,
  until the maintainer says otherwise. Note the two installs cannot run
  at the same time (same container names).
- **Whether Airlock becomes public, and where.** No GitHub repo was
  created and nothing was pushed; there is no remote. This is the same
  decision as the licence, made twice.

**Two of the three were settled the same day. See the 2026-08-22 section
below, which supersedes the licence item and the publication item; the
retirement of `<sandboxdesign>` is still open.**

---

# 2026-08-22, later — the licence, the PCHQ migration, the create-repo script

Three rulings from the maintainer, in one pass. This section is appended
to log 001 rather than opened as log 002, as instructed.

## 1 — the licence: applied

The maintainer ruled the OTU Green License applies.

### the convention, as measured rather than assumed

Every repo in the line was inspected before anything was written:

| repo | `LICENSE` / `LICENSE.md` present | PDF at repo root | PDF tracked in git | licence named in a `README.md` |
|---|---|---|---|---|
| `PseudoCoupHQ` | no | yes | yes | no README |
| `PseudoCoup_v6` | no | yes | yes | no README |
| `PseudoCoup_v5` | no | yes | yes | README exists, does not mention it |
| `PseudoIR` | no | yes | yes | no README |
| `PlanPlan` | no | yes | yes | README exists, does not mention it |

**The convention is the PDF alone, at the repo root, tracked in git.**
No repo in the line carries a `LICENSE` or `LICENSE.md`, and none names
the licence in prose. All five PDFs are byte-identical —
`md5 ade2787e0d32c6276ae69855f55d61ce`, 129,093 bytes.

### what was done

| action | detail |
|---|---|
| carried the file | PseudoCoupHQ's `OTU GREEN LICENSE FOR UNIVERSAL WORKS.pdf` → `OTU GREEN LICENSE FOR UNIVERSAL WORKS.pdf`. Verified byte-identical with `cmp` and `md5sum` after the copy |
| rewrote `LICENSE.md` | the placeholder is gone. It now names the licence and points at the PDF beside it, and **restates no term of it** |
| referenced it in `README.md` | a new `## Licence` section, a `Contents` table row, and two rows in the `Files` table (the PDF, and what `LICENSE.md` now is) |

The licence identifies itself, in its own text, as **OTU GREEN LICENSE
FOR UNIVERSAL WORKS ("OTU-GL v8"), Version 8 — 2026-04-27, Copyright (c)
2026 The Student**. Those identifiers are quoted, not paraphrased. Its
§13 states that a work released under `OTU-GL v8` is governed solely by
that version unless the Contributor says otherwise; Airlock says nothing
otherwise. **No term, condition, permission or restriction is summarised
anywhere in this repo** — a summary that drifts from the text it
summarises is worse than no summary.

Airlock deviates from the five repos on exactly one point, and
deliberately: it keeps a `LICENSE.md`. The five have no README to name
the licence in and are private; Airlock is public-facing, and a reader
landing on a repo with only a PDF has to guess. `LICENSE.md` is a
signpost, not a second copy of the terms.

## 2 — PseudoCoupHQ migrated from SandboxDesign to Airlock

The maintainer: *"if you can migrate from SandboxDesign to Airlock for
PCHQ -- and the Claude skill if needed -- yes please"*.

Recorded in full at PseudoCoupHQ's
`DevComms/log_060_sandbox_to_airlock_migration.md`,
which carries the whole old-path→new-path and old-command→new-command
mapping. The summary:

### the scope, measured

The brief estimated "roughly 20+ files". Measured: **50 files** in
PseudoCoupHQ contain the string
`SandboxDesign` — 18 DevComms logs, 2 top-level memory files, 5 Planning
files, 17 `Research/` files, and 8 `__pycache__/*.pyc` artefacts. The
estimate was low because it did not count the `Research/` tree.

### the rule applied

**A reference is updated when it tells someone what to do next. It is
left when it records what happened on a date.**

| set | count | action |
|---|---|---|
| `CLAUDE.md`, `AgentMemory.md` | 2 | updated to Airlock, CLI-first |
| Planning `CORE_*.md` (present-tense method statements) | 2 | updated to Airlock |
| Planning `PROGRESS.md` (all four references sit inside dated bullets) | 3 files, 4 references | **left**, each named individually in log 060 |
| `DevComms/log_0*.md` | 18 | **left, bodies untouched**, verified by sha256 before and after |
| `Research/**` generators and readers | 17 | **left**, with the reason recorded — see below |
| `hq.sh`, `create_github_repo.sh`, `git_commit_push.sh`, `git_commit_push_all.sh` | 4 | **no change needed**; verified line by line |

Four files edited, one written
(`DevComms/log_060_sandbox_to_airlock_migration.md`). `git status` in
PseudoCoupHQ shows exactly those five entries and nothing else.

### `hq.sh` needed no change — verified, not assumed

`hq.sh` contains the word "sandbox" four times, and **not one of them is
this repo**. All four mean the Cowork agent sandbox: the thing that
cannot set an executable bit, and that leaves stale `.git/index.lock`
files it is then denied deleting. Same for the three `git_commit_push*`
scripts and `create_github_repo.sh`. No PseudoCoupHQ shell script names
`SandboxDesign` at all.

### `bash hq.sh check` after the edits

Run from PseudoCoupHQ's own tree as
`HOME=<session mount root> bash hq.sh check`:

```
summary: 0 error(s), 8 warning(s)
[exit 0]
```

**0 errors.** The 8 warnings are the pre-existing SUPPORT-file and
completeness notices in the PseudoIR and PseudoCoup_v6 trees; none is in
a file this work touched.

### the DevComms logs were not rewritten, and that is provable

The sha256 of all 18 logs naming `SandboxDesign` was taken before the
first edit and checked after the last. All 18 report `OK`. Their
references are correct as of their dates; log 060 is the single place the
mapping from those dates to today's tree lives, and no log needed a note
appended to it.

### the `Research/` tree was deliberately not repointed

Seventeen files under
PseudoCoupHQ's `Research/` resolve a
`SandboxDesign` path. They are live tooling and the obvious move is to
repoint them. They were left alone because repointing them **breaks them
against their own data**: `<sandboxdesign>/agent/out`
holds **480 products** — every run of record for that line — and
`agent/out` holds **0**, exactly as `MIGRATING.md` says it should. A
reader repointed at Airlock finds nothing.

Where the line's data lives is a structural decision, so it is the
maintainer's. The two coherent options and the full 17-file inventory
are in log 060
§4. One incidental finding recorded there:
`Research/kind_fuzz_clustering/timing_build.py` hardcodes a **stale agent
session mount path** that no longer exists — broken either way.

### the toolchain skill

`~/.claude/skills/toolchain/SKILL.md` carries 15 `SandboxDesign`
references across 12 blocks, and its §0 is a standing policy written
entirely about that repo. The copy visible from a session is a
**read-only cache**; writing to it does not change the saved skill on the host.
**It was not edited.**

The deliverable instead is
`DevComms/toolchain_skill_airlock_patch.md`:
the exact replacement text for every affected block, quoted old against
new, in file order, with cached line numbers and an instruction to match
by the OLD text rather than by line number if the saved skill has
drifted. It marks one block as **no change needed** (the frontmatter
description, which is trigger text and names no repo) and one as
**optional** (§6 repo conventions, which contains no `SandboxDesign`
reference but would mislead a reader about Airlock's creation script).

**That patch file is gitignored**, along with `create_public_repo.sh`.
Both name one machine's layout and one project's repos, which is the
precise class of content `README.md`'s contract calls drift. Tracking a
PseudoCoupHQ-specific handoff document in Airlock would contradict the
structural property this repo exists to hold. It sits at the path the
brief named, so the session that saves the skill will find it; it is one
`.gitignore` line to reverse if the maintainer prefers it tracked.

## 3 — `create_public_repo.sh`

The maintainer: *"public gh repo on the github account i have active
locally. same one we are using for PCHQ. as soon as the license is
updated, you can
generate a gitignored bash script that i can run to create the public
repo."*

Written at `create_public_repo.sh`, following
PseudoCoupHQ's `create_github_repo.sh` (and SandboxDesign's
copy, which is the same file with the name and the
commit message changed). **The account mechanism is not reinvented**: it
is whichever account `gh` is authenticated as on the machine, exactly as
PseudoCoupHQ's script relies on. No account name is hardcoded.

| requirement | how it is met |
|---|---|
| public repo named `Airlock` | `gh repo create Airlock --public --source . --remote origin --push` |
| the same account | `gh`'s own authentication. The script reads it back with `gh api user --jq .login` only to *print* it in the plan |
| adds the remote, pushes the initial commit | the `gh repo create` flags do both. Where the repo already exists but the remote does not, it adds `origin` from `gh repo view --json url` and pushes |
| safe to run twice | every step is state-checked first: `.git` present, a commit present, `origin` present, and `gh repo view <account>/Airlock`. Each already-done step prints `SKIP` with what it found, and the run continues |
| prints exactly what it is about to do, before doing it | the whole plan is printed as a markdown table plus a numbered step list — each step already marked `SKIP` where it will be skipped — followed by a `proceed? [y/N]` prompt. `--dry-run` prints the plan and stops; `--yes` skips only the prompt |
| refuses clearly if `gh` is not authenticated | two separate refusals with remedies: `gh` not on `PATH`, and `gh auth status` failing. Both exit 1 before anything is read or written |
| gitignored | a named block in `.gitignore` saying why |

Beyond the brief, and deliberately: it never force-pushes, never rewrites
history, never deletes, and **never changes the visibility of a
repository that already exists** — if it finds `Airlock` already there
and private, it says so and prints the `gh repo edit` command rather than
running it. It warns when the working tree is dirty, distinguishing the
case where there is no commit yet (step 2 will commit everything) from
the case where there is (the uncommitted work will not be published). It
closes by printing the remote and reminding the reader the repo is public
and that `mounts.conf` and `proxy/allowlist.txt` were not published.

`bash -n` passes. **It was not run** — that is the maintainer's to do:

```
bash <airlock>/create_public_repo.sh --dry-run   # see the plan, change nothing
bash <airlock>/create_public_repo.sh             # do it, with one confirmation
```

## Testing, this section's work

| check | result |
|---|---|
| `cmp` and `md5sum`, the carried PDF against PseudoCoupHQ's | byte-identical, `ade2787e0d32c6276ae69855f55d61ce` |
| `bash -n create_public_repo.sh` | syntax OK |
| sha256 of all 18 PseudoCoupHQ DevComms logs, before and after | all 18 `OK` — no log body was written to |
| `git status --porcelain` in PseudoCoupHQ | exactly 4 modified, 1 untracked. Nothing else |
| `bash hq.sh check` | `0 error(s), 8 warning(s)`, exit 0 |
| banned-vocabulary sweep over every file written or edited in this section | `parent` 0, `child` 0, `children` 0, `sibling` 0, `ancestor` 0, `descendant` 0, `orphan` 0, `death` 0, `died` 0, `dead` 0 |

Not verified, and marked so: `create_public_repo.sh` was not executed —
no repository was created, no remote was added, nothing was pushed, and
`gh` was not invoked. Its refusal paths and its `SKIP` reporting are
therefore **unverified at run time**; only its syntax was checked.
Whether the toolchain-skill patch applies cleanly to the *saved* skill is
also unverified, because only the read-only cache could be read — the
patch says so and gives the fallback.

---

## decided, recorded for audit — 2026-08-22, this section

- **The licence is the OTU GREEN LICENSE FOR UNIVERSAL WORKS
  (`OTU-GL v8`), Version 8, 2026-04-27**, applied by carrying the PDF to
  the repo root byte-identical, exactly as the five repos in the line do.
  No term is retyped or paraphrased anywhere in Airlock.
- **The convention was measured, not assumed**: PDF alone at the repo
  root, tracked in git, no `LICENSE` or `LICENSE.md` and no README
  mention in any of the five. Airlock adds a `LICENSE.md` that is a
  signpost only, because it is the one repo of the six that a stranger
  will read.
- **`README.md` names the licence** in a new `## Licence` section, in the
  `Contents` table and in the `Files` table.
- **PseudoCoupHQ's sandbox of record is now `<airlock>`.**
  Four files edited, one log written; full mapping in log 060.
- **The 18 PseudoCoupHQ DevComms logs were not rewritten**, proved by
  sha256 before and after. A log said what was true on its date.
- **Four `PROGRESS.md` references were left** for the same reason — each
  sits inside a dated bullet recording a past event. Named individually
  in log 060 §3.
- **`hq.sh` needed no change.** Its four "sandbox" occurrences mean the
  Cowork agent sandbox. Verified line by line, as were the three
  `git_commit_push*` scripts and `create_github_repo.sh`.
- **`bash hq.sh check` reports 0 errors** after the edits.
- **The 17 `Research/` files were deliberately not repointed**, because
  the 480 products they read live in
  `<sandboxdesign>/agent/out` and Airlock's is
  empty by design. Full inventory and the two coherent options in log
  060 §4.
- **The toolchain skill's cached copy was not edited** — editing it
  changes nothing. The replacement text for all 12 blocks is at
  `DevComms/toolchain_skill_airlock_patch.md`.
- **`create_public_repo.sh` uses `gh`'s own authentication**, the same
  mechanism PseudoCoupHQ's script uses. No account name is hardcoded, no
  new auth approach was invented.
- **`create_public_repo.sh` and the toolchain patch file are both
  gitignored**, with a named block in `.gitignore` explaining why. This
  keeps the "nothing project-specific and no personal path in a tracked
  file" property intact; both are one line to reverse.
- **`create_public_repo.sh` was not run.** No repository exists, no
  remote is configured, nothing was pushed.
- **`<sandboxdesign>` was still not modified** by
  any part of this section.
- **One additional commit in `<airlock>`**, no
  remote, no push — as instructed.

## awaiting the maintainer — 2026-08-22, this section

Two, kept minimal.

- **Whether to repoint the 17 `Research/` files in PseudoCoupHQ**, and
  if so whether to move the 480 products out of
  `<sandboxdesign>/agent/out` first. This decides
  where the line's data lives. Log 060 §4 has the inventory and both
  options.
- **Saving the toolchain skill.** The replacement text is written and
  ready at
  `DevComms/toolchain_skill_airlock_patch.md`;
  applying it needs the skill-save mechanism, which this session does not
  have.

Still open from the original list above: **whether to retire
`<sandboxdesign>`.** It is untouched, still works,
and still holds the runs of record — the `Research/` question above bears
directly on it.

