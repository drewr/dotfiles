# Dotfiles Repository

Personal dotfiles and development environment, declaratively managed with shell scripts, [Nix](https://nixos.org/), and [Home Manager](https://github.com/nix-community/home-manager). Reproducible across macOS (aarch64-darwin) and Linux (x86_64-linux, aarch64-linux).

## Core build flow (know this before editing)

The repo is NOT built in place. `make install` copies files into `$HOME`, then Home Manager builds from `$HOME/.config/home-manager` (the installed copy), not from the repo's `d/.config/home-manager`.

- `make install` — `zsh install`: copies `zprofile`, `zshrc`, `zshenv` and `zsh.d/` into `$HOME`, tar-extracts the whole `d/` tree over `$HOME` (this is how the `~/bin` scripts, `~/.claude/skills` and `~/.ssh/rc` arrive), and creates `$HOME/go`.
- `make home` — runs `make install` first, then `zsh build-home-manager` (build + switch).
- `make update` — `nix flake update --flake d/.config/home-manager` (regenerates the lockfile only), with `flake-self-attrs` enabled for jolt's submodules and `accept-flake-config` so the flake's own substituters apply.
- `make news` — `home-manager news` for the current `<user>@<system>`; Home Manager's own lookup doesn't match this flake's config names.
- `./build-home-manager` — by itself, builds and switches from the **installed** `$HOME/.config/home-manager`. If you edit the repo's Nix files, run `make install` (or `make home`) first, or the edit won't be picked up. Honours `UPDATE=1` (flake update before building) and `NIXPKGS_INPUT=<flake-ref>` (override the nixpkgs input).
- `./update-dotfiles` — the whole loop: `git pull --ff-only`, `make update`, `make home`, then `git add . && git commit -m "chore: update deps"` (skips the commit when nothing changed). Flags: `-m MSG`, `--no-pull`, `--no-commit`, `--stash`.

## Warn before these actions

- **`UPDATE=1` / `make update` / `./update-dotfiles` / flake input bumps** — human-only. The `updater` agent (`.opencode/agents/updater.md`) is the sanctioned path for updates. The sensitive input is `nixpkgs`, which follows `llm-agents/nixpkgs` and deliberately lags: codex does not build against newer nixpkgs (aws-lc dropped its `openssl.pc` compat file). A bump that builds here can still break aarch64-linux or aarch64-darwin.
- **Manual `nix-env -i` package installs** — forbidden; breaks reproducibility. All packages go through Home Manager.
- **Credentials/secrets setup** (AWS, GPG, keychain) — out of scope; never commit secrets.
- **No CI** exists — the human is the only build gate across the three supported systems. Local build success does not verify the other systems.

## Where things live

```
d/.config/home-manager/     # Nix flake + modules (the real config)
  flake.nix                 # inputs, mkHomeConfig, homeConfigurations
  default.nix / util.nix / clojure.nix / desktop.nix / network.nix
  jolt.nix                  # builds the jolt package (not a home module)
  flake.lock                # pinned deps, committed
  d/                        # sources for home.file entries (gitconfig, tmux.conf,
                            #   ssh-allowed-signers, bin/, claude-settings-defaults.json, ...)
d/.claude/skills/           # agent skills, copied to ~/.claude/skills by `make install`
d/bin/                      # legacy scripts installed to $HOME/bin via `make install`
d/.config/home-manager/d/bin/  # scripts installed via home.file (gcp-env, rand, ...)
zsh.d/                      # zsh modules, numeric-prefixed load order; zsh.Darwin / zsh.Linux
nix/                        # language-specific nix (python, rust, zig)
conf/ etc/ bb/ go/ hs/ rs/ linux/   # misc configs and language trees
build-home-manager          # build switch wrapper
update-dotfiles             # pull + update + rebuild + commit
install / Makefile          # bootstrap
```

## Two bin directories — both needed, different how they reach ~/bin (easy to get wrong)

Both dirs end up contributing files to `~/bin`, each by a different mechanism and a different final form. The two pipelines are disjoint in `~/bin` — no name is served by both:

- **`d/.config/home-manager/d/bin/`** — 11 scripts (diskfree, gcp-env, gh-assigned, gh-user-activity, latency-tcp, my-ip, oc-status, ping1, pingn, rand, ssh-signing-key). Each must be registered in a module's `home.file` (default.nix, network.nix, util.nix). These reach `~/bin` **only** as Home Manager–managed **symlinks** — reproducible and rebuilt by `make home`.
- Root **`d/bin/`** — 29 scripts. These are **copied** (not symlinked) into `~/bin` by `make install` when it tar-extracts the whole `d/` tree. They land as real files and stay nix-unmanaged.

`make install`'s tar preserves paths: the flake `d/` subtree copies into `~/.config/home-manager/d/` (e.g. `~/.config/home-manager/d/bin/rand`), never flattened into `~/bin`. So the flake scripts are never plain files in `~/bin` — only symlinks, from `home.file`. The two mechanisms don't overlap.

Deciding where a script belongs:
- **Nix-managed / reproducible** → put it in `d/.config/home-manager/d/bin/` AND register it in `home.file` (only `make home` restores the symlink).
- **Plain file copied by `make install`** (no nix wiring needed) → root `d/bin/`. New scripts there need `chmod +x` and are picked up as copies by any `make install`/`make home`.

## Adding / modifying configuration

- **Packages** — edit the relevant module's `home.packages` list (default.nix for core, util/clojure/desktop/network for concerns), then `make home`.
- **Flake deps** — add to `inputs` in `flake.nix`, wire into `outputs`, then resolve the lockfile (`make update`). `nixpkgs` is not pinned directly: it is `follows = "llm-agents/nixpkgs"`. A new input should follow `nixpkgs` too unless it must diverge. `jolt` uses the `git+https` scheme because its flake sets `inputs.self.submodules`.
- **Zsh** — new module files in `zsh.d/` with numeric prefix (e.g. `35-myconfig`); lower numbers load first (`zshrc` sources `~/.zsh.d/[0-9][0-9]*[^~]`). Platform-specific bits go in `zsh.Darwin` / `zsh.Linux`, sourced as `zsh.${OS}`.
- **Exact-string note**: `home.file` sources resolve relative to the module file (`./d/...` = `d/.config/home-manager/d/...`), not the repo root.

## Supported systems & users

- Systems: `aarch64-darwin`, `x86_64-linux`, `aarch64-linux`.
- Users: **`aar@`** (primary) and **`drewr@`** (secondary) for each system — 6 `homeConfigurations` total in `flake.nix`.
- `build-home-manager` auto-detects the system from `uname -mo` (`arm64 Darwin` / `Darwin arm64` → `aarch64-darwin`, `x86_64 GNU/Linux` → `x86_64-linux`, else `aarch64-linux`) and the user from `LOGNAME` (fallback `whoami`); it pins Home Manager via `nix run github:nix-community/home-manager/release-26.05`.

## Key flake inputs (in flake.nix)

- `nixpkgs` (nixos-unstable, `follows = "llm-agents/nixpkgs"` — deliberately lagging so codex builds).
- `llm-agents.nix` — provides claude-code, gemini-cli, codex, pi, pi-acp and herdr; its `opencode2` is wrapped and exposed as `opencode`.
- `home-manager` (follows nixpkgs), `zigutils` (zsh-nix-env, gitclone, tmphttp, zsh-hist), `datumctl`, `yolo`.
- `una-src` — Haskell tool built from source with `pkgs.haskell.packages.ghc910`, nixpkgs' default GHC, so its dependencies come prebuilt. There is no separate `nixpkgs-haskell` pin.
- `jolt` — `git+https` (its flake needs submodules); no aarch64-linux package upstream, so it is null-filtered there.

## Notes

- Home Manager config lives in a non-standard location (`d/.config/home-manager/`, not repo root).
- Only commit intended files; the updater agent commits only `d/.config/home-manager/flake.lock`. `update-dotfiles` does `git add .`, so run it on a clean tree.
- `install` itself only creates `$HOME/go`; the compinit/zcompile cache under `$HOME/.zsh-cache` is built by `zshrc` on the first interactive shell.
- Commit signing is **forwarding-only**: `gpg.format=ssh` with `gpg.ssh.defaultKeyCommand=ssh-signing-key`, and the machine holds no private keys. Signing therefore requires a live forwarded agent from a connected device: `ssh -A`, or `autossh -A host 'exec sleep infinity'` as a supervised holder (`ssh -A -N` forwards nothing — no session channel, so no socket). `ssh-signing-key` emits only keys whose blob is in `~/.ssh/allowed_signers` (ECDSA preferred, then ED25519), so **every device's agent key must be listed there**. With no device connected, signing fails by design.
