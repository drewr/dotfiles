{ config, pkgs, system, ... }:

{
  home.packages = [
    pkgs.babashka
    pkgs.clojure
    pkgs.leiningen
  ];
}
