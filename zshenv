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
# zshrc, so agent-forwarded git signing works from cron, editors and agents.
# ~/.ssh/rc keeps the symlink current on each inbound SSH connection;
# update_auth_sock (zsh.d/20-fns) refines it per tmux session. The -S test
# skips a dangling link left behind when an agent dies.
if [[ -S ~/.ssh/ssh_auth_sock ]]; then
  export SSH_AUTH_SOCK=~/.ssh/ssh_auth_sock
fi
