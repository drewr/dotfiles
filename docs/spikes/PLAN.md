# Plan: Datum Compute + Unikraft for opencode/claude sessions

Status: research complete for Spike 0 (runtime/build capability). Spikes 1–4 pending.

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
| H3 | A single root/init process can spawn children (s6/systemd idea) | CONFIRMED (mechanism) | `CONFIG_LIBUKBOOT_INIT` provides `/sbin/init`-like logic: spawns the app as a process, fosters orphaned children, reaps zombies, coordinates shutdown. Unikraft explicitly invites a custom init. |
| H4 | systemd or s6 can be that init | LIKELY FAILS | systemd needs true `fork()`, cgroups, `/proc`, udev, dbus, mount namespaces. s6 is lighter but uses `fork()` and expects `/proc`. A vfork-safe init is the realistic target. |
| H5 | We can control the Unikraft kernel config via `--kraftfile` | REFUTED (key finding) | `internal/cmd/compute/build/compute_image.go`: "The runtime kernel is intentionally omitted; Datum Compute injects the correct runtime at boot." Image is initrd-only; `org.unikraft.kernel.image` is supplied by Datum. `--kraftfile` delegates the userspace build to the `unikraft` CLI but cannot inject a kernel. |
| H6 | Node/Bun (opencode, claude-code) run | **LIKELY OK (revised up)** | H2's refutation is decisive: true COW `fork()` means libuv `child_process`, Worker threads, and `posix_spawn` all have their primitives. The remaining risks are not fork: (a) Node needs `/proc`, `epoll`, `inotify`, `io_uring`-optional, signals, and a large runtime; (b) 2 GiB RAM ceiling with the rootfs held in memory. |
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
