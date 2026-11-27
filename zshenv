# -*- sh -*-
[[ -o interactive ]] && echo "+++Reading .zshenv."

case $OSTYPE in
  darwin*) OS=Darwin ;;
  linux*)  OS=Linux ;;
  *)       OS=$(uname -s) ;;
esac
export OS
MANPATH=/opt/local/man:/usr/local/man:$MANPATH
LEDGER_FILE=$HOME/.ledger; export LEDGER_FILE
EDITOR=vi; export EDITOR
EMAIL="andrew@raines.me"; export EMAIL
FULLNAME="Andrew Raines"; export FULLNAME

LC_ALL=en_US.UTF-8; export LC_ALL
LANG=en_US.UTF-8; export LANG

# PATH and tool environment. This lives here, not in zshrc, because
# non-interactive shells (`ssh host cmd`, cron, editors, agent harnesses) read
# only this file, and they need to find the same programs a prompt would.
# Nothing in this file may print: output breaks scp, rsync and git over ssh.
#
# Each step prepends, so later entries win. -U drops duplicates, keeping the
# first occurrence, so re-prepending a directory moves it to the front.
typeset -U path PATH manpath MANPATH

_zshenv_prepend() {
  local d
  for d; do [[ -d $d ]] && path=($d $path); done
}

_zshenv_prepend /usr/local/sbin /usr/local/bin
_zshenv_prepend $HOME/.rbenv/shims $HOME/.rbenv/bin
_zshenv_prepend $HOME/.cabal/bin $HOME/.local/bin $HOME/.cargo/bin

[[ -s $HOME/.gvm/scripts/gvm ]] && . $HOME/.gvm/scripts/gvm

VOLTA_HOME=$HOME/.volta; export VOLTA_HOME
_zshenv_prepend $VOLTA_HOME/bin

[[ -r $HOME/perl5/perlbrew/etc/bashrc ]] && . $HOME/perl5/perlbrew/etc/bashrc

CLOJURESCRIPT_HOME=$HOME/src/clojure/clojurescript; export CLOJURESCRIPT_HOME
_zshenv_prepend $CLOJURESCRIPT_HOME/bin

[[ -r $HOME/.gcloud/path.zsh.inc ]] && . $HOME/.gcloud/path.zsh.inc

GOPATH=$HOME/go; export GOPATH
_zshenv_prepend $GOPATH/bin

# The Nix scripts also export NIX_PROFILES, NIX_SSL_CERT_FILE and
# XDG_DATA_DIRS. They skip themselves when a parent shell already ran them,
# so add the bin directories explicitly too, in case that parent's PATH was
# reset (sudo, systemd) while the guard variable survived.
if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
[[ -f $HOME/.nix-profile/etc/profile.d/nix.sh ]] && . $HOME/.nix-profile/etc/profile.d/nix.sh
_zshenv_prepend /nix/var/nix/profiles/default/bin $HOME/.nix-profile/bin
if [[ -d $HOME/.nix-profile/lib/locale ]]; then
  LOCALE_ARCHIVE="$(readlink $HOME/.nix-profile/lib/locale)/locale-archive"
  export LOCALE_ARCHIVE
fi

_zshenv_prepend $HOME/.nimble/bin $HOME/bin

# Requires `nix-env -i opam && opam init`. Its init.zsh loads completion and
# the precmd env hook only when the shell is interactive.
[[ -r $HOME/.opam/opam-init/init.zsh ]] && . $HOME/.opam/opam-init/init.zsh

_zshenv_prepend $HOME/.janet/bin $HOME/.npm/bin
[[ $OS == Darwin ]] && _zshenv_prepend /opt/local/sbin /opt/local/bin

unfunction _zshenv_prepend
export PATH

# On macOS, /etc/zprofile runs path_helper in login shells, which moves the
# system directories ahead of everything above. ~/.zprofile restores this.
_zshenv_path=($path)

