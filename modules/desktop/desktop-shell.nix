{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkIf types;
in
{
    flake.modules.nixos.desktopShell = { config, pkgs, ... }:
    let
        inherit (config.internal.desktop) shell;
    in
    {
        options = {
            internal.desktop.shell.enable = mkEnableOption "Desktop shell" // { internal = true; };
        };
        
        config = mkIf shell.enable {
            # @TODO: Do shell stuff here
        };
    };
}