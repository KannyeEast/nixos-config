{ lib, ... }:
let
  mkBtrfsRaid = import ../../lib/mkBtrfsRaid.nix;
in
{
  disko.devices.disk =
    mkBtrfsRaid {
      name = "tank";
      destroy = false;
      devices = [
        "/dev/disk/by-id/ata-WDC_WD80EFPX-68C4ZN0_WD-RD31AHZH"
        "/dev/disk/by-id/ata-WDC_WD80EFPX-68C4ZN0_WD-RD31HTJG"
      ];
      content.subvolumes = {
        "media" = {
          mountpoint = "/server/media";
          mountOptions = [
            "compress=zstd:1"
            "noatime"
            "nofail"
            "x-systemd.device-timeout=10s"
          ];
        };
        "data" = {
          mountpoint = "/server/data";
          mountOptions = [
            "compress=zstd:1"
            "noatime"
            "nofail"
            "x-systemd.device-timeout=10s"
          ];
        };
      };
    }
    // {
      scratch = {
        type = "disk";
        destroy = false;
        device = "/dev/disk/by-id/ata-INTENSO_SSD_AA000000000000000565";
        content = {
          type = "btrfs";
          extraArgs = [
            "-f"
            "-L"
            "scratch"
          ];
          subvolumes."scratch" = {
            mountpoint = "/server/scratch";
            mountOptions = [
              "noatime"
              "nofail"
              "x-systemd.device-timeout=10s"
            ];
          };
        };
      };
      vault = {
        type = "disk";
        destroy = false;
        device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_500GB_S4CNNF0M701774A";
        content = {
          type = "btrfs";
          extraArgs = [
            "-f"
            "-L"
            "vault"
          ];
          subvolumes."vault" = {
            mountpoint = "/server/vault";
            mountOptions = [
              "noatime"
              "nofail"
              "x-systemd.device-timeout=10s"
            ];
          };
        };
      };
    };

  # if the head disk dies surviving members can still mount through the label
  fileSystems."/server/media".device = lib.mkForce "/dev/disk/by-label/tank";
  fileSystems."/server/data".device = lib.mkForce "/dev/disk/by-label/tank";
}