# Every zsh reads this file, including non-interactive ones that never load
# zshrc (cron, editors, agent harnesses), so agent-forwarded git signing must
# resolve SSH_AUTH_SOCK here, not only in a preexec hook. The goal is to
# bind to a LIVE agent, never to a dead path, and to prefer an agent that
# holds keys over one that is merely reachable.
#
# Pass 1 takes the first candidate holding at least one identity:
#   1. an inherited SSH_AUTH_SOCK -- leave it alone
#   2. the stable ~/.ssh/ssh_auth_sock symlink, which ~/.ssh/rc refreshes on
#      every inbound SSH connection that brings a forwarded agent
#   3. the newest /tmp/ssh-*/agent.<pid> socket owned by us, for the windows
#      where ~/.ssh/rc hasn't refreshed the symlink: chains through the box,
#      mosh reconnects, and anything opened while sshd was already gone
# Pass 2, when none has keys, takes the first of those that answers but is
# empty, then (macOS) the launchd per-user agent. An empty agent is still
# worth binding to: it is the one keys get loaded into later (ssh-add, or
# macOS's launchd ssh-agent, which starts empty at every boot). But it must
# not win over a forwarded agent with keys -- e.g. gpg-agent's
# S.gpg-agent.ssh, which the systemd user environment advertises at boot even
# when it holds nothing, or the launchd agent a new Terminal window inherits
# while a device is forwarding into this Mac.
# zsh.d/20-fns also runs ssh_auth_sock_pick before every command, so
# long-lived interactive shells re-resolve.

_ssh_add_bound=()
if (( $+commands[timeout] )); then
  _ssh_add_bound=(timeout 3)
elif (( $+commands[gtimeout] )); then
  _ssh_add_bound=(gtimeout 3)
fi

# Classify the agent socket $1 by return status:
#   0  live, holds at least one identity
#   1  live, but holds no identities
#   2  unusable: not a socket, a dead sshd session's leftover, no agent
#      answering, or a half-dead forward that never answers
# These match ssh-add -l's own exit codes, except that a timeout counts as 2.
ssh_auth_sock_state() {
  # A /tmp/ssh-*/agent.<pid> socket names the sshd session that created it.
  # If that session is gone its socket file can linger; nothing listens on
  # it, so reject it instead of handing shells a dead path. /proc only
  # exists on Linux; elsewhere the glob never matches forwarded sockets.
  [[ -S $1 ]] || return 2
  [[ -d /proc ]] && [[ $1 == /tmp/ssh-*/agent.* ]] && [[ ! -e /proc/${1##*.} ]] && return 2
  # A forwarded socket whose ssh connection is half-dead accepts connections
  # but never answers, so ssh-add -l would block every shell start forever.
  # Bound it where a timeout command exists (coreutils, or gtimeout on macOS).
  local st
  SSH_AUTH_SOCK=$1 $_ssh_add_bound ssh-add -l >/dev/null 2>&1 </dev/null
  st=$?
  (( st <= 1 )) && return st
  return 2
}

# macOS only. The launchd agent's socket lives in a directory whose name is
# random per agent start (/var/run/com.apple.launchd.XXXXXX/Listeners), so the
# path cannot be hardcoded or cached -- a stale one is exactly how the symlink
# in ~/.ssh ends up dangling. launchd publishes it in the Aqua domain's
# environment only, so ssh sessions (launchctl managername: Background) never
# inherit it. Ask launchd, which is the only authority.
ssh_auth_sock_launchd() {
  [[ $OS == Darwin ]] || return 1
  launchctl print gui/$UID 2>/dev/null |
    sed -n 's/.*SSH_AUTH_SOCK => \(.*\)$/\1/p' | head -1
}

ssh_auth_sock_pick() {
  local s st empty
  # Glob only where sshd puts agent sockets instead of walking all of /tmp,
  # which holds hundreds of thousands of Nix build files and took seconds.
  # Qualifiers: N no match is fine, = sockets, U owned by us, om newest first.
  # Each candidate is probed once; the first live-but-empty one is remembered
  # for pass 2 so it never needs a second ssh-add round trip.
  for s in "$SSH_AUTH_SOCK" \
           $HOME/.ssh/ssh_auth_sock \
           /tmp/ssh-*/agent.*(N=Uom)
  do
    [[ -n $s ]] || continue
    ssh_auth_sock_state $s
    st=$?
    if (( st == 0 )); then
      # Keep the export attribute: assigning to an unset variable leaves it
      # shell-local, so children (git, ssh, ssh-keygen) would not see it.
      export SSH_AUTH_SOCK=$s
      return
    fi
    (( st == 1 )) && [[ -z $empty ]] && empty=$s
  done
  if [[ -n $empty ]]; then
    export SSH_AUTH_SOCK=$empty
    return
  fi
  # Last resort on macOS, and only after the cheap checks: preexec
  # runs this before every command.
  s=$(ssh_auth_sock_launchd)
  if [[ -n $s ]] && { ssh_auth_sock_state $s; (( $? <= 1 )) }; then
    export SSH_AUTH_SOCK=$s
    return
  fi
  # Nothing answers: leave nothing behind rather than a misleading socket.
  # Signing then fails visibly (ssh-signing-key reports no reachable agent).
  unset SSH_AUTH_SOCK
}

ssh_auth_sock_pick
