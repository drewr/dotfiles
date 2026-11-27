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

# PATH lives here so non-interactive shells (ssh host cmd, cron, editors)
# get it too. Nothing here may print: it breaks scp, rsync and git over ssh.
# Later prepends win; -U keeps the first occurrence.
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

# The Nix scripts skip themselves if a parent already ran them, so add their
# bin dirs explicitly in case that parent's PATH was reset (sudo, systemd).
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

[[ -r $HOME/.opam/opam-init/init.zsh ]] && . $HOME/.opam/opam-init/init.zsh

_zshenv_prepend $HOME/.janet/bin $HOME/.npm/bin
[[ $OS == Darwin ]] && _zshenv_prepend /opt/local/sbin /opt/local/bin

unfunction _zshenv_prepend
export PATH

# ~/.zprofile restores this order after macOS's path_helper.
_zshenv_path=($path)

# Bind SSH_AUTH_SOCK to a live agent, preferring one that holds keys. This
# runs here so non-interactive shells can sign too; zsh.d/20-fns reruns it
# before every command. Candidates, in order: the inherited value, the
# ~/.ssh/ssh_auth_sock symlink (kept by ~/.ssh/rc), sshd's own sockets, and
# on macOS the launchd agent. A live but empty agent is the fallback.

_ssh_add_bound=()
if (( $+commands[timeout] )); then
  _ssh_add_bound=(timeout 3)
elif (( $+commands[gtimeout] )); then
  _ssh_add_bound=(gtimeout 3)
fi

# Agent socket $1: 0 live with keys, 1 live but empty, 2 unusable.
ssh_auth_sock_state() {
  [[ -S $1 ]] || return 2
  # Leftover socket from an sshd session that has exited (Linux).
  [[ -d /proc ]] && [[ $1 == /tmp/ssh-*/agent.* ]] && [[ ! -e /proc/${1##*.} ]] && return 2
  # A half-dead forward never answers; the timeout keeps it from hanging.
  local st
  SSH_AUTH_SOCK=$1 $_ssh_add_bound ssh-add -l >/dev/null 2>&1 </dev/null
  st=$?
  (( st <= 1 )) && return st
  return 2
}

# macOS launchd agent. Its path is random per boot and ssh sessions don't
# inherit it, so ask launchd.
ssh_auth_sock_launchd() {
  [[ $OS == Darwin ]] || return 1
  launchctl print gui/$UID 2>/dev/null |
    sed -n 's/.*SSH_AUTH_SOCK => \(.*\)$/\1/p' | head -1
}

ssh_auth_sock_pick() {
  local s st empty
  # Glob qualifiers: N allow no match, = sockets, U ours, om newest first.
  for s in "$SSH_AUTH_SOCK" \
           $HOME/.ssh/ssh_auth_sock \
           /tmp/ssh-*/agent.*(N=Uom)
  do
    [[ -n $s ]] || continue
    ssh_auth_sock_state $s
    st=$?
    if (( st == 0 )); then
      export SSH_AUTH_SOCK=$s
      return
    fi
    (( st == 1 )) && [[ -z $empty ]] && empty=$s
  done
  if [[ -n $empty ]]; then
    export SSH_AUTH_SOCK=$empty
    return
  fi
  # Last, since launchctl is the slowest check.
  s=$(ssh_auth_sock_launchd)
  if [[ -n $s ]] && { ssh_auth_sock_state $s; (( $? <= 1 )) }; then
    export SSH_AUTH_SOCK=$s
    return
  fi
  # Nothing answers: unset rather than leave a dead path.
  unset SSH_AUTH_SOCK
}

ssh_auth_sock_pick
