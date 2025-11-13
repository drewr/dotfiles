{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    utils.url = "github:numtide/flake-utils";
    una = {
      url = "github:jwiegley/una";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, utils, una }:
  let
    una = pkgs.haskell.packages.ghc98.callCabal2nix "una" una {};
    homeModules = [
      ./default.nix
      ./util.nix
      ./clojure.nix
      ./desktop.nix
      ./network.nix
    ];
  in {
    homeManagerModules.default = { pkgs, ... }: {
      imports = homeModules ++ [
        {
          home.packages = [ una ];
        }
      ];
      _module.args.una = una;
    };
    
    homeConfigurations.aar = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = homeModules;
      extraSpecialArgs = { inherit una; };
    };

    legacyPackages = utils.lib.eachDefaultSystemMap (system: {
      homeConfigurations.aar = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = homeModules;
        extraSpecialArgs = { inherit una; };
      };
      homeConfigurations.drewr = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = homeModules ++ [
          {
            home.username = "drewr";
            home.homeDirectory = "/home/drewr";
          }
        ];
        extraSpecialArgs = { inherit una; };
      };
    });
  };
}


