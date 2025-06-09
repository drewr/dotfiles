{ config, pkgs, system, ... }:

{
  home.packages = [
    pkgs.babashka
    pkgs.clojure
    pkgs.leiningen
  ];

  home.file = {
    ".lein/profiles.clj".source = ./d/lein/profiles.clj;
    ".foo".source = ./../home/foo;
  };
}
