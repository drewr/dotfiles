#!/bin/sh
# Agent sandbox init. Configures loopback, installs the session's SSH keys,
# then supervises dropbear (loopback only) and dumbpipe (iroh endpoint).
#
# Environment, from the per-session Secret written by agent-sandbox:
#   IROH_SECRET          iroh endpoint secret key; the client derives the ticket
#   AUTHORIZED_KEYS_B64  base64 authorized_keys for root
#   SSH_HOST_KEY_B64     base64 OpenSSH ed25519 host key; the client pins it
#   PROVIDER_KEYS        names of the provider keys (from the shared Secret
#                        agent-providers) passed in as variables of those names,
#                        e.g. "ANTHROPIC_API_KEY TOKENROUTER_API_KEY"; optional.
#                        OAuth logins (claude /login, codex login, ...) persist
#                        in the shared home instead.
#   SESSION_NAME         hostname
# Shared home (optional; all from the shared Secret agent-home):
#   META_TICKET          dumbpipe ticket for the JuiceFS metadata Redis
#   META_URL             redis://:<password>@127.0.0.1:6379/1, through that tunnel
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY   bucket-scoped key for JuiceFS data
#   JFS_MOUNT_OPTS       extra `juicefs mount` options (word-split), from agent-sandbox
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
  # Mount at /mnt/agent-fs and use its home/ subdirectory as HOME: JuiceFS puts
  # virtual control files (.config, .stats, .accesslog, .trash) at the mount
  # root, and ~/.config being a JuiceFS file broke every XDG program.
  mkdir -p /mnt/agent-fs /home /tmp/jfs-cache
  for _ in $(seq 30); do /bin/nc -z 127.0.0.1 6379 2>/dev/null && break; sleep 1; done
  # Cache lives in RAM (the root overlay is RAM-backed), so keep it bounded.
  # Dual-stack S3: some locations (staging us-east-1) have no IPv4 egress at
  # all, and JuiceFS rewrites the bucket URL to the IPv4-only endpoint.
  # shellcheck disable=SC2086  # JFS_MOUNT_OPTS is a list of options
  if AWS_USE_DUALSTACK_ENDPOINT=true /bin/juicefs mount --background --cache-dir /tmp/jfs-cache --cache-size 256 \
       --buffer-size 128 --log /tmp/juicefs.log $JFS_MOUNT_OPTS "$META_URL" /mnt/agent-fs; then
    mkdir -p /mnt/agent-fs/home/work /work
    ln -sfn /mnt/agent-fs/home /home/agent
    AGENT_HOME=/home/agent
    log "shared home mounted at /home/agent"
    # Repos live in RAM under /work and persist to ~/work via ws (agent/ws).
    (HOME=/home/agent /bin/ws autosave) &
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
  echo 'export OPENCODE_CONFIG=/etc/agent/opencode.json'
  echo "export AGENT_HARNESS=$(cat /etc/agent/harness 2>/dev/null)"
  for k in $PROVIDER_KEYS; do
    case $k in ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;; esac   # names reach eval
    eval "v=\${$k:-}"
    # Single-quote the value; escape any single quotes inside it.
    # shellcheck disable=SC2154  # v is set by the eval above
    [ -n "$v" ] && printf "export %s='%s'\n" "$k" "$(printf '%s' "$v" | sed "s/'/'\\\\''/g")"
  done
} > /root/.agent-env
cat > /root/.bash_profile <<'PROFILE'
. /root/.agent-env
# ws open/clone print the RAM path of the workspace; land the shell there.
ws() {
  case ${1:-} in
    open|clone) local d; d=$(command ws "$@") && cd "$d" ;;
    close) command ws "$@" && case $PWD/ in /work/"$2"/*) cd ;; esac ;;
    *) command ws "$@" ;;
  esac
}
cd
PROFILE
cp /root/.bash_profile /root/.profile
# opencode provider config for the registry providers whose key is set (needs
# the keys and the network, so it runs here in the background).
# shellcheck disable=SC1091  # written above, at runtime
( . /root/.agent-env && /bin/agent-providers sync >/dev/null 2>&1 ) &
unset AUTHORIZED_KEYS_B64 SSH_HOST_KEY_B64
for k in $PROVIDER_KEYS; do case $k in ''|[0-9]*|*[!A-Za-z0-9_]*) ;; *) unset "$k" ;; esac; done

log "mem: $(grep MemAvailable /proc/meminfo | tr -s ' ')"
log "harness: $(cat /etc/agent/harness 2>/dev/null)"
log "keys: $(wc -l < /root/.ssh/authorized_keys) authorized; providers: $(echo "${PROVIDER_KEYS:-none}" | wc -w) key(s)"

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

# On shutdown, copy every workspace from RAM to the shared home first.
shutdown() {
  log "stopping: saving workspaces"
  [ "$AGENT_HOME" = /home/agent ] && HOME=/home/agent /bin/ws save --all 2>&1 | head -20
  log "stopped"
  exit 0
}
trap shutdown TERM INT

sleep 1
while :; do
  # Background + wait, so a signal runs the trap now rather than after dumbpipe.
  /bin/dumbpipe listen-tcp --host 127.0.0.1:2222 2>&1 | /bin/grep -v -e 'endpoint[a-z0-9]\{20\}' &
  wait $!
  log "dumbpipe exited; restarting"
  sleep 5
done
