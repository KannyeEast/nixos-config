{ inputs, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  flake.modules.nixos.impermanence =
    { config, pkgs, user, ... }:
    let
      inherit (config.internal)
        system
        ;
    in
    {
      imports = [
        inputs.impermanence.nixosModules.impermanence
      ];
      
      options = {
        internal.system.impermanence = {
          directories = mkOption {
            type = types.listOf (types.either types.str (types.attrsOf types.anything));
            default = [ ];
            internal = true;
            description = "Directories that should persist";
          };
          files = mkOption {
            type = types.listOf types.str;
            default = [ ];
            internal = true;
            description = "Files that should persist";
            };
        };
      };

      config = {
        internal.system.impermanence = {
          directories = [
            "/var/lib/NetworkManager"
            "/var/lib/nixos"
            "/var/lib/systemd"
            "/var/log"
          ];
          files = [
            "/etc/machine-id"
          ];
        };
      
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
          directories = system.impermanence.directories;
          files = system.impermanence.files;
        };
      };
    };
}
