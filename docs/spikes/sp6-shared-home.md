# Spike 6a — a shared live home on JuiceFS

Date: 2026-10-19. Goal: mimic a laptop. Every agent sandbox mounts the same
home, so `~/.claude` (conversations, `claude --resume`) and `~/work` (repos,
including uncommitted changes) are shared live across sessions.

## Setup

| Piece | Where |
| - | - |
| JuiceFS volume `agent-home` (1.4.1) | data in S3 `agent-home-007091975061-use2` (us-east-2; private, versioned, SSE, 30-day noncurrent expiry) |
| Metadata | Redis 8.10 on the EC2 build box (us-east-2), AOF `everysec`, password, loopback only. A **temporary** `systemd-run` unit, not yet in `configuration.nix` |
| Metadata transport | its own dumbpipe endpoint on the box; sandboxes run `dumbpipe connect-tcp` to `127.0.0.1:6379` with a relay-carrying ticket |
| Credentials | Datum Secret `agent-home`: `META_TICKET`, `META_URL`, plus an access key for IAM user `agent-home-juicefs` (policy: that bucket only) |
| Sandbox | `agent/init.sh` mounts at `/home/agent` and login shells use it as `HOME`; `agent-sandbox new` wires it in when the Secret exists (`--no-home` opts out) |

FUSE works in the instances: the kernel has `fuse`, `/dev/fuse` opens, and the
session runs as root with every capability. The root filesystem is an overlay
with the image as a read-only erofs lower layer and a RAM-backed upper layer.

## Results

Correctness: **works.** A file written in `h1` was read in `h2` about 1 s later.

Performance (repo: this dotfiles repo, 328 files, run in the same sandbox):

| Operation | RAM (`/tmp`) | JuiceFS home | Slowdown |
| - | -: | -: | -: |
| `git clone` | 2.0 s | 292.5 s | ~145× |
| `git status` (1st) | 0.23 s | 54.2 s | ~240× |
| `git status` (2nd) | 0.17 s | 33.1 s | ~200× |
| `rg` over tree | 0.06 s | 29.3 s | ~490× |
| write 200 small files + `sync` | 0.007 s | 129.0 s | — |

The run was cut off by its 900 s timeout before `git add + commit`.

Why: JuiceFS reported a Redis ping of **51 ms** through the tunnel. That path
is Datum us-central-1 (Dallas) → n0 relay `use1-1` (Virginia) → EC2 (Ohio).
Every uncached lookup, getattr, open and close is at least one such round trip,
and every small file's first read or write is also an S3 request from Dallas to
Ohio. git touches each file several times. With the default 1 s attribute
cache, nothing amortizes.

## Bug found and fixed

The metadata tunnel inherited `IROH_SECRET` from init, so it came up as the same
iroh endpoint as the SSH listener. The relay drops one of two connections that
share an identity, so the listener restarted every ~20 s, and SSH streams were
corrupted mid-session ("Bad packet length"). `init.sh` now starts the tunnel
with `env -u IROH_SECRET`.

## Options from here

1. **Tune JuiceFS:** longer attribute, entry and dir-entry caches (30–60 s),
   `--open-cache`, `--writeback` (asynchronous S3 uploads). This helps repeat
   operations and writes. Other sessions then see changes only after the cache
   TTL. First touches stay slow.
2. **Cut the round trip:** put metadata in AWS's Dallas Local Zone (a few ms
   from Datum us-central-1), and get a direct iroh path instead of the
   Virginia relay. Combined with option 1, this might come within a small
   multiple of local for metadata. Data first-touch still goes to S3 in Ohio.
3. **Hybrid:** share `~/.claude` and dotfiles live on JuiceFS (few, small
   files; conversations resumable anywhere), and keep repos in RAM per session
   with a checkout and check-in to the shared home (rsync or git bundle on
   open, periodically, and on exit), plus a per-repo lock. git runs at local
   speed and work persists and resumes elsewhere, but two sessions can't edit
   the same repo at once.

## Round 2 (2026-10-19): Ashburn, EC2 baseline, dual-stack S3

| | RAM | EC2 us-east-2, local Redis | Datum us-east-1 (IAD) | Datum us-central-1 (DFW) |
| - | -: | -: | -: | -: |
| Redis round trip | — | 0.1 ms | 15 ms | 51 ms |
| `git clone` | 0.4 s | 5.6 s | 70 s | 292 s |
| `git status` (2nd) | 0.05 s | 0.13 s | 8.4 s | 33 s |
| `rg` over tree | 0.02 s | 0.07 s | 8.4 s | 29 s |
| write 200 small files | 0.002 s | 4.8 s | 41 s | 129 s |
| `git add` + commit | 0.15 s | 7.0 s | 154 s | (timed out) |

Speed tracks the metadata round trip; with Redis local (EC2) JuiceFS is close
to disk for reads. Next: move Redis and the bucket to AWS us-east-1 (same metro
as Datum IAD, ~1–2 ms).

Staging findings (staging is not a dependency; sessions now target production):

* Staging us-east-1 has **no IPv4 egress**: plain resolvers instead of DNS64,
  and no NAT64 (`64:ff9b::/96` unreachable). GitHub and IPv4-only S3 endpoints
  are unreachable. Dallas has DNS64 and NAT64.
* JuiceFS rewrites the bucket URL to the IPv4-only S3 endpoint ("no addresses
  to dial"). `AWS_USE_DUALSTACK_ENDPOINT=true` on the mount fixes it in any
  location.
* Staging's `default` network never got a us-east-1 VPC identifier
  (`NetworkFailedToCreate`); a freshly created network worked.
