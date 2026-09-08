# Moving an install to another machine

Three scripts, in order. `pack.sh` runs on the machine that has the working
install; `prepare_host.sh` and `unpack.sh` run on the machine that is to
receive it.

| script | runs where | what it does |
|---|---|---|
| `pack.sh` | the machine you have | writes a bundle folder: the tool as a git bundle, the built images as OCI archives, every `instances/*.conf`, `mounts.conf`, the proxy allowlist, each persist volume, and a copy of every host directory `mounts.conf` exposes |
| `prepare_host.sh` | the new machine | installs podman, git, rsync, python3; delegates the `cpu` cgroup controller to the user if the distribution has not; enables lingering so containers survive logout. `--check` reports and changes nothing |
| `unpack.sh` | the new machine, from inside the bundle | clones the tool, loads the images, restores the config and the volumes, restores the projects, optionally rewrites every instance's caps for a bigger machine, and brings named instances up |

```
bash <airlock>/pack.sh --out <bundle dir> [--skip <path substring>]...
# copy <bundle dir> to the new machine, then there:
bash prepare_host.sh --check
bash prepare_host.sh
bash unpack.sh --cpus <N> --memory <N>g --up sandbox
```

`--skip` leaves out a mounted directory a queued task does not read; the
manifest records what was skipped so the omission is visible later.

## Receiving machines that do not run podman

The bundle assumes podman, a persistent home directory, and systemd for
lingering. A host that has none of those -- a storage appliance whose root
filesystem lives in RAM, for instance -- can still receive the bundle by
running an ordinary Linux guest on its own hypervisor and treating the guest
as the receiving machine. Nothing in the bundle changes; every path inside
the guest is a normal home directory again.

Settings that matter for the guest:

| setting | why |
|---|---|
| cores and memory | these become the ceiling every instance conf is rewritten to by `unpack.sh --cpus --memory` |
| disk, at least four times the bundle's size | the bundle, the loaded images, the restored volumes and the restored projects all land on it, and lanes then write scratch |
| bridged network | so the bundle can be copied straight into the guest, and so a session can reach it |
| virtual disk on the fastest pool available | the term stores and the regen stores are read repeatedly by long lanes |

## Two more scripts, for a machine the bundle cannot be copied into

| script | what it does |
|---|---|
| `push_bundle.sh` | restores a bundle onto a remote machine over ssh, streaming each archive straight into podman there, so the archives never occupy the receiving disk. For a machine with no share and no room for the bundle beside what is restored from it |
| `remote_lane.sh` | drives the remote install from here with the same lane protocol: `submit`, `wait`, `log`, `status`, `up`, `down`, `conf`, and `sync-to` / `sync-back` to mirror a working folder around a lane. `AIRLOCK_REMOTE` and `AIRLOCK_REMOTE_ROOT` name the target |

`prepare_host.sh` installs, besides podman itself, the pieces a distribution's
podman 4.x needs and does not pull in: `slirp4netns` for rootless networking,
and the `dnsname` CNI plugin. `up.sh` no longer depends on container name
lookup at all: it reads the proxy's address after starting it and hands the
runner a hosts entry, because the CNI backend gives an internal network no
name lookup.
