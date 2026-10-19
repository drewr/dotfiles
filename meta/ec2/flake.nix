{
  # JuiceFS metadata host for agent sandboxes: Redis on loopback, reachable only
  # over an iroh tunnel (dumbpipe). See meta/README.md. The box applies this config to
  # itself at first boot via user-data:
  #   nixos-rebuild switch --flake github:drewr/dotfiles/<rev>?dir=meta/ec2#agentmeta
  description = "JuiceFS metadata host for agent sandboxes";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    nixosConfigurations.agentmeta = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
        ./configuration.nix
      ];
    };
  };
}
