{
  # Spike 5 (H15): does the agents' Bun runtime run on Unikraft? Ships the real
  # claude-code binary from llm-agents.nix, pinned to the same rev as the dotfiles.
  #
  # llm-agents packages the Bun executable with wrapBuddy: the ELF interpreter is
  # a stub that reads a sidecar (bin/..claude-wrapped.wrapbuddy) naming the
  # glibc loader and lib dirs by absolute /nix/store path. So the binary, its
  # sidecar and that glibc ship at their original store paths, unmodified, and
  # /bin/claude is a symlink. (A copy at /bin with FHS libs fails with
  # "wrapBuddy: open loader".)
  description = "Spike 5 claude-code (Bun) unikernel image for Datum Compute";

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

    rootfs = pkgs.runCommand "sp5-rootfs" { } ''
      R=$out
      mkdir -p $R/bin $R/etc/ssl/certs $R/tmp

      # claude-code's bin dir (binary + wrapBuddy sidecar) at its store path.
      mkdir -p $R${claude}/bin
      cp -a ${claude}/bin/.claude-wrapped ${claude}/bin/..claude-wrapped.wrapbuddy $R${claude}/bin/
      ln -s ${claude}/bin/.claude-wrapped $R/bin/claude
      # Every store path the binary or sidecar names: the stub hardcodes
      # wrap-buddy's loader.bin, and the sidecar names the glibc it loads.
      for p in $(grep -aho '/nix/store/[a-z0-9]\{32\}-[^/:[:space:]"]*' \
                   ${claude}/bin/.claude-wrapped ${claude}/bin/..claude-wrapped.wrapbuddy \
                 | sort -u | grep -v -- "${claude}"); do
        mkdir -p $R$p && cp -a $p/lib $R$p/
      done

      cp ${./init.sh} $R/init
      cp ${busybox}/bin/busybox $R/bin/busybox
      for a in sh ls cat echo mkdir sleep ps grep head tail timeout env free tr; do
        ln -s /bin/busybox $R/bin/$a
      done
      cp -L ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $R/etc/ssl/certs/ca-certificates.crt

      # Bun and claude look up the current user; give them a root entry.
      echo 'root:x:0:0:root:/tmp/home:/bin/sh' > $R/etc/passwd
      echo 'root:x:0:' > $R/etc/group
      echo 'hosts: files dns' > $R/etc/nsswitch.conf

      chmod -R u+w $R
      chmod 0555 $R/bin/busybox $R/init
      chmod 1777 $R/tmp
    '';
  in {
    packages.${system} = {
      inherit rootfs;
      default = rootfs;
    };
  };
}
