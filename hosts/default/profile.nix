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
                        rev = "172068ab35708de05d21b0684b7af8f53524a922";
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
                        theme = "where-is-my-sddm-theme";
                    };
                   extraPackages = [
                        (pkgs.where-is-my-sddm-theme.override {
                            variants = [ "qt6" ];
                            themeConfig.General = {
                                backgroundFillMode = "aspect";
                                blurRadius = 0;
                                
                                passwordCharacter = "•";
                                passwordFontSize = 32;
                                passwordInputWidth = 0.25;
                                passwordInputRadius = 12;
                                passwordInputBackground = "#171a21";
                                passwordTextColor = "#e6e8ee";
                                passwordCursorColor = "#8aa2ff";
                                
                                basicTextColor = "#7d8494";
                                showSessionsByDefault = false;
                                showUsersByDefault = false;
                            };
                        })
                   ];
                };
            };
        };
    };                                
}