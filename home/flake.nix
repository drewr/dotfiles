{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #    home-manager.url = "github:nix-community/home-manager/release-25.05"; # Match stateVersion
    home-manager.url = "https://github.com/nix-community/home-manager/commit/86b95fc1ed2b9b04a451a08ccf13d78fb421859c";
    home-manager.inputs.nixpkgs.follows = "nixpkgs"; # Crucial for consistent Nixpkgs version
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
