#!/bin/sh
# Combined build-box setup + Spike 1 build, in ONE invocation, because a workload
# replace wipes the instance filesystem (no persistence).
# Run as:  GHCR_TOKEN=... sh boxrun.sh   with source already unpacked at /root/sp1
set -e
export PATH=/root/.nix-profile/bin:$PATH
NIX="nix --extra-experimental-features nix-command --extra-experimental-features flakes"

echo "== install tooling (sequential; multi-package install conflicts) =="
for p in buildkit runc gnutar gzip git cacert crane gcc binutils; do
  $NIX profile install "nixpkgs#$p" >/dev/null 2>&1 && echo "  ok: $p" || echo "  SKIP: $p"
done
export PATH=/root/.nix-profile/bin:$PATH

echo "== start buildkitd =="
pkill buildkitd 2>/dev/null || true
sleep 2
rm -rf /var/lib/buildkit /run/buildkit
mkdir -p /var/lib/buildkit /run/buildkit
nohup buildkitd --root /var/lib/buildkit --addr unix:///run/buildkit/buildkitd.sock > /tmp/buildkitd.log 2>&1 &
sleep 12
if grep -q 'running server' /tmp/buildkitd.log; then echo buildkitd_up; else echo buildkitd_FAILED; tail -5 /tmp/buildkitd.log; fi

echo "== compile static-pie =="
cd /root/sp1
gcc -static-pie -O2 -o vforktest vforktest.c
gcc -static-pie -O2 -o spikeecho spikeecho.c
ls -la vforktest spikeecho

echo "== build + push compute image =="
export BUILDKIT_HOST=unix:///run/buildkit/buildkitd.sock
printf '%s' "$GHCR_TOKEN" | crane auth login ghcr.io -u drewr --password-stdin 2>&1 | tail -1
/tmp/datumctl-compute build --push -o ghcr.io/drewr/vforktest-uk:spike1 /root/sp1 2>&1 | tail -6
