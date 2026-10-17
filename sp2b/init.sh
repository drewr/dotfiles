#!/bin/sh
# Spike 2b workaround probe: bypass s6-svscan's PATH-based lookup of s6-supervise.
#
# s6-svscan fails to spawn s6-supervise with ENOENT. Hypothesis: Unikraft's execve
# does not perform PATH search for a bare program name. This wrapper:
#   1. proves a bare-name exec fails (execvp semantics test), and
#   2. drives s6-supervise with an ABSOLUTE path, which is what a working supervisor
#      would do anyway.
#
# If the absolute-path path works, s6-style supervision is viable on Unikraft via a
# thin launcher; only svscan's own lookup needs replacing.
set -e
export PATH=/command:/sbin:/bin

echo "[sp2b-init] busybox sh as init: pid=$$"
echo "[sp2b-init] testing PATH search for a bare name (execvp semantics):"
if command -v s6-supervise >/dev/null 2>&1; then
  echo "[sp2b-init] 'command -v s6-supervise' resolves to: $(command -v s6-supervise)"
else
  echo "[sp2b-init] 'command -v s6-supervise' NOT found"
fi

# Try a bare-name exec in a subshell; if Unikraft lacks PATH search this fails.
( exec s6-supervise /nonexistent-svc ) 2>/dev/null && echo "[sp2b-init] bare-name exec: started" \
  || echo "[sp2b-init] bare-name exec FAILED (exit $?) — confirms no PATH search"

echo "[sp2b-init] launching s6-supervise by ABSOLUTE path for /service/echo"
mkdir -p /service/echo
# s6-supervise daemonizes and scans /service/echo; it must be started for the dir.
exec /command/s6-supervise /service/echo </dev/null >/tmp/supervise.log 2>&1 &
SUP=$!
echo "[sp2b-init] s6-supervise started pid=$SUP"
sleep 3
echo "[sp2b-init] supervise log:"; cat /tmp/supervise.log 2>/dev/null || true

# Keep pid 1 alive and periodically report, standing in for a real supervisor loop.
i=0
while :; do
  i=$((i+1))
  echo "[sp2b-init] alive tick $i"
  sleep 3
done
