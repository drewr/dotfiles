#!/usr/bin/env bash
# Set up a Datum Compute general-purpose instance as a unikernel build box.
#
# Run this INSIDE the instance (see box.md). It installs tooling to the nix
# profile and starts buildkitd with its root on /dev/shm, which is required
# because the instance's writable filesystem is fuse and has no xattr support.
#
# Needs the workload to grant SYS_ADMIN et al. via securityContext.capabilities.
set -euo pipefail

export PATH=/root/.nix-profile/bin:$PATH
NIX="nix --extra-experimental-features nix-command --extra-experimental-features flakes"

echo "== installing tooling (sequential; multi-package install conflicts) =="
for p in buildkit runc gnutar gzip git cacert crane gcc binutils; do
  $NIX profile install "nixpkgs#$p" >/dev/null 2>&1 && echo "  ok: $p" || echo "  SKIP: $p"
done
export PATH=/root/.nix-profile/bin:$PATH

echo "== starting buildkitd (root on tmpfs) =="
pkill buildkitd 2>/dev/null || true
sleep 2
rm -rf /dev/shm/buildkit /run/buildkit
mkdir -p /dev/shm/buildkit /run/buildkit
nohup buildkitd --root /dev/shm/buildkit --addr unix:///run/buildkit/buildkitd.sock \
  > /tmp/buildkitd.log 2>&1 &
sleep 12
if grep -q 'running server' /tmp/buildkitd.log; then
  echo "buildkitd up"
else
  echo "buildkitd FAILED"; tail -5 /tmp/buildkitd.log; exit 1
fi

cat > /root/.buildbox-env <<'EOF'
export PATH=/root/.nix-profile/bin:$PATH
export BUILDKIT_HOST=unix:///run/buildkit/buildkitd.sock
EOF
echo "ready — source /root/.buildbox-env"
