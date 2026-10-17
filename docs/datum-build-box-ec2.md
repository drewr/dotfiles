# Cheapest EC2 build box for Datum Compute unikernel images

Date: 2026-10-17. Prices from the public AWS pricing API for `us-east-1`,
`Linux`/`Shared`/on-demand, retrieved 2026-10-17. Prices change; re-check before
buying.

## What the build has to do

`datumctl compute build --buildkit-host tcp://HOST:PORT` builds the unikernel
image on a remote BuildKit and pushes to a registry. The build box runs:

- BuildKit (OCI worker, `native` snapshotter) solving a `Dockerfile.datum`.
- `nix` to produce the userspace and its closure.
- An OCI export/push step to a registry.

Observed footprint from the spikes on the Datum `d1-standard-2` buildbox:

| Item | Size |
| - | - |
| Assembled node rootfs (final image) | 153 MB |
| Node closure in the nix store | ~223 MB |
| RSS during rootfs assembly | ~440 MB |
| nix store for toolchains (buildkit, runc, patchelf, node, glibc, icu) | ~1-3 GB after a fresh install |

Requirements:

- **x86_64.** Datum Compute targets `linux/amd64`. A Graviton (`t4g`, arm64)
  instance would need emulation or a separate build path, so exclude it.
- **Memory.** 2 GB is the floor but is exactly what tripped the Datum OOM once
  tmpfs was involved. BuildKit plus `nix` plus a solve is safer with 4 GB.
- **Disk.** ~10 GB gp3 is comfortable (nix store, BuildKit layers, OCI export).
- **Network.** Outbound to `cache.nixos.org` and the target registry.

## Prices (us-east-1, on-demand, Linux, x86)

| Instance | vCPU | RAM | $/hr | 24/7 | 2 h/day | 20 h/mo |
| - | - | - | - | - | - | - |
| t3a.micro | 2 | 1 GB | 0.0094 | $6.86 | $0.56 | $0.19 |
| t3.micro | 2 | 1 GB | 0.0104 | $7.59 | $0.62 | $0.21 |
| **t3a.small** | **2** | **2 GB** | **0.0188** | **$13.72** | **$1.13** | **$0.38** |
| t3.small | 2 | 2 GB | 0.0208 | $15.18 | $1.25 | $0.42 |
| **t3a.medium** | **2** | **4 GB** | **0.0376** | **$27.45** | **$2.26** | **$0.75** |
| t3.medium | 2 | 4 GB | 0.0416 | $30.37 | $2.50 | $0.83 |
| t3a.large | 2 | 8 GB | 0.0752 | $54.90 | $4.51 | $1.50 |
| m6i.large | 2 | 8 GB | 0.0960 | $70.08 | $5.76 | $1.92 |
| c6i.large | 2 | 4 GB | 0.0850 | $62.05 | $5.10 | $1.70 |

`t3a` is AMD and consistently ~10% cheaper than the equivalent `t3`. `t2` is
EOL-ish and never cheapest.

## Recommendation

**`t3a.medium` (2 vCPU, 4 GB) — $0.0376/hr, about $0.75/month at 20 hours of
builds.**

Reasoning:

- It is the **cheapest x86 instance with 4 GB**. `t3a.small` (2 GB) is half the
  price, but 2 GB is the exact ceiling that caused the silent OOM on Datum; the
  same margin would be uncomfortable with BuildKit and `nix` in the same box.
- A build box is **episodic**, so stop it between builds. At 20 hours a month the
  compute cost is under a dollar, and the dominant cost becomes EBS.
- `t3a` saves ~10% over `t3` for identical specs.

### Cheapest possible if 2 GB is judged sufficient

**`t3a.small` (2 vCPU, 2 GB) — $0.0188/hr, about $0.38/month at 20 hours.**
Only pick this if builds are verified to stay well under 2 GB (keep BuildKit's
root on disk, never tmpfs, and use `nodejs-slim`). It is the true price floor for
x86 at the required memory class.

### Absolute cheapest that could work at all

`t3a.micro` (2 vCPU, 1 GB) at $0.0068/hr is the cheapest x86 option, but 1 GB is
below what a BuildKit solve plus `nix` needs. Not recommended.

### Even cheaper if the workload allows it

- **Spot**: `t3a.medium` spot is usually a fraction of on-demand, and a build box
  tolerates interruption retries. Worth using for a box that is started on demand
  and terminated after.
- **Graviton (`t4g.small`, 2 GB, $0.0168/hr)**: cheapest per GB, but **arm64**.
  Only usable if the build cross-compiles to amd64 (`--platform linux/amd64`,
  which is slow under emulation) or if Datum adds arm64 support. Excluded here.

## Storage

- Root: **gp3, 16 GB** — $0.08/GB-month = **$1.28/month** if left running, or
  ~$0.09 for a 20-hour month if the volume is deleted with the instance.
- Keeping a stopped instance's volume costs $1.28/month regardless, which quickly
  exceeds the compute cost. Consider terminating rather than stopping, and
  re-provisioning.

## Total

`t3a.medium`, 20 build-hours a month, volume deleted between runs:

```
compute   20 h x $0.0376   = $0.75
storage   16 GB gp3, 20 h  = $0.09
                           ------
                          ~ $0.84 / month
```

## Wiring it up

```
# on the build box
BUILDKIT_HOST=tcp://0.0.0.0:1234 buildkitd --addr tcp://0.0.0.0:1234 &

# locally
datumctl compute build --buildkit-host tcp://BUILD_BOX:1234 \
  --push --output ghcr.io/drewr/sp3-node:dev .
```

BuildKit's TCP listener is unauthenticated; restrict it with a security group
that allows port 1234 only from your address, or tunnel it over SSH.
