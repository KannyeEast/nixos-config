{ ... }:
let
    inherit (builtins.fromJSON (builtins.readFile ./host.json)) hostname;
in
{
    imports = [
        (import ../../lib/mkHost.nix ./.)
    ];
    
    flake.modules.nixos."${hostname}Configuration" = { pkgs, ... }:
    {
        config = {
            profile.system = {
                # Grub attributes
                bootloader.settings = { };
                # Plymouth attributes
                bootloader.plymouth = {
                    theme = "loader_2";
                    themePackages = [
                        (pkgs.adi1090x-plymouth-themes.override {
                            selected_themes = [ "loader_2" ];
                        })
                    ];
                };
                
                # Dual boot - rEFInd
                bootloader.refind = {
                    enable = true;
                    theme.name = "rEFInd-minimal-dark";
                    theme.source = builtins.fetchGit {
                        url = "https://github.com/KannyeEast/rEFInd-minimal-dark";
                        rev = "cd24cb4e6dd25daf52a6f90b6da96fcf4deacb12";
                    };
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