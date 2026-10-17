# Plan: Datum Compute + Unikraft for opencode/claude sessions

Status: Spikes 1, 2, 2b, 3 PASSED on Datum's unikernel tier (Node runs, H6). The
agents ship as Bun single-file executables, so Spike 5 (H15, Bun) is next, then
Spike 4 (transport). Builds run on the EC2 box in `buildbox/ec2/`; see
`docs/spikes/NEXT-STEPS.md`.

## Goal

Launch Datum Compute instances to host opencode and claude-code sessions, TUI over
SSH, built from a Nix-produced minimal userspace. Target size 80–200 MB (alpine is
inspiration, not a hard target). Unikraft runtime class is preferred; no fallback
to `general-purpose`. SSH is expected to travel over iroh via Datum Connect
(`feat/projectless-local-tunnel`) rather than a public port.

## Hypothesis board

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | Unikraft cannot fork/exec → no sshd possible | REFUTED | `unikraft/lib/posix-process` (staging) documents a full Multiprocess level: `vfork`, `execve`, `wait4`, `clone` all supported. **Confirmed live on Datum (Spike 1): `vfork`+`execve`+`wait4` and `posix_spawn`+`waitpid` both work.** |
| H2 | Unikraft has only `vfork`, not true `fork` | **REFUTED (live evidence)** | Spike 1 case C: a child mutated a local variable and the parent still saw the original value → **TRUE copy-on-write `fork()`**, not a vfork alias. Upstream README says vfork-only; the deployed Datum build is newer/better. |
| H3 | A single root/init process can spawn children (s6/systemd idea) | **CONFIRMED (live)** | Spike 2: an entrypoint with `ppid=1` spawned a long-lived child, the child ran across ticks (`ppid=410`), and the parent reaped it with the correct exit code (5). |
| H4 | systemd or s6 can be that init | **s6 WORKS (revised up)** | Spike 2b: `s6-supervise` started a service under Unikraft (`[echo-svc] starting: pid=415`). `s6-svscan` fails only because of H14 — it spawns helpers by PATH lookup. systemd remains out (cgroups, udev, dbus, namespaces). |
| **H14** | `execve` performs PATH search for a bare program name | **REFUTED (key finding)** | Spike 2b: `command -v s6-supervise` → `/command/s6-supervise`, but a bare-name `exec` "FAILED (exit 111) — confirms no PATH search". Unikraft's `execve` requires an absolute (or explicit relative) path. This is why `s6-svscan` cannot spawn `s6-supervise`. **Workaround (decided, untested): give s6 a shim with hardcoded absolute paths** (e.g. s6-svscan spawns `/command/s6-supervise`, not `s6-supervise`), so nothing depends on PATH lookup. |
| **H11** | `/proc` exists and is usable | **CONFIRMED** | Spike 2: `/proc` is a directory with 112 entries; `/proc/self/stat` and `/proc/self/status` read OK. |
| **H12** | Signals work | **CONFIRMED** | Spike 2: `SIGUSR1` self-delivery ran the handler; `waitpid` reported the child's real exit status. |
| **H13** | PTYs / `setsid` are available (needed for TUI over SSH) | **CONFIRMED** | Spike 2: `setsid()` returned a valid session id; `open("/dev/ptmx")` succeeded. |
| H5 | We can control the Unikraft kernel config via `--kraftfile` | REFUTED (key finding) | `internal/cmd/compute/build/compute_image.go`: "The runtime kernel is intentionally omitted; Datum Compute injects the correct runtime at boot." Image is initrd-only; `org.unikraft.kernel.image` is supplied by Datum. `--kraftfile` delegates the userspace build to the `unikraft` CLI but cannot inject a kernel. |
| H6 | Node/Bun (opencode, claude-code) run | **LIKELY OK (revised up)** | H2's refutation is decisive: true COW `fork()` means libuv `child_process`, Worker threads, and `posix_spawn` all have their primitives. The remaining risks are not fork: (a) Node needs `/proc`, `epoll`, `inotify`, `io_uring`-optional, signals, and a large runtime; (b) 2 GiB RAM ceiling with the rootfs held in memory. |
| **H15** | The agents' Bun runtime runs on Unikraft | **CONFIRMED for startup (Spike 5A)**; API + tool call pending (5B) | `claude` 2.1.301 (268 MB) and `opencode2` 2.0.30 (212 MB) from llm-agents.nix are Bun single-file executables, not Node scripts, so H6 does not cover them. Spike 5A: `claude --version`/`--help` and `-p` (to a clean auth error) work on Datum's unikernel tier. Needs wrapBuddy's store paths in the rootfs (`sp5/RESULTS.md`). |
| H7 | Real NixOS boot on the unikernel class | REFUTED | No user-supplied kernel on the sandbox/unikernel path (H5). |
| H8 | alpine-sized with agents on unikernel | REFUTED (for unikernel) | Rootfs lives in RAM against a 2 GiB cap; Node runtime + two agents is 200 MB+ even static. |
| H9 | A VM runtime shape can boot a user-supplied OS image | CONFIRMED (new) | `VirtualMachineRuntime`: "boots a full OS provided by the user via an image", with a native `datum/<ssh-keys>` annotation. Class-independent: "Either a sandbox or a virtual machine can run in any class the platform offers." |
| H10 | A custom boot image (real NixOS) works today | LIKELY FAILS TODAY | `internal/workloadspec/render.go`: "Today the server accepts only `DefaultInstanceType` and `DefaultBootImage`" (`datumcloud/ubuntu-2204-lts`). Admission rejects other boot images. Soft blocker: allowlist, not architecture. |

