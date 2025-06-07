{
  description = "My Home Manager configuration";

  inputs = {
    utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    una.url = "github:jwiegley/una";
  };

  outputs = { self, nixpkgs, home-manager, utils, una }:
    utils.lib.eachDefaultSystem (system:
      let

      in
        {
          legacyPackages = {
            homeConfigurations.aar = home-manager.lib.homeManagerConfiguration {
              pkgs = import nixpkgs { inherit system; };
              inherit system;
              modules = [
                ./default.nix
              ];
            };
          };
        }
    );
}
