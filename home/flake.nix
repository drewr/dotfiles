{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    nixpkgs.rev = "c7c6a3a73ea54f8e5f7eb04618f5acea1cb34870";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.rev = "86b95fc1ed2b9b04a451a08ccf13d78fb421859c";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, home-manager, ... }: {
    homeConfigurations."aar" = home-manager.lib.homeManagerConfiguration {
      #inherit (inputs) nixpkgs; # Pass nixpkgs to home.nix
      pkgs = import nixpkgs { system = "aarch64-darwin"; };
      modules = [
        ./default.nix # This is the link to your main Home Manager config
      ];

      # You can pass extra arguments to your home.nix like this:
      # extraSpecialArgs = {
      #   myCustomArg = "hello";
      # };
    };
  };
}
