{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkIf types elem;
in
{
    flake.modules.nixos.experimental = { config, pkgs, ... }:
    let
        inherit (config.profile.desktop) experimental;
        iExperimental = config.internal.desktop.experimental;
    in
    {
        options = {
            internal.desktop.experimental.enable = mkEnableOption "Experimental programs" // { internal = true; };
            profile.desktop.experimental = {
                programs = mkOption {
                    type = types.listOf (types.enum [ /* @TODO: Make experimental programs */ ]);
                    default = [ /* All of them eventually */ ];
                    description = "Which experimental programs to enable";
                };
                packages = mkOption {
                    type = types.listOf types.package;
                    default = [ ];
                    description = "Extra packages to install alongside this group";
                };
            };
        };
        
        config = mkIf iExperimental.enable {
            environment.systemPackages = [
                
            ] ++ experimental.packages;
            
            # Ideas: 
            # LLM Suite -- selfhosted (Pewd's Odysseus) and cloud based
            # 3D Dev/Graphics Programming/VFX stuff
        };
    };
}