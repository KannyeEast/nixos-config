let
  device = "/dev/nvme0n1";
in
{
  disko.devices.disk.main = {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "512M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "defaults"
              "umask=0077"
            ];
          };
        };
        swap = {
          priority = 2;
          size = "17G";
          content = {
            type = "swap";
            discardPolicy = "both";
            resumeDevice = true;
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            subvolumes = {
              "/root" = {
                mountpoint = "/";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                  "space_cache=v2"
                ];
              };
              "/nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                  "space_cache=v2"
                ];
              };
              "/persistent" = {
                mountpoint = "/persistent";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                  "space_cache=v2"
                ];
              };
            };
          };
        };
      };
    };
  };
}
