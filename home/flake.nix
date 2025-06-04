{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
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
