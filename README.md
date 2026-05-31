# Media server

A self-hosted **Jellyfin** media server with the **arr** automation stack
(Sonarr/Radarr/Bazarr/Prowlarr) and **qBittorrent**, built as a single NixOS flake.

This guide assumes **minimal NixOS experience**. Follow the steps in order.

## Overview

```
Internet ─8443─> AT&T gateway (IP passthrough) ─8443─> this box
                                                          │
   Cloudflare DNS (your hostname -> dynamic public IP, auto-updated)
                                                          │
     Caddy :8443 ──TLS──> Anubis (blocks scraper bots) ──> Jellyfin
                                                          │
   nixarr: Jellyfin + Sonarr/Radarr/Bazarr/Prowlarr + qBittorrent(via VPN)
                                                          │
     Netbird (private mesh) ── you administer arr apps + SSH, never public
```

- **Your friend** opens `https://YOUR-HOSTNAME:8443` (or the Jellyfin app) — that's all they touch.
- **You** administer everything else over a private Netbird tunnel; nothing admin is exposed publicly.

## VPNs

| VPN | Purpose | Where configured |
|-----|---------|------------------|
| Commercial VPN (e.g. Mullvad) | Hides **torrent** traffic only | `wg.conf` file + `nixarr.vpn` |
| Netbird | Private **admin** access (arr apps, SSH) | `services.netbird` |

---

## Prerequisites

1. A **domain** whose DNS is managed by **Cloudflare** (free plan is fine). You'll use a
   subdomain like `jelly.example.com`.
2. A **Cloudflare API token** scoped to `Zone › DNS › Edit` for that domain
   (Cloudflare dashboard → My Profile → API Tokens → Create Token → "Edit zone DNS").
3. A **commercial VPN** WireGuard config file for torrents (e.g. Mullvad → WireGuard →
   download a `.conf`).
