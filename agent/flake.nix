{
  # Agent sandbox image for Datum Compute (unikernel class): claude-code plus a
  # login environment, reachable only by SSH over iroh. Combines what Spikes 4
  # and 5 proved: dropbear on loopback exposed by dumbpipe, and the claude-code
  # Bun binary shipped with its wrapBuddy store paths.
  #
  # Every tool ships as its full nix closure at the original /nix/store paths:
  # no patchelf (it can corrupt Bun executables), and wrapBuddy's hardcoded
  # loader and glibc paths resolve as built. Built on the EC2 box:
  #   buildbox/ec2/build.sh agent ghcr.io/drewr/agent-sandbox:dev
  description = "Datum Compute agent sandbox (claude-code over SSH/iroh)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, llm-agents }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    claude = llm-agents.packages.${system}.claude-code;
    busybox = pkgs.pkgsStatic.busybox;
    # Linked into /bin ahead of busybox applets of the same name.
    tools = with pkgs; [ claude bashInteractive gitMinimal ripgrep dropbear dumbpipe ];
    closure = pkgs.closureInfo { rootPaths = tools ++ [ pkgs.cacert ]; };

    rootfs = pkgs.runCommand "agent-rootfs" { } ''
      R=$out
      mkdir -p $R/bin $R/etc/ssl/certs $R/root $R/tmp $R/run $R/nix/store

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

      ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $R/etc/ssl/certs/ca-certificates.crt
      echo 'root:x:0:0:root:/root:/bin/bash' > $R/etc/passwd
      echo 'root:x:0:' > $R/etc/group
      printf '/bin/bash\n/bin/sh\n' > $R/etc/shells
      echo 'hosts: files dns' > $R/etc/nsswitch.conf

      chmod -R u+w $R
      chmod 0555 $R/bin/busybox $R/init
      chmod 0700 $R/root
      chmod 1777 $R/tmp
    '';
  in {
    packages.${system} = {
      inherit rootfs;
      default = rootfs;
    };
  };
}
