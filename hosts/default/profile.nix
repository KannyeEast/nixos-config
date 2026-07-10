{ config, ... }:
let
    inherit (config.flake.modules) nixos; 
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname user;
in
{
    imports = [
        (import ../../lib/mkHost.nix ./.)
    ];
    
    flake.modules.nixos."${hostname}Configuration" = { pkgs, ... }: 
    {
        config = {
            sops.secrets = {
            };
            
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
                browser = {
                    extensions.extra = { };
                    extensions.exclude = [ ];
                    bookmarks.extra = [ ];
                    tabs.extra = { };
                    tabs.exclude = [ ];
                    spaces.extra = { };
                };
                
                displayManager = {
                    settings = {
                        theme = "sddm-astronaut-theme";
                        extraPackages = [ 
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