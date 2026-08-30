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

      nixos.backup
      nixos.proxy
      nixos.storage
      nixos.syncthing
    ];

    config = {
      home-manager.sharedModules = [ ];
    };
  };
}
