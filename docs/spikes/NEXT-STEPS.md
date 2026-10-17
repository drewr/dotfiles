# Next steps: Datum Compute + Unikraft agent sessions

Status as of 2026-10-17. Branch `datum-unikraft-sessions`. Continues
`docs/spikes/PLAN.md` (hypothesis board) and the spike `RESULTS.md` files.

## Where things stand

### Proven on Datum's unikernel tier

- **Process creation works.** Spike 1: live `vfork`+`execve`+`wait4`,
  `posix_spawn`+`waitpid`, and `_exit` all behave. Case C proved **true COW
  `fork()`**, not a vfork alias — the deployed Unikraft build is newer than the
  upstream README that claims vfork-only.
- **An init model works.** Spike 2: an entrypoint at `ppid=1` spawned a
  long-lived child, the child survived across ticks, and the parent reaped it
  with the correct exit code.
- **s6 works.** Spike 2b: `s6-supervise` started a service under Unikraft. Only
  `s6-svscan` fails, because it spawns helpers by bare-name PATH lookup and
  Unikraft's `execve` requires an absolute path (finding H14).
- **`/proc`, signals, PTYs** (`setsid`, `/dev/ptmx`) all work — the primitives a
  TUI over SSH needs.

### Still open

- **H6 — does Node run?** Spike 3 is blocked before the run step. The Node rootfs
  assembles (153 MB), but building the image inside Datum fails.
- **Spike 4 — transport.** Not started.

### Why Spike 3 is blocked

Two independent problems, both now diagnosed and filed:

1. **Silent container OOM.** The `d1-standard-2` container is capped at 2 GiB via
   cgroup (`memory.max = 2147483648`) even though the VM has ~4 GiB. Exceeding it
   kills and recreates the sandbox with a new `boot_id`, a wiped filesystem, no
   event, and a stale instance `Age`.
   Filed: datum-cloud/compute#491, #492.
2. **IPv6-only DNS times out intermittently.** `nslookup releases.nixos.org`
   fails while `cache.nixos.org` resolves, so `nix profile install` silently
   installs nothing and the build fails for a non-OOM reason.
   Filed: datum-cloud/compute#493.

A third conflict, found in `buildbox/README.md` gotcha 2: the Datum instance's
writable filesystem is **fuse (no xattrs)**, so BuildKit's native snapshotter
needs its root on **tmpfs** — and tmpfs pages are unreclaimable, so they count in
full against the 2 GiB cap. The two requirements are in direct conflict on Datum.
That is the core reason the build cannot succeed there reliably.

## Immediate next step: build on EC2, not on Datum

Datum Compute should **run** the unikernel, not **build** it. Build off-platform,
push to GHCR, then `datumctl compute deploy`. See `docs/datum-build-box-ec2.md`.

- **Instance: `t3a.medium` (2 vCPU, 4 GB), ~$0.0376/hr, ~$0.84/month at 20 build
  hours.** Cheapest x86 instance with 4 GB.
- On EC2 the 2 GiB cap and the fuse/xattr problem both disappear: BuildKit's root
  lives on normal ext4, and the box has real memory.
- Connect to BuildKit over **iroh** (`dumbpipe`) rather than an open TCP port —
  BuildKit's TCP listener is unauthenticated. Wiring is in
  `docs/datum-build-box-ec2.md`.

### Steps

1. Provision `t3a.medium` (`us-east-1`), 16 GB gp3, x86_64.
2. Install: `nix`, `buildkit`, `runc`, `docker` (for context handling), `crane`.
3. Start `buildkitd --addr tcp://127.0.0.1:1234 --root /var/lib/buildkit`
   (root on disk, not tmpfs).
4. Expose it with `dumbpipe listen-tcp --host localhost:1234`; keep the ticket.
5. Locally: `dumbpipe connect-tcp --addr 127.0.0.1:1234 <ticket>`, then
   `datumctl compute build --buildkit-host tcp://127.0.0.1:1234 --push --output
   ghcr.io/drewr/sp3-node:dev sp3/` (use `sp3/run-once.sh` as the recipe).
6. Deploy `sp3/workload.yaml` as a unikernel workload and read the logs — this
   answers **H6**: does Node start, and does `fork`/`spawnSync` work?
7. If H6 passes, proceed to Spike 4 (transport) and then the agent images.

## Build recipes to reuse

- `buildbox/setup.sh` — tooling install order (one package at a time; a
  multi-package `nix profile install` collides and drops tools).
- `sp3/boxrun.sh` — rootfs assembly: node binary, busybox, glibc loader, closure
  libs, `patchelf --set-interpreter`/`--set-rpath`, and content dedupe (292 MB →
  153 MB).
- Static-PIE is required for the unikernel ELF loader:
  `cc -static-pie -fPIE -O2` (sp1, sp2).
- Publish the OCI **index**, not a flattened manifest: `datumctl compute build
  --push` writes an index with `platform: {x86_64, kraftcloud}`; a `crane push`
  of a layout dir flattens it and the platform cannot pull the result.

## Constraints (carried from PLAN.md)

- Unikernel rootfs is held in memory and counts against the 2 GiB instance.
- Unikernel class: no shell, no `datumctl compute exec`, no `envFrom`; per-key
  `valueFrom` and ConfigMap/Secret volumes only.
- Public ingress is HTTP(S) via the Datum ALB only; SSH travels over iroh/Connect,
  never a public port.
- Secrets: ≤256 KiB each, ≤1 MiB total per workload per location.
- No persistence: any instance replace wipes the filesystem.
- `general-purpose` is **off the table** for the agent instances (user decision);
  it remains acceptable for a build box, but the build box is moving to EC2.

## Filed issues

| Issue | Title |
| - | - |
| datum-cloud/compute#491 | Silent container OOM recreates the sandbox with no event or status change |
| datum-cloud/compute#492 | Instance type memory is an undocumented per-container cgroup limit, smaller than the VM |
| datum-cloud/compute#493 | IPv6-only DNS resolvers time out intermittently |

## Parallel ask (unchanged)

Request that Datum accept a customer-supplied VM boot image (a NixOS image) for
the VM runtime shape, referencing `DefaultBootImage` in `workloadspec/render.go`.
If granted, that is the path to a real NixOS boot. Low effort, high payoff.
