---
title: Getting Started
---

# Getting Started

This guide shows how to add Nixflix to your NixOS configuration using flakes.

## Prerequisites

- NixOS with flakes enabled
- Git for version control
- Basic familiarity with NixOS modules
- Some form of secrets management, like [sops-nix](https://github.com/Mic92/sops-nix)

## Enable Flakes

If you haven't already enabled flakes, add this to your configuration:

```nix
{
  nix.settings.experimental-features = ["nix-command" "flakes"];
}
```

## Adding Nixflix to Your Flake

Add Nixflix as an input to your `flake.nix`:

```nix
{
  description = "My NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixflix = {
      url = "github:kiriwalawren/nixflix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixflix,
    ...
  }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        nixflix.nixosModules.default
      ];
    };
  };
}
```

## Minimal Configuration Example

Here's a minimal configuration to get started:

```nix
{
  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state";

    nginx.enable = true;
    postgres.enable = true;

    sonarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets."sonarr/api_key".path;};
        hostConfig.password = {_secret = config.sops.secrets."sonarr/password".path;};
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets."radarr/api_key".path;};
        hostConfig.password = {_secret = config.sops.secrets."radarr/password".path;};
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets."prowlarr/api_key".path;};
        hostConfig.password = {_secret = config.sops.secrets."prowlarr/password".path;};
      };
    };

    sabnzbd = {
      enable = true;
      settings = {
        misc.api_key = {_secret = config.sops.secrets."sabnzbd/api_key".path;};
      };
    };

    jellyfin = {
      enable = true;
      users.admin = {
        policy.isAdministrator = true;
        password = {_secret = config.sops.secrets."jellyfin/admin_password".path;};
      };
    };
  };
}
```

## macOS MVP

The Darwin backend is intentionally smaller than the NixOS backend. It targets a Mac mini on a tailnet with Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, and qBittorrent download-client wiring.

Darwin does not configure nginx, Usenet, SABnzbd, Lidarr, Seerr, Recyclarr, Mullvad, or Tailscale Serve. Access the services by explicit ports over MagicDNS, for example `http://mac-mini:8096` for Jellyfin or `http://mac-mini:9696` for Prowlarr. If you want Tailscale Serve, configure it outside Nixflix for now.

The Darwin backend binds Arr services and qBittorrent beyond localhost so MagicDNS port access works. Because qBittorrent is reachable, set `nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Password_PBKDF2` declaratively along with `nixflix.torrentClients.qbittorrent.password`.

Prowlarr private trackers such as BTN/PTP are normal `nixflix.prowlarr.config.indexers` entries. Current Prowlarr schema names are `PassThePopcorn` and `BroadcasTheNet`; for PTP, set `username` to the PTP API user and `apiKey` to the PTP API key. Nixflix does not ship tracker-specific modules.

Do not test BTN/PTP with fake credentials. Nixflix rejects empty or obvious placeholder indexer secrets before mutating Prowlarr, because Prowlarr may validate credentials against the tracker while creating an indexer.

## Next Steps

- Review the [Basic Setup Example](../examples/basic-setup.md) for a complete configuration
- See the [Options Reference](../reference/index.md) for all available settings
