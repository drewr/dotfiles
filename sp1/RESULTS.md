# Spike 1: process primitives on Datum Compute unikernel

**Result: PASS.** All of `vfork`, true COW `fork`, `execve`, `wait4`, and
`posix_spawn`/`waitpid` work on a live Datum unikernel instance.

## What was run

Static-PIE musl binaries, packaged as a unikernel image with `datumctl compute
build`, deployed with `--runtime-class=unikernel`, and read back from the
instance logs.

Probes (`vforktest.c`):
- case A: `vfork` + `execve(/bin/spikeecho)` + `wait4`
- case B: `vfork` + `_exit(42)` + `wait4`
- case C: `fork()` copy-on-write check — child writes a local, parent must not see it
- case D: `posix_spawn` + `waitpid`

## Observed output (from `datumctl compute logs vforktest`)

```
[vforktest] case A: vfork + execve(/bin/spikeecho) + wait4
[spikeecho] ran as pid=411 argc=2 arg0=/bin/spikeecho arg1=hello-from-child
[vforktest] case A OK: child exited 7 (execve worked)
[vforktest] case B: vfork + _exit(42) + wait4
[vforktest] case B OK: child returned 42
[vforktest] case C: fork() semantics check (is it true COW fork?)
[vforktest] case C OK: TRUE COW fork (parent saw 111, child's write isolated)
[vforktest] case D: posix_spawn(/bin/spikeecho) + waitpid
[spikeecho] ran as pid=414 argc=2 arg0=/bin/spikeecho arg1=hello-from-spawn
[vforktest] case D OK: posix_spawn child exited 7
```

Distinct PIDs across cases (409–414) confirm real process creation.

## Conclusion

The premise that Unikraft (as deployed by Datum) can only `vfork` is wrong. It
provides true copy-on-write `fork()`. That removes the single biggest predicted
blocker for running an SSH server and the agents it spawns.

Remaining unknowns move to Spike 2 (can an init manage long-lived services?) and
Spike 3 (does Node itself run?).

## Build-box notes (reusable)

These cost real time; recorded so they are not rediscovered:

1. **Build host.** `datumctl compute build` needs Docker/BuildKit. No Docker on
   the Mac, so a general-purpose Datum instance (`drewr/nixos-gp`) is the build
   host. It needs `SYS_ADMIN` (and friends) via `securityContext.capabilities.add`
   or BuildKit's mounts fail with EPERM.
2. **BuildKit root on tmpfs.** The instance's writable filesystem is **fuse**,
   which has no xattr support, so BuildKit's native snapshotter fails with
   `failed to get xattr ... operation not supported`. Fix: run
   `buildkitd --root /dev/shm/buildkit` (`/dev/shm` is tmpfs).
3. **Push format.** Use `datumctl compute build --push`. It writes an OCI
   **index** with `platform: {architecture: x86_64, os: kraftcloud}`. Pushing a
   flattened manifest with `crane push` of a layout dir produces an image the
   platform cannot pull.
4. **Pull credentials.** The image is private. The `ghcr-drewr` Secret must hold a
   token that can read packages. A stale token there failed silently with
   `could not be pulled using credentials from "ghcr-drewr"`.
5. **No persistence.** Every workload replace wipes the instance filesystem
   (`/root`, `/tmp`, nix profile). Batch setup + build + push into a single
   `datumctl compute exec` invocation.

## Reproduce

```sh
# 1. ensure the build box is up (general-purpose, SYS_ADMIN)
datumctl apply -f workload.yaml        # sp1 version points at ghcr-drewr-v2

# 2. on the build box, in ONE exec: install tooling, start buildkitd on tmpfs,
#    compile static-PIE, build + push
GHCR_TOKEN=$(gh auth token)
cat sp1-src.tgz | datumctl compute exec <buildbox> -i -- sh -c '...'   # see boxrun.sh

# 3. deploy the unikernel and read logs
datumctl compute destroy vforktest -y; datumctl apply -f /tmp/sp1-wl2.yaml
datumctl compute logs vforktest
```
