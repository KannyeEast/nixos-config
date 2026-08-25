{ lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkMerge
    mkIf
    optionalAttrs
    escapeShellArg
    makeBinPath
    removeSuffix
    removePrefix
    ;
    
  inherit (lib.filesystem)
    listFilesRecursive
    ;
in
{
  flake.modules.nixos.boot =
    {
      config,
      pkgs,
      host,
      ...
    }:
    let
      inherit (config.internal) system;

      hostConfigDir = ../../hosts/${host.name}/home/.config/system;
      refindDir = hostConfigDir + "/refind";
      grubDir = hostConfigDir + "/grub";
      plymouthDir = hostConfigDir + "/plymouth";

      plymouthName =
        if builtins.pathExists (plymouthDir + "/theme") then
          removeSuffix "\n" (builtins.readFile (plymouthDir + "/theme"))
        else
          "";

      hasRefind = builtins.pathExists (refindDir + "/refind.conf");
      hasPlymouth = builtins.pathExists (plymouthDir + "/${plymouthName}");
      hasGrubTheme = builtins.pathExists (grubDir + "/theme.txt");

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

      getFiles =
        src: dest:
        builtins.listToAttrs (
          map (path: {
            name = "${dest}/${removePrefix "${toString src}/" (toString path)}";
            value = path;
          }) (listFilesRecursive src)
        );

      # Shared shell preamble for both install & uninstall rEFInd
      efibootmgrSetup = esp: ''
        set -eu
        export PATH=${
          makeBinPath [
            pkgs.efibootmgr
            pkgs.util-linux
            pkgs.coreutils
            pkgs.gnugrep
          ]
        }:$PATH
        esp=${escapeShellArg esp}
      '';

      removeStaleRefind = ''
        for n in $(efibootmgr -v | grep -iE '^Boot[0-9A-Fa-f]{4}\*?.*refind_x64\.efi' | cut -c5-8 || true); do
          efibootmgr -q -b "$n" -B
        done
      '';
    in
    {
      options = {
        internal.system = {
          bootloader.enable = mkEnableOption "Enable boot-loader" // {
            internal = true;
          };
          dualBoot.enable = mkEnableOption "Enable dual-booting" // {
            internal = true;
          };
        };
      };

      config = mkMerge [
        {
          internal.system.dualBoot.enable = hasRefind;
        }

        (mkIf system.bootloader.enable (mkMerge [
          {
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

              loader.grub = {
                enable = true;
                device = "nodev";
                useOSProber = false;
                efiSupport = true;
                gfxmodeEfi = "1920x1080";
                splashImage = null;
                font = "${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf";
                fontSize = 20;
              }
              // optionalAttrs hasGrubTheme { theme = grubDir; };
            };
          }

          (mkIf hasPlymouth {
            boot.plymouth = {
              enable = true;
              theme = plymouthName;
              themePackages = [
                (pkgs.runCommand "plymouth-theme-${plymouthName}" { } ''
                  dest=$out/share/plymouth/themes/${plymouthName}
                  mkdir -p "$dest"
                  cp -r ${plymouthDir}/${plymouthName}/. "$dest"/
                  chmod -R u+w "$dest"
                  for f in "$dest"/*.plymouth; do
                  substituteInPlace "$f" --replace-fail "@THEME_DIR@" "$dest"
                  done
                '')
              ];
            };
          })

          (mkIf system.dualBoot.enable {
            environment.systemPackages = [
              refindOverride
              pkgs.efibootmgr
            ];

            boot.loader.grub = {
              extraFiles = getFiles refindDir "EFI/refind" // {
                "EFI/refind/refind_x64.efi" = "${refindOverride}/share/refind/refind_x64.efi";
                "EFI/tools/shellx64.efi" = "${pkgs.edk2-uefi-shell}/shell.efi";
                "EFI/tools/memtest86.efi" = "${pkgs.memtest86-efi}/BOOTX64.efi";
              };
              extraInstallCommands = "${pkgs.writeShellScript "install-refind" (
                efibootmgrSetup config.boot.loader.efi.efiSysMountPoint
                + ''
                  part_dev=$(findmnt -no SOURCE --target "$esp")
                  disk=/dev/$(lsblk -no PKNAME "$part_dev")
                  part=$(cat "/sys/class/block/$(basename "$part_dev")/partition")
                ''
                + removeStaleRefind
                + ''
                  efibootmgr -q -c -d "$disk" -p "$part" -L "rEFInd" -l '\EFI\refind\refind_x64.efi'
                ''
              )}";
            };
          })

          (mkIf (!system.dualBoot.enable) {
            boot.loader.grub.extraInstallCommands = "${pkgs.writeShellScript "uninstall-refind" (
              efibootmgrSetup config.boot.loader.efi.efiSysMountPoint
              + removeStaleRefind
              + ''
                rm -rf "$esp/EFI/refind"
              ''
            )}";
          })
        ]))

        (mkIf (!system.bootloader.enable) {
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
        })
      ];
    };
}
