# log 002 — removing personal information from a public repo

2026-08-22. This repo was published to GitHub with two commits before
anyone checked what the tracked files actually said. They said too much.
This log records what was removed, how it was proved removed, and what
publication does not undo.

**This file is written to be public.** It names the *shapes* of the
strings that were removed, never the strings themselves. Where a pattern
would otherwise reproduce what it is describing, it is written with a
placeholder (`/home/<user>`) or assembled at runtime from fragments. The
same trick is used in `scrub_check.sh`, and for the same reason.

---

## §1 what counts as personal information here

The rule adopted, and now enforced by `scrub_check.sh`:

| class | shape | why it is not publishable | what replaced it |
|---|---|---|---|
| absolute home path | `/home/<user>/...` | names the operating-system account that built the repo | `~/...` where the path is outside this repo; a repo-relative path where it is inside it |
| macOS home path | `/Users/<user>/...` | same | same |
| agent session mount path | `/sessions/<session-name>/...` | ephemeral session infrastructure. It means nothing to a reader and identifies where the work ran | the surrounding sentence was rewritten. No stub was left behind |
| personal handle | the maintainer's given name, as used in conversation | this is a public repo; the working notes addressed one person by name throughout | "the maintainer", "one person", "one machine", or the sentence restructured so no one is addressed |
| email address | `<local>@<domain>` | direct contact detail | none were in file content; one was in the git author/committer metadata — see §4 |
| subuid/subgid mapping | `<account>:<uid>:<gid>` | names a real account on a real machine | not present in any tracked file; the guard watches for it because it appears in the untracked toolchain notes |

**Deliberately kept.** `TheStudent00` and "The Student" are the chosen
public identity for this line of work. `TheStudent00` is the GitHub
account; "The Student" is named in the licence itself. Scrubbing them
would break the licence and the remote. They are not in the pattern list.

---

## §2 where it was found

The leak was concentrated in the development record, which is exactly
where it always concentrates: working notes are written to a person, on a
machine, and nobody re-reads them before a push.

Counts are **lines carrying the pattern**; several lines carried more than
one occurrence.

| file | absolute home path | agent session path | personal handle |
|---|---|---|---|
| `DevComms/log_001_airlock_derivation.md` | 64 | 4 | 29 |
| `DevComms/log_001_shape_pass2.py` | 2 | — | — |
| `MIGRATING.md` | — | — | 1 |
| `.gitignore` | — | — | 1 |

Nothing was found in `README.md`, `LICENSE.md`, the licence PDF (its
compressed streams were decompressed and searched, not just its raw
bytes), `Containerfile`, `airlock`, `daemon/watcher.py`, any `*.sh`, any
file under `agent/`, `proxy/` or `quadlet/`.

### the near miss that was not in the brief

`DevComms/toolchain_SKILL_updated.md` was **untracked but not ignored**.
It carries a machine model, a CPU model, a kernel version, a subuid/subgid
mapping naming a real account, and the personal handle 13 times. A single
`git add -A` — including the one that rebuilt this history — would have
published it. It is now ignored by glob rather than by exact filename
(`DevComms/toolchain_*`, `DevComms/*_SKILL_*`), because the earlier
exact-filename rule covered one co-located document of the same kind and
missed this one, which differed only in its name.

This class — *untracked, unignored, one command from publication* — is
now a first-class failure in `scrub_check.sh`, not a warning.

---

## §3 how it was fixed

Not by deletion. Each hit was rewritten so the sentence still says what it
said:

- Paths **inside this repo** became repo-relative: a table cell that read
  as an absolute path to `airlock` now reads `` `airlock` ``. Paths to
  **other** repos became a placeholder pairing a projects-directory name
  with the repo name. The later tidiness pass recorded below drops the
  projects-directory name too — see its section for why.
- The one captured `--help` transcript keeps its shape — the program does
  print a path there — rendered as `<airlock>/...`.
- Agent session mount paths had their sentences rewritten. The paragraph
  that existed only to explain the mount prefix now explains that the
  paths are shown in their `~` form and that the mount carried no meaning
  outside the session. One reference to a stale mount in another project's
  file now says "a stale agent session mount path" and no longer quotes it.
- The awaiting-list headings, quoted rulings and possessives were
  restructured, not find-and-replaced: "his call" became "the maintainer's
  call", "the two commands he needs" became "the two commands needed",
  "an inventory of <name>'s actual machine" became "an inventory of one
  real machine". Lines were re-wrapped where the substitution pushed them
  past the file's width, so no paragraph reads as patched.
