#!/bin/sh
# Spike 2b: assemble an s6-supervised rootfs and build+push it as a unikernel image.
# Run inside the build box, in ONE invocation (instances have no persistence).
# Assumes source already unpacked at /root/sp2b and the plugin at /tmp/dc.
# Requires GHCR_TOKEN in the environment.
set -e
export PATH=/root/.nix-profile/bin:$PATH
NIX="nix --extra-experimental-features nix-command --extra-experimental-features flakes"
export BUILDKIT_HOST=unix:///run/buildkit/buildkitd.sock

echo "== fetch cached s6 (dynamic) and busybox (static) =="
S6=$($NIX build --no-link --print-out-paths "nixpkgs#s6" | grep -v -- -man | grep -v -- -doc | head -1)
BB=$($NIX build --no-link --print-out-paths "nixpkgs#pkgsStatic.busybox" | head -1)
echo "s6=$S6"
echo "busybox=$BB"

echo "== assemble rootfs =="
R=/root/sp2b/rootfs
rm -rf "$R"
mkdir -p "$R/sbin" "$R/bin" "$R/command" "$R/service/echo" "$R/lib" "$R/lib64"
# s6's convention: helper binaries live in /command and s6-svscan finds s6-supervise
# there. Use REAL files, not symlinks: Unikraft's loader may not follow symlinks.
for b in s6-svscan s6-supervise s6-svstat s6-svc; do
  cp "$S6/bin/$b" "$R/command/$b"
  cp "$S6/bin/$b" "$R/sbin/$b"
done
cp "$BB/bin/busybox" "$R/bin/busybox"
for a in sh ls cat echo mkdir sleep ps; do ln -sf /bin/busybox "$R/bin/$a"; done
cp /root/sp2b/init.sh "$R/init"
cp /root/sp2b/run-service.sh "$R/service/echo/run"
chmod +x "$R/command/"* "$R/init" "$R/service/echo/run"

echo "== copy s6's runtime closure (loader + libs) into standard paths =="
# Unikraft's app-elfloader expects the loader and libs at the usual Linux locations:
#   /lib64/ld-linux-x86-64.so.2  and  /lib/x86_64-linux-gnu/*.so*
# Find glibc inside s6's runtime closure rather than trusting a `nix build` output path.
$NIX path-info -r "$S6" > /tmp/s6-closure.txt
GLIBC_DIR=$(grep -o '/nix/store/[^ ]*-glibc-[0-9.]*-[0-9]*' /tmp/s6-closure.txt | grep -v -- -dev | grep -v -- -bin | head -1)
echo "glibc dir: $GLIBC_DIR"
mkdir -p "$R/lib64" "$R/lib/x86_64-linux-gnu"
cp -aL "$GLIBC_DIR/lib/ld-linux-x86-64.so.2" "$R/lib64/" && echo "  loader ok" || echo "  loader MISSING"
# Nix-built binaries record an absolute PT_INTERP into the nix store. Unikraft's
# analyzer (and the loader) look for that exact path, so reproduce it in the rootfs.
mkdir -p "$R/nix/store/$(basename "$GLIBC_DIR")/lib"
cp -aL "$GLIBC_DIR/lib/ld-linux-x86-64.so.2" "$R/nix/store/$(basename "$GLIBC_DIR")/lib/" 2>/dev/null || true
for so in "$GLIBC_DIR/lib/"*.so*; do cp -aL "$so" "$R/lib/x86_64-linux-gnu/" 2>/dev/null || true; done
for p in $(cat /tmp/s6-closure.txt); do
  [ -d "$p/lib" ] || continue
  for so in "$p/lib/"*.so*; do cp -aL "$so" "$R/lib/x86_64-linux-gnu/" 2>/dev/null || true; done
done
echo "libs: $(ls "$R/lib/x86_64-linux-gnu" 2>/dev/null | wc -l) files"
du -sh "$R"
echo "== install patchelf =="
$NIX profile install "nixpkgs#patchelf" >/dev/null 2>&1 || true
export PATH=/root/.nix-profile/bin:$PATH
# Rewrite the interpreter and RPATH of the s6 binaries to standard Linux paths so
# they boot under Unikraft's ELF loader without a nix store present.
for b in s6-svscan s6-supervise s6-svstat s6-svc; do
  patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 \
           --set-rpath /lib/x86_64-linux-gnu "$R/command/$b" 2>&1 | head -2 || echo "  patchelf $b failed"
  cp "$R/command/$b" "$R/sbin/$b"
done
echo "patched interpreters; loader at: $(ls "$R/lib64")"

echo "== start buildkitd =="
pkill buildkitd 2>/dev/null || true
sleep 2
rm -rf /dev/shm/buildkit /run/buildkit
mkdir -p /dev/shm/buildkit /run/buildkit
nohup buildkitd --root /dev/shm/buildkit --addr unix:///run/buildkit/buildkitd.sock > /tmp/buildkitd.log 2>&1 &
sleep 12
grep -q 'running server' /tmp/buildkitd.log && echo buildkitd_up || { echo buildkitd_FAILED; tail -5 /tmp/buildkitd.log; exit 1; }

echo "== build (analyze) + push =="
printf '%s' "$GHCR_TOKEN" | crane auth login ghcr.io -u drewr --password-stdin 2>&1 | tail -1
cd /root/sp2b
/tmp/dc build --analyze --push -o ghcr.io/drewr/sp2b-s6:dev /root/sp2b 2>&1 | tail -25
