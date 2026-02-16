# Dotfiles Repository

Personal dotfiles and development environment configuration managed with shell, [Nix](https://nixos.org/), and [Home Manager](https://github.com/nix-community/home-manager).

## Repository Overview

This repository contains personal configuration files, shell scripts, and environment setup for Unix-like systems (macOS and Linux). The configuration is declaratively managed using Nix flakes and Home Manager, enabling reproducible development environments across multiple machines. It is bootstrapped by a Makefile.

## Structure

```
dotfiles/
├── d/                          # User home directory files
│   ├── .config/home-manager/   # Home Manager configuration
│   │   ├── flake.nix          # Main Nix flake with dependencies
│   │   ├── default.nix        # Base packages and settings
│   │   ├── util.nix           # Utility tools
│   │   ├── clojure.nix        # Clojure development environment
│   │   ├── desktop.nix        # Desktop applications (ffmpeg, ghostty, etc.)
│   │   └── network.nix        # Network utilities
│   └── bin/                    # Custom utility scripts (30+ tools)
├── zsh.d/                      # Zsh configuration modules
├── nix/                        # Language-specific Nix configs
├── conf/                       # Application configurations
├── etc/                        # System-level configs
├── vm/                         # VM and Puppet configurations
├── install                     # Installation script
└── build-home-manager          # Home Manager build wrapper
```

## Key Components

### Nix Flake Configuration

The main configuration is in `d/.config/home-manager/flake.nix`, which includes, among other things:

**External Dependencies:**
- `nixpkgs` - NixOS package collection (unstable channel)
- `home-manager` - User environment management
- `zigutils` - Custom Zig utilities (nix-zsh-env, gitclone)
- `claude-code` - Claude Code CLI
- `datumctl` - Datum cloud control tool
- `gemini-cli` - Gemini CLI tool
- `codex-cli` - Codex CLI tool
- `una` - Haskell-based tool (custom build)

**Supported Systems:**
- `aarch64-darwin` (Apple Silicon macOS)
- `aarch64-linux` (ARM Linux)
- `x86_64-linux` (Intel/AMD Linux)

**User Configurations:**
- `aar@{system}` - Primary user configuration
- `drewr@{system}` - Secondary user configuration

### Custom Utilities (d/bin/)

The repository includes 30+ custom shell scripts and utilities:
- `gh-user-activity` - GitHub user activity tracker
- `my-ip` - IP address lookup
- `latency-tcp` - TCP latency measurement
- `rand` - Random number/string generation
- `awsg`, `envg`, `gpgg` - AWS, environment, and GPG helpers
- `kc` - Kubernetes context management
- `timebuddy` - Time zone helper
- `took` - Command timing utility
- And many more specialized tools

### Zsh Configuration

Modular zsh setup in `zsh.d/`:
- `00-opts` - Shell options
- `01-env` - Environment variables
- `10-completion` - Command completion
- `15-alias` - Shell aliases
- `20-fns` - Custom functions
- `25-git` - Git-specific configuration
- `30-screen` - Screen/tmux integration
- `60-prompt` - Prompt customization
- Platform-specific: `zsh.Darwin`, `zsh.Linux`

## Recent Development Activity

### Last 6 Months Highlights

**Networking & Tools (Jan-Feb 2026):**
- Added `dnslookup` utility for DNS queries
- Added research skill for structured research reports
- Upgraded to `curlFull` with HTTP/3 support
- Added Wireguard interface management for macOS

**CLI Tools & AI Integration:**
- Integrated Claude Code from Nix flake
- Added `gemini-cli` and `datumctl`
- Added custom Zig utilities (`nix-zsh-env`, `gitclone`)
- Enhanced GitHub integration with PR management and user activity tracking

**Configuration Management:**
- Made `flake.lock` configurable per system
- Upgraded to AWS CLI v2
- Updated Home Manager release tracking
- Fixed tmux window resize issues

**Terminal & Desktop:**
- Switched Ghostty theme with Geist Mono font
- Fixed Emacs keybindings in Ghostty (M-!, CTRL-i)
- Added `ffmpeg` for media processing
- Removed `mpv` from bundled packages (available via `nix run`)

**Development Environment:**
- Added `jet` (JSON/EDN processor)
- Added `jujutsu` (version control)
- Enhanced Clojure development with Leiningen plugins
- Added Gnus dependencies for email

## Installation & Usage

### Initial Setup

```bash
# Clone the repository
git clone <repo-url> ~/src/drewr/dotfiles
cd ~/src/drewr/dotfiles

# Run installation script
make
```

### Building Home Manager Configuration

```bash
# Build for current system (auto-detected)
make home
```

## Working in This Repository

### Adding New Packages

1. Edit the appropriate `.nix` file in `d/.config/home-manager/`:
   - `default.nix` - Core tools and utilities
   - `clojure.nix` - Clojure-related packages
   - `desktop.nix` - Tools that require a window system
   - `network.nix` - Network tools
   - `util.nix` - Miscellaneous utilities

2. Add the package to `home.packages` list:
   ```nix
   home.packages = [
     pkgs.new-package
   ];
   ```

3. Rebuild: `./build-home-manager`

### Adding Custom Scripts

1. Create script in `d/bin/`
2. Make it executable: `chmod +x d/bin/script-name`
3. Reference it in the appropriate `.nix` file:
   ```nix
   home.file = {
     "bin/script-name".source = ./d/bin/script-name;
   };
   ```

### Adding Flake Dependencies

1. Edit `d/.config/home-manager/flake.nix`
2. Add input in the `inputs` section:
   ```nix
   inputs = {
     new-tool = {
       url = "github:owner/repo";
       inputs.nixpkgs.follows = "nixpkgs";
     };
   };
   ```
3. Add to `outputs` function signature and `mkHomeConfig`
4. Update `flake.lock`: `nix flake update`

### Modifying Zsh Configuration

- Add new zsh scripts to `zsh.d/` with numeric prefix (e.g., `35-myconfig`)
- Lower numbers load first
- Platform-specific configs go in `zsh.Darwin` or `zsh.Linux`

## File Locations

After installation, files are symlinked/copied to:
- `~/.zshrc`, `~/.zshenv`, `~/.zprofile` - Zsh initialization
- `~/.zsh.d/` - Zsh configuration modules
- `~/bin/` - Custom utility scripts
- `~/.config/home-manager/` - Home Manager configuration
- `~/.gitconfig` - Git configuration
- `~/.tmux.conf` - Tmux configuration
- `~/.config/ghostty/config` - Ghostty terminal config

## Configuration Philosophy

This repository follows these principles:

1. **Declarative Configuration**: Use Nix to declare what should be installed
2. **Reproducibility**: Same configuration produces same environment
3. **Multi-platform**: Support both macOS and Linux
4. **Modularity**: Separate concerns into focused `.nix` files
5. **Custom Tooling**: Build small, focused utilities for common tasks
6. **Version Control**: Track all configuration in git
7. **Flake Inputs**: Pin external dependencies for stability

## Maintenance

### Updating Dependencies

See if anything changed:

```bash
# Update all flake inputs
cd ~/.config/home-manager
nix flake update
```

If the output is non-empty:

```bash
make home
```

### Garbage Collection

```bash
# Remove old Home Manager generations
nix run github:nix-community/home-manager expire-generations "-30 days"

# Run Nix garbage collection
nix-collect-garbage -d
```

## Notes for Claude

When working in this repository:

1. **Nix Configuration**: All package management goes through Home Manager Nix files and home-manager config is in a non-standard location
2. **Don't Break Reproducibility**: Avoid manual `nix-env -i` installs
3. **Multi-user Setup**: Remember there are configurations for both `aar` and `drewr`
4. **Platform Awareness**: Check which system is being targeted (Darwin vs Linux)
5. **Flake Updates**: This repo doesn't track a `flake.lock`
6. **Script Permissions**: New scripts in `d/bin/` need to be executable
7. **Home Manager**: Changes require rebuild with `./build-home-manager`
8. **Coding Agents Integration**: Prefer OpenCode

## Related Files

- `.gitignore` - Keeps Nix build artifacts out of git
- `Makefile` - Additional build automation

## Git Workflow

This repository uses a simple trunk-based workflow:
- Main branch: `main`
- Commits focus on incremental improvements
- Commit messages describe the change, not implementation details
