#!/bin/sh
# Spike 3: package a Nix-built node plus a capability probe and run it on Unikraft.
# Self-contained: unpacks its own source, fetches deps, assembles the rootfs, and
# builds. Must run in ONE invocation because the instance filesystem is ephemeral
# and is wiped whenever the instance restarts.
# Requires GHCR_TOKEN in the environment.
set -e
export PATH=/root/.nix-profile/bin:$PATH
NIX="nix --extra-experimental-features nix-command --extra-experimental-features flakes"
export BUILDKIT_HOST=unix:///run/buildkit/buildkitd.sock

# --- self-contained source bootstrap ---
if [ ! -f /root/sp3/forktest.js ]; then
  mkdir -p /root/sp3 && cd /root/sp3 && tar xzf /tmp/sp3-src.tgz && rm -f ._* || true
fi
echo "== source =="; ls /root/sp3

echo "== fetch node and busybox =="
NODE=$($NIX build --no-link --print-out-paths "nixpkgs#nodejs" | grep -v '\-dev$' | head -1)
BB=$($NIX build --no-link --print-out-paths "nixpkgs#pkgsStatic.busybox" | head -1)
echo "node=$NODE"
echo "busybox=$BB"
echo "== assemble rootfs =="
R=/root/sp3/rootfs
rm -rf "$R"
mkdir -p "$R/bin" "$R/probe" "$R/lib64" "$R/lib/x86_64-linux-gnu"

# node binary
cp "$NODE/bin/node" "$R/bin/node"
cp /root/sp3/forktest.js "$R/probe/forktest.js"
cp /root/sp3/init.sh "$R/init"

# busybox for /bin/sh and friends
cp "$BB/bin/busybox" "$R/bin/busybox"
for a in sh ls cat echo mkdir sleep ps; do ln -sf /bin/busybox "$R/bin/$a"; done
chmod +x "$R/bin/node" "$R/init"

echo "== gather node's runtime libs and loader =="
$NIX path-info -r "$NODE" | grep -v -- -dev$ | grep -v -- -doc$ > /tmp/node-closure.txt
echo "closure size: $(wc -l < /tmp/node-closure.txt)"
GLIBC_DIR=$(grep -o '/nix/store/[^ ]*-glibc-[0-9.]*-[0-9]*' /tmp/node-closure.txt | grep -v -- -dev | grep -v -- -bin | head -1)
echo "glibc dir: $GLIBC_DIR"
cp -aL "$GLIBC_DIR/lib/ld-linux-x86-64.so.2" "$R/lib64/" && echo "  loader ok" || echo "  loader MISSING"
for so in "$GLIBC_DIR/lib/"*.so*; do cp -aL "$so" "$R/lib/x86_64-linux-gnu/" 2>/dev/null || true; done
# node's own .so deps (libnode, libuv, icu, ssl, etc.) from its closure.
# Copy each real file once; the closure lists .so, .so.N and .so.N.M as separate
# entries but they are the same content, so skip entries whose content we have.
for p in $(cat /tmp/node-closure.txt); do
  [ -d "$p/lib" ] || continue
  for so in "$p/lib/"*.so*; do
    [ -e "$so" ] || continue
    cp -aL "$so" "$R/lib/x86_64-linux-gnu/" 2>/dev/null || true
  done
done
# Collapse duplicate content: identical .so files (libicudata.so, .so.78, .so.78.3)
# blow the rootfs up. Replace byte-identical files with hardlinks to save space.
# busybox ash has no associative arrays, so track hashes via a temp file.
cd "$R/lib/x86_64-linux-gnu"
: > /tmp/seen-hashes
for f in *; do
  [ -f "$f" ] || continue
  h=$(sha256sum "$f" | cut -d' ' -f1)
  prev=$(grep -m1 "^$h " /tmp/seen-hashes 2>/dev/null | cut -d' ' -f2)
  if [ -n "$prev" ]; then
    rm -f "$f" && ln "$prev" "$f"
  else
    printf '%s %s\n' "$h" "$f" >> /tmp/seen-hashes
  fi
done
cd - >/dev/null
echo "libs: $(ls "$R/lib/x86_64-linux-gnu" | wc -l) files"
du -sh "$R"

echo "== patchelf node and its libs to standard paths =="
$NIX profile install "nixpkgs#patchelf" >/dev/null 2>&1 || true
export PATH=/root/.nix-profile/bin:$PATH
patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 \
         --set-rpath /lib/x86_64-linux-gnu "$R/bin/node" 2>&1 | head -2 || echo "  patchelf node failed"
for so in "$R/lib/x86_64-linux-gnu/"*.so*; do
  case "$so" in *ld-linux*) continue;; esac
  patchelf --set-rpath /lib/x86_64-linux-gnu "$so" 2>/dev/null || true
done

echo "== buildkitd =="
command -v buildkitd >/dev/null 2>&1 || $NIX profile install "nixpkgs#buildkit" >/dev/null 2>&1 || true
command -v runc >/dev/null 2>&1 || $NIX profile install "nixpkgs#runc" >/dev/null 2>&1 || true
export PATH=/root/.nix-profile/bin:$PATH
pkill buildkitd 2>/dev/null || true
sleep 2
rm -rf /dev/shm/buildkit /run/buildkit
mkdir -p /dev/shm/buildkit /run/buildkit
nohup buildkitd --root /dev/shm/buildkit --addr unix:///run/buildkit/buildkitd.sock > /tmp/buildkitd.log 2>&1 &
sleep 12
grep -q 'running server' /tmp/buildkitd.log && echo buildkitd_up || { echo buildkitd_FAILED; tail -5 /tmp/buildkitd.log; exit 1; }

echo "== build (analyze) + push =="
# datumctl compute build --push reads registry credentials from ~/.docker/config.json
cd /root/sp3
/tmp/dc build --analyze --push -o ghcr.io/drewr/sp3-node:dev /root/sp3 2>&1 | tail -30
