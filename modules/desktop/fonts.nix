{ lib, ... }:
let
    inherit (lib) mkOption types;
in
{
    flake.modules.nixos.fonts = { config, pkgs, ... }:
    let
        inherit (config.profile.user) fonts;
    in
    {
        options = {
            profile.user = {
                fonts = {
                    packages = mkOption {
                        type = types.listOf types.package;
                        default = [ ];
                        description = "Import any font package you want";
                    };
                    defaults = {
                        serif = mkOption {
                            type = types.listOf types.str;
                            default = [ "Noto Serif" ];
                            description = "Default Serif font";
                        };
                        sans = mkOption {
                            type = types.listOf types.str;
                            default = [ "Noto Sans" ];
                            description = "Default Sans font";
                        };
                        mono = mkOption {
                            type = types.listOf types.str;
                            default = [ "JetBrains Mono" ];
                            description = "Default Mono font";
                        };
                    };
                };
            };
        };
        
        config = {
            fonts = {
                fontDir.enable = true;
                enableDefaultPackages = true;
                
                packages = [
                    pkgs.noto-fonts     
                    pkgs.noto-fonts-cjk-sans 
                    pkgs.noto-fonts-color-emoji 
                    pkgs.nerd-fonts.jetbrains-mono
                ] ++ fonts.packages;
                
                fontconfig = {
                    defaultFonts.serif = fonts.defaults.serif;
                    defaultFonts.sansSerif = fonts.defaults.sans;
                    defaultFonts.monospace = fonts.defaults.mono;
                };
            };
        };
    };
}