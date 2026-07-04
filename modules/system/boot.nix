{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkMerge mkIf mkForce types recursiveUpdate;
in
{
    flake.modules.nixos.boot = { config, pkgs, ... }:
    let
        inherit (config.profile.system) bootloader plymouth;
        
        createConfig = name: preset: 
            if bootloader.type == name
            then (recursiveUpdate preset bootloader.settings) // { enable = lib.mkForce true; }
            else { };
    in
    {
        options = {
            profile.system.bootloader = {
                type = mkOption {
                    type = types.enum [ "systemd-boot" "grub" "limine" ];
                    default = "systemd-boot";
                    description = "Choose which bootloader to enable";
                };
                settings = mkOption {
                    type = types.attrsOf types.anything;
                    default = { };
                    description = "Options for theming and configuring the chosen bootloader";
                };
                extras = mkOption {
                    type = types.attrsOf types.anything;
                    default = { };
                    description = "Extra boot settings not present by default or for flake inputs";
                };
            };
            profile.system.plymouth = {
                enable = mkEnableOption "Plymouth";
                settings = mkOption {
                    type = types.attrsOf types.anything;
                    default = { };
                    description = "Options for theming and configuring plymouth";
                };
            };
        };
        
        config = mkMerge [
            {
                boot.loader.efi.canTouchEfiVariables = true;
                boot.loader.timeout = 5;
                boot.consoleLogLevel = 0;
                boot.kernelParams = [
                    "quiet"
                    "splash"
                    "loglevel=3"
                    "rd.systemd.show_status=false"
                    "rd.udev.log_level=3"
                    "systemd.show_status=auto"
                ];
            }
            
            { boot.loader.systemd-boot = createConfig "systemd-boot" { }; }
            { boot.loader.grub = createConfig "grub" { device = "nodev"; useOSProber = true; efiSupport = true; }; }
            { boot.loader.limine = createConfig "limine" { }; }
            
            { boot = bootloader.extras; }
            
            { boot.plymouth = {
                enable = plymouth.enable;
            } // plymouth.settings; }
        ];
    };
}

