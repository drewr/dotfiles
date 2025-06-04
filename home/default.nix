{ config, pkgs, ... }:

let
  username = "aar";
  derivedHome =
    if targetSystem == "x86_64-linux" then "/home/${username}"
    else if targetSystem == "aarch64-linux" then "/home/${username}"
    else if targetSystem == "x86_64-darwin" then "/Users/${username}"
    else if targetSystem == "aarch64-darwin" then "/Users/${username}"
    else "/home/${username}"; # Fallback
in
{
  programs.home-manager.enable = true;
  home.username = username;
  home.homeDirectory = derivedHome;
  home.stateVersion = "22.05";
  home.file.".gitconfig".source = ./d/gitconfig;
  home.file.".somedir/xinitrc".source = ./d/xinitrc;
}
