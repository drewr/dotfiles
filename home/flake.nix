{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, home-manager, ... }:
    let
      system = builtins.currentSystem;
      pkgs = import nixpkgs { inherit system; };
    in
      {
        homeConfigurations.aar = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          inherit (pkgs.lib) lib;

          extraSpecialArgs = {
            inherit system;
          };

          modules = [
            ./default.nix
          ];
        };
      };
}
