{ config, ... }:
let
    inherit (config.flake.modules) nixos; 
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
in
{
    flake.modules.nixos."${hostname}Configuration" = { pkgs, ... }: 
    {
        imports = [
            (import ../../lib/mkHost.nix ./.)
        ];
        
        config = {
            # Temp access >> Role system later
            internal.system.debug.enable = true;
            # internal.system.bootloader.enable = true;
        
            profile.system = {
                dualBoot = false;
                
                bootloader.settings = { };
                bootloader.plymouth = {
                    theme = "loader_2";
                    themePackages = [
                        (pkgs.adi1090x-plymouth-themes.override {
                            selected_themes = [ "loader_2" ];
                        })
                    ];
                };
            };
              
            profile.user = {
                # hashedPasswordFile = age.secrets.<ageFile>.path;
                terminal = "kitty";
                xkb.layout = "us";
                xkb.variant = "";
                
                fonts = {
                    packages = [ ];
                    defaults.serif = [ "Noto Serif" ];
                    defaults.sans  = [ "Noto Sans" ];
                    defaults.mono  = [ "JetBrains Mono" ];
                };
            };
                
            profile.desktop = {
                displayManager = {
                    settings = {
                        theme = "sddm-astronaut-theme";
                        extraPackages = [ 
                            # @TODO: These can probably be directly handled by the custom quickshell bar later
                            pkgs.kdePackages.qtsvg 
                            pkgs.kdePackages.qtmultimedia 
                            pkgs.kdePackages.qtvirtualkeyboard 
                            pkgs.kdePackages.qt5compat
                        ];
                    };
                    extraPackages = [
                        (pkgs.sddm-astronaut.override {
                            embeddedTheme = "astronaut";
                        })
                    ];
                };
            };
        };
    };                                
}
