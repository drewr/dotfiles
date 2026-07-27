{ config, pkgs, system, ... }:

{
  home.packages = [
  ];

  home.file = {
    "bin/gh-user-activity".source = ./d/bin/gh-user-activity;
    "bin/gh-assigned".source = ./d/bin/gh-assigned;
  };
}