- One table cell quoted a docstring line from the source repo that itself
  contained the name. The quotation was replaced with a description of it.

`.gitignore` gained the glob above, an entry for the force-push script,
and an entry for a local-only pattern file.

---

## §4 verification — working tree

Every tracked file, one sweep per pattern class. `xargs` reports exit 123
when `grep` finds nothing in any file; that is the empty result.

```
$ git ls-files -z | xargs -0 grep -nIE '/home/[a-z]'; echo "exit $?"
exit 123

$ git ls-files -z | xargs -0 grep -nIE '/sessions/[a-z0-9]'; echo "exit $?"
exit 123

$ h=$(printf '%s%s' 'D' 'ee')                      # the handle, unwritten
$ git ls-files -z | xargs -0 grep -nIE "(^|[^A-Za-z])${h}([^A-Za-z]|$)"; echo "exit $?"
exit 123

$ u=$(printf '%s%s' 'luc' 'as')                    # the account name, unwritten
$ git ls-files -z | xargs -0 grep -nIi "$u"; echo "exit $?"
exit 123

$ git ls-files -z | xargs -0 grep -nIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'; echo "exit $?"
DevComms/log_002_pii_scrub.md:  … <TheStudent00@users.noreply.github.com> …
DevComms/log_002_pii_scrub.md:  git config user.email "TheStudent00@users.noreply.github.com"
exit 0
```

The email sweep is the one that is not empty, and both hits are this file
quoting the noreply address it set in §6. That address is the *fix* for a
leaked mailbox, not a leak; it is the single entry in `scrub_check.sh`'s
`ALLOW` list, which is why the guard below passes. No other tracked file
contains an address of any kind.

And the guard itself, over all 40 tracked files and every untracked file
that is not ignored:

```
$ bash ./scrub_check.sh
=== scrub_check: 6 pattern(s), 40 tracked file(s), 0 untracked-and-unignored file(s) ===
scrub_check: PASS - no personal or machine-identifying pattern found.
$ echo $?
0
```

---

## §5 verification — history

Scrubbing the tip is not enough: the leak was in **both** published
commits, and `git log -p` hands out every historical version of every
file. With only two commits there is no rebase worth writing. The history
was rebuilt:

1. the working tree was left exactly as scrubbed, and its file list and
   modes recorded first (40 tracked entries, 16 of them mode 100755);
