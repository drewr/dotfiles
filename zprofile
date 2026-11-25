# -*- sh -*-

# Login shells only, after /etc/zprofile. On macOS that file runs
# path_helper, which moves /usr/bin and friends ahead of the PATH zshenv
# built. Put zshenv's order back in front; typeset -U path (zshenv) drops the
# duplicates further down.
(( ${+_zshenv_path} )) && path=($_zshenv_path $path)
