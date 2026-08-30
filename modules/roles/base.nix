{ config, ... }:
let
  inherit (config.flake.modules)
    homeManager
    nixos
    ;
in
{
  flake.modules.nixos.base = {
    imports = [
      nixos.hardware

      nixos.boot
      nixos.homeManager
      nixos.impermanence
      nixos.locale
      nixos.networking
      nixos.secrets
      nixos.ssh
      nixos.syncthing
      nixos.system
      nixos.tailscale
      nixos.user
    ];

    config = {
      home-manager.sharedModules = [
        homeManager.git
        homeManager.ssh
      ];
    };
  };
}
