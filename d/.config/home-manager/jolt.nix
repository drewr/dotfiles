# jolt's flake package, wrapped for Linux.
#
# jolt's Nix build links against its own glibc, whose dynamic linker does not
# search the distro's /usr/lib, but lev's :jolt/native specs dlopen ICU,
# OpenBLAS and OpenSSL by name, so a bare install cannot load them. On Linux
# we wrap the flake's package so those libraries resolve to the nixpkgs
# copies (pinned by flake.lock, so reproducible); each library's own RUNPATH
# resolves its transitive deps (libicudata, libstdc++, libgfortran, libgomp).
#
# JOLT_OPENSSL_LIBDIR is set explicitly because jolt's own wrapper derives it
# from `toString pkgs.openssl`, which this nixpkgs resolves to the -bin output
# (no libraries); the base wrapper's --set-default does not override an
# already-set variable. On Darwin the native specs use absolute Homebrew paths
# and the system loader finds them, so the package passes through unwrapped.
{ nixpkgs, jolt }:
system:
  if builtins.hasAttr system jolt.packages
  then let
    pkgs = import nixpkgs { system = system; config.allowUnfree = true; };
    base = jolt.packages.${system}.jolt;
  in
  if pkgs.stdenv.isLinux
  then pkgs.symlinkJoin {
    name = "jolt";
    paths = [ base ];
    # Referenced by the wrapper below; must be inputs to pass the
    # references-to check without being symlinked into $out.
    buildInputs = [ pkgs.bash pkgs.icu.out pkgs.openblas.out pkgs.openssl.out ];
    postBuild = ''
      mv $out/bin/jolt $out/bin/.jolt-base
      cat > $out/bin/jolt <<EOF
#!${pkgs.bash}/bin/bash -e
if [ -n "\$LD_LIBRARY_PATH" ]; then
  LD_LIBRARY_PATH="\$LD_LIBRARY_PATH:${pkgs.icu.out}/lib:${pkgs.openblas.out}/lib:${pkgs.openssl.out}/lib"
else
  LD_LIBRARY_PATH="${pkgs.icu.out}/lib:${pkgs.openblas.out}/lib:${pkgs.openssl.out}/lib"
fi
export LD_LIBRARY_PATH
export JOLT_OPENSSL_LIBDIR=${pkgs.openssl.out}/lib
exec $out/bin/.jolt-base "\$@"
EOF
      chmod +x $out/bin/jolt
    '';
  }
  else base
  else null
