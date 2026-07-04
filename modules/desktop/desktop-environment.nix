{ inputs, config, lib, ... }:
let
    inherit (config.flake.modules) nixos;
    inherit (lib) mkEnableOption mkOption mkIf types getExe;
in
{
    flake.modules.nixos.desktopEnvironment = { config, pkgs, ... }:
    let
        inherit (config.profile) user;
        inherit (config.internal) desktop;
    in
    {
        imports = [
            nixos.desktopShell
        ];
        
        options = {
            internal.desktop.environment.enable = mkEnableOption "Desktop Environment" // { internal = true; };
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
        
        config = mkIf desktop.environment.enable {
            # Enable shells if we have a DE
            internal.desktop.shell.enable = true;
        
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
