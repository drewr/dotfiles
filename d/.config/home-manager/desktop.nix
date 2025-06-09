{ config, pkgs, system, una, ... }:

{
  home.packages = [
  ];

  home.file = {
    ".Xresources".source = ./d/X11/Xresources;
    ".Xmodmap".source = ./d/X11/Xmodmap;
    ".Xdefaults".source = ./d/X11/Xdefaults;
    ".xinitrc".source = ./d/X11/xinitrc;
  };
}
