{ inputs, ... }:
{
  flake.modules.nixos.impermanence =
    { pkgs, host, ... }:
    let
      inherit (host) user;
    in
    {
      imports = [
        inputs.impermanence.nixosModules.impermanence
      ];

      config = {
        fileSystems."/persist".neededForBoot = true;

        boot.initrd.systemd.initrdBin = [ pkgs.btrfs-progs ];

        boot.initrd.systemd.services.rollback = {
          description = "Reset the root subvolume to a blank state";
          wantedBy = [ "initrd.target" ];
          after = [ "initrd-root-device.target" ];
          before = [ "sysroot.mount" ];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            mkdir -p /btrfs_tmp
            mount -o subvol=/ /dev/disk/by-partlabel/disk-main-root /btrfs_tmp

            delete_subvolume_recursively() {
              IFS=$'\n'
              for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                delete_subvolume_recursively "/btrfs_tmp/$i"
              done
              btrfs subvolume delete "$1"
            }

            delete_subvolume_recursively /btrfs_tmp/root
            btrfs subvolume create /btrfs_tmp/root

            umount /btrfs_tmp
          '';
        };

        systemd.tmpfiles.rules = [
          "Z /persist/home/${user.name} - ${user.name} users -"
        ];

        environment.persistence."/persist" = {
          hideMounts = true;
          directories = [
            {
              directory = "/home/${user.name}";
              user = user.name;
              group = "users";
              mode = "0700";
            }
            "/var/cache/fontconfig"
            "/var/lib/bluetooth"
            "/var/lib/NetworkManager"
            "/var/lib/nixos"
            "/var/lib/systemd"
            "/var/log"
          ];
          files = [
            "/etc/machine-id"
          ];
        };
      };
    };
}
