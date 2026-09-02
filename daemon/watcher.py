#!/usr/bin/env python3
"""
Hot-folder daemon. Watches /drop and runs each bash script that lands there.

WHAT IT WATCHES FOR
    moved_to     a file was renamed INTO /drop. This is the intended path:
                 the submitter writes ".name.sh" (hidden) and then renames
                 it to "name.sh". Rename inside one directory is atomic, so
                 a half-written file never appears under the final name.
    close_write  a file that was written directly in /drop had its last
                 writer close it. Covers submitters that do not rename.

WHAT IT IGNORES
    Any name starting with "." — that is the "not ready yet" marker.
    Any name not ending in ".sh".

STATUS FILES (added 2026-07-30, for unattended submitters)
    A log's name embeds the run's timestamp, so a submitter cannot predict
    it. For every script the daemon also writes /status/<name>.status, whose
    path IS predictable from the script name. It is key=value lines, written
    once when the run starts (state=running) and rewritten when it ends
    (state=done, exit=<rc>). An agent that dropped "x.sh" can therefore poll
    one known path to learn whether the run is still going, what it exited
    with, and which log to read — no parsing of prose, no directory listing.

    Disk headroom on /work is recorded in the log header and footer, because
    a run that exhausts scratch space is otherwise diagnosed only by its
    wreckage.

EXECUTION IS SERIAL. run_script() is called synchronously from the single
event loop, so two scripts dropped at once run one after the other. This is
deliberate: concurrent heavy runs are what exhaust scratch space.

NO EXTERNAL DEPENDENCIES. inotify is reached through ctypes so the image
does not need pip packages for the daemon itself.

HOW THE DOORBELL IS CHOSEN (AIRLOCK_WATCH, added 2026-09-02)
    inotify is the default and is what this daemon has always used.

    inotify has a PER-USER limit on how many inotify INSTANCES may exist at
    once: /proc/sys/fs/inotify/max_user_instances, 128 on a stock Ubuntu.
    Every editor, file manager, language server and podman process on the
    machine holds some. When they are exhausted, inotify_init1 fails with
    ENOSPC and the message reads "No space left on device" — which is about
    instances, not about disk, and has misdirected at least one operator.

    AIRLOCK_WATCH=poll replaces the doorbell with a directory scan every
    POLL_INTERVAL seconds. It needs no kernel resource at all. It is OFF by
    default because it is strictly worse: a lane waits up to one interval
    before it starts, and a large /drop costs a listdir per interval.
    Nothing else changes — the same lane runs, writes the same log, the
    same status file and the same archive.

    AIRLOCK_WATCH=auto tries inotify and falls back to polling with a loud
    line in the log if the kernel refuses an instance. A run is never lost
    to a resource the daemon could have done without.

LOW PRIORITY (added 2026-08-22). Every lane script is niced (see LANE_NICE)
before it execs, so a long probe run competes gently for CPU instead of
holding every core at full tilt for hours. This is a fixed, simple cap —
no temperature sensor, no feedback loop — paired with the --cpus cap in
up.sh. It changes nothing about how the run is observed: the forked
process's own exit status still becomes proc.returncode untouched, so
status-file and log handling are exactly as before.
"""

import ctypes
import ctypes.util
import errno
import os
import select
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone

DROP_DIR = os.environ.get("DROP_DIR", "/drop")
LOG_DIR = os.environ.get("LOG_DIR", "/logs")
WORK_DIR = os.environ.get("WORK_DIR", "/work")
STATUS_DIR = os.environ.get("STATUS_DIR", "/status")
# Wall-clock ceiling per script. A runaway script is stopped by the operating
# system (the ABORT outcome), not left to spin.
TIMEOUT_SECONDS = int(os.environ.get("SCRIPT_TIMEOUT", "3600"))
# Scheduling priority for every lane script (higher = gentler on the CPU).
# Paired with the --cpus cap in up.sh so long probe runs leave the host
# responsive for anything else run on it at the same time.
LANE_NICE = int(os.environ.get("LANE_NICE", "15"))
# "inotify" (default), "poll", or "auto". See the note at the top of this
# file. up.sh sets this from the instance's `watch` key.
WATCH_MODE = os.environ.get("AIRLOCK_WATCH", "inotify").strip().lower()
# How often the polling doorbell rescans /drop, in seconds.
POLL_INTERVAL = float(os.environ.get("AIRLOCK_POLL_INTERVAL", "2"))