## Constraints carried through

- Unikernel rootfs is held in memory and counts against the instance's 2 GiB.
- Unikernel class: no shell, no `datumctl compute exec`, no `envFrom` (use per-key
  `valueFrom`), no added capabilities, ConfigMap/Secret volumes supported.
- Public ingress is HTTP(S) via Datum ALB only; no raw TCP/UDP. SSH must therefore
  use iroh/Connect (outbound), not a listener exposed through the ALB.
- Secrets: ≤256 KiB each, ≤1 MiB total referenced per workload per location.
- Files written at runtime are lost when an instance is replaced (no persistence).

## Spike sequence

### Spike 0 — Runtime/build capability (DONE, this document)
Answered H1, H2, H5, H7, H9, H10 by reading the plugin source at
`~/src/datum-cloud/compute`. Outcome: the kernel is injected by Datum, so a real
NixOS boot is impossible on the sandbox path; a VM shape exists but its boot image
is allowlisted to Ubuntu 22.04 today.

### Spike 1 — Does vfork + execve work in Datum's unikernel? (PASSED)
Minimal static-PIE musl probes deployed as a real unikernel workload
(`ghcr.io/drewr/vforktest-uk:spike1b`). Results from live instance logs:

- case A: `vfork` + `execve(/bin/spikeecho)` + `wait4` → child exited 7 ✅
- case B: `vfork` + `_exit(42)` + `wait4` → parent saw 42 ✅
- case C: `fork()` with COW check → parent's memory unmodified by child's write
  → **TRUE COW fork**, not a vfork alias ✅
- case D: `posix_spawn` + `waitpid` → child exited 7 ✅

Conclusion: process creation and reaping work normally on Datum's unikernel tier.
H2 refuted; H6 downgraded from "likely fails" to "likely ok, watch /proc + memory".

**Build-box gotchas found (worth reusing):**
- `datumctl compute build` needs Docker/BuildKit. There is no Docker on the Mac,
  so a general-purpose Datum instance is used as the build host.
- BuildKit's native snapshotter needs xattrs; the instance's writable fs is **fuse**
  (no xattr support) → put BuildKit's root on **`/dev/shm`** (tmpfs, 2 GiB).
- Image pull from ghcr needs the Secret to carry a token that can **read** packages.
  Push via `datumctl compute build --push` (produces an OCI **index** with
  `os: kraftcloud`); a plain `crane push` of a flattened manifest is NOT pullable.
- Instances have no persistence: any workload replace wipes `/root`, `/tmp`, and
  installed tooling. Do setup + build + push in a single `exec` invocation.

### Spike 2 — Can an init process spawn a service? (tests the s6 idea)
H2 is refuted, so s6 has a real chance: it needs only `fork`/`execve`/`wait4`, all
proven. Remaining risks are `/proc`, signals, and pid-1 semantics.

