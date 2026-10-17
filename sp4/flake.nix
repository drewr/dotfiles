{
  # Spike 4: SSH into a unikernel instance over iroh, with no inbound port and no
  # project-scoped Connect gateway. dropbear listens on loopback; dumbpipe exposes
  # it as an iroh endpoint whose secret key comes from a Datum Secret, so the
  # client computes the ticket itself (`dumbpipe generate-ticket`).
  #
  # dumbpipe and dropbear are ordinary dynamically linked nixpkgs builds, so the
  # rootfs carries their whole closure at the original /nix/store paths: no
  # patchelf, and the interpreters resolve as built.
  description = "Spike 4 ssh-over-iroh unikernel image for Datum Compute";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    busybox = pkgs.pkgsStatic.busybox;
    tools = [ pkgs.dumbpipe pkgs.dropbear ];
    closure = pkgs.closureInfo { rootPaths = tools; };

    rootfs = pkgs.runCommand "sp4-rootfs" { } ''
      R=$out
      mkdir -p $R/bin $R/etc/dropbear $R/root/.ssh $R/tmp $R/nix/store

      for p in $(cat ${closure}/store-paths); do cp -a $p $R/nix/store/; done
      ln -s ${pkgs.dumbpipe}/bin/dumbpipe $R/bin/dumbpipe
      for b in dropbear dropbearkey; do ln -s ${pkgs.dropbear}/bin/$b $R/bin/$b; done

      cp ${./init.sh} $R/init
      cp ${busybox}/bin/busybox $R/bin/busybox
      for a in sh ls cat echo mkdir sleep ps grep head tail env tr uname id sed \
               hostname ip ifconfig nslookup wget mount tty stty clear vi; do
        ln -s /bin/busybox $R/bin/$a
      done

      echo 'root:x:0:0:root:/root:/bin/sh' > $R/etc/passwd
      echo 'root:x:0:' > $R/etc/group
      echo '/bin/sh' > $R/etc/shells
      echo 'hosts: files dns' > $R/etc/nsswitch.conf
      cp ${./authorized_keys} $R/root/.ssh/authorized_keys

      chmod -R u+w $R
      chmod 0555 $R/bin/busybox $R/init
      chmod 0700 $R/root $R/root/.ssh
      chmod 0600 $R/root/.ssh/authorized_keys
      chmod 1777 $R/tmp
    '';
  in {
    packages.${system} = {
      inherit rootfs;
      default = rootfs;
    };
  };
}
