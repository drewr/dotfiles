[[ -o interactive ]] && echo "+++Reading .zshenv (for interactive use)."

OS=$(uname -s); export OS
PATH=/opt/local/bin:/opt/local/sbin:$PATH
PATH=/usr/local/bin:/usr/local/sbin:$PATH
PATH=~/bin:$PATH
MANPATH=/opt/local/man:/usr/local/man:$MANPATH
WORDCHARS='*?_[]~=&;!#$%^(){}'
WORDCHARS=${WORDCHARS:s,/,,}
LEDGER_FILE=$HOME/.ledger; export LEDGER_FILE
JARHOME=$HOME/tmp/src/jar; export JARHOME
EMAIL="aaraines@gmail.com"; export EMAIL
FULLNAME="Drew Raines"; export FULLNAME

export JAVA_HOME
[[ $OS == "Darwin" ]] && JAVA_HOME=/System/Library/Frameworks/JavaVM.framework/Versions/1.6/Home
[[ $TERM == "dumb" ]] && unsetopt zle && PS1='$ '
