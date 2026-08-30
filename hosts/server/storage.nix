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
          mountpoint = "/srv/media";
          mountOptions = [
            "compress=zstd:1"
            "noatime"
            "nofail"
            "x-systemd.device-timeout=10s"
          ];
        };
        "data" = {
          mountpoint = "/srv/data";
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
            mountpoint = "/srv/scratch";
            mountOptions = [
              "noatime"
              "nofail"
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
            mountpoint = "/srv/vault";
            mountOptions = [
              "noatime"
              "nofail"
            ];
          };
        };
      };
    };

  # any surviving member answers to the label, unlike the head device
  fileSystems."/srv/media".device = lib.mkForce "/dev/disk/by-label/tank";
  fileSystems."/srv/data".device = lib.mkForce "/dev/disk/by-label/tank";
}
