{ config, ... }:
let
  inherit (config.flake.modules)
    homeManager
    nixos
    ;
in
{
  flake.modules.nixos.server = {
    imports = [
      nixos.base
      
      nixos.proxy
      nixos.storage
    ];

    config = {
      home-manager.sharedModules = [ ];
    };
  };
}
