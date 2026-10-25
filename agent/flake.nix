{
  # Agent sandbox images for Datum Compute (unikernel class): one image per
  # harness from the dotfiles (claude-code, gemini-cli, codex, opencode, pi),
  # each with the same login environment, reachable only by SSH over iroh.
  # Providers beyond each harness's native ones come from ./providers via
  # agent-providers. llm-agents and nixpkgs follow the dotfiles' pins
  # (agent/sync-pins, run by agent/build-image). Combines
  # what Spikes 4 and 5 proved: dropbear on loopback exposed by dumbpipe, and
  # Bun executables shipped with their wrapBuddy store paths.
  #
  # Every tool ships as its full nix closure at the original /nix/store paths:
  # no patchelf (it can corrupt Bun executables), and wrapBuddy's hardcoded
  # loader and glibc paths resolve as built. Built on the EC2 box, one per
  # harness (packages.<harness>; Dockerfile.datum's HARNESS build arg):
  #   buildbox/ec2/build.sh agent ghcr.io/drewr/agent-claude:dev --build-arg HARNESS=claude
  description = "Datum Compute agent sandboxes, one image per harness (SSH/iroh)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Same rev as the dotfiles (agent/sync-pins), but on llm-agents' own nixpkgs
    # rather than following ours as the dotfiles do: the harness versions are
    # the same, and only these builds are in cache.numtide.com.
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, llm-agents }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    agents = llm-agents.packages.${system};
    # The same harnesses the dotfiles install (d/.config/home-manager/flake.nix),
    # from the same pinned llm-agents rev; opencode2 is also exposed as opencode.
    opencode = pkgs.symlinkJoin {
      name = "opencode";
      paths = [ agents.opencode2 ];
      postBuild = "ln -s ${agents.opencode2}/bin/opencode2 $out/bin/opencode";
    };
    # Image name -> harness package.
    harnesses = {
      claude = agents.claude-code;
      gemini = agents.gemini-cli;
      codex = agents.codex;
      inherit opencode;
      pi = agents.pi;
    };
    busybox = pkgs.pkgsStatic.busybox;
    base = with pkgs; [ bashInteractive zsh gitMinimal openssh iputils ripgrep curl jq nix dropbear dumbpipe juicefs rsync ];

    # The login user (SSH lands here, not root), whose HOME is the shared home.
    user = { name = "drewr"; uid = 1000; };
    # Only the locale the dotfiles' zshenv asks for (LC_ALL=en_US.UTF-8).
    locales = pkgs.glibcLocales.override { allLocales = false; locales = [ "en_US.UTF-8/UTF-8" ]; };
    # The dotfiles' zsh config (zshrc, zshenv, zprofile, zsh.d), copied into the
    # build context by agent/build-image; absent when evaluating from the repo.
    dotfilesZsh = if builtins.pathExists ./zsh then ./zsh else null;

    # nix in the sandbox: a root nix-daemon (started by init) that the login user
    # talks to, builds as root (the image has no build users), no build sandbox, flakes on, and nixpkgs pinned to the rev the images are
    # built from, so `nix shell nixpkgs#tool` mostly hits cache.nixos.org and
    # needs no global registry lookup. Store paths go to RAM (/nix is on the
    # root overlay) and last for the session.
    nixConf = pkgs.writeText "nix.conf" ''
      experimental-features = nix-command flakes
      build-users-group =
      sandbox = false
      trusted-users = root ${user.name}
      flake-registry =
      substituters = https://cache.nixos.org
      trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
    '';
    nixRegistry = pkgs.writeText "registry.json" (builtins.toJSON {
      version = 2;
      flakes = [{
        from = { type = "indirect"; id = "nixpkgs"; };
        to = { type = "github"; owner = "nixos"; repo = "nixpkgs"; rev = nixpkgs.rev; };
      }];
    });

    mkRootfs = name: harness: let
      # Linked into /bin ahead of busybox applets of the same name.
      tools = [ harness ] ++ base;
      closure = pkgs.closureInfo { rootPaths = tools ++ [ pkgs.cacert locales ]; };
    in pkgs.runCommand "agent-rootfs-${name}" { } ''
      R=$out
      mkdir -p $R/bin $R/etc/ssl/certs $R/root $R/tmp $R/run $R/nix/store $R/etc/agent

      for p in $(cat ${closure}/store-paths); do cp -a $p $R/nix/store/; done
      for t in ${pkgs.lib.concatStringsSep " " (map toString tools)}; do
        for b in $t/bin/*; do
          case "$(basename $b)" in .*) continue;; esac
          ln -sf $b $R/bin/$(basename $b)
        done
      done
      cp ${busybox}/bin/busybox $R/bin/busybox
      for a in $(${busybox}/bin/busybox --list); do
        [ -e $R/bin/$a ] || [ -L $R/bin/$a ] || ln -s /bin/busybox $R/bin/$a
      done
      cp ${./init.sh} $R/init
      cp ${./ws} $R/bin/ws
      cp ${./nix-zsh-env} $R/bin/nix-zsh-env   # for the dotfiles' zsh prompt
      cp ${./agent-providers} $R/bin/agent-providers
      ln -s agent-providers $R/bin/with-provider
      cp ${./providers} $R/etc/agent/providers
      # GitHub's published SSH host keys (gh api meta), so git over SSH needs no prompt.
      mkdir -p $R/etc/ssh
      cp ${./ssh_known_hosts} $R/etc/ssh/ssh_known_hosts
      echo ${name} > $R/etc/agent/harness
      # Store paths shipped in the image, for init to register with nix.
      cp ${closure}/registration $R/etc/agent/nix-registration
      mkdir -p $R/etc/nix $R/nix/var/nix
      cp ${nixConf} $R/etc/nix/nix.conf
      cp ${nixRegistry} $R/etc/nix/registry.json
      # Static parts of the login environment; init adds the session's.
      echo 'export LOCALE_ARCHIVE=${locales}/lib/locale/locale-archive' > $R/etc/agent/env.static
      ${pkgs.lib.optionalString (dotfilesZsh != null) "cp -r ${dotfilesZsh} $R/etc/agent/zsh"}
      # zsh and bash login shells load the session environment (/etc/agent/env).
      echo '[ -r /etc/agent/env ] && . /etc/agent/env' > $R/etc/zshenv
      cp $R/etc/zshenv $R/etc/profile

      ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $R/etc/ssl/certs/ca-certificates.crt
      printf 'root:x:0:0:root:/root:/bin/bash\n${user.name}:x:${toString user.uid}:${toString user.uid}:${user.name}:/home/agent:/bin/zsh\n' > $R/etc/passwd
      printf 'root:x:0:\n${user.name}:x:${toString user.uid}:\n' > $R/etc/group
      printf '/bin/zsh\n/bin/bash\n/bin/sh\n' > $R/etc/shells
      echo ${user.name} > $R/etc/agent/user
      echo 'hosts: files dns' > $R/etc/nsswitch.conf

      chmod -R u+w $R
      chmod 0555 $R/bin/busybox $R/init $R/bin/ws $R/bin/agent-providers $R/bin/nix-zsh-env
      chmod 0700 $R/root
      chmod 1777 $R/tmp
    '';
  in {
    packages.${system} = builtins.mapAttrs mkRootfs harnesses;
  };
}
