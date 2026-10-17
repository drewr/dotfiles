# Spike 3 — can opencode / claude-code run on a Unikraft instance?

Status: **BLOCKED on build environment stability, not yet on the hypothesis.**

## What this spike is meant to answer

H6: Node/Bun (which opencode and claude-code require) run under Unikraft.

Sub-questions:
* Does `node` start at all in a unikernel (no fork needed)?
* Can `node` spawn child processes (`spawnSync`, `execSync`) — the agent tool-call path?
* Does agent startup / TUI initialisation work?
* Does tool use (which shells out) work?

## Progress

The probe (`forktest.js`) is written and the packaging pipeline is built
(`sp3/boxrun.sh`): it fetches `nodejs` and busybox-static, assembles a rootfs,
copies the glibc loader + node's `.so` closure, dedupes byte-identical libraries
(292 MB → 153 MB), `patchelf`s the interpreter and rpath, and runs
`datumctl compute build --analyze --push`.

Blockers hit while trying to get the image built:

1. **The buildbox instance resets repeatedly.** `/root/sp3`, `/tmp/dc`, and the
   docker config are wiped between calls, sometimes mid-build. `datumctl compute
   instances` shows the container `NotRunning`, then it recovers. This looks like
   the `buildbox` workload restarting under load, not an issue with the spike.

2. **Missing build tooling on a fresh buildbox generation.** Each new generation
   came up without `tar`, `gzip`, `patchelf`, `buildkitd`, or `runc`. Installing
   them via `nix profile add` works but requires the instance to stay up, and it
   needs network (one attempt failed DNS resolution to `releases.nixos.org` for
   ~2 minutes; it recovered).

3. **`buildkitd` needs `runc`** to find a worker (`no worker found, rebuild the
   buildkit daemon?`). Installing `nixpkgs#runc` fixes it and the worker starts
   with the `overlayfs` snapshotter.

4. **Registry credentials.** `datumctl compute build --push` reads
   `~/.docker/config.json`. The buildbox did not have one, so pushes 401'd until
   the local GHCR config was copied over. (The local config holds a personal GHCR
   PAT; a scoped, build-only token would be better for a long-lived setup.)

5. **`datumctl compute exec` does not pipe stdin.** `... -- sh -s` with a piped
   script silently produces no output. Scripts must be passed via `-c`.

## What is still unknown

H6 itself. Nothing has been run inside a unikernel yet, because the image has not
been built. The `--analyze` gate has not reported on the Node rootfs either — that
alone would be informative (it checks the entrypoint, dynamic loader, and libs).

## Next attempt (when the buildbox is stable)

* Run the entire assemble + build in one detached, nohup'd command so a session
  drop does not kill it, and poll the log file afterwards.
* Or build the image locally (macOS has Docker/linuxkit) and push from the Mac,
  skipping the buildbox entirely. This avoids the buildbox stability problem
  completely and is probably the right move: `datumctl compute build` can run
  anywhere Docker BuildKit is available.
* Consider a leaner Node: `nodejs-slim` exists in the closure listing and would
  cut the rootfs substantially.