# ---- inotify constants (from linux/inotify.h) ---------------------------
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_Q_OVERFLOW = 0x00004000
IN_NONBLOCK = 0o4000

EVENT_HEADER = struct.Struct("iIII")  # wd, mask, cookie, len


def log(msg):
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    print(f"[{stamp}] {msg}", flush=True)


class Inotify:
    """Minimal inotify wrapper. One watched directory is all we need."""

    def __init__(self):
        self.libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
        self.fd = self.libc.inotify_init1(IN_NONBLOCK)
        if self.fd < 0:
            e = ctypes.get_errno()
            raise OSError(e, f"inotify_init1 failed: {os.strerror(e)}")

    def add_watch(self, path, mask):
        wd = self.libc.inotify_add_watch(self.fd, path.encode(), mask)
        if wd < 0:
            e = ctypes.get_errno()
            raise OSError(e, f"inotify_add_watch({path}) failed: {os.strerror(e)}")
        return wd

    def read_events(self):
        """Block until at least one event, then return every queued name."""
        select.select([self.fd], [], [])
        try:
            buf = os.read(self.fd, 65536)
        except OSError as ex:
            if ex.errno == errno.EAGAIN:
                return []
            raise
        out, pos = [], 0
        while pos < len(buf):
            wd, mask, cookie, length = EVENT_HEADER.unpack_from(buf, pos)
            pos += EVENT_HEADER.size
            raw = buf[pos:pos + length]
            pos += length
            if mask & IN_Q_OVERFLOW:
                log("WARNING: inotify queue overflowed; rescanning /drop")
                out.append(None)  # sentinel -> caller does a full rescan
                continue
            name = raw.split(b"\0", 1)[0].decode("utf-8", "replace")
            if name:
                out.append(name)
        return out


class Poller:
    """The doorbell that needs no kernel resource.

    It holds the set of runnable names it has already reported and, every
    POLL_INTERVAL seconds, reports whatever is in /drop and not in that
    set. A name that ran and was archived out of /drop leaves the set too,
    so a lane resubmitted under the same name is seen again.

    read_events() has the same contract as Inotify.read_events(): it
    blocks, then returns a list of names. The main loop cannot tell the
    two apart.
    """

    def __init__(self, drop_dir, interval):
        self.drop_dir = drop_dir
        self.interval = interval
        self.seen = set()

    def _listing(self):
        try:
            return set(os.listdir(self.drop_dir))
        except OSError:
            return set()

    def read_events(self):
        while True:
            time.sleep(self.interval)
            present = self._listing()
            self.seen &= present          # forget what is no longer there
            fresh = sorted(n for n in present
                           if is_runnable(n) and n not in self.seen)
            if fresh:
                self.seen |= set(fresh)
                return fresh


def open_watcher(drop_dir):
    """Return the doorbell this daemon will use, and say which it is.

    inotify  the default; fails loudly if the kernel has no instance left
    poll     a directory scan; needs nothing from the kernel
    auto     inotify, falling back to poll on the ENOSPC that means
             "no inotify instances left", never on any other error
    """
    if WATCH_MODE == "poll":
        log(f"watch mode: poll (every {POLL_INTERVAL}s) — no inotify instance used")
        return Poller(drop_dir, POLL_INTERVAL)

    try:
        ino = Inotify()
        ino.add_watch(drop_dir, IN_MOVED_TO | IN_CLOSE_WRITE)
        log("watch mode: inotify (moved_to, close_write)")
        return ino
    except OSError as ex:
        if WATCH_MODE != "auto" or ex.errno != errno.ENOSPC:
            raise
        log(f"WARNING: the kernel refused an inotify instance ({ex}).")
        log("WARNING: this is the per-user limit in "
            "/proc/sys/fs/inotify/max_user_instances, NOT disk space.")
        log(f"WARNING: falling back to polling every {POLL_INTERVAL}s "
            "(AIRLOCK_WATCH=auto).")
        return Poller(drop_dir, POLL_INTERVAL)


def _lower_priority():
    """Run in the newly forked process, before exec. Lowers its scheduling
    priority (see LANE_NICE) so a lane script does not compete for CPU with
    anything else on the host. Best-effort: if the platform refuses,
    the run proceeds at normal priority rather than aborting the lane."""
    try:
        os.nice(LANE_NICE)
    except OSError as ex:
        log(f"WARNING: could not lower priority (nice {LANE_NICE}): {ex}")


