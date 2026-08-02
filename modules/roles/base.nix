{ config, ... }:
let
  inherit (config.flake.modules) nixos homeManager;
in
{
  flake.modules.nixos.base =
    { ... }:
    {
      imports = [
        nixos.hardware

        nixos.boot
        nixos.homeManager
        nixos.impermanence
        nixos.locale
        nixos.networking
        nixos.ssh
        nixos.system
        nixos.user
        nixos.secrets
      ];

      config = {
        home-manager.sharedModules = [
          homeManager.git
          homeManager.ssh
        ];
      };
    };
}
