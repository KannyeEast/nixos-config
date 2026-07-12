{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkMerge mkIf mkForce types recursiveUpdate optionalString;
in
{
    flake.modules.nixos.boot = { config, pkgs, ... }:
    let
        inherit (config.profile.system) bootloader;
        iBoot = config.internal.system.bootloader;
        
        createConfig = preset: settings:
            (recursiveUpdate preset settings) // { enable = mkForce true; };
            
        refindConfig = pkgs.writeText "refind.conf" ''
            #
            # refind.conf
            # Configuration file for the rEFInd boot menu
            # https://rodsbooks.com/refind/configfile.html
            #
        
            timeout 20
            use_nvram false
            scanfor internal,manual
            
            # @TODO: See other default directories we dont want
            dont_scan_dirs EFI/nixos-boot
            
            ${optionalString (bootloader.refind.theme.name != null && bootloader.refind.theme.source != null)
            "include themes/${bootloader.refind.theme.name}/theme.conf"}
        '';
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
                    description = "Plymouth configuration";
                };
                refind = {
                    enable = mkEnableOption "Enable rEFInd for dual-booting NixOS";
                    theme.name = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "rEFInd theme name";
                    };
                    theme.source = mkOption {
                        type = types.nullOr types.path;
                        default = null;
                        description = "rEFInd theme config";
                    };
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
            
             (mkIf (iBoot.enable && bootloader.refind.enable) {
                systemd.tmpfiles.settings."10-refind" = {
                    "/boot/EFI/refind/refind_x64.efi"."C+".argument = "${pkgs.refind}/share/refind/refind_x64.efi";
                    "/boot/EFI/refind/refind.conf"."C+".argument = "${refindConfig}";
                    "/boot/EFI/tools/shellx64.efi"."C+".argument = "${pkgs.edk2-uefi-shell}/shell.efi";
                    "/boot/EFI/tools/memtest86/memtest86.efi"."C+".argument = "${pkgs.memtest86plus}/memtest.efi";
                };
             })
            
            (mkIf (iBoot.enable &&
                   bootloader.refind.enable &&
                   bootloader.refind.theme.name != null &&
                   bootloader.refind.theme.source != null)
                {
                    systemd.tmpfiles.settings."10-refind" = {
                        "/boot/EFI/refind/themes/${bootloader.refind.theme.name}"."C+".argument = "${bootloader.refind.theme.source}";
                    };  
                }
            )
            
            (mkIf (!iBoot.enable) {
                boot.loader.systemd-boot.enable = true;
            })
        ];
    };
}