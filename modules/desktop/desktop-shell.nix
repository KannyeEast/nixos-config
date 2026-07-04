{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkIf types;
in
{
    flake.modules.nixos.desktopShell = { config, pkgs, ... }:
    let
        inherit (config.profile.desktop) shell;
        iDesktopShell = config.internal.desktop.shell;
    in
    {
        options = {
            internal.desktop.shell.enable = mkEnableOption "Desktop shell" // { internal = true; };
            profile.desktop.shell = mkOption {
                type = types.enum [ "waybar" "dms" "noctalia" "caelestia" ];
                default = [ ];
                description = "Which shell to enable";
            };
        };
        
        config = mkIf iDesktopShell.enable {
            # @TODO: Do shell stuff here
        };
    };
}