[[ -o interactive ]] && echo "+++Reading .zshenv"

OS=$(uname -s); export OS
MANPATH=/opt/local/man:/usr/local/man:$MANPATH
WORDCHARS='*?_[]~=&;!#$%^(){}'
WORDCHARS=${WORDCHARS:s,/,,}
LEDGER_FILE=$HOME/.ledger; export LEDGER_FILE
EMAIL="aaraines@gmail.com"; export EMAIL
FULLNAME="Drew Raines"; export FULLNAME
OPSCODE_USER=sonian_devs; export OPSCODE_USER

export JAVA_HOME
[[ $OS == "Darwin" ]] && \
   JAVA_HOME=/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Home

## With Emacs 23, I've found this needs to go in ~root/.zshrc too to
## help with Tramp hangs.
[[ $TERM == "dumb" ]] && unsetopt zle && PS1='$ '
[[ ! $TERM == "dumb" ]] && TERM=xterm-256color
