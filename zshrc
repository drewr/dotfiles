# -*- sh -*-
echo "+++Reading .zshrc."

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

for zshrc in ~/.zsh.d/[0-9][0-9]*[^~]; do
  [[ -n $ZSHDEBUG ]] && echo +++ ${zshrc:t}
  source $zshrc
done

[[ -f ~/.zsh.d/zsh.${OS} ]] && source ~/.zsh.d/zsh.${OS}
