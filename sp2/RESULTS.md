# Spike 2 — init / supervisor capability on Unikraft

Question: can a single root process act as an init and supervise long-lived
services? This is the prerequisite for running an SSH server or any service manager
inside a Unikraft instance.

## Results

### 2a — custom init probe (`sp2/initprobe.c`)

All facilities an init needs are present:

| Facility | Result |
| - | - |
| entrypoint runs as pid 1-like (`ppid=1`) | yes |
| `fork()` a long-lived child | yes — child ran across 3 ticks, `ppid` correct |
| `waitpid()` reap with correct exit status | yes — `status=1280 exit=5` |
| `/proc` | yes — 112 entries; `/proc/self/stat` and `/proc/self/status` readable |
| signals (`SIGUSR1` handler + `kill`) | yes — handler ran |
| `setsid()` | yes |
| PTY (`/dev/ptmx`) | yes — this is what makes a TUI over SSH feasible |

Conclusion: the "single root process spawns and supervises children" model works.

### 2b — s6 (`sp2b/`)

s6 is available as a static-cached dynamic build (`pkgsStatic.s6` is NOT in the
binary cache and fails to build on the instance because the instance filesystem is
`fuse`: `Cannot change mode to rwxr-sr-x: Operation not permitted`). The plain
`nixpkgs#s6` (dynamic, glibc) IS cached and was used instead.

Observed:

* `s6-svscan` starts and runs — it scans `/service` and keeps trying.
* `s6-svscan` **cannot spawn `s6-supervise`**: `warning: unable to spawn
  s6-supervise for echo: No such file or directory`, every 10s.
* Direct test in the instance: `command -v s6-supervise` resolves to
  `/command/s6-supervise`, but a **bare-name `exec` FAILS (exit 111)**.
* Launching `s6-supervise` by **absolute path** works: the service started
  (`[echo-svc] starting: pid=415`) and the supervisor stayed up.

**Root cause:** Unikraft's `execve` does not implement PATH search for bare program
names. Anything that relies on `execvp`/`execvep` semantics — `s6-svscan`, and
potentially many other tools — breaks. Workaround: invoke helpers by absolute path.

## Build notes (reusable)

* `patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 --set-rpath
  /lib/x86_64-linux-gnu` on every dynamically linked binary; otherwise
  `datumctl compute build --analyze` reports `missing-libs` for the loader.
* Copy the glibc loader and `.so*` files into `/lib64` and `/lib/x86_64-linux-gnu`.
* `key get`: the glibc store dir must be found by grep with the full numeric
  suffix, e.g. `-glibc-[0-9.]*-[0-9]*`, or you get `-glibc-2.42` which does not exist.
* Deploying the same image tag does NOT necessarily re-pull; pin the manifest image
  to an explicit `@sha256:` digest to force the new content.
* Unikernel rootfs with glibc is ~17 MB; busybox-static is ~1 MB.

## Verdict

Init/supervisor pattern: **works**. s6: **works with an absolute-path launcher**.
The blocker is narrow and identified (H14: no PATH search in `execve`), not
architectural.
