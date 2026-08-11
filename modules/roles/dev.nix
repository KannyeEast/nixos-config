{ config, ... }:
let
  inherit (config.flake.modules) nixos;
in
{
  flake.modules.nixos.dev =
    { ... }:
    {
      imports = [
        nixos.debug
        nixos.direnv
        nixos.ide
        nixos.tuiShell
      ];

      config = {
        home-manager.sharedModules = [ ];

        # internal.system.debug.enable = true;
      };
    };
}
