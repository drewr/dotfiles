# Datum Compute + Unikraft for opencode/claude sessions

Work in progress. See `docs/spikes/PLAN.md` for the full plan and hypothesis board,
and `sp1/RESULTS.md` for the first spike's findings.

## Short version

Goal: run opencode and claude-code TUIs over SSH on Datum Compute instances, from a
Nix-built minimal userspace, preferring the `unikernel` runtime class.

Findings so far:

- **Process primitives work** on the unikernel tier: true COW `fork`, `execve`,
  `wait4`, `posix_spawn` (see `sp1/`).
- **The kernel is supplied by Datum**, so a real NixOS *boot* is not possible on the
  sandbox path; "NixOS-based" means the userspace is built by Nix.
- **`buildbox/`** is a general-purpose instance that builds unikernel images.

## Layout

```
buildbox/   general-purpose instance used to build unikernel images
sp1/        spike 1: process primitives probe
docs/       plan and hypothesis board
```
