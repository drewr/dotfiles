#!/bin/sh
# Agent sandbox init. Configures loopback, installs the session's SSH keys,
# then supervises dropbear (loopback only) and dumbpipe (iroh endpoint).
#
# Environment, from the per-session Secret written by agent-sandbox:
#   IROH_SECRET          iroh endpoint secret key; the client derives the ticket
#   AUTHORIZED_KEYS_B64  base64 authorized_keys for root
#   SSH_HOST_KEY_B64     base64 OpenSSH ed25519 host key; the client pins it
#   ANTHROPIC_API_KEY    optional; otherwise run `claude /login` in the session
#   SESSION_NAME         hostname
# Programs run by absolute path: Unikraft's execve does no PATH search (H14).
export PATH=/bin
export HOME=/root
log() { echo "[agent] $*"; }

# lo is down with no addresses at boot (sp4/RESULTS.md).
/bin/ip link set lo up
/bin/ip addr add 127.0.0.1/8 dev lo
/bin/ip -6 addr add ::1/128 dev lo
[ -n "$SESSION_NAME" ] && /bin/hostname "$SESSION_NAME"

umask 077
mkdir -p /root/.ssh /root/work /etc/dropbear
echo "$AUTHORIZED_KEYS_B64" | /bin/base64 -d > /root/.ssh/authorized_keys
echo "$SSH_HOST_KEY_B64" | /bin/base64 -d > /run/host_key
/bin/dropbearconvert openssh dropbear /run/host_key /etc/dropbear/host_key >/dev/null 2>&1 \
  || log "host key conversion FAILED"
rm -f /run/host_key

# dropbear does not pass the container environment to sessions, so login
# shells read it from here.
{
  echo 'export PATH=/bin'
  echo 'export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt'
  echo 'export DISABLE_AUTOUPDATER=1'
  [ -n "$ANTHROPIC_API_KEY" ] && echo "export ANTHROPIC_API_KEY='$ANTHROPIC_API_KEY'"
} > /root/.agent-env
printf '. /root/.agent-env\ncd /root/work\n' > /root/.bash_profile
cp /root/.bash_profile /root/.profile
unset AUTHORIZED_KEYS_B64 SSH_HOST_KEY_B64 ANTHROPIC_API_KEY

log "mem: $(grep MemAvailable /proc/meminfo | tr -s ' ')"
log "keys: $(wc -l < /root/.ssh/authorized_keys) authorized; api key $(grep -q ANTHROPIC /root/.agent-env && echo set || echo unset)"

(
  while :; do
    /bin/dropbear -F -E -s -r /etc/dropbear/host_key -p 127.0.0.1:2222
    log "dropbear exited rc=$?; restarting"
    sleep 2
  done
) &

# Reachability of iroh's discovery server, which the client needs: the endpoint
# publishes its relay address there over HTTPS (pkarr), and clients look it up
# as a TXT record. Logged per address, because the network is IPv6-only (ULA)
# and publishing has been seen to hang silently.
for a in $(/bin/nslookup dns.iroh.link 2>/dev/null | /bin/awk '/^Address: /{print $2}'); do
  if /bin/nc -z -w 5 "$a" 443 2>/dev/null; then r=ok; else r=FAIL; fi
  log "dns.iroh.link $a:443 $r"
done

# Watchdog: if our discovery record is missing, restart dumbpipe so it publishes
# again. ENDPOINT_DNS is _iroh.<z32 id>.dns.iroh.link, from agent-sandbox.
(
  [ -n "$ENDPOINT_DNS" ] || exit 0
  sleep 30
  miss=0
  while :; do
    if /bin/nslookup -type=TXT "$ENDPOINT_DNS" 2>/dev/null | /bin/grep -q 'relay='; then
      [ $miss -gt 0 ] && log "discovery record present"
      miss=0
    else
      miss=$((miss + 1))
      log "discovery record missing ($miss)"
      [ $miss -ge 2 ] && { /bin/pkill -x dumbpipe; miss=0; }
    fi
    sleep 30
  done
) &

sleep 1
while :; do
  /bin/dumbpipe listen-tcp --host 127.0.0.1:2222 2>&1 | /bin/grep -v -e 'endpoint[a-z0-9]\{20\}'
  log "dumbpipe exited; restarting"
  sleep 5
done
