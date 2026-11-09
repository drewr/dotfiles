# -*- sh -*-
[[ -o interactive ]] && echo "+++Reading .zshenv."

HOME_=$(readlink $(dirname $HOME))
if [[ -z $HOME_ ]]; then
  HOME_=$HOME
else
  HOME_=${HOME_}/$USER
fi

OS=$(uname -s); export OS
MANPATH=/opt/local/man:/usr/local/man:$MANPATH
WORDCHARS='*?_[]~=&;!#$%^(){}'
WORDCHARS=${WORDCHARS:s,/,,}
LEDGER_FILE=${HOME_}/.ledger; export LEDGER_FILE
EDITOR=vi; export EDITOR
EMAIL="andrew@raines.me"; export EMAIL
FULLNAME="Andrew Raines"; export FULLNAME

LC_CTYPE=en_US.UTF-8; export LC_CTYPE
LC_ALL=en_US.UTF-8; export LC_ALL
LANG=en_US.UTF-8; export LANG

# Every zsh reads this file, including non-interactive ones that never load
# zshrc (cron, editors, agent harnesses), so agent-forwarded git signing must
# resolve SSH_AUTH_SOCK here, not only in update_auth_sock. There can be more
# than one agent running (forwarded, keyring-spawned); the goal is to always
# bind to a LIVE socket, never a dead path. Priority:
#   1. an inherited SSH_AUTH_SOCK that is a live socket -- leave it alone
#   2. the stable ~/.ssh/ssh_auth_sock symlink, which ~/.ssh/rc refreshes on
#      every inbound SSH connection that brings a forwarded agent
#   3. the newest /tmp/ssh-*/agent.<pid> socket owned by us, for the windows
#      where ~/.ssh/rc hasn't refreshed the symlink: chains through the box,
#      mosh reconnects, and anything opened while sshd was already gone
#   4. the keyring agent, which exists even with no inbound SSH; key-less on
#      hosts that only hold the public half, but a valid socket beats none
# update_auth_sock (zsh.d/20-fns) reuses ssh_auth_sock_pick so long-lived
# interactive shells re-resolve before every command.
ssh_auth_sock_ok() {
  # A /tmp/ssh-*/agent.<pid> socket names the sshd session that created it.
  # If that session is gone its socket file can linger; nothing listens on
  # it, so reject it instead of handing shells a dead path.
  [[ -S $1 ]] || return 1
  [[ $1 == /tmp/ssh-*/agent.* ]] && [[ ! -e /proc/${1##*.} ]] && return 1
  return 0
}

ssh_auth_sock_pick() {
  if ssh_auth_sock_ok $SSH_AUTH_SOCK; then
    return
  fi
  local s
  # Glob only where sshd puts agent sockets instead of walking all of /tmp,
  # which holds hundreds of thousands of Nix build files and took seconds.
  # Qualifiers: N no match is fine, = sockets, U owned by us, om newest first.
  for s in $HOME/.ssh/ssh_auth_sock \
           /tmp/ssh-*/agent.*(N=Uom) \
           /run/user/$UID/keyring/.ssh
  do
    if [[ -n $s ]] && ssh_auth_sock_ok $s; then
      # Keep the export attribute: assigning to an unset variable leaves it
      # shell-local, so children (git, ssh, ssh-keygen) would not see it.
      export SSH_AUTH_SOCK=$s
      return
    fi
  done
  unset SSH_AUTH_SOCK
}

ssh_auth_sock_pick
