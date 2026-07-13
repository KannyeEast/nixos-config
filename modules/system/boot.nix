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
        
        # Refind
        getFiles = src: dest:
        let
            collect = dir: prefix:
                concatMapAttrs (name: type:
                    if type == "directory"
                    then collect ("${dir}/${name}") "${prefix}${name}/"
                    else { "${dest}/${prefix}${name}" = "${dir}/${name}"; }
                ) (builtins.readDir dir);
        in
            collect "${src}" "";
        
        refindTheme = bootloader.refind.theme.name != null && bootloader.refind.theme.source != null;
        
        refindIcons = pkgs.runCommand "refind-icons" {
            nativeBuildInputs = [ pkgs.librsvg ];
        } ''
            mkdir -p $out
            cp -r ${refindOverride}/share/refind/icons/* $out/
            chmod -R u+w $out
            rsvg-convert -w 128 -h 128 \
                ${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg \
                -o $out/os_nixos.png
        '';
        
        refindIconsDir = 
            if refindTheme 
            then "EFI/refind/themes/${bootloader.refind.theme.name}/icons"
            else "EFI/refind/icons";
        
        refindAssets = 
            if refindTheme
            then getFiles bootloader.refind.theme.source "EFI/refind/themes/${bootloader.refind.theme.name}"
            else getFiles refindIcons "EFI/refind/icons";
            
        refindOverride = pkgs.refind.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
                substituteInPlace refind/config.c \
                    --replace-fail \
                        'SetMem(GlobalConfig.ShowTools, NUM_TOOLS * sizeof(UINTN), 0);' \
                        'refit_call3_wrapper(gBS->SetMem, GlobalConfig.ShowTools, NUM_TOOLS * sizeof(UINTN), 0);' \
                    --replace-fail \
                        '(i < TokenCount) && (i < NUM_TOOLS)' \
                        '(i < TokenCount) && (i <= NUM_TOOLS)'
            '';
        });
            
        refindConfig = pkgs.writeText "refind.conf" ''
            #
            # refind.conf
            # Configuration file for the rEFInd boot menu
            # https://rodsbooks.com/refind/configfile.html
            #
        
            timeout 20
            use_nvram false
            
            # Specify which entries we want
            scanfor manual
            
            showtools shell,memtest,about,reboot,shutdown,firmware
            
            ${optionalString refindTheme
                "include themes/${bootloader.refind.theme.name}/theme.conf"}
            
            menuentry "NixOS" {
                icon /${refindIconsDir}/os_nixos.png
                loader /EFI/NixOS-boot/grubx64.efi
            }
        '';
        
        refindFiles = refindAssets // {
            "EFI/refind/refind_x64.efi" = "${refindOverride}/share/refind/refind_x64.efi";
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
        
        win=$esp/EFI/Microsoft/Boot/bootmgfw.efi
        if [ -f "$win" ];
        then
        cat >> "$esp/EFI/refind/refind.conf" <<EOF
        
        menuentry "Windows" {
            volume "ESP"
            icon   /${refindIconsDir}/os_win.png
            loader /EFI/Microsoft/Boot/bootmgfw.efi
        }
        EOF
        fi
        '';
        
        refindUninstaller = pkgs.writeShellScript "uninstall-refind" ''
        set -eu
        
        export PATH=${makeBinPath [
            pkgs.efibootmgr
            pkgs.coreutils
            pkgs.gnugrep
        ]}:$PATH
        
        esp=${escapeShellArg config.boot.loader.efi.efiSysMountPoint}
        
        for n in $(efibootmgr | grep -E '^Boot[0-9A-F]{4}\*? +rEFInd$' | cut -c5-8 || true); do
            efibootmgr -q -b "$n" -B
        done
        
        rm -rf "$esp/EFI/refind"
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
                    refindOverride
                    pkgs.efibootmgr 
                ];

                boot.loader.grub = {
                    extraFiles = refindFiles;
                    extraInstallCommands = "${refindInstaller}";
                };
            })
            
            (mkIf (iBoot.enable && !bootloader.refind.enable) {
                boot.loader.grub.extraInstallCommands = "${refindUninstaller}";
            })
            
            (mkIf (!iBoot.enable) {
                boot.loader.systemd-boot.enable = true;
            })
        ];
    };
}