def is_runnable(name):
    return name.endswith(".sh") and not name.startswith(".")


def free_mb(path):
    """Free space in MB on the filesystem holding `path` (-1 if unavailable)."""
    try:
        st = os.statvfs(path)
        return (st.f_bavail * st.f_frsize) // (1024 * 1024)
    except OSError:
        return -1


def write_status(name, **fields):
    """Write /status/<name>.status as key=value lines.

    The path is derived from the SCRIPT NAME alone, so a submitter that
    dropped the script can poll it without knowing the run's timestamp.
    Written atomically (temp + rename) so a poller never reads half a file.
    """
    os.makedirs(STATUS_DIR, exist_ok=True)
    final = os.path.join(STATUS_DIR, f"{name}.status")
    tmp = os.path.join(STATUS_DIR, f".{name}.status.tmp")
    body = "".join(f"{k}={v}\n" for k, v in fields.items())
    try:
        with open(tmp, "w") as fh:
            fh.write(body)
        os.replace(tmp, final)
    except OSError as ex:
        log(f"WARNING: could not write status for {name}: {ex}")


def run_script(name):
    path = os.path.join(DROP_DIR, name)
    if not os.path.isfile(path):
        return
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    logpath = os.path.join(LOG_DIR, f"{stamp}__{name}.log")
    started = time.monotonic()
    started_iso = datetime.now(timezone.utc).isoformat(timespec="seconds")
    free_before = free_mb(WORK_DIR)

    write_status(name, script=name, state="running", started=started_iso,
                 log=logpath, work_free_mb_before=free_before)

    log(f"RUN  {name}  -> {logpath}  (work free {free_before} MB)")
    with open(logpath, "wb") as lf:
        header = (
            f"# script: {path}\n"
            f"# started: {started_iso}\n"
            f"# timeout: {TIMEOUT_SECONDS}s\n"
            f"# work free before: {free_before} MB\n"
            f"{'-' * 60}\n"
        )
        lf.write(header.encode())
        lf.flush()
        try:
            proc = subprocess.run(
                ["/bin/bash", path],
                cwd=WORK_DIR,
                stdout=lf,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                timeout=TIMEOUT_SECONDS,
                preexec_fn=_lower_priority,
            )
            rc = proc.returncode
            verdict = f"exit {rc}"
        except subprocess.TimeoutExpired:
            rc = -1
            verdict = f"KILLED after {TIMEOUT_SECONDS}s timeout"
        elapsed = time.monotonic() - started
        free_after = free_mb(WORK_DIR)
        footer = (
            f"{'-' * 60}\n"
            f"# {verdict} in {elapsed:.1f}s\n"
            f"# work free after: {free_after} MB "
            f"(consumed {free_before - free_after} MB)\n"
        )
        lf.write(footer.encode())

    write_status(name, script=name, state="done", exit=rc,
                 started=started_iso,
                 finished=datetime.now(timezone.utc).isoformat(timespec="seconds"),
                 elapsed_s=f"{elapsed:.1f}", log=logpath,
                 work_free_mb_after=free_after,
                 work_consumed_mb=free_before - free_after,
                 verdict=verdict)

    log(f"DONE {name}  {verdict}  ({elapsed:.1f}s, work free {free_after} MB)")

    # Move the script out of /drop so a restart does not re-run it.
    done_dir = os.path.join(DROP_DIR, ".done")
    os.makedirs(done_dir, exist_ok=True)
    try:
        os.replace(path, os.path.join(done_dir, f"{stamp}__{name}"))
    except OSError as ex:
        log(f"WARNING: could not archive {name}: {ex}")


def sweep():
    """Run anything already sitting in /drop (startup, or after overflow)."""
    for name in sorted(os.listdir(DROP_DIR)):
        if is_runnable(name):
            run_script(name)


def main():
    for d in (DROP_DIR, LOG_DIR, WORK_DIR, STATUS_DIR):
        os.makedirs(d, exist_ok=True)

    watcher = open_watcher(DROP_DIR)
    log(f"watching {DROP_DIR} (moved_to, close_write); logs -> {LOG_DIR}")
    log(f"status -> {STATUS_DIR}/<name>.status ; work free {free_mb(WORK_DIR)} MB")
    log(f"submit by renaming '.name.sh' -> 'name.sh', or by writing directly")

    sweep()  # catch anything present before we started

    while True:
        for name in watcher.read_events():
            if name is None:
                sweep()
            elif is_runnable(name):
                run_script(name)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
