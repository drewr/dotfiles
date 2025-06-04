{ config, pkgs, ... }:

let
  actualHome = builtins.getEnv "HOME";
  derivedHome =
    if pkgs.stdenv.isLinux then actualHome
    else if pkgs.stdenv.isDarwin then actualHome
    else "/home/${config.home.username}";
in
{
  programs.home-manager.enable = true;
  home.username = "aar";
  home.homeDirectory = builtins.path derivedHome;
  home.stateVersion = "22.05";
  home.file.".gitconfig".source = ./d/gitconfig;
  home.file.".somedir/xinitrc".source = ./d/xinitrc;
}