4. A free **Netbird** account (https://app.netbird.io) and a **setup key**
   (Netbird dashboard → Setup Keys → create one).
5. Your **SSH public key** (the contents of `~/.ssh/id_ed25519.pub` on your laptop).
6. The **old computer**, plus a USB stick with the NixOS installer.

---

## 1. Install NixOS on the box

1. Download the **minimal ISO** from https://nixos.org/download (64-bit).
2. Write it to USB (`dd` / Rufus / balenaEtcher), boot the old computer from it.
3. Partition and install. This covers the common case: a single disk with UEFI boot.

   Run `lsblk` to find the disk name (often `/dev/sda` or `/dev/nvme0n1`). The steps
   below erase that disk, so confirm it's the right one first.

   Open it in fdisk:

   ```bash
   fdisk /dev/sda
   ```

   Enter these at the prompt. The first command, `g`, deletes any existing partitions
   and starts a fresh GPT table. Press Enter to accept each default in parentheses.

   - `g` — new GPT table
   - `n`, Enter, Enter, then `+512M` — a 512 MB boot partition
   - `t`, `1` — set its type to EFI System
   - `n`, Enter, Enter, Enter — a second partition filling the rest
   - `w` — write and exit

   Format and mount the two partitions, then generate the config and install. On nvme
   disks the partitions are `${D}p1` and `${D}p2` rather than `${D}1` and `${D}2`.

   ```bash
   D=/dev/sda

   mkfs.fat -F 32 -n boot ${D}1
   mkfs.xfs -L nixos ${D}2

   mount /dev/disk/by-label/nixos /mnt
   mkdir -p /mnt/boot
   mount /dev/disk/by-label/boot /mnt/boot

   nixos-generate-config --root /mnt
   nixos-install
   reboot
   ```

   On a legacy-BIOS machine, use the manual's BIOS partition steps instead; the rest of
   this guide is the same.
4. Reboot into the new system and log in as `root`.

## 2. Copy this config onto the box

Copy this repository to `/etc/nixos` on the box (replacing the generated config):

```bash
rm -rf /etc/nixos
git clone <this-repo-url> /etc/nixos    # or scp the folder over
cd /etc/nixos
```

## 3. Generate the hardware config

The included `hardware-configuration.nix` is only a placeholder. Generate the real one
**on the box** (this detects its disks/CPU):

```bash
nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
```

## 4. Fill in your settings

Open the files and fill in the `TODO`s:

- **`media.nix`**
  - `domain = "jelly.example.com";` → your real subdomain.
  - `email = "you@example.com";` → your email (for the TLS certificate).
- **`configuration.nix`**
  - Paste your SSH public key into `users.users.admin.openssh.authorizedKeys.keys`.

## 5. Create the secret files

Run these on the box as root. **Do not** put any of these in git.

```bash
# 1) Commercial VPN config for torrents (paste your Mullvad/etc WireGuard .conf):
mkdir -p /data/.secret
install -m 600 /dev/null /data/.secret/wg.conf
nano /data/.secret/wg.conf          # paste the full [Interface]/[Peer] config

# 2) Cloudflare token for TLS certificates (DNS-01):
mkdir -p /var/lib/secrets
printf 'CLOUDFLARE_API_TOKEN=%s\n' 'YOUR_CF_TOKEN' > /var/lib/secrets/caddy-cloudflare.env
chmod 600 /var/lib/secrets/caddy-cloudflare.env

# 3) Cloudflare token for dynamic DNS (can be the SAME token):
printf '%s' 'YOUR_CF_TOKEN' > /var/lib/secrets/cloudflare-dyndns-token
chmod 600 /var/lib/secrets/cloudflare-dyndns-token
```

## 6. Configure the AT&T gateway

The AT&T gateway likes to keep port 443 for itself, so we expose the server on **8443**.

1. Log into the gateway (usually http://192.168.1.254).
2. Enable **IP Passthrough** to this box (Firewall → IP Passthrough → DHCPS-fixed → pick
   the box). This hands the public IP to the box.
3. No port-forwarding rules are needed in passthrough mode. (If you keep NAT instead,
   forward external **8443 → box:8443**.)
4. Do **not** forward port 22 (SSH stays private over Netbird).

## 7. First build

```bash
cd /etc/nixos
nixos-rebuild switch --flake .#media
```

**Expected on the first run:** the build stops with a Caddy **hash mismatch** error
(because we ship `lib.fakeHash` for the Cloudflare DNS plugin). Copy the `got: sha256-…`
value it prints, paste it into `media.nix` replacing `lib.fakeHash`, then run the rebuild
again:

```nix
# media.nix
hash = "sha256-THE_VALUE_NIX_PRINTED=";
```

```bash
nixos-rebuild switch --flake .#media   # now succeeds
```

> If instead it complains the plugin **version** `@v0.2.1` can't be found, update that
> version string in `media.nix` to the latest tag at
> https://github.com/caddy-dns/cloudflare/tags and rebuild.

## 8. Join the Netbird mesh

```bash
netbird up --setup-key YOUR_NETBIRD_SETUP_KEY
netbird status        # should show "Connected"
```

Install the Netbird client on your own laptop/phone and log into the same account. `netbird
status` lists the box's Netbird IP — that IP (or the name Netbird assigns it) is the
`<netbird-host>` used in the SSH commands below.

## 9. Set up Jellyfin

1. From your laptop (on the Netbird mesh) open Jellyfin's local port via an SSH tunnel:
   ```bash
   ssh -L 8096:localhost:8096 admin@<netbird-host>
   ```
   then browse to `http://localhost:8096` and complete the setup wizard (create the admin
   account, add libraries).
2. In **Dashboard → Networking**: enable **Allow remote connections**, and set
   **Known Proxies** to `127.0.0.1` (so real viewer IPs survive Caddy + Anubis).

## 10. Set up the arr stack

Reach each app's web UI the same way (SSH tunnel over Netbird), e.g.:

```bash
ssh -L 9696:localhost:9696 admin@<netbird-host>   # Prowlarr at http://localhost:9696
```

Default local ports: Prowlarr `9696`, Sonarr `8989`, Radarr `7878`, Bazarr `6767`,
qBittorrent `8080`. Configure Prowlarr first (add indexers), then point Sonarr/Radarr at
Prowlarr and at qBittorrent.

---

## Verification

1. **Services up:** `systemctl status jellyfin sonarr radarr prowlarr qbittorrent caddy 'anubis-*'`
2. **Public path (from phone on cellular):**
   `curl https://YOUR-HOSTNAME:8443/System/Info/Public` → returns HTTP 200 + JSON.
3. **Friend's experience:** open the Jellyfin app, server address `YOUR-HOSTNAME:8443`, log in.
4. **Bot wall sanity:** a browser-style request gets challenged, an app-style one passes:
   ```bash
   curl -A "Mozilla/5.0" https://YOUR-HOSTNAME:8443/        # Anubis challenge page (HTML)
   curl -A "Jellyfin/1.0" https://YOUR-HOSTNAME:8443/System/Info/Public  # JSON, 200
   ```
   If any real client (TV, Roku, etc.) is blocked, add an allowlist rule under
   `services.anubis.instances.jellyfin.policy` and rebuild.
5. **Nothing else is public:** from off-network, `nmap YOUR-PUBLIC-IP` should show only 8443.
6. **Torrents are masked:** in qBittorrent, the public IP should be the VPN's, and stopping
   the VPN should stop torrent traffic.

## Updates

```bash
cd /etc/nixos
nix flake update          # pull newer nixpkgs / nixarr
nixos-rebuild switch --flake .#media
```

The box also auto-applies updates nightly (see `system.autoUpgrade` in `configuration.nix`).

## Backups

- `/data/media` — your library (or accept it's re-downloadable).
- `/data/.state/nixarr` — all app state/config.
- The secret files from Step 5.
