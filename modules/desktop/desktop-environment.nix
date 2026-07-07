{ lib, ... }:
let
    inherit (lib) mkOption types getExe;
in
{
    flake.modules.nixos.desktopEnvironment = { config, pkgs, ... }:
    let
        inherit (config.profile) user;
    in
    {
        options = {
            profile.user = {
                terminal = mkOption {
                    type = types.str;
                    default = "alacritty";
                    description = "";
                };
                keyboard.layout = mkOption {
                    type = types.str;
                    default = "us";
                    description = "xkb keyboard layout";
                };
                keyboard.variant = mkOption {
                    type = types.str;
                    default = "";
                    description = "xkb keyboard variant";
                };
            };
        };
        
        config = {
            xdg.portal = {
                enable = true;
                extraPortals = [
                    pkgs.xdg-desktop-portal-gtk
                    pkgs.xdg-desktop-portal-gnome
                ];
                config = {
                    common.default = [ "gtk" ];
                    niri.default = [ "gnome" "gtk" ];
                };
            };
            
            environment.systemPackages = [
                pkgs.${user.terminal}
            ];
            
            environment.sessionVariables = {
                NIXOS_OZONE_WL = "1";
                TERMINAL = user.terminal;
                XKB_DEFAULT_LAYOUT = user.keyboard.layout;
                XKB_DEFAULT_VARIANT = user.keyboard.variant;
            };
            
            programs.niri.enable = true;
            programs.niri.useNautilus = true;
            programs.dconf.enable = true;
            services.gnome.gnome-keyring.enable = true;
        };
    };
}   
