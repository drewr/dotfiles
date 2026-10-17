# Spike 5 — does the agents' Bun runtime run on Unikraft? (H15)

Date: 2026-10-17. The first spike built entirely on the EC2 build box
(`buildbox/ec2/`): `build.sh sp5 ghcr.io/drewr/sp5-claude:dev` over dumbpipe,
with the Nix build running inside BuildKit on the box.

## Part A (no credentials): PASS

Image `ghcr.io/drewr/sp5-claude@sha256:6104b28ac7a52b5d852c3ff1a74c8fbaf3c385b5d4eb9d4a6ab83fe54433b0e8`,
`unikernel` workload in `us-central-1`:

```
[sp5] mem at start: MemTotal: 2032564 kB MemAvailable: 1927996 kB
[sp5] A1 claude --version
2.1.302 (Claude Code)
[sp5] A1 rc=0
[sp5] A2 claude --help (first lines)
Usage: claude [options] [command] [prompt]
[sp5] A3 claude -p without a key (expect an auth error, not a crash)
Not logged in · Please run /login
[sp5] mem at end: MemTotal: 2032564 kB MemAvailable: 1819160 kB
```

The real claude-code binary (a 268 MB Bun single-file executable) starts, parses
its CLI, and runs the `-p` path through to a clean auth error. The guest sees
~1.94 GiB, with ~1.84 GiB available before claude runs.

## Packaging finding: wrapBuddy needs its store paths

llm-agents.nix packages the Bun executables with **wrapBuddy**: the ELF
interpreter is replaced by a 407-byte stub that

1. opens `/nix/store/…-wrap-buddy-1.0.0/lib/wrap-buddy/loader.bin` (hardcoded
   in the binary), then
2. reads the sidecar `bin/..claude-wrapped.wrapbuddy`, which names the glibc
   loader and lib dirs by absolute `/nix/store` path.

Copying the binary to `/bin` with FHS glibc fails with `wrapBuddy: open loader`
(rc 127). The fix ships the binary, its sidecar, and every store path the two
reference, at their original paths. `/bin/claude` is a symlink. This also avoids
`patchelf`, which can corrupt Bun executables. The same applies to `opencode2`.

## Part B (API call + Bash tool): pending

Needs an `ANTHROPIC_API_KEY` Datum Secret wired through `secretKeyRef`.
`init.sh` already runs B when the variable is set. Open question for B: Claude
Code's Bash tool may reject busybox `sh` and require `bash`.