2. `.git` removed, `git init -b master` (the remote's branch is `master`);
3. repo-local identity set so no personal address rides in the commit
   metadata — see §6;
4. one commit, with a message that names no person;
5. `origin` re-added, pointing at the same remote.

The rebuilt history is one commit. `git log --all -p` prints every version
of every file in it, so grepping that output is the whole proof. `grep`
exit 1 is the empty result. The account name and the handle are built from
fragments so this record does not reproduce them.

```
$ u=$(printf '%s%s' 'luc' 'as')            # the account name, unwritten
$ h=$(printf '%s%s' 'D' 'ee')              # the handle, unwritten

$ git log --all -p | grep -i "$u"; echo "exit $?"
exit 1

$ git log --all -p | grep -nE '/sessions/[a-z0-9]'; echo "exit $?"
exit 1

$ git log --all -p | grep -E "(^|[^A-Za-z])${h}([^A-Za-z]|$)"; echo "exit $?"
exit 1

$ git log --all -p | grep -E '/home/[a-z]'; echo "exit $?"
exit 1

$ git log --all -p | grep -iE '<old mailbox local part>'; echo "exit $?"
exit 1
```

Identity and shape of the new history:

```
$ git rev-list --all --count
1

$ git log --all --format='%an <%ae> | %cn <%ce>'
TheStudent00 <TheStudent00@users.noreply.github.com> | TheStudent00 <TheStudent00@users.noreply.github.com>

$ git remote -v
origin	https://github.com/TheStudent00/Airlock.git (fetch)
origin	https://github.com/TheStudent00/Airlock.git (push)

$ git rev-parse --abbrev-ref HEAD
master
```

The tree itself did not move. The index was recorded before `.git` was
removed and compared after the rebuild — 40 entries, byte-identical
including file modes:

```
$ diff /tmp/before_index.txt /tmp/after_index.txt && echo IDENTICAL
IDENTICAL
```

The two old commit hashes are deliberately not written here. They are the
one thing that still resolves on the remote for a while after a
force-push, and this file is public.

---

## §6 the commit identity

The original two commits carried author and committer
`TheStudent00 <a personal mailbox>`. The handle is the chosen public
identity and stays. The address was a real, personal mailbox and is
directly harvestable from a public repo's commit metadata, so it was
replaced with GitHub's noreply form. Set **repo-locally**, so nothing
outside this repo changed:

```
git config user.name  "TheStudent00"
git config user.email "TheStudent00@users.noreply.github.com"
```

There was no global git identity to worry about — both values were already
repo-local.

---

## §7 the guard

`scrub_check.sh` is tracked, documented in `README.md`, and wired into
`selftest.sh` as check 0. It scans two sets: tracked files, and untracked
files that are not ignored. It exits non-zero listing every offender with
file and line.

The pattern list is one array near the top of the script, entries of the
form `"<label>|<extended regex>"`. Adding a class is one line. A
machine-specific pattern that is itself too sensitive to publish goes in
`.scrub_patterns.local`, which is gitignored and read if present.

Two deliberate properties:

- The script **excludes itself** from the match. It necessarily contains
  the patterns; scanning itself would fail forever.
- The personal handle is **assembled at runtime** from fragments rather
  than written into the file, so this tracked, public file does not carry
  the string it exists to keep out.

`selftest.sh` was a good home for it: check 0 needs no container, runs in
milliseconds, and reports OK and moves on outside a git checkout, so it
does not break a tarball install. The six sandbox checks are unchanged and
still numbered 1–6.

---

## §8 what a force-push does not undo

Stated plainly, neither minimised nor inflated.

**What the force-push does.** It replaces the branch tip on the remote.
After it, cloning the repo, browsing it, and reading its history in the
GitHub UI all show only the scrubbed commit. The old commits stop being
reachable from any branch or tag.

**What it does not do.**

- *Unreferenced objects survive on GitHub for a period.* An old commit
  hash, once known, may still resolve in the web UI and in some API
  responses until GitHub's own garbage collection runs. GitHub does not
  publish a guaranteed interval. Both old hashes appeared in this
  session's notes and in any local clone.
- *Forks keep everything.* A fork is a separate repository. A force-push
  to the source does not touch it, and objects reachable in a fork can
  remain reachable through the fork network.
- *Pull requests and their diffs* are retained even when the underlying
  commits are unreferenced.
- *Third-party copies.* Search-engine caches, code-search indexes,
  archival mirrors, dataset scrapes and anyone who cloned. None of these
  are under anyone's control here.
- *Local clones.* Anyone who pulled has the old objects until they
  re-clone. The old commits also survive in any local reflog, including
  any other copy of this repo on the machine.

**The one certain removal** is deleting the repository on GitHub and
recreating it — this drops the fork network and the unreferenced objects
along with it. It also loses stars, watchers, issues and the URL's history,
and it is irreversible. **That decision is not made here.** It is listed
below as awaiting the maintainer.

Contacting GitHub Support to request expiry of the unreferenced objects is
the middle option: it is the documented route, and it does not require
deleting the repository.

---

## decided, recorded for audit

1. **Every personal-information hit in the working tree was rewritten, not
   deleted.** Sentences were restructured so no paragraph reads as
   patched. §4 is the proof.
2. **History was rebuilt rather than rewritten in place.** Two commits, no
   external contributors, no tags — a rebase or filter run would have been
   more machinery for the same result and more places to be wrong.
3. **The commit identity was changed repo-locally** to a noreply address,
   keeping the public handle. §6.
4. **The near-miss file was ignored by glob, not by name.** The exact-name
   rule is what let it through.
5. **`scrub_check.sh` was wired into `selftest.sh` as check 0** rather
   than left as a script someone must remember. It degrades to OK outside
   a git checkout, so it cannot break an install.
6. **The force-push was written, not run.** `force_push_scrubbed.sh` is
   gitignored, syntax-checked, refuses without authentication, refuses if
   `scrub_check.sh` fails, prints the exact command, warns that this
   rewrites public history, and requires a typed `y`.
7. **The licence PDF was searched, not assumed clean** — decompressed
   streams as well as raw bytes. It is clean.

## awaiting the maintainer

1. **Run the force-push.** Nothing reaches the remote until it is run:
   `bash force_push_scrubbed.sh`.
2. **Whether to delete and recreate the repository on GitHub.** The only
   certain removal, with the costs named in §8. The alternative is to
   accept the residual window, optionally with a support request to expire
   the unreferenced objects.
3. **Whether `DevComms/` belongs in a public repo at all.** Both files are
   now clean and both are genuinely useful — the derivation log is the
   only record of what was left behind and why, and the shape snapshot
   makes the middle pass auditable. But they are internal working records:
   they name other private repos by path, quote conversation, and are the
   file class that leaked in the first place. The recommendation recorded
   here is to keep them for now and treat every future log as public from
   its first character, as this one was written; moving `DevComms/` out of
   the public repo entirely remains a defensible call and is the
   maintainer's to make.

---

## 2026-08-22, later — git helpers, and a disc-layout tidiness pass

This is not a second PII incident. The maintainer's own framing, recorded
here because it shapes what follows: naming this repo's directory layout
gives away disc information for no benefit, and reads oddly to a stranger
who does not keep their own repos the same way. Nothing below was a
`scrub_check.sh` offender before this pass; everything below is tidiness.

### §9 the two git-ignored helpers added

Two scripts, both gitignored (see `.gitignore`), neither committed,
neither run by this session — the maintainer runs them:

- **`git_commit_push.sh`** — add, commit and push this repo, following
  the same private-repo helper's pattern this line of work already uses
  elsewhere: message priority is an explicit argument, then
  `DevComms/next_commit_message.txt` (emptied after use), then a default;
  stale git locks from an interrupted sandbox git are cleared first.
  Because this repo is public, two refusals were added that the private
  version does not carry, and neither can be skipped: `scrub_check.sh`
  must pass before anything is staged, and the script refuses outright if
  `git add -A` would pick up any file that is untracked and not
  gitignored — the exact hole this log's §2 already describes. It only
  ever fast-forwards; it does not force-push and does not rewrite
  history. Justification: this is the one script actually requested, and
  the public-repo refusals are what make it safe to hand to a routine
  workflow.
- **`git_status.sh`** — a read-only pre-flight. It reports what
  `git status` sees, which files (if any) are untracked-and-unignored,
  and the `scrub_check.sh` result, then states plainly whether
  `git_commit_push.sh` would proceed or refuse. It runs no git command
  that changes anything. Justification: seeing the refusal conditions
  before running the script that enforces them is worth one small file;
  it was kept to exactly what `git_commit_push.sh` already checks,
  nothing more, so the two stay in sync by construction rather than by
  discipline.

No third script was added. A `git_status.sh`-style pre-flight and the
commit-push driver cover the request; anything further (a log/diff
viewer, a branch helper) was judged to be toolkit-building rather than
what was asked for, and is left out.

Both scripts hardcode this repo's install location, the same convention
`create_public_repo.sh` already uses and for the same reason: they are
one machine's workflow, gitignored, never published, so the usual
"assume nothing about where the repo lives" rule that governs every
*tracked* file does not apply to them. `DevComms/next_commit_message.txt`
was added to `.gitignore` alongside them — it is the handoff file
`git_commit_push.sh` reads and empties, meaningful for one run only.

Verified for both: `bash -n` clean, and — because they are gitignored —
excluded from `scrub_check.sh`'s scan by construction (it only scans
tracked files and untracked-but-not-ignored files), so their real path
never risks being published.

