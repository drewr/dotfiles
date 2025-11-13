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
  };

  outputs = { self, nixpkgs, home-manager, una-src }:
  let
    homeModules = [
      ./default.nix
      ./util.nix
      ./clojure.nix
      ./desktop.nix
      ./network.nix
    ];

    mkHomeConfig = system: username: extraModules:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        unaPackage = pkgs.haskell.packages.ghc98.callCabal2nix "una" una-src {};
        homeDirectory =
          if pkgs.stdenv.isDarwin
          then "/Users/${username}"
          else "/home/${username}";
      in
      home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = homeModules ++ extraModules ++ [
          {
            home.packages = [ unaPackage ];
            home.username = username;
            home.homeDirectory = homeDirectory;
          }
        ];
        extraSpecialArgs = { una = unaPackage; };
      };
  in {
    homeManagerModules.default = { pkgs, ... }:
      let
        unaPackage = pkgs.haskell.packages.ghc98.callCabal2nix "una" una-src {};
      in {
        imports = homeModules;
        home.packages = [ unaPackage ];
        _module.args.una = unaPackage;
      };

    homeConfigurations = {
      "aar@aarch64-darwin" = mkHomeConfig "aarch64-darwin" "aar" [];
      "drewr@aarch64-darwin" = mkHomeConfig "aarch64-darwin" "drewr" [];

      "aar@x86_64-linux" = mkHomeConfig "x86_64-linux" "aar" [];
      "drewr@x86_64-linux" = mkHomeConfig "x86_64-linux" "drewr" [];

      "aar@aarch64-linux" = mkHomeConfig "aarch64-linux" "aar" [];
      "drewr@aarch64-linux" = mkHomeConfig "aarch64-linux" "drewr" [];
    };
  };
}
