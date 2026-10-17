# Spike 3 — fitting the build inside Datum Compute's 2 GiB, and the DNS blocker

Date: 2026-10-17. Follows `docs/datum-compute-buildbox-diagnosis.md`.

## What was measured

* **Node rootfs assembles at 153 MB**, and assembly itself used only ~440 MB of the
  container's memory. The unikernel image, once built, is small.
* **Disk page cache is reclaimable.** Writing 1.5 GB to a real file took
  `memory.current` to 1.59 GB and did not trigger the OOM — the kernel reclaimed
  cache under the cap.
* **tmpfs is unreclaimable.** `memory.current` and `memory.peak` count tmpfs pages
  in full, with no reclaim. This is what pushes a container over the limit.
* A deliberate 2.6 GB allocation to `/dev/shm` reproduced the silent recreation
  deterministically (new `boot_id`, wiped filesystem).

## Causes found for build failures inside `d1-standard-2`

1. **Build state in tmpfs.** The first version of `sp3/boxrun.sh` ran
   `buildkitd --root /dev/shm/buildkit`. tmpfs pages are unreclaimable and count
   against the 2 GiB cgroup limit, so the build drove the container into the OOM
   described in issue #491. Fixed to `--root /var/lib/buildkit` (disk).
2. **Intermittent DNS failure.** The buildbox has IPv6-only nameservers:

   ```
   nameserver 2001:4860:4860::6464
   nameserver 2001:4860:4860::64
   nameserver 2606:4700:4700::64
   ```

   IPv6 DNS resolution times out intermittently. In one probe,
   `nslookup releases.nixos.org` returned "no servers could be reached" while
   `nslookup cache.nixos.org` resolved on the next attempt, and plain
   `curl https://releases.nixos.org/` returned HTTP 200 moments later. When DNS
   fails, `nix profile add` fails, the toolchain install silently no-ops, and the
   build cannot run. This masqueraded as more OOM events.

## Answer: what would let us run BuildKit on Datum Compute reliably

| Option | Helps? | Reason |
| - | - | - |
| Different OS | No | The 2 GiB cap is a cgroup limit tied to the instance type, not the image. `drewr/nixos-gp` is capped the same as any other image. |
| A larger instance type | Yes, directly | `d1-standard-2` is the only type available today. A larger type moves the cap. This is what issues #137 and #492 are about. |
| Keep the build under 2 GiB | Yes, partially | Feasible: keep state on disk, not tmpfs; use `nodejs-slim`; build in stages. Assembly used only ~440 MB, so the headroom exists if transient allocations are bounded. |
| Remote BuildKit | Yes, best near-term | `datumctl compute build --buildkit-host tcp://HOST:PORT` uses a BuildKit that is not under the 2 GiB cap. Sidesteps the limit entirely. |
| Fix DNS | Needed regardless | IPv6-only resolvers that intermittently time out break any network-dependent build. |
| Build elsewhere, deploy to Datum | Yes, recommended | Datum Compute should *run* the unikernel, not build it. Build on a host with more memory, push to GHCR, and `datumctl compute deploy`. |

## Reframe

The 2 GiB limit constrains **building large images on Datum**, not **running
unikernel instances**. A unikernel instance with a 153 MB or smaller rootfs fits
comfortably in 2 GiB of RAM. So the architecture that works is:

1. Build the unikernel image on a machine with adequate memory (or a remote
   BuildKit).
2. Push it to a registry.
3. `datumctl compute deploy` it as a `unikernel` workload.

## Open items

* Report the IPv6 DNS instability on Compute instances (separate from #491/#492).
* Decide the build host: a remote BuildKit, or build on the Mac and push.
