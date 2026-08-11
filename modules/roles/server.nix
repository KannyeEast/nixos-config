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

      ];

      config = {
        home-manager.sharedModules = [ ];
      };
    };
}