1. A tiny custom init with `CONFIG_LIBUKBOOT_INIT` that spawns a long-lived listener
   and reaps it.
2. Then s6 (`s6-svscan`/`s6-supervise`) as the init. Capture exact failures with logs
   (expect `/proc` and signal gaps rather than fork problems).
3. If s6 fails, investigate how Kata Containers runs many processes inside a microVM
   and whether the same technique (a real init + shared-kernel services, or a
   process-manager shim) is portable to Unikraft.

### Spike 3 — Can the agents run? (H6)
Nix-built musl PIE `node`/`bun` on Unikraft, trivial script first, then
opencode/claude-code. Expect failure at `fork()`. If it fails, determine whether any
agent mode avoids `fork` (unlikely for Node) before declaring the unikernel path
unable to host these agents.

### Spike 4 — Transport
`datumctl connect local --port 22` inside the instance + `iroh-ssh` / `datumctl
connect dial` on the Mac, with `~/.ssh/config` `ProxyCommand iroh-ssh proxy %h`.
Only meaningful once a listener runs (Spike 2+).

**Constraint (important):** ssh-over-iroh must NOT depend on a project-scoped
Connect gateway (e.g. the `connect-gw-*` workload). Nothing may assume one exists.
Use the **project-less local tunnel** path (`datumctl connect local` / `dial TICKET`)
from `feat/projectless-local-tunnel`, which needs no login, project, or gateway.

## Deliverables that survive regardless of spike outcome

1. Secret transfer (works on both runtime shapes):
   - `datum-session-secrets.yaml`: per-key `secretKeyRef` for `ANTHROPIC_API_KEY`
     and friends (unikernel-compatible), plus a Secret volume for `~/.ssh/id_ed25519`
     and `allowed_signers` at `defaultMode: 0600`. Document the size limits.
2. Helper scripts in the dotfiles (flake `d/bin/` + `home.file`, consistent with
   `network.nix`): wrappers for `datumctl compute build/deploy` + secret wiring.
3. Hypothesis/spike log in the repo (this document, kept current) so the evidence
   trail is durable.

## Parallel ask (independent of spikes)

Send `support@datum.net` a request to accept a customer-supplied VM boot image (a
NixOS image) for the VM runtime shape, referencing `DefaultBootImage` in
`workloadspec/render.go`. If granted, that is the path to a *real* NixOS boot and
sidesteps H6/H8 entirely. Low effort, potentially high payoff — worth doing in
parallel with the spikes.

## Open risks

- H6: Node under vfork-only. If this fails, the unikernel path cannot host the
  agents as-is.
- Spike 2: whether any real init works under vfork-only semantics.
- The `virtualMachineRuntime` boot-image allowlist (H10) is the only route to real
  NixOS; it depends on Datum, not on us.

## Decision log

- 2026-10-17: User chose to pursue Unikraft despite blockers; keep `general-purpose`
  off the table. Nix-built userspace accepted as the definition of "NixOS-based".
  Spikes first; s6 tried before Kata-style approaches.
- 2026-10-17: Build moves off Datum Compute to an EC2 box, because `d1-standard-2`
  cannot build reliably (2 GiB container cgroup cap that silently recycles the
  sandbox, issues #491/#492; fuse/no-xattr writable fs forcing BuildKit's root onto
  tmpfs, which is unreclaimable and triggers that cap; intermittent IPv6 DNS,
  issue #493). Instance `t3a.medium`, region **`us-east-2`**, profile
  **`datum-sandbox-admin`**. Connect to BuildKit over iroh (`dumbpipe`), not an
  open TCP port. Datum Compute's job is to *run* the unikernel, not build it.
- 2026-10-17: The AWS provisioning and all subsequent work continue from the user's
  other machine; see `docs/spikes/NEXT-STEPS.md`.
- 2026-10-17: H6 passed. Agents are Bun executables, so Spike 5 tests Bun before
  Spike 4 (transport). H14 is to be worked around with an s6 shim that uses
  hardcoded absolute paths. Commits from phone-driven sessions go unsigned over
  HTTPS (`gh` credentials), to be signed later.
