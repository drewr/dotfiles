# Agent sandboxes on Datum Compute

`agent-sandbox` spawns an agent session on Datum Compute's `unikernel` class and
connects to it by SSH over iroh. Each session runs **one** harness from the
dotfiles, in its own image: `claude` (default), `gemini`, `codex`, `opencode`
or `pi`. There is no inbound port, no Connect
gateway, and no login or project on the iroh side.

```sh
agent-sandbox new work            # about 10 s to a working SSH session (claude)
agent-sandbox new oc --agent opencode
agent-sandbox ssh work            # interactive shell; then run `claude`
agent-sandbox ssh work -- claude  # or straight into a harness
agent-sandbox ls
agent-sandbox rm work
```

- **Keys:** `new` authorizes the keys in your ssh-agent, or `~/.ssh/id_*.pub`, or
  `--key FILE.pub`. If the private key sits next to `FILE.pub`, it is also used
  as the identity.
- **Providers:** see "Model providers" below.
- **Images:** one per harness, pinned by digest in `images`. Rebuild with
  `agent/build-image HARNESS...` (the EC2 build box must be running); it
  updates `images`.
- **Needs locally:** `datumctl` (logged in), `ssh` with a working
  `SSH_AUTH_SOCK` (on this host: `export SSH_AUTH_SOCK=~/.ssh/ssh_auth_sock`),
  `ssh-keygen`, `openssl`, `jq`, `xxd`, `base32`, and `dumbpipe` (falls back to
  `nix build nixpkgs#dumbpipe`).

## Inside a session

- **You log in as `drewr`** (uid 1000) with zsh and the dotfiles' zsh config
  (prompt included), linked from the image into the home
  (`~/.zshrc -> /etc/agent/zsh/zshrc`, and so on) unless the home already has
  its own. `AGENT_SANDBOX_USER=root agent-sandbox ssh NAME` gets root.
- **`HOME` is the shared home** (`/home/agent`), owned by `drewr`.
- **`nix`** works through a root `nix-daemon`; `nixpkgs` is pinned to the
  images' rev. `nix shell nixpkgs#tool` takes ~25 s the first time in a session
  (fetching nixpkgs), then about a second per tool. Installs live in RAM for the
  session; add tools you always want to `base` in `flake.nix`.
- **claude starts with Remote Control on:** init adds
  `"remoteControlAtStartup": true` to `~/.claude/settings.json` unless that key
  is already set. Log in once (`/login` in any session) and every session is
  logged in, via the shared home.

## Model providers

Keys live in **one** Datum Secret, `agent-providers`, which every session
reads. `agent-sandbox new` lists its key names and wires each one in as a
variable of the same name (the unikernel class has no `envFrom`). Values never
pass through the client. Add any keys you use:

```sh
DATUM_SESSION=aaraines@gmail.com@api.datum.net datumctl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata: { name: agent-providers }
type: Opaque
stringData:
  ANTHROPIC_API_KEY: "..."     # claude (or use `claude /login`)
  OPENAI_API_KEY: "..."        # codex, opencode, pi
  GEMINI_API_KEY: "..."        # gemini
  OPENROUTER_API_KEY: "..."    # opencode, pi
  TOKENROUTER_API_KEY: "..."   # via agent/providers
  SUBCONSCIOUS_API_KEY: "..."  # via agent/providers
EOF
```

New sessions pick up the current set of keys. OAuth logins (`claude /login`,
`codex login`, `gemini`'s Google login, `opencode auth login`) need no keys:
their tokens live in the shared home and carry over to every session.

Routers and other OpenAI- or Anthropic-compatible providers are listed in
`agent/providers` (name, key variable, base URLs); add a line to add one. Each
harness takes custom endpoints differently, so the wiring differs:

| Harness | How a registry provider reaches it | Verified (dummy key, provider's own 401) |
| - | - | - |
| claude | `with-provider subconscious claude` (Anthropic-compatible base URL + token) | subconscious |
| opencode | automatic: generated `$OPENCODE_CONFIG` (`/etc/agent/opencode.json`) | subconscious |
| pi | automatic: `agent-providers sync` adds the provider to `~/.pi/agent/models.json` unless an entry with that name exists | subconscious |
| codex | `with-provider NAME codex …` passes the provider as `-c` overrides; codex only speaks the Responses API, so the provider must serve `/v1/responses` | subconscious (TokenRouter: unknown) |
| gemini | Google only (`GEMINI_API_KEY` or Google login) | — |

```sh
agent-providers ls          # providers and whether their key is set
agent-providers sync        # regenerate opencode/pi provider config (also runs at boot)
with-provider subconscious claude
with-provider subconscious codex exec 'fix the tests'
```

Notes from testing: pi and codex ignore `OPENAI_BASE_URL` for custom
endpoints (both went to api.openai.com), hence the per-harness config. Your own
`~/.config/opencode`, `~/.codex/config.toml` and existing pi entries are left
alone. With an invalid key, claude retries the 401 with backoff and looks hung
for a minute or more.

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

`packages.<harness>`: one harness from llm-agents.nix at the dotfiles' pinned
rev (claude-code, gemini-cli, codex, opencode or pi), plus the
same base in every image: zsh, bash, git, ripgrep, curl, jq, nix, rsync,
juicefs, dropbear, dumbpipe, `ws`, `agent-providers`, `nix-zsh-env` (a sh port
of the zigutils tool, which no longer builds: its pinned zig dev tarball is
gone), the en_US.UTF-8 locale, CA certificates, the dotfiles' zsh config, and
static busybox for everything else. `Dockerfile.datum` picks the harness with
the `HARNESS` build argument; `build-image` adds the zsh config to the build
context.
Each is shipped as its full nix closure at the original `/nix/store` paths
(the image is ~480 MB). This keeps wrapBuddy's hardcoded paths valid and needs
no patchelf. About 1.83 GiB of the instance's memory is free with a session
open.

## Known gaps

- Anything outside the shared home and `ws` workspaces (e.g. `nix shell`
  installs, `/tmp`) is lost when the instance goes.
- `datumctl connect local` (the project-less Connect tunnel) would replace
  dumbpipe once it ships.
- Spike 5B (an API call and a Bash tool call) still needs an API key.
