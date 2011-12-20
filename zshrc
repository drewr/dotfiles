echo -n "+++Reading .zshrc"
[[ -o interactive ]] && echo -n " (for interactive use)"
echo .

autoload -U compinit zrecompile

zsh_cache=${HOME}/.zsh-cache
mkdir -p $zsh_cache

if [ $UID -eq 0 ]; then
  compinit
else
  compinit -d $zsh_cache/zcomp-$HOST

  for f in ~/.zshrc $zsh_cache/zcomp-$HOST; do
    zrecompile -p $f && rm -f $f.zwc.old
  done
fi

setopt EXTENDED_GLOB
for zshrc in ~/.zsh.d/[0-9][0-9]*[^~] ; do
  if [[ ! -z $ZSHDEBUG ]]; then
    echo +++ $(basename $zshrc)
  fi
  source $zshrc
done
unsetopt EXTENDED_GLOB

[[ -f ~/.zsh.d/zsh.${OS} ]] && source ~/.zsh.d/zsh.${OS}

# Move these from zshenv because /etc/zprofile will overwrite.
PATH=/usr/local/bin:/usr/local/sbin:$PATH
[[ -d $HOME/.rbenv ]] && PATH=$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH

CLOJURESCRIPT_HOME=$HOME/src/clojurescript; export CLOJURESCRIPT_HOME
[[ -d $CLOJURESCRIPT_HOME ]] && PATH=$CLOJURESCRIPT_HOME/bin:$PATH

GOROOT=$HOME/src/go; export GOROOT
[[ -d $GOROOT ]] && PATH=$GOROOT/bin:$PATH

PATH=$HOME/bin:$PATH
