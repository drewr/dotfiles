# -*- sh -*-
[[ -o interactive ]] && echo "+++Reading .zshenv."

OS=$(uname -s); export OS
MANPATH=/opt/local/man:/usr/local/man:$MANPATH
WORDCHARS='*?_[]~=&;!#$%^(){}'
WORDCHARS=${WORDCHARS:s,/,,}
LEDGER_FILE=$HOME/.ledger; export LEDGER_FILE
EDITOR=vi; export EDITOR
EMAIL="andrew@raines.me"; export EMAIL
FULLNAME="Andrew Raines"; export FULLNAME

LC_CTYPE=en_US.UTF-8; export LC_CTYPE
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
# resolve SSH_AUTH_SOCK here, not only in update_auth_sock. Forwarding is the
# only source of signing keys: this machine keeps no local private keys, so
# the goal is to bind to a LIVE forwarded agent holding at least one key,
# never to a dead path or to a keyless socket. Priority:
#   1. an inherited SSH_AUTH_SOCK that is usable -- leave it alone
#   2. the stable ~/.ssh/ssh_auth_sock symlink, which ~/.ssh/rc refreshes on
#      every inbound SSH connection that brings a forwarded agent
#   3. the newest /tmp/ssh-*/agent.<pid> socket owned by us, for the windows
#      where ~/.ssh/rc hasn't refreshed the symlink: chains through the box,
#      mosh reconnects, and anything opened while sshd was already gone
# update_auth_sock (zsh.d/20-fns) reuses ssh_auth_sock_pick so long-lived
# interactive shells re-resolve before every command.
# gpg-agent's S.gpg-agent.ssh is deliberately not a candidate: the systemd
# user environment advertises it at boot even when it holds no identities,
# and an empty agent cannot sign anything.

# True when ssh can reach an agent at $1 that holds at least one identity.
# ssh-add -l exits 0 with identities, 1 when the agent is reachable but
# empty, and 2 when there is no agent (or the socket is dead). Only 0 is
# usable. Setting SSH_AUTH_SOCK explicitly reuses this for any candidate.
ssh_auth_sock_has_keys() {
  [[ -n $1 ]] || return 1
  # A forwarded socket whose ssh connection is half-dead accepts connections
  # but never answers, so ssh-add -l would block every shell start forever.
  # Bound it where a timeout command exists (coreutils, or gtimeout on macOS).
  local t
  for t in timeout gtimeout; do
    (( $+commands[$t] )) && { SSH_AUTH_SOCK=$1 $t 3 ssh-add -l >/dev/null 2>&1 </dev/null; return; }
  done
  SSH_AUTH_SOCK=$1 ssh-add -l >/dev/null 2>&1 </dev/null
}

ssh_auth_sock_ok() {
  # A /tmp/ssh-*/agent.<pid> socket names the sshd session that created it.
  # If that session is gone its socket file can linger; nothing listens on
  # it, so reject it instead of handing shells a dead path. /proc only
  # exists on Linux; elsewhere the glob never matches forwarded sockets.
  [[ -S $1 ]] || return 1
  [[ -d /proc ]] && [[ $1 == /tmp/ssh-*/agent.* ]] && [[ ! -e /proc/${1##*.} ]] && return 1
  ssh_auth_sock_has_keys $1
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
           /tmp/ssh-*/agent.*(N=Uom)
  do
    if [[ -n $s ]] && ssh_auth_sock_ok $s; then
      # Keep the export attribute: assigning to an unset variable leaves it
      # shell-local, so children (git, ssh, ssh-keygen) would not see it.
      export SSH_AUTH_SOCK=$s
      return
    fi
  done
  # No device is connected: leave nothing behind rather than a misleading
  # socket. git then fails with "user.signingKey needs to be set", which is
  # the honest answer under a zero-local-secrets design.
  unset SSH_AUTH_SOCK
}

ssh_auth_sock_pick
