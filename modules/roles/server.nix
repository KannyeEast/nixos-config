{ config, ... }:
let
  inherit (config.flake.modules) nixos;
in
{
  flake.modules.nixos.server =
    { ... }:
    {
      imports = [
        nixos.base

        nixos.storage
      ];

      config = {
        home-manager.sharedModules = [ ];
      };
    };
}
