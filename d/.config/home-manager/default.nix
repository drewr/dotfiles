{ config, pkgs, lib, system, una, ... }:

{
  home.username = lib.mkDefault "aar";
  home.homeDirectory = lib.mkDefault "/home/aar";
  home.stateVersion = "22.05";

  home.packages = [
    pkgs.autossh
    pkgs.awscli2
    pkgs.curlFull
    pkgs.dnslookup
    pkgs.emacs
    pkgs.fzf
    pkgs.gh
    pkgs.git
    pkgs.gnupg
    pkgs.htop
    pkgs.ispell
    pkgs.jet
    pkgs.jq
    pkgs.jujutsu
    pkgs.keychain
    pkgs.gnumake
    pkgs.pandoc
    pkgs.ripgrep
    pkgs.simple-http-server
    pkgs.tmux
    # compile takes forever... ## una.packages.${pkgs.system}.default
    pkgs.xh
    pkgs.xz

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })
  ];

  home.file = {
    ".claude/settings.defaults.json".source = ./d/claude-settings-defaults.json;
    ".gitconfig".source = ./d/gitconfig;
    ".tmux.conf".source = ./d/tmux.conf;
    ".ssh/allowed_signers".source = ./d/ssh-allowed-signers;

    "bin/rand".source = ./d/bin/rand;

    ".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm
    '';

    ".config/home-manager/current-config".text = ''
      hoping to put in \$\{config.home\} at some point
    '';
  };

  home.sessionVariables = {
    HM_VERSION = "THIS SHOULD GET A VALUE FROM config";
  };

  home.activation.mergeClaudeSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    defaults="$HOME/.claude/settings.defaults.json"
    settings="$HOME/.claude/settings.json"
    if [ -f "$defaults" ]; then
      if [ -f "$settings" ]; then
        tmp=$(${pkgs.coreutils}/bin/mktemp)
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$defaults" "$settings" > "$tmp" \
          && mv "$tmp" "$settings"
      else
        ${pkgs.coreutils}/bin/install -Dm644 "$defaults" "$settings"
      fi
    fi
  '';

  programs.home-manager.enable = true;
}
