#!/bin/sh
# Spike 4 entrypoint: dropbear on loopback, exposed over iroh by dumbpipe.
# IROH_SECRET comes from a Datum Secret (secretKeyRef), so the endpoint id and
# ticket are known to the client in advance. Both daemons are restarted if they
# exit, and every exit is logged.
export PATH=/bin
export HOME=/root

echo "[sp4] kernel: $(uname -a)"
echo "[sp4] links before: $(ip -o link 2>&1 | tr -s ' ' | tr '\n' ';')"
# The instance comes up with lo unconfigured (no 127.0.0.1), so a loopback-only
# dropbear is unreachable. Configure it before starting anything.
ip link set lo up 2>&1 | sed 's/^/[sp4] lo up: /'
ip addr add 127.0.0.1/8 dev lo 2>&1 | sed 's/^/[sp4] lo v4: /'
ip -6 addr add ::1/128 dev lo 2>&1 | sed 's/^/[sp4] lo v6: /'
echo "[sp4] lo after: $(ip -o addr show dev lo 2>&1 | tr -s ' ' | tr '\n' ';')"
echo "[sp4] resolv.conf: $(tr '\n' ' ' < /etc/resolv.conf 2>/dev/null)"
echo "[sp4] addrs: $(ip -o addr 2>/dev/null | tr -s ' ' | tr '\n' ';')"
echo "[sp4] /dev/pts: $(ls /dev/pts 2>&1 | tr '\n' ' ')"
[ -n "$IROH_SECRET" ] && echo "[sp4] IROH_SECRET set" || echo "[sp4] IROH_SECRET missing: random endpoint key"

(
  while :; do
    # -R: generate host keys on first connection; -F: foreground; -E: log to
    # stderr; -s: no passwords. Absolute path: Unikraft execve has no PATH search.
    /bin/dropbear -R -F -E -s -p 127.0.0.1:2222
    echo "[sp4] dropbear exited rc=$?; restarting"
    sleep 2
  done
) &

sleep 1
[ -n "$IROH_SECRET" ] && echo "[sp4] ticket: $(/bin/dumbpipe generate-ticket 2>&1)"

while :; do
  RUST_LOG=dumbpipe=debug /bin/dumbpipe listen-tcp --host 127.0.0.1:2222
  echo "[sp4] dumbpipe exited rc=$?; restarting"
  sleep 5
done
