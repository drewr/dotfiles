{ system, config, pkgs, ... }:

let
  username = "aar";
  derivedHome =
    if system == "x86_64-linux" then "/home/${username}"
    else if system == "aarch64-linux" then "/home/${username}"
    else if system == "x86_64-darwin" then "/Users/${username}"
    else if system == "aarch64-darwin" then "/Users/${username}"
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
