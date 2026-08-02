{ lib, ... }:
let
  inherit (lib)
    mkOption
    mkForce
    types
    recursiveUpdate
    ;
in
{
  flake.modules.nixos.displayManager =
    { config, pkgs, ... }:
    let
      inherit (config.profile.desktop) displayManager;

      createConfig = preset: settings: (recursiveUpdate preset settings) // { enable = mkForce true; };
    in
    {
      options = {
        profile.desktop.displayManager = {
          settings = mkOption {
            type = types.attrsOf types.anything;
            default = { };
            description = "Extra options for theming and configuring the display-manager";
          };
          extraPackages = mkOption {
            type = types.listOf types.package;
            default = [ ];
            description = "Extra packages to import as systemPackages alongside the display-manager";
          };
        };
      };

      config = {
        services.displayManager.sddm = createConfig {
          wayland = {
            enable = true;
            compositor = "kwin";
          };
          package = pkgs.kdePackages.sddm;
          extraPackages = displayManager.extraPackages;
        } displayManager.settings;

        environment.systemPackages = displayManager.extraPackages;
      };
    };
}
