[[ -o interactive ]] && echo "+++Reading .zshenv"

OS=$(uname -s); export OS
MANPATH=/opt/local/man:/usr/local/man:$MANPATH
WORDCHARS='*?_[]~=&;!#$%^(){}'
WORDCHARS=${WORDCHARS:s,/,,}
LEDGER_FILE=$HOME/.ledger; export LEDGER_FILE
EDITOR=vi; export EDITOR
EMAIL="andrew@raines.me"; export EMAIL
FULLNAME="Andrew Raines"; export FULLNAME

export JAVA_HOME
[[ $OS == "Darwin" ]] && \
   JAVA_HOME=$(/usr/libexec/java_home -v 1.8)

## With Emacs 23, I've found this needs to go in ~root/.zshrc too to
## help with Tramp hangs.
if [[ $TERM == "dumb" ]]; then
  unsetopt zle
  PS1='$ '
  PAGER=cat; export PAGER
fi

[[ ! $TERM == "dumb" ]] && TERM=xterm-256color
