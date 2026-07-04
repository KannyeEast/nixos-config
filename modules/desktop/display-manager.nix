{ lib, ... }:
let
    inherit (lib) mkOption mkMerge mkIf mkForce types recursiveUpdate;
in
{
    flake.modules.nixos.displayManager = { config, pkgs, ... }:
    let
        inherit (config.profile.desktop) displayManager;
        inherit (config.profile.user) username;
        
        createConfig = name: preset:
            if displayManager.type == name
            then (recursiveUpdate preset displayManager.settings) // { enable = mkForce true; }
            else { };
    in
    {
        options = {
            profile.desktop.displayManager = {
                type = mkOption {
                    type = types.nullOr (types.enum [ "gdm" "regreet" "lemurs" "ly" "sddm" ]);
                    default = null;
                    description = "Choose which display manager to enable";
                };
                settings = mkOption {
                    type = types.attrsOf types.anything;
                    default = { };
                    description = "Extra options for theming and configuring the chosen display-manager";
                };
                extraPackages = mkOption {
                    type = types.listOf types.package;
                    default = [ ];
                    description = "Extra packages to import as systemPackages alongside the display-manager";
                };
            };
        };
        
        config = mkIf (displayManager.type != null) (mkMerge [
            { services.displayManager.gdm = createConfig "gdm" { }; }
            { programs.regreet = createConfig "regreet" { }; }
            { services.displayManager.lemurs = createConfig "lemurs" { }; }
            { services.displayManager.ly = createConfig "ly" { }; }
            { services.displayManager.sddm = createConfig "sddm" { wayland.enable = true; package = pkgs.kdePackages.sddm; }; }
            
            { environment.systemPackages = displayManager.extraPackages; }
            
            (mkIf (displayManager.type == "lemurs") {
                users.users.${username}.extraGroups = [ "seat" ];
            })
        ]);
    };
}
