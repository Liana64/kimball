# PLACEHOLDER — replace on the target machine.
# On the friend's box after a minimal NixOS install run:
#   nixos-generate-config --show-hardware-config > hardware-configuration.nix
# and commit the result. This stub only exists so the flake parses; it will
# NOT boot as-is (no real filesystems / bootloader device).
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
