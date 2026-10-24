#!/bin/sh
# Agent sandbox init. Configures loopback, installs the session's SSH keys,
# mounts the shared home, then supervises dropbear (loopback only) and dumbpipe
# (iroh endpoint). Logins land as the unprivileged user in /etc/agent/user.
#
# Environment, from the per-session Secret written by agent-sandbox:
#   IROH_SECRET          iroh endpoint secret key; the client derives the ticket
#   AUTHORIZED_KEYS_B64  base64 authorized_keys (for the user and root)
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

# Nix normalizes permissions in store outputs, so the image's modes for /tmp
# and /root don't survive; set them here.
chmod 1777 /tmp
chmod 0700 /root

U=$(cat /etc/agent/user 2>/dev/null || echo drewr)
UID_=$(/bin/id -u "$U")
as_user() { /bin/su "$U" -s /bin/sh -c "$1"; }

# nix: register the store paths shipped in the image (the store database lives
# on the RAM overlay and starts empty), then run the daemon the user talks to.
if [ -s /etc/agent/nix-registration ] && [ ! -e /nix/var/nix/db/db.sqlite ]; then
  if /bin/nix-store --load-db < /etc/agent/nix-registration 2>/tmp/nix-load-db.log; then
    log "nix: registered $(grep -c '^/nix/store/' /etc/agent/nix-registration) store paths"
  else
    log "nix: load-db FAILED: $(tail -2 /tmp/nix-load-db.log | tr '\n' ' ')"
  fi
fi
/bin/nix-daemon > /tmp/nix-daemon.log 2>&1 &

# lo is down with no addresses at boot (sp4/RESULTS.md).
/bin/ip link set lo up
/bin/ip addr add 127.0.0.1/8 dev lo
/bin/ip -6 addr add ::1/128 dev lo
[ -n "$SESSION_NAME" ] && /bin/hostname "$SESSION_NAME"

# SSH keys: dropbear -D reads authorized_keys from /etc/agent/ssh for every
# user, so the session's keys stay out of the shared home.
mkdir -p /etc/agent/ssh /etc/dropbear
echo "$AUTHORIZED_KEYS_B64" | /bin/base64 -d > /etc/agent/ssh/authorized_keys
chmod 0644 /etc/agent/ssh/authorized_keys
umask 077
echo "$SSH_HOST_KEY_B64" | /bin/base64 -d > /run/host_key
/bin/dropbearconvert openssh dropbear /run/host_key /etc/dropbear/host_key >/dev/null 2>&1 \
  || log "host key conversion FAILED"
rm -f /run/host_key
umask 022

# Shared home: JuiceFS (data in S3, metadata in Redis reached over iroh) mounted
# at /mnt/agent-fs; its home/ subdirectory is the user's HOME (/home/agent), so
# every session sees the same ~/.claude and ~/work, as on a laptop.
SHARED=0
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
  # Not the mount root: JuiceFS puts virtual control files (.config, .stats,
  # .accesslog, .trash) there, and ~/.config being one broke every XDG program.
  mkdir -p /mnt/agent-fs /home /tmp/jfs-cache
  for _ in $(seq 30); do /bin/nc -z 127.0.0.1 6379 2>/dev/null && break; sleep 1; done
  # Cache lives in RAM (the root overlay is RAM-backed), so keep it bounded.
  # Dual-stack S3: some locations (staging us-east-1) have no IPv4 egress at
  # all, and JuiceFS rewrites the bucket URL to the IPv4-only endpoint.
  # shellcheck disable=SC2086  # JFS_MOUNT_OPTS is a list of options
  if AWS_USE_DUALSTACK_ENDPOINT=true /bin/juicefs mount --background --cache-dir /tmp/jfs-cache --cache-size 256 \
       --buffer-size 128 --log /tmp/juicefs.log $JFS_MOUNT_OPTS "$META_URL" /mnt/agent-fs; then
    mkdir -p /mnt/agent-fs/home/work
    # Files written before the login user existed belong to root; hand them over once.
    if [ "$(stat -c %u /mnt/agent-fs/home)" != "$UID_" ]; then
      log "giving the shared home to $U"
      chown -R "$UID_:$UID_" /mnt/agent-fs/home
    fi
    ln -sfn /mnt/agent-fs/home /home/agent
    SHARED=1
    log "shared home mounted at /home/agent"
  else
    log "shared home mount FAILED; HOME is local ($(tail -3 /tmp/juicefs.log 2>/dev/null | tr '\n' ' '))"
  fi
fi
unset META_URL META_TICKET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
if [ $SHARED = 0 ]; then
  mkdir -p /home/local && chown "$UID_:$UID_" /home/local
  ln -sfn /home/local /home/agent
