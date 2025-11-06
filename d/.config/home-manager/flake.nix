{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    utils.url = "github:numtide/flake-utils";
    una.url = "github:jwiegley/una";
  };

  outputs = { self, nixpkgs, home-manager, utils, una }:
  let
    homeModules = [
      ./default.nix
      ./clojure.nix
      ./desktop.nix
      ./network.nix
    ];
  in {
    homeManagerModules.default = { pkgs, ... }: {
      imports = homeModules;
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
    });
  };
}


