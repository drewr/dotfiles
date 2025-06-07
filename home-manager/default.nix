{ config, pkgs, system, ... }:

{
  home.username = "aar";
  home.homeDirectory = "/Users/aar";
  home.stateVersion = "22.05";

  home.packages = [
    pkgs.autossh
    pkgs.awscli
    pkgs.emacs
    pkgs.fzf
    pkgs.gnupg
    pkgs.htop
    pkgs.jq
    pkgs.keychain
    pkgs.pandoc
    pkgs.ripgrep
    pkgs.s6-dns
    pkgs.tcping-go
    pkgs.tmux
    pkgs.xh
    pkgs.xz


    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    (pkgs.writeShellScriptBin "latency-tcp" ''
      #!/bin/sh
      
      while true; do
        /bin/echo -n `date +%H:%M` \'\'
        tcping -c 1 dns9.quad9.net | grep -E 'time=|failed:'
        sleep 11
      done
    '')
  ];

  home.file = {
    ".gitconfig".source = ./d/gitconfig;
    ".tmux.conf".source = ./d/tmux.conf;

    ".config/home-manager/current-config".text = ''
      hoping to put in ${config.home.release}
    '';
  };

  home.sessionVariables = {
    HM_VERSION = "THIS SHOULD GET A VALUE FROM config";
  };

  programs.home-manager.enable = true;
}


