{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkIf types elem;
in
{
    flake.modules.nixos.optionals = { config, pkgs, ... }:
    let
        inherit (config.profile.desktop) optionals;
        iOptionals = config.internal.desktop.optionals;
    in
    {
        options = {
            internal.desktop.optionals.enable = mkEnableOption "Optional programs" // { internal = true; };
            profile.desktop.optionals = {
                programs = mkOption {
                    type = types.listOf (types.enum [ /* @TODO: Make experimental programs */ ]);
                    default = [ /* All of them eventually */ ];
                    description = "Which optional programs to enable";
                };
                packages = mkOption {
                    type = types.listOf types.package;
                    default = [ ];
                    description = "Extra packages to install alongside this group";
                };
            };
        };
        
        config = mkIf iOptionals.enable {
            environment.systemPackages = [
                
            ] ++ optionals.packages;
        };
    };
}