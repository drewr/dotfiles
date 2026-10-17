{
  # EC2 build box for Datum Compute images: BuildKit on loopback, reachable only
  # over an iroh tunnel (dumbpipe). See README.md. The box applies this config to
  # itself at first boot via user-data:
  #   nixos-rebuild switch --flake github:drewr/dotfiles/<rev>?dir=buildbox/ec2#buildbox
  description = "Datum Compute EC2 build box";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    nixosConfigurations.buildbox = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
        ./configuration.nix
      ];
    };
  };
}
