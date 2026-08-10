# Dotfiles Repository

Personal dotfiles and development environment, declaratively managed with shell scripts, [Nix](https://nixos.org/), and [Home Manager](https://github.com/nix-community/home-manager). Reproducible across macOS (aarch64-darwin) and Linux (x86_64-linux, aarch64-linux).

## Core build flow (know this before editing)

The repo is NOT built in place. `make install` copies files into `$HOME`, then Home Manager builds from `$HOME/.config/home-manager` (the installed copy), not from the repo's `d/.config/home-manager`.

- `make install` — copies `zprofile`, `zshrc`, `zshenv`, `zsh.d/`, and the whole `d/` tree into `$HOME`.
- `make home` — runs `make install` first, then `zsh build-home-manager` (build + switch).
- `make update` — `nix flake update --flake d/.config/home-manager` (regenerates the lockfile only).
- `./build-home-manager` — by itself, runs against the **installed** `$HOME/.config/home-manager`. If you edit the repo's Nix files, you must `make install` (or `make home`) first for changes to be picked up.
- `UPDATE=1 make home` / `UPDATE=1 ./build-home-manager` — updates flake inputs then builds. **Human-only action** (see below).

## Warn before these actions

- **`UPDATE=1` / `make update` / flake input bumps** — human-only. A nixpkgs bump can silently break the build on cross-system, especially the pinned `nixpkgs-haskell` rev whose ghc-9.8.4 must stay cacheable. Don't bump autonomously; hand to the human. The `updater` agent (`.opencode/agents/updater.md`) is the sanctioned path for updates.
- **Manual `nix-env -i` package installs** — forbidden; breaks reproducibility. All packages go through Home Manager.
- **Credentials/secrets setup** (AWS, GPG, keychain) — out of scope; never commit secrets.
- **No CI** exists — the human is the only build gate across the three supported systems. Local build success does not verify the other systems.

## Where things live

```
d/.config/home-manager/     # Nix flake + modules (the real config)
  flake.nix                 # inputs, mkHomeConfig, homeConfigurations
  default.nix / util.nix / clojure.nix / desktop.nix / network.nix
  flake.lock                # pinned deps, committed
  d/                        # sources for home.file entries (gitconfig, tmux.conf, bin/, ...)
d/bin/                      # legacy scripts installed to $HOME/bin via `make install`
d/.config/home-manager/d/bin/  # scripts installed via home.file (gcp-env, rand, my-ip, ...)
zsh.d/                      # zsh modules, numeric-prefixed load order; zsh.Darwin / zsh.Linux
nix/                        # language-specific nix (python, rust, zig)
conf/ etc/ bb/ go/ hs/ rs/ linux/   # misc configs and language trees
build-home-manager          # build switch wrapper
install / Makefile          # bootstrap
```

## Two bin directories — both needed, different how they reach ~/bin (easy to get wrong)

Both dirs end up contributing files to `~/bin`, each by a different mechanism and a different final form. The two pipelines are disjoint in `~/bin` — no name is served by both:

- **`d/.config/home-manager/d/bin/`** — 6 scripts (gcp-env, rand, my-ip, latency-tcp, gh-user-activity, gh-assigned). Each must be registered in a module's `home.file` (e.g. `network.nix` does `"bin/my-ip".source = ./d/bin/my-ip`). These reach `~/bin` **only** as Home Manager–managed **symlinks** — reproducible and rebuilt by `make home`.
- Root **`d/bin/`** — 29 scripts. These are **copied** (not symlinked) into `~/bin` by `make install` when it tar-extracts the whole `d/` tree. They land as real files and stay nix-unmanaged.

`make install`'s tar preserves paths: the flake `d/` subtree copies into `~/.config/home-manager/d/` (e.g. `~/.config/home-manager/d/bin/rand`), never flattened into `~/bin`. So the 6 flake scripts are never plain files in `~/bin` — only symlinks, from `home.file`. The two mechanisms don't overlap.

Deciding where a script belongs:
- **Nix-managed / reproducible** → put it in `d/.config/home-manager/d/bin/` AND register it in `home.file` (only `make home` restores the symlink).
- **Plain file copied by `make install`** (no nix wiring needed) → root `d/bin/`. New scripts there need `chmod +x` and are picked up as copies by any `make install`/`make home`.

## Adding / modifying configuration

- **Packages** — edit the relevant module's `home.packages` list (default.nix for core, clojure/desktop/network/util for concerns). Reference by module-correct file, then `make home`.
- **Flake deps** — add to `inputs` in `flake.nix`, wire into `outputs`, then resolve the lockfile (`nix flake update --flake d/.config/home-manager`). Note `nixpkgs-haskell` is an intentional separate pinned input — don't merge it into `nixpkgs`.
- **Zsh** — new module files in `zsh.d/` with numeric prefix (e.g. `35-myconfig`); lower numbers load first. Platform-specific in `zsh.Darwin` / `zsh.Linux`. `zshrc` sources `~/.zsh.d/[0-9][0-9]*` in order and loads `zsh.${OS}`.
- **Exact-string note**: `home.file` sources resolve relative to the module file (`./d/...` = `d/.config/home-manager/d/...`), not the repo root.

## Supported systems & users

- Systems: `aarch64-darwin`, `x86_64-linux`, `aarch64-linux`.
- Users: **`aar@`** (primary) and **`drewr@`** (secondary) for each system — 6 `homeConfigurations` total in `flake.nix`.
- `build-home-manager` auto-detects system from `uname` (`aarch64-darwin` / `x86_64-linux` / else `aarch64-linux`) and username from `LOGNAME`; pins Home Manager via `nix run github:nix-community/home-manager/release-26.05`.

## Key flake inputs (in flake.nix)

- `nixpkgs` (nixos-unstable) and `nixpkgs-haskell` (**pinned rev**, ghc-9.8.4 cache-critical — do not bump without verifying).
- `home-manager` (follows nixpkgs), `zigutils`, `datumctl`, `llm-agents.nix` (provides claude-code, gemini-cli, codex, opencode, pi, hermes-agent), `una-src` (Haskell tool, built via `nixpkgs-haskell` ghc98).

## Notes

- Home Manager config lives in a non-standard location (`d/.config/home-manager/`, not repo root).
- Only commit intended files; the updater agent commits only `d/.config/home-manager/flake.lock`.
- Fresh `install` script also creates `$HOME/go` and builds `zsh-cache`/compinit data in `$HOME/.zsh-cache`.
