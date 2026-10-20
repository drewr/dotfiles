#!/usr/bin/env bash
# Client side: build an image on the EC2 build box's BuildKit, over iroh.
#
#   BUILDBOX_TICKET=<ticket> buildbox/ec2/build.sh sp3 ghcr.io/drewr/sp3-node:dev
#   BUILDBOX_TICKET=<ticket> buildbox/ec2/build.sh agent ghcr.io/drewr/agent-pi:dev \
#       --build-arg HARNESS=pi       # extra arguments go to datumctl compute build
#
# Needs only dumbpipe and datumctl locally. The heavy work (nix, BuildKit solve)
# runs on the box; datumctl then packages and pushes the image from here, so the
# client downloads the rootfs and uploads the image (~300 MB for sp3).
set -euo pipefail
ctx=${1:?usage: build.sh CONTEXT IMAGE [DATUMCTL-BUILD-ARGS...]}
image=${2:?usage: build.sh CONTEXT IMAGE [DATUMCTL-BUILD-ARGS...]}
shift 2
: "${BUILDBOX_TICKET:?set BUILDBOX_TICKET (buildbox/ec2/provision.sh ticket)}"
port=${BUILDBOX_PORT:-12340}

dumbpipe connect-tcp --addr "127.0.0.1:$port" "$BUILDBOX_TICKET" &
pipe=$!
trap 'kill $pipe 2>/dev/null' EXIT
for _ in $(seq 30); do
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break
  sleep 1
done

datumctl compute build --analyze --push \
  --buildkit-host "tcp://127.0.0.1:$port" -o "$image" "$@" "$ctx"
