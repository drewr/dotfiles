{
  description = "My Home Manager configuration";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" "https://cache.nixos.org" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "cache.nixos.org-1:6NCHd0Y9XMDA9/4lQpJzN3fPXMmHIvWtGBJpvGm0w1g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Pinned to the rev where ghc-9.8.4 is in cache.nixos.org; do not bump
    # without verifying the new rev's ghc98 derivation is cached.
    nixpkgs-haskell.url = "github:nixos/nixpkgs/b12141ef619e0a9c1c84dc8c684040326f27cdcc";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    una-src = {
      url = "github:jwiegley/una";
      flake = false;
    };
    zigutils = {
      url = "github:drewr/zigutils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    datumctl = {
      url = "github:datum-cloud/datumctl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-haskell, home-manager, una-src, zigutils, datumctl, llm-agents }:
  let
    homeModules = [
      ./default.nix
      ./util.nix
      ./clojure.nix
      ./desktop.nix
      ./network.nix
    ];

    buildUna = pkgs: nixpkgs-haskell.legacyPackages.${pkgs.system}.haskell.packages.ghc98.callCabal2nix "una" una-src {};
    mkUnaPackage = system: buildUna nixpkgs.legacyPackages.${system};

    mkHomeConfig = system: username: unaPackage: extraModules:
      let
        pkgs = import nixpkgs { system = system; config.allowUnfree = true; };
        homeDirectory =
          if pkgs.stdenv.isDarwin
          then "/Users/${username}"
          else "/home/${username}";
      in
      home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = homeModules ++ extraModules ++ [
          {
            home.packages = [
              unaPackage
              zigutils.packages.${pkgs.system}.nix-zsh-env
              zigutils.packages.${pkgs.system}.gitclone
              llm-agents.packages.${pkgs.system}.claude-code
              datumctl.packages.${pkgs.system}.default
              llm-agents.packages.${pkgs.system}.gemini-cli
              llm-agents.packages.${pkgs.system}.codex
              llm-agents.packages.${pkgs.system}.opencode
            ];
            home.username = username;
            home.homeDirectory = homeDirectory;
          }
        ];
        extraSpecialArgs = {
          una = unaPackage;
        };
      };

    systems = {
      aarch64-darwin = mkUnaPackage "aarch64-darwin";
      x86_64-linux = mkUnaPackage "x86_64-linux";
      aarch64-linux = mkUnaPackage "aarch64-linux";
    };
  in {
    homeManagerModules.default = { pkgs, ... }: {
      imports = homeModules;
      home.packages = [
        (buildUna pkgs)
        zigutils.packages.${pkgs.system}.nix-zsh-env
        zigutils.packages.${pkgs.system}.gitclone
        llm-agents.packages.${pkgs.system}.claude-code
        datumctl.packages.${pkgs.system}.default
        llm-agents.packages.${pkgs.system}.gemini-cli
        llm-agents.packages.${pkgs.system}.codex
        llm-agents.packages.${pkgs.system}.opencode
      ];
      _module.args.una = buildUna pkgs;
    };

    homeConfigurations = {
      "aar@aarch64-darwin" = mkHomeConfig "aarch64-darwin" "aar" systems.aarch64-darwin [];
      "drewr@aarch64-darwin" = mkHomeConfig "aarch64-darwin" "drewr" systems.aarch64-darwin [];

      "aar@x86_64-linux" = mkHomeConfig "x86_64-linux" "aar" systems.x86_64-linux [];
      "drewr@x86_64-linux" = mkHomeConfig "x86_64-linux" "drewr" systems.x86_64-linux [];

      "aar@aarch64-linux" = mkHomeConfig "aarch64-linux" "aar" systems.aarch64-linux [];
      "drewr@aarch64-linux" = mkHomeConfig "aarch64-linux" "drewr" systems.aarch64-linux [];
    };
  };
}
