#!/bin/sh
# Single-shot launcher for Spike 3. Intended to be piped into
#   datumctl compute exec <box> -- sh -s
# so that the whole spike runs in ONE exec call and survives nothing being
# persisted between calls (the instance filesystem resets).
#
# The source tarball is embedded below as base64 and decoded first.
set -e
export PATH=/root/.nix-profile/bin:$PATH

echo "== decode source =="
rm -rf /root/sp3
mkdir -p /root/sp3
cd /root/sp3
base64 -d > /tmp/sp3-src.tgz <<'SRC_EOF'
__SRC_B64__
SRC_EOF
tar xzf /tmp/sp3-src.tgz
rm -f ._*
ls

echo "== ensure docker credentials =="
if [ ! -f /root/.docker/config.json ]; then
  mkdir -p /root/.docker
  base64 -d > /root/.docker/config.json <<'DOCKER_EOF'
__DOCKER_B64__
DOCKER_EOF
fi

echo "== run boxrun =="
sh /root/sp3/boxrun.sh
