{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    utils.url = "github:numtide/flake-utils";
    una.url = "github:jwiegley/una";
  };

  outputs = { self, nixpkgs, home-manager, utils, una }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        {
          legacyPackages = {
            homeConfigurations.aar = home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ./default.nix
                ./network.nix
              ];

              extraSpecialArgs = {
                inherit una;
              };
            };
          };
        }
    );
}


