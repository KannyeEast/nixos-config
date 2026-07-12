{ lib, ... }:
let
    inherit (lib) mkEnableOption mkOption mkMerge mkIf mkForce
        types recursiveUpdate optionalString concatMapAttrs
        escapeShellArg makeBinPath;
in
{
    flake.modules.nixos.boot = { config, pkgs, ... }:
    let
        inherit (config.profile.system) bootloader;
        iBoot = config.internal.system.bootloader;
        
        createConfig = preset: settings:
            (recursiveUpdate preset settings) // { enable = mkForce true; };
        
        refindTheme = bootloader.refind.theme.name != null && bootloader.refind.theme.source != null;
            
        refindThemeFiles = 
        let
            inherit (bootloader.refind) theme;
            collect = dir: prefix:
                concatMapAttrs (name: type:
                    if type == "directory"
                    then collect ("${dir}/${name}") "${prefix}${name}/"
                    else { "EFI/refind/themes/${theme.name}/${prefix}${name}" = "${dir}/${name}"; }
                ) (builtins.readDir dir);
        in
            if refindTheme
            then collect "${theme.source}" ""
            else { };
            
        refindConfig = pkgs.writeText ''
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
            
            ${optionalString refindTheme
            "include themes/${bootloader.refind.theme.name}/theme.conf"
            }
        '';
        
        refindFiles = refindThemeFiles // {
            "EFI/refind/refind_x64.efi" = "${pkgs.refind}/share/refind/refind_x64.efi";
            "EFI/refind/refind.conf"    = refindConfig;
            
            "EFI/tools/shellx64.efi"   = "${pkgs.edk2-uefi-shell}/shell.efi";
            "EFI/tools/memtest86.efi"  = "${pkgs.memtest86-efi}/BOOTX64.efi";
        };
        
        refindInstaller = pkgs.writeShellScript "install-refind" ''
            set -eu
            export PATH=${makeBinPath [
                pkgs.efibootmgr
                pkgs.util-linux
                pkgs.coreutils
                pkgs.gnugrep
            ]}:$PATH
            
            esp=${escapeShellArg config.boot.loader.efi.efiSysMountPoint}
            
            part_dev=$(findmnt -no SOURCE --target "$esp")      # e.g. /dev/nvme0n1p1
            disk=/dev/$(lsblk -no PKNAME "$part_dev")           # e.g. /dev/nvme0n1
            part=$(cat "/sys/class/block/$(basename "$part_dev")/partition")
            
            # Drop stale entries so this stays idempotent across rebuilds.
            for n in $(efibootmgr | grep -E '^Boot[0-9A-F]{4}\*? +rEFInd$' | cut -c5-8); do
                efibootmgr -q -b "$n" -B
            done
            
            efibootmgr -q -c -d "$disk" -p "$part" \
                -L "rEFInd" -l '\EFI\refind\refind_x64.efi'
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
                        useOSProber = false;
                        efiSupport = true;
                    } bootloader.settings;
                    
                    plymouth = createConfig { } bootloader.plymouth;
                };
            })
            
            (mkIf (iBoot.enable && bootloader.refind.enable) {
                environment.systemPackages = [
                    pkgs.refind
                    pkgs.efibootmgr 
                ];

                boot.loader.grub = {
                    extraFiles = refindFiles;
                    extraInstallCommands = "${refindInstaller}";
                };
            })
            
            (mkIf (!iBoot.enable) {
                boot.loader.systemd-boot.enable = true;
            })
        ];
    };
}