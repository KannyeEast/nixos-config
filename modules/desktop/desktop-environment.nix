{ inputs, lib, ... }:
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
            
            environment.sessionVariables.NIXOS_OZONE_WL = "1";
            
            programs.niri = {
                enable = true;
                package = inputs.wrapper-modules.wrappers.niri.wrap {
                    inherit pkgs;
                    settings = {
                        input.keyboard.xkb.layout = user.keyboard.layout;
                        input.keyboard.xkb.variant = user.keyboard.variant;
                        xwayland-satellite.path = getExe pkgs.xwayland-satellite;
                        binds."Mod+Return".spawn-sh = getExe pkgs.${user.terminal};
                    };
                };
            };
            
            programs.dconf.enable = true;
            services.gnome.gnome-keyring.enable = true;
        };
    };
}   
