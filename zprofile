# -*- sh -*-

# Undo macOS path_helper (/etc/zprofile) reordering the PATH zshenv built.
(( ${+_zshenv_path} )) && path=($_zshenv_path $path)
