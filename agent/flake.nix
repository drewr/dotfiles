{
  # Agent sandbox images for Datum Compute (unikernel class): one image per
  # harness from the dotfiles (claude-code, gemini-cli, codex, opencode, pi,
  # hermes-agent), each with the same login environment, reachable only by SSH
  # over iroh. Providers beyond each
  # harness's native ones come from ./providers via agent-providers. Combines
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
      hermes = agents.hermes-agent;
    };
    busybox = pkgs.pkgsStatic.busybox;
    base = with pkgs; [ bashInteractive gitMinimal ripgrep curl jq dropbear dumbpipe juicefs rsync ];

    mkRootfs = name: harness: let
      # Linked into /bin ahead of busybox applets of the same name.
      tools = [ harness ] ++ base;
      closure = pkgs.closureInfo { rootPaths = tools ++ [ pkgs.cacert ]; };
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
      cp ${./agent-providers} $R/bin/agent-providers
      ln -s agent-providers $R/bin/with-provider
      cp ${./providers} $R/etc/agent/providers
      echo ${name} > $R/etc/agent/harness

      ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $R/etc/ssl/certs/ca-certificates.crt
      echo 'root:x:0:0:root:/root:/bin/bash' > $R/etc/passwd
      echo 'root:x:0:' > $R/etc/group
      printf '/bin/bash\n/bin/sh\n' > $R/etc/shells
      echo 'hosts: files dns' > $R/etc/nsswitch.conf

      chmod -R u+w $R
      chmod 0555 $R/bin/busybox $R/init $R/bin/ws $R/bin/agent-providers
      chmod 0700 $R/root
      chmod 1777 $R/tmp
    '';
  in {
    packages.${system} = builtins.mapAttrs mkRootfs harnesses;
  };
}
