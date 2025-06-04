{
  description = "My Home Manager configuration";

  # inputs = {
  #   nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05"; # Or a specific branch/commit
  #   home-manager.url = "github:nix-community/home-manager/release-24.05"; # Match stateVersion
  #   home-manager.inputs.nixpkgs.follows = "nixpkgs"; # Crucial for consistent Nixpkgs version
  # };

  outputs = inputs@{ nixpkgs, home-manager, ... }: {
    homeConfigurations."yourusername" = home-manager.lib.homeManagerConfiguration {
      inherit (inputs) nixpkgs; # Pass nixpkgs to home.nix
      # Or: pkgs = import nixpkgs { system = "x86_64-linux"; }; # If you want to specify system here
      modules = [
        ./home/default.nix # This is the link to your main Home Manager config
      ];

      # You can pass extra arguments to your home.nix like this:
      # extraSpecialArgs = {
      #   myCustomArg = "hello";
      # };
    };
  };
}