fi
mkdir -p /work && chown "$UID_:$UID_" /work

# dropbear does not pass the container environment to sessions, so login
# shells load it from /etc/agent/env (via /etc/zshenv and /etc/profile).
{
  echo 'export PATH=/bin'
  echo 'export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt'
  echo 'export DISABLE_AUTOUPDATER=1'
  echo 'export OPENCODE_CONFIG=/etc/agent/opencode.json'
  # Caches in RAM, per user: per-session anyway, and nix's tarball and eval
  # caches are thousands of small files that would be slow on JuiceFS.
  # shellcheck disable=SC2016  # expanded when a login shell loads the file
  echo 'export XDG_CACHE_HOME=/tmp/.cache-$(id -un)'
  echo "export AGENT_HARNESS=$(cat /etc/agent/harness 2>/dev/null)"
  cat /etc/agent/env.static 2>/dev/null
  for k in $PROVIDER_KEYS; do
    case $k in ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;; esac   # names reach eval
    eval "v=\${$k:-}"
    # Single-quote the value; escape any single quotes inside it.
    # shellcheck disable=SC2154  # v is set by the eval above
    [ -n "$v" ] && printf "export %s='%s'\n" "$k" "$(printf '%s' "$v" | sed "s/'/'\\\\''/g")"
  done
} > /etc/agent/env
chown "root:$UID_" /etc/agent/env && chmod 0640 /etc/agent/env
unset AUTHORIZED_KEYS_B64 SSH_HOST_KEY_B64
for k in $PROVIDER_KEYS; do case $k in ''|[0-9]*|*[!A-Za-z0-9_]*) ;; *) unset "$k" ;; esac; done

# ws open/clone print the RAM path of the workspace; land the shell there.
# shellcheck disable=SC2016  # a function for login shells, expanded there
WS_FN='ws() {
  case ${1:-} in
    open|clone) local d; d=$(command ws "$@") && cd "$d" ;;
    close) command ws "$@" && case $PWD/ in /work/"$2"/*) cd ;; esac ;;
    *) command ws "$@" ;;
  esac
}'
printf '%s\n' "$WS_FN" > /etc/zshrc
printf '%s\ncd\n' "$WS_FN" > /root/.bash_profile

# The user's home, as that user: the dotfiles' zsh config (linked from the
# image, so it tracks the image, unless the home already has its own),
# ~/go (01-env warns without it), and in the claude image Remote Control on
# at startup unless the user settings already decide it.
touch /etc/agent/opencode.json && chown "$UID_:$UID_" /etc/agent/opencode.json
# shellcheck disable=SC2016  # runs in the user's shell
as_user '
  cd "$HOME" || exit 0
  if [ -d /etc/agent/zsh ]; then
    for f in zshrc zshenv zprofile; do [ -e ".$f" ] || [ -L ".$f" ] || ln -s "/etc/agent/zsh/$f" ".$f"; done
    [ -e .zsh.d ] || [ -L .zsh.d ] || ln -s /etc/agent/zsh/zsh.d .zsh.d
  fi
  mkdir -p go
  if [ "$(cat /etc/agent/harness)" = claude ]; then
    mkdir -p .claude
    [ -s .claude/settings.json ] || echo "{}" > .claude/settings.json
    if ! jq -e "has(\"remoteControlAtStartup\")" .claude/settings.json >/dev/null 2>&1; then
      jq ". + {remoteControlAtStartup: true}" .claude/settings.json > .claude/settings.json.tmp \
        && mv .claude/settings.json.tmp .claude/settings.json
    fi
  fi
'

# opencode and pi provider config for the registry providers whose key is set
# (needs the keys and the network, so it runs in the background).
as_user '. /etc/agent/env && /bin/agent-providers sync' >/dev/null 2>&1 &
# Repos live in RAM under /work and persist to ~/work via ws (agent/ws).
[ $SHARED = 1 ] && as_user 'exec /bin/ws autosave' &

log "mem: $(grep MemAvailable /proc/meminfo | tr -s ' ')"
log "harness: $(cat /etc/agent/harness 2>/dev/null); login user: $U"
log "keys: $(wc -l < /etc/agent/ssh/authorized_keys) authorized; providers: ${PROVIDER_KEYS:-none}"

(
  while :; do
    /bin/dropbear -F -E -s -D /etc/agent/ssh -r /etc/dropbear/host_key -p 127.0.0.1:2222
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

# On shutdown, copy every workspace from RAM to the shared home first. (Datum
# deletes workloads without SIGTERM, so autosave and agent-sandbox rm matter more.)
shutdown() {
  log "stopping: saving workspaces"
  [ $SHARED = 1 ] && as_user '/bin/ws save --all' 2>&1 | head -20
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
