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
# Shared home (optional; all from the shared Secret agent-home):
#   META_TICKET          dumbpipe ticket for the JuiceFS metadata Redis
#   META_URL             redis://:<password>@127.0.0.1:6379/1, through that tunnel
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY   bucket-scoped key for JuiceFS data
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

# Shared home: JuiceFS (data in S3, metadata in Redis reached over iroh) mounted
# at /home/agent and used as HOME by login shells, so every session sees the
# same ~/.claude and ~/work, as on a laptop. Per-session secrets stay in /root.
AGENT_HOME=/root
if [ -n "$META_TICKET" ] && [ -n "$META_URL" ]; then
  (
    while :; do
      # Without IROH_SECRET: that key belongs to the SSH listener, and two
      # endpoints with one key knock each other off the relay.
      /bin/env -u IROH_SECRET /bin/dumbpipe connect-tcp --addr 127.0.0.1:6379 "$META_TICKET" 2>&1 \
        | /bin/grep -v -e 'endpoint[a-z0-9]\{20\}'
      log "meta tunnel exited; restarting"
      sleep 2
    done
  ) &
  mkdir -p /home/agent /tmp/jfs-cache
  for _ in $(seq 30); do /bin/nc -z 127.0.0.1 6379 2>/dev/null && break; sleep 1; done
  # Cache lives in RAM (the root overlay is RAM-backed), so keep it bounded.
  # Dual-stack S3: some locations (staging us-east-1) have no IPv4 egress at
  # all, and JuiceFS rewrites the bucket URL to the IPv4-only endpoint.
  if AWS_USE_DUALSTACK_ENDPOINT=true /bin/juicefs mount --background --cache-dir /tmp/jfs-cache --cache-size 256 \
       --buffer-size 128 --log /tmp/juicefs.log "$META_URL" /home/agent; then
    AGENT_HOME=/home/agent
    mkdir -p /home/agent/work
    log "shared home mounted at /home/agent"
  else
    log "shared home mount FAILED; using /root ($(tail -3 /tmp/juicefs.log 2>/dev/null | tr '\n' ' '))"
  fi
fi
unset META_URL META_TICKET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# dropbear does not pass the container environment to sessions, so login
# shells read it from here.
{
  echo "export HOME=$AGENT_HOME"
  echo 'export PATH=/bin'
  echo 'export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt'
  echo 'export DISABLE_AUTOUPDATER=1'
  [ -n "$ANTHROPIC_API_KEY" ] && echo "export ANTHROPIC_API_KEY='$ANTHROPIC_API_KEY'"
} > /root/.agent-env
# shellcheck disable=SC2016  # expanded by the login shell, not here
printf '. /root/.agent-env\nmkdir -p "$HOME/work"; cd "$HOME/work"\n' > /root/.bash_profile
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