### §10 the disc-layout sweep of tracked files

Every tracked file was swept for a home-relative path naming this
maintainer's projects directory by name. Three files carried it: the
derivation log, this log, and the migration guide.
None of the hits were the personal-information class §1–§8 above cover —
no `/home/<user>` path, no handle, no email — they were this repo's own
install location and a small number of sibling-repo locations, written
as if every reader keeps their repos in the same place the maintainer
does.

The fix, applied throughout rather than by blind substitution:

- **This repo's own install location** became `<airlock>`, matching the
  placeholder `MIGRATING.md` already used for it in every "what changes"
  table. A handful of rendered command transcripts and `usage()`-style
  examples took the same placeholder with the trailing script name kept,
  e.g. `<airlock>/airlock`.
- **The predecessor sandbox's location** became `<sandboxdesign>`, the
  same convention, for the same reason — it is Airlock's own lineage,
  not a project using it, and is already named freely throughout both
  logs without a path.
- **A systemd unit's specifier-form equivalent** (`%h` standing in for
  `~`, quoted in both logs as a historical description of a line the
  repo no longer carries) became `%h/<sandboxdesign>/...` for the same
  reason.
- **Paths naming a different, real project that uses this sandbox**
  (the derivation log names one such project by the path it once lived
  under, plus four more in a licence-convention comparison) had the
  disc-layout prefix dropped and the bare project name kept. That name
  was already used freely, undecorated, dozens of times elsewhere in the
  same historical record — hiding it only where a path preceded it would
  not have protected anything and would have made the record harder to
  audit. **This is a judged, recorded deviation** from anonymising the
  path entirely: if the maintainer wants those project names withheld
  everywhere rather than just out of path form, that is a larger,
  separate pass and is listed below as awaiting the maintainer.
