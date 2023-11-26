{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "aar";
  home.homeDirectory = "/Users/aar";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.05";

  home.packages = [
    pkgs.autossh
    pkgs.fennel
    pkgs.fzf
    pkgs.gnupg
    pkgs.htop
    pkgs.jq
    pkgs.keychain
    pkgs.mcfly
    pkgs.minikube
    pkgs.s6-dns
    pkgs.tmux
    pkgs.xh
    pkgs.xz

    ## emacs
    pkgs.pandoc
    pkgs.emacs29
  ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
