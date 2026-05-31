{ self, config, lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "media";

  # Behind AT&T IP-passthrough the box holds the public IP directly, so the
  # firewall is the only WAN filter. Public WAN exposes 8443 (Caddy) ONLY.
  # Everything administrative is reachable solely over the Netbird mesh (wt0).
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 8443 ];
    trustedInterfaces = [ "wt0" ];
  };

  # Netbird client -> hosted Netbird cloud. Creates the default wt0 tunnel.
  # First join is a one-time manual step (out of band, keeps the key off-disk):
  #   netbird up --setup-key <SETUP_KEY>
  services.netbird.enable = true;
  services.resolved.enable = true; # required for Netbird *.netbird.cloud DNS

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    # SSH is not in allowedTCPPorts, so it is reachable only over wt0 (trusted).
    # Do NOT forward 22 at the gateway.
  };

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # TODO: paste the owner's SSH public key here.
    ];
  };

  # Unattended security updates from this flake. Set the flake ref to wherever
  # the repo lives on the box (or a remote git URL).
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos";
    flags = [ "--update-input" "nixpkgs" "--update-input" "nixarr" ];
    dates = "04:30";
    randomizedDelaySec = "30min";
    allowReboot = true;
    rebootWindow = { lower = "04:00"; upper = "06:00"; };
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  system.stateVersion = "26.05";
}
