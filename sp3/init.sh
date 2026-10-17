#!/bin/sh
# Spike 3 entrypoint: run the Node capability probe inside the unikernel.
set -e
export PATH=/command:/sbin:/bin
echo "[sp3] starting node probe"
exec /bin/node /probe/forktest.js
