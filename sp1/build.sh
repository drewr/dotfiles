#!/bin/sh
# Spike 1 end-to-end, run inside the build box. Expects sp1 source tar on stdin.
set -e
export PATH=/root/.nix-profile/bin:$PATH
export BUILDKIT_HOST=unix:///run/buildkit/buildkitd.sock

mkdir -p /root/sp1 && cd /root/sp1 && tar xzf - && rm -f ._*
ls -la /root/sp1

echo "== compiling static-pie =="
nix --extra-experimental-features "nix-command flakes" shell nixpkgs#gcc nixpkgs#binutils --command sh -c '
  cd /root/sp1
  gcc -static-pie -O2 -o vforktest vforktest.c && echo built_vforktest
  gcc -static-pie -O2 -o spikeecho spikeecho.c && echo built_spikeecho
'
ls -la /root/sp1/vforktest /root/sp1/spikeecho

echo "== building compute image =="
/tmp/datumctl-compute build --push -o ghcr.io/drewr/vforktest-uk:spike1 /root/sp1 2>&1 | tail -8
