#!/bin/sh
# Spike 2: build + push the init/supervisor probe as a unikernel image.
# Run inside the build box, in ONE invocation (no persistence across replaces).
# Expects source tar on stdin: initprobe.c Dockerfile.datum
# Requires GHCR_TOKEN in the environment.
set -e
export PATH=/root/.nix-profile/bin:$PATH
NIX="nix --extra-experimental-features nix-command --extra-experimental-features flakes"

echo "== install tooling =="
for p in buildkit runc gnutar gzip git cacert crane gcc binutils; do
  $NIX profile install "nixpkgs#$p" >/dev/null 2>&1 && echo "  ok: $p" || echo "  SKIP: $p"
done
export PATH=/root/.nix-profile/bin:$PATH

echo "== unpack =="
mkdir -p /root/sp2 && cd /root/sp2 && tar xzf - && rm -f ._*

echo "== buildkitd (tmpfs root: instance fs is fuse, no xattrs) =="
pkill buildkitd 2>/dev/null || true
sleep 2
rm -rf /dev/shm/buildkit /run/buildkit
mkdir -p /dev/shm/buildkit /run/buildkit
nohup buildkitd --root /dev/shm/buildkit --addr unix:///run/buildkit/buildkitd.sock > /tmp/buildkitd.log 2>&1 &
sleep 12
grep -q 'running server' /tmp/buildkitd.log && echo buildkitd_up || { echo buildkitd_FAILED; tail -5 /tmp/buildkitd.log; exit 1; }

echo "== compile static-pie (musl) =="
CC=$($NIX build --no-link --print-out-paths nixpkgs#pkgsStatic.stdenv.cc | grep -v -- -man | head -1)/bin/x86_64-unknown-linux-musl-cc
echo "cc: $CC"
cd /root/sp2
$CC -static-pie -fPIE -O2 -o initprobe initprobe.c
ls -la initprobe

echo "== build + push =="
export BUILDKIT_HOST=unix:///run/buildkit/buildkitd.sock
printf '%s' "$GHCR_TOKEN" | crane auth login ghcr.io -u drewr --password-stdin 2>&1 | tail -1
/tmp/dc build --push -o ghcr.io/drewr/sp2-initprobe:dev /root/sp2 2>&1 | tail -6
