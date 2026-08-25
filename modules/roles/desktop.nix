{ config, ... }:
let
  inherit (config.flake.modules) nixos homeManager;
in
{
  flake.modules.nixos.desktop = {
    imports = [
      nixos.base

      nixos.audio
      nixos.bluetooth
      nixos.desktopEnvironment
      nixos.desktopShell
      nixos.displayManager
      nixos.fonts
      nixos.packages
    ];

    config = {
      home-manager.sharedModules = [
        homeManager.browser
        homeManager.desktopEnvironment
        homeManager.directories
        homeManager.dotfiles
        homeManager.passwords
      ];

      internal.system.bootloader.enable = true;
    };
  };
}
