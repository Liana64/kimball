{ config, lib, pkgs, ... }:

let
  # TODO: set to the public hostname your friend will use.
  domain = "jelly.example.com";
  jellyfinPort = 8096; # nixarr default
  anubisPort = 8923; # Anubis listens here; Caddy proxies to it
in
{
  ##########################################################################
  # nixarr: Jellyfin + arr stack + qBittorrent (torrents via commercial VPN)
  ##########################################################################
  nixarr = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state/nixarr";

    # Commercial wg-quick VPN (e.g. Mullvad) used ONLY for torrent egress.
    # This is unrelated to Netbird. Keep wg.conf OUT of git / the Nix store.
    vpn = {
      enable = true;
      wgConf = "/data/.secret/wg.conf";
    };

    jellyfin.enable = true;

    # arr UIs bind to localhost (nixarr default). Reach them by SSH-forwarding
    # over Netbird, e.g.:  ssh -L 9696:localhost:9696 admin@<netbird-host>
    sonarr.enable = true;
    radarr.enable = true;
    bazarr.enable = true;
    prowlarr.enable = true;

    qbittorrent = {
      enable = true;
      vpn.enable = true; # route torrent traffic through nixarr.vpn
      peerPort = 50000;
    };
  };

  # After first boot, set Jellyfin Dashboard -> Networking:
  #   - Allow remote connections
  #   - Known Proxies: 127.0.0.1  (so real client IPs survive Caddy + Anubis)

  ##########################################################################
  # Anubis: bot wall in front of Jellyfin (challenges browser UAs, passes
  # native Jellyfin app UAs). Listens on a localhost TCP port for Caddy.
  ##########################################################################
  services.anubis.instances.jellyfin = {
    settings = {
      TARGET = "http://127.0.0.1:${toString jellyfinPort}";
      BIND = "127.0.0.1:${toString anubisPort}";
      BIND_NETWORK = "tcp";
    };
    # Built-in default rules: deny named AI bots, challenge Mozilla-UA browsers,
    # pass everything else (native apps). Add allowlist rules here only if a
    # real client gets challenged during the verification matrix.
    policy.useDefaultBotRules = true;
  };

  ##########################################################################
  # Caddy: public TLS endpoint on :8443. DNS-01 via Cloudflare (no inbound
  # 80/443 needed — sidesteps the AT&T gateway hijacking 443).
  ##########################################################################
  services.caddy = {
    enable = true;
    # TODO after first build: run `nixos-rebuild`, copy the hash Nix prints,
    # and replace lib.fakeHash. Confirm the plugin version resolves.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
      hash = lib.fakeHash;
    };
    email = "you@example.com"; # TODO: ACME contact
    # Cloudflare token (Zone.DNS) for the ACME DNS-01 challenge. File holds:
    #   CLOUDFLARE_API_TOKEN=<token>
    # Persistent, root-only (0600). Not in git / the Nix store.
    environmentFile = "/var/lib/secrets/caddy-cloudflare.env";
    # disable_redirects stops Caddy opening a port-80 redirect listener; with
    # acme_dns the cert comes via DNS-01 so port 80 is never needed.
    globalConfig = ''
      auto_https disable_redirects
      acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    '';
    virtualHosts."https://${domain}:8443".extraConfig = ''
      # Security headers ported from the home-infra Traefik secure-headers
      # middleware. The strict CSP and Cross-Origin-Embedder-Policy from that
      # stack are intentionally omitted — they break Jellyfin's web client
      # (scripts, artwork, media blobs). TLS 1.2/1.3 + strong ciphers are
      # already Caddy's defaults, matching the Traefik TLSOption.
      header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
        Content-Security-Policy "upgrade-insecure-requests;"
        Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
        X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, notranslate, noimageindex"
        X-Permitted-Cross-Domain-Policies "none"
        -Server
        -X-Powered-By
      }
      reverse_proxy 127.0.0.1:${toString anubisPort}
    '';
  };

  ##########################################################################
  # Dynamic DNS: keep the A record pointed at the dynamic WAN IP.
  ##########################################################################
  services.cloudflare-dyndns = {
    enable = true;
    domains = [ domain ];
    apiTokenFile = "/var/lib/secrets/cloudflare-dyndns-token";
  };
}
