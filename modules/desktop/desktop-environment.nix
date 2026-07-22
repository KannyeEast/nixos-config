{ lib, ... }:
let
    inherit (lib) mkOption types;
in
{
    flake.modules.nixos.desktopEnvironment = { config, pkgs, ... }:
    let
        inherit (config.profile) user;
    in
    {
        options = {
            profile.user = {
                xkb.layout = mkOption {
                    type = types.str;
                    default = "us";
                    description = "xkb keyboard layout";
                };
                xkb.variant = mkOption {
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
            
            # @TODO: Look for other package combos with niri
            environment.systemPackages = [
                pkgs.xwayland-satellite
            ];
            
            environment.sessionVariables = {
                NIXOS_OZONE_WL = "1";
                XKB_DEFAULT_LAYOUT = user.xkb.layout;
                XKB_DEFAULT_VARIANT = user.xkb.variant;
            };
            
            programs.niri.enable = true;
            programs.niri.useNautilus = true;
            programs.dconf.enable = true;
            services = {
                gnome.gnome-keyring.enable  = true;
                xserver = {
                    enable = true;
                    xkb.layout = user.xkb.layout;
                };
            };
        };
    };
}