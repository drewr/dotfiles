{ config, pkgs, system, ... }:

{
  home.packages = [
  ];

  home.file = {
    "bin/gh-user-activity".source = ./d/bin/gh-user-activity;
  };
}
