{
  # Spike 3: reproducible build of the Node unikernel image for Datum Compute.
  #
  # The rootfs is a pure derivation: every input is pinned by flake.lock, and the
  # store gives every file mtime 1, so the same lock yields the same rootfs.
  #
  # Dockerfile.datum runs `nix build path:/src#rootfs` inside BuildKit, so the
  # build happens wherever BuildKit runs (the EC2 build box, buildbox/ec2/) and
  # the client only sends these few source files. Datum Compute is x86_64 only.
  description = "Spike 3 Node unikernel image for Datum Compute";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    node = pkgs.nodejs;
    busybox = pkgs.pkgsStatic.busybox;
    closure = pkgs.closureInfo { rootPaths = [ node ]; };

    # Unikraft's ELF loader wants the loader and libs at standard FHS paths, so
    # node is patched to /lib64/ld-linux-x86-64.so.2 and /lib/x86_64-linux-gnu.
    rootfs = pkgs.runCommand "sp3-rootfs" { nativeBuildInputs = [ pkgs.patchelf ]; } ''
      R=$out
      L=$R/lib/x86_64-linux-gnu
      mkdir -p $R/bin $R/probe $R/lib64 $L

      cp ${node}/bin/node $R/bin/node
      cp ${./forktest.js} $R/probe/forktest.js
      cp ${./init.sh} $R/init
      cp ${busybox}/bin/busybox $R/bin/busybox
      for a in sh ls cat echo mkdir sleep ps; do ln -s /bin/busybox $R/bin/$a; done

      cp -L ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 $R/lib64/
      # store-paths is sorted, so on a name clash the first path wins.
      for p in $(cat ${closure}/store-paths); do
        [ -d "$p/lib" ] || continue
        for so in "$p"/lib/*.so*; do
          [ -f "$so" ] || continue
          [ -e "$L/$(basename "$so")" ] || install -m 0644 "$so" $L/
        done
      done
      chmod -R u+w $R

      # Collapse byte-identical .so copies (libicudata.so, .so.78, .so.78.3).
      declare -A seen
      for f in $L/*; do
        h=$(sha256sum "$f" | cut -d' ' -f1)
        if [ -n "''${seen[$h]:-}" ]; then ln -f "''${seen[$h]}" "$f"; else seen[$h]=$f; fi
      done

      patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 \
               --set-rpath /lib/x86_64-linux-gnu $R/bin/node
      for so in $L/*.so*; do
        case "$so" in *ld-linux*) continue;; esac
        patchelf --set-rpath /lib/x86_64-linux-gnu "$so" 2>/dev/null || true
      done
      chmod 0555 $R/bin/node $R/bin/busybox $R/init
    '';
  in {
    packages.${system} = {
      inherit rootfs;
      default = rootfs;
    };
  };
}
