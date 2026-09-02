{ config, ... }:
let
  inherit (config.flake.modules)
    nixos
    ;
in
{
  flake.modules.nixos.server = {
    imports = [
      nixos.base

      nixos.auth
      nixos.backup
      nixos.dns
      nixos.proxy
      nixos.storage
      nixos.syncthingProxy
    ];

    config = {
      home-manager.sharedModules = [ ];
    };
  };
}
