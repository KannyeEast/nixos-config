{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkMerge mkIf mkForce types recursiveUpdate;
in
{
    flake.modules.nixos.boot = { config, pkgs, ... }:
    let
        inherit (config.profile.system) bootloader;
        iBoot = config.internal.system.bootloader;
        
        createConfig = preset: settings:
            (recursiveUpdate preset settings) // { enable = mkForce true; };
    in
    {
        options = {
            internal.system.bootloader.enable = mkEnableOption "Enable boot-loader" // { internal = true; };
            profile.system.bootloader = {
                settings = mkOption {
                    type = types.attrsOf types.anything;
                    default = { };
                    description = "Options for configuring the boot-loader";
                };
                plymouth = mkOption {
                    type = types.attrsOf types.anything;
                    default = { };
                    description = "Plymouth configuring";
                };
                dualBoot = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Are you dual-booting NixOS";
                };  
            };
        };
        
        config = mkMerge [
            (mkIf iBoot.enable {
                boot = {
                    loader.efi.canTouchEfiVariables = true;
                    loader.timeout = 5;
                    consoleLogLevel = 0;
                    kernelParams = [
                        "quiet"
                        "splash"
                        "loglevel=3"
                        "rd.systemd.show_status=false"
                        "rd.udev.log_level=3"
                        "systemd.show_status=auto"
                    ];
                    
                    loader.grub = createConfig {
                        device = "nodev";
                        useOSProber = true;
                        efiSupport = true;
                    } bootloader.settings;
                    
                    plymouth = createConfig { } bootloader.plymouth;
                };
            })
            
             (mkIf (iBoot.enable && bootloader.dualBoot) {
                systemd.tmpfiles.settings."10-refind" = {
                    "/boot/EFI/refind/refind_x64.efi"."C+".argument = "${pkgs.refind}/share/refind/refind_x64.efi";
                    "/boot/EFI/refind/refind.conf"."C+".argument = "${./refind/refind.conf}";
                    "/boot/EFI/refind/themes"."C+".argument = "${./refind/themes}";
                    "/boot/EFI/tools/shellx64.efi"."C+".argument = "${pkgs.edk2-uefi-shell}/shell.efi";
                    "/boot/EFI/tools/memtest86/memtest86.efi"."C+".argument = "${pkgs.memtest86plus}/memtest.efi";
                };
             })
            
            (mkIf (!iBoot.enable) {
                boot.loader.systemd-boot.enable = true;
            })
        ];
    };
}