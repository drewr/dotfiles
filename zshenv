[[ -o interactive ]] && echo "+++Reading .zshenv"

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

