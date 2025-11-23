{ config, pkgs, system, una, ... }:

{
  home.packages = [
    pkgs.mpv
    pkgs.msmtp
    pkgs.python3Packages.grip
  ];

  home.file = {
    ".Xresources".source = ./d/X11/Xresources;
    ".Xmodmap".source = ./d/X11/Xmodmap;
    ".Xdefaults".source = ./d/X11/Xdefaults;
    ".xinitrc".source = ./d/X11/xinitrc;
    ".config/ghostty/config".source = ./d/ghostty.conf;
  };
}
