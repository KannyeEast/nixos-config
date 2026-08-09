{ lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkMerge
    mkIf
    mkForce
    types
    recursiveUpdate
    concatMapAttrs
    escapeShellArg
    makeBinPath
    ;
in
{
  flake.modules.nixos.boot =
    { config, pkgs, host, ... }:
    let
      inherit (config.profile.system) bootloader;
      iBoot = config.internal.system.bootloader;

      createConfig = preset: settings: (recursiveUpdate preset settings) // { enable = mkForce true; };

      # Refind
      getFiles =
        src: dest:
        let
          collect =
            dir: prefix:
            concatMapAttrs (
              name: type:
              if type == "directory" then
                collect ("${dir}/${name}") "${prefix}${name}/"
              else
                { "${dest}/${prefix}${name}" = "${dir}/${name}"; }
            ) (builtins.readDir dir);
        in
        collect "${src}" "";

      # Implements [a63681]
      # https://sourceforge.net/u/l0sermcl0ser/refind/ci/a63681fca1e5135e619dc3127c29810d87e5e487/  
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

      refindFiles = getFiles ../../hosts/${host.hostname}/home/.config/refind "EFI/refind" // {
        "EFI/refind/refind_x64.efi" = "${refindOverride}/share/refind/refind_x64.efi";
        "EFI/tools/shellx64.efi" = "${pkgs.edk2-uefi-shell}/shell.efi";
        "EFI/tools/memtest86.efi" = "${pkgs.memtest86-efi}/BOOTX64.efi";
      };

      refindInstaller = pkgs.writeShellScript "install-refind" ''
        set -eu
        
        export PATH=${
          makeBinPath [
            pkgs.efibootmgr
            pkgs.util-linux
            pkgs.coreutils
            pkgs.gnugrep
          ]
        }:$PATH

        esp=${escapeShellArg config.boot.loader.efi.efiSysMountPoint}

        part_dev=$(findmnt -no SOURCE --target "$esp")
        disk=/dev/$(lsblk -no PKNAME "$part_dev")
        part=$(cat "/sys/class/block/$(basename "$part_dev")/partition")

        # Drop stale entries so this stays idempotent across rebuilds.
        for n in $(efibootmgr | grep -E '^Boot[0-9A-F]{4}\*? +rEFInd$' | cut -c5-8); do
            efibootmgr -q -b "$n" -B
        done

        efibootmgr -q -c -d "$disk" -p "$part" -L "rEFInd" -l '\EFI\refind\refind_x64.efi'
      '';

      refindUninstaller = pkgs.writeShellScript "uninstall-refind" ''
        set -eu

        export PATH=${
          makeBinPath [
            pkgs.efibootmgr
            pkgs.coreutils
            pkgs.gnugrep
          ]
        }:$PATH

        esp=${escapeShellArg config.boot.loader.efi.efiSysMountPoint}

        for n in $(efibootmgr | grep -E '^Boot[0-9A-F]{4}\*? +rEFInd$' | cut -c5-8 || true); do
            efibootmgr -q -b "$n" -B
        done

        rm -rf "$esp/EFI/refind"
      '';
    in
    {
      options = {
        internal.system.bootloader.enable = mkEnableOption "Enable boot-loader" // {
          internal = true;
        };
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

        (mkIf (iBoot.enable && builtins.pathExists ../../hosts/${host.hostname}/home/.config/refind) {
          environment.systemPackages = [
            refindOverride
            pkgs.efibootmgr
          ];

          boot.loader.grub = {
            extraFiles = refindFiles;
            extraInstallCommands = "${refindInstaller}";
          };
        })

        (mkIf (iBoot.enable && !builtins.pathExists ../../hosts/${host.hostname}/home/.config/refind) {
          boot.loader.grub.extraInstallCommands = "${refindUninstaller}";
        })

        (mkIf (!iBoot.enable) {
          boot.loader.systemd-boot.enable = true;
        })
      ];
    };
}