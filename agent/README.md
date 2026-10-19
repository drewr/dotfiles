# Agent sandboxes on Datum Compute

`agent-sandbox` spawns a claude-code session on Datum Compute's `unikernel` class
and connects to it by SSH over iroh. There is no inbound port, no Connect
gateway, and no login or project on the iroh side.

```sh
agent-sandbox new work            # about 10 s to a working SSH session
agent-sandbox ssh work            # interactive shell; then run `claude`
agent-sandbox ssh work -- claude  # or straight into the TUI
agent-sandbox ls
agent-sandbox rm work
```

- **Keys:** `new` authorizes the keys in your ssh-agent, or `~/.ssh/id_*.pub`, or
  `--key FILE.pub`. If the private key sits next to `FILE.pub`, it is also used
  as the identity.
- **API key:** if `ANTHROPIC_API_KEY` is set locally, it is copied into the
  session's Secret. Otherwise run `claude /login` inside the session.
- **Image:** `image.ref` (digest-pinned). Rebuild on the EC2 box with
  `buildbox/ec2/build.sh agent ghcr.io/drewr/agent-sandbox:dev`, then write the
  printed digest to `image.ref`.
- **Needs locally:** `datumctl` (logged in), `ssh`, `ssh-keygen`, `openssl`,
  `xxd`, `base32`, and `dumbpipe` (falls back to `nix build nixpkgs#dumbpipe`).

## Workspaces: repos in RAM, persisted to the shared home

`~` is the shared home (JuiceFS), live across all sessions: `~/.claude`
(conversations, `claude --resume`), dotfiles, settings. Repos don't run there,
because git over JuiceFS is about 100x slower than RAM (see
`docs/spikes/sp6-shared-home.md`). Each repo is instead a **workspace**: it
lives in RAM at `/work/NAME` while a session holds it, and persists to
`~/work/NAME`.

```sh
ws clone https://github.com/you/repo.git   # into /work/repo; you land there
ws open repo                               # resume a workspace from any session
ws save                                    # also automatic every 2 min
ws close repo                              # save, release the lock, free the RAM
ws ls                                      # workspaces and who holds them
```

- **One session at a time per workspace.** A lock in `~/.ws/locks` with a
  heartbeat. `ws open` on a held workspace names the holder. After 15 minutes
  without a heartbeat, or with `--force`, it takes over, and the old holder
  stops saving that workspace.
- **Same path everywhere** (`/work/NAME`), so Claude Code's per-project history
  lines up across sessions.
- **When work is saved:** `ws save`, autosave every 2 minutes, `ws close`, and
  `agent-sandbox rm`, which runs `ws close --all` over SSH before deleting.
  Deleting a workload by other means stops it **without** SIGTERM (tested), so
  that loses up to the last 2 minutes of changes.

Measured on production us-east-1 (dotfiles repo, 328 files): `git status` in a
workspace 0.007 s, against 0.8–1.3 s directly on the shared home. Incremental
save 0.8 s. First `ws open` of the repo 7.7 s; first `ws clone` plus save 15 s.

## How a session is wired

`new` generates three things locally, under `~/.local/state/agent-sandbox/NAME/`:

1. **iroh secret key:** the client derives the endpoint id and builds the ticket
   itself.
2. **SSH host key:** the client pins it in a per-session `known_hosts`, so there
   is no trust-on-first-use.
3. **authorized_keys.**

All three go into the Datum Secret `agent-NAME`, which the workload reads with
`secretKeyRef`. Inside, `init.sh` brings up loopback, installs the keys, writes
a login environment, and supervises dropbear on `127.0.0.1:2222` and
`dumbpipe listen-tcp`.

**The ticket carries the relay URL.** Instances have repeatedly failed to
publish to iroh's DNS discovery (`dns.iroh.link`): their TXT record never
appears, so a bare endpoint-id ticket gets "No addressing information
available". The boot diagnostics show `dns.iroh.link` reachable over IPv6 and
unreachable over IPv4 from the IPv6-only (ULA) network. The publish hangs
without logging an error. `agent-sandbox` therefore writes a ticket containing
the relay URL (`AGENT_SANDBOX_RELAY`, default `use1-1.relay.n0.iroh.link`, the
home relay us-central-1 instances have chosen in every run), so the client
dials the relay directly. If an instance ever picks a different home relay,
set `AGENT_SANDBOX_RELAY` to match.

## Image contents (`flake.nix`)

claude-code (llm-agents.nix, pinned to the dotfiles rev), bash, git, ripgrep,
dropbear, dumbpipe, CA certificates, and static busybox for everything else.
Each is shipped as its full nix closure at the original `/nix/store` paths
(the image is ~480 MB). This keeps wrapBuddy's hardcoded paths valid and needs
no patchelf. About 1.83 GiB of the instance's memory is free with a session
open.

## Known gaps

- No persistence: an instance replace wipes `/root`. Push work somewhere.
- The discovery watchdog in `init.sh` has not logged anything; the instance's
  own DNS lookups may hang. It is harmless, because the relay ticket does not
  need discovery.
- `datumctl connect local` (the project-less Connect tunnel) would replace
  dumbpipe once it ships.
- Spike 5B (an API call and a Bash tool call) still needs an API key.
