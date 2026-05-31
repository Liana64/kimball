{
  description = "Media server stack based on nixarr";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixarr.url = "github:nix-media-server/nixarr";
    nixarr.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixarr, ... }: {
    nixosConfigurations.media = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit self; };
      modules = [
        nixarr.nixosModules.default
        ./hardware-configuration.nix
        ./configuration.nix
        ./media.nix
      ];
    };
  };
}
