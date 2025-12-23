{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
  };

  outputs = { self, nixpkgs, home-manager, una-src, zigutils }:
  let
    homeModules = [
      ./default.nix
      ./util.nix
      ./clojure.nix
      ./desktop.nix
      ./network.nix
    ];

    buildUna = pkgs: pkgs.haskell.packages.ghc98.callCabal2nix "una" una-src {};
    mkUnaPackage = system: buildUna nixpkgs.legacyPackages.${system};

    mkHomeConfig = system: username: unaPackage: extraModules:
      let
        pkgs = nixpkgs.legacyPackages.${system};
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
              zigutils.packages.${system}.nix-zsh-env
            ];
            home.username = username;
            home.homeDirectory = homeDirectory;
          }
        ];
        extraSpecialArgs = { una = unaPackage; };
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
        zigutils.packages.${system}.nix-zsh-env
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
