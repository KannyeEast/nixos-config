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
                    enable = false;
                    theme.name = "rEFInd-minimal-dark";
                    theme.source = builtins.fetchGit {
                        url = "https://github.com/KannyeEast/rEFInd-minimal-dark";
                        rev = "5e56a8110af88323fe4bc7aa95442ecf5d0ba4ed";
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
                        theme = "where_is_my_sddm_theme";
                    };
                   extraPackages = [
                        (pkgs.where-is-my-sddm-theme.override {
                            themeConfig.General = {
                                background = "";                      
                                backgroundFill = "#0f1115";
                                backgroundFillMode = "fill";
                        
                                font = "Inter";
                                basicTextColor = "#9aa1b1";
                                hideCursor = false;

                                passwordCharacter = "•";
                                passwordMask = true;
                                passwordFontSize = 28;                
                                passwordInputWidth = 0.22;
                                passwordInputRadius = 12;
                                passwordInputBackground = "#171a21";
                                passwordInputBorderWidth = 1;
                                passwordInputBorderColor = "#262b36";
                                passwordTextColor = "#e6e8ee";
                                passwordCursorColor = "#8aa2ff";
                                passwordInputCursorVisible = true;
                                cursorBlinkAnimation = true;
                        
                                wrongPasswordBorderColor = "#ff6b7a";
                                wrongPasswordBorderRadius = 12;
                        
                                showUsersByDefault = true;
                                showUserRealNameByDefault = false;
                                usersFontSize = 16;
                        
                                showSessionsByDefault = true;
                                sessionsFontSize = 12;
                        
                                helpFont = "Inter";
                                helpFontSize = 11;
                            };
                        })
                    ];
                };
            };
        };
    };                                
}