- Two generic phrases named the projects-directory convention **as a
  category**, not as part of a path (describing "the single worst
  disc-layout assumption in the repo"), and were reworded to say exactly
  that instead of naming the directory.
- One phrase describing the *shape* of the earlier scrub's own fix (a
  placeholder pairing the projects-directory name with a repo name,
  itself already a placeholder rather than a real path) was reworded so
  this log does not carry the swept string a second time, and now points
  at this section instead.

No sentence was substituted blind; each was re-read after editing.
Verified: a repo-wide `grep` for the swept shape, across every tracked
file, returns nothing (`xargs` exit 123, its empty-result code), and
`scrub_check.sh` still passes.

### §11 the `scrub_check.sh` decision

Added: one pattern, `(~|%h)/Programming`, labelled a disc-layout
assumption rather than personal information — it is a different class
from §1's table and does not claim to be PII. Written split across an
alternation so the guard's own tracked source does not carry the literal
string it watches for, the same reason the personal-handle pattern above
it is assembled at runtime rather than written out.

**Declined:** the broader "any home-relative project path" shape the
brief also invited. Several tracked files legitimately print real
home-relative paths that are not this maintainer's disc layout at all —
toolchain locations (`~/.cargo`, `~/.rustup`, `~/Android/Sdk`, and
similar, in `probe_host.sh`), a systemd unit's own config directory
(`~/.config/containers/systemd/`), and the neutral example paths
`submit_project.sh` and `mounts.conf.example` already use
(`~/code/MyProject` and siblings). A pattern broad enough to catch every
home-relative shape would flag all of these on every future run, and a
guard that cries wolf gets ignored — the brief's own warning. The
narrow, literal pattern added has zero current matches and zero
plausible false positives against anything in this repo today.

**Proved, not asserted:**

```
$ bash ./scrub_check.sh
=== scrub_check: 7 pattern(s), 40 tracked file(s), 0 untracked-and-unignored file(s) ===
scrub_check: PASS - no personal or machine-identifying pattern found.
```

A planted violation (a throwaway untracked file whose one line joined
the swept shape with a fake repo name — deleted immediately after, never
committed, not reproduced here) was caught:

```
=== scrub_check: 7 pattern(s), 40 tracked file(s), 1 untracked-and-unignored file(s) ===
  FAIL  __scrub_violation_test.md  [untracked, NOT ignored - would be published by git add -A]
        pattern: disc-layout path assuming a specific projects directory
        1:<the planted line, one occurrence of the pattern above>

scrub_check: FAIL - 1 file/pattern hit(s) above.
  Fix the file, or - if it is a private working document - add it to
  .gitignore so it is never a candidate for publication.
```

Because the gitignored scripts above are excluded from both of
`scrub_check.sh`'s scanned sets by construction (`git ls-files` and
`git ls-files --others --exclude-standard` never include a gitignored
path), the new pattern was added with no risk of flagging the real paths
those two scripts legitimately need.

## decided, recorded for audit

1. **`git_commit_push.sh` and `git_status.sh` were written, gitignored,
   and not run.** Both refuse before touching git if `scrub_check.sh`
   fails or if an untracked-and-unignored file is present. Neither
   force-pushes or rewrites history.
2. **`DevComms/next_commit_message.txt` was added to `.gitignore`**
   alongside them, as the handoff file the commit script consumes.
3. **Every occurrence of the swept disc-layout shape in tracked files was
   rewritten**, none by blind substitution — proof in §10.
4. **`scrub_check.sh` gained one narrow pattern**, `(~|%h)/Programming`,
   written so its own source does not carry the literal string. The
   broader "any home-relative path" version was declined with reasons
   in §11.
5. **Sibling-project paths lost their disc-layout prefix but kept the
   bare project name**, a judged deviation from full anonymisation —
   reasoning in §10, flagged below.

## awaiting the maintainer

1. **Whether sibling-project names should be withheld entirely**, not
   just their disc-layout prefix. The derivation log names one real
   project that uses this sandbox, and four more alongside it in a
   licence-convention table, by bare name in several places outside any
   path. This pass left those as they were; scrubbing them fully is a
   larger, separate, structural pass and is the maintainer's call.
2. **Whether `git_commit_push.sh` and `git_status.sh` are wanted as
   written.** Untested by this session, by instruction — nothing above
   was run.
