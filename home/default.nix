{ config, pkgs, ... }:

{
  programs.home-manager.enable = true;
  home.username = "aar";
  home.homeDirectory = /WHAT;
  home.stateVersion = "22.05";
  home.file.".gitconfig".source = ./d/gitconfig;
  home.file.".somedir/xinitrc".source = ./d/xinitrc;
